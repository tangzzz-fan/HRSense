import Foundation
import CoreBluetooth
import HRSenseProtocol
import HRSenseCore

/// The single file in the project that imports CoreBluetooth.
///
/// Wraps CBCentralManager and bridges delegate callbacks into AsyncStreams
/// for consumption by upper layers.
///
/// GATT Characteristic mapping (doc 03 §3.1):
///   0002 Data/Notify  — device→App data (HR, waveform, events)
///   0003 Control/Write — App→device commands (HELLO, START_STREAM, OTA control)
///   0004 Info           — device→App readable metadata
///   0005 OTA Data       — App→device firmware image chunks (Write Without Response)
public final class BLECentralDataSource: NSObject, @unchecked Sendable {

    // All CBUUID/CoreBluetooth state is isolated to bleQueue.
    private let bleQueue = DispatchQueue(label: "com.hrsense.app.ble")

    private let serviceUUID = CBUUID(string: "48525330-0001-4B8E-9F2A-1D3C5E7B9A10")
    private let notifyCharUUID = CBUUID(string: "48525330-0002-4B8E-9F2A-1D3C5E7B9A10")
    private let writeCharUUID = CBUUID(string: "48525330-0003-4B8E-9F2A-1D3C5E7B9A10")
    private let infoCharUUID = CBUUID(string: "48525330-0004-4B8E-9F2A-1D3C5E7B9A10")
    private let otaDataCharUUID = CBUUID(string: "48525330-0005-4B8E-9F2A-1D3C5E7B9A10")

    private var _centralManager: CBCentralManager?
    private var _state: ConnectionState = .idle
    private var _discoveredPeripherals: [UUID: (CBPeripheral, DeviceInfo)] = [:]
    private var _connectedPeripheral: CBPeripheral?
    private var _notifyCharacteristic: CBCharacteristic?
    private var _writeCharacteristic: CBCharacteristic?
    private var _otaDataCharacteristic: CBCharacteristic?

    private var connectionStateContinuation: AsyncStream<ConnectionState>.Continuation?
    private var discoveredDevicesContinuation: AsyncStream<DeviceInfo>.Continuation?
    private var heartRateContinuation: AsyncStream<HeartRateSample>.Continuation?
    private var commandResponseContinuation: CheckedContinuation<DecodedFrame, Error>?

    public let connectionStateStream: AsyncStream<ConnectionState>
    public let discoveredDevicesStream: AsyncStream<DeviceInfo>
    public let heartRateStream: AsyncStream<HeartRateSample>
    public let waveformRingBuffer: (any WaveformRingBufferProtocol)?

    public let dataParser = BLEDataParser()
    public let metricsCollector = MetricsCollector()
    public let connectionStateMachine = BLEConnectionStateMachine()
    public var mtu: Int = 185

    /// Persistent FrameAssembler — one per connection to correctly reassemble multi-fragment frames.
    private var frameAssembler = FrameAssembler()

    public init(
        waveformRingBuffer: (any WaveformRingBufferProtocol)? = nil,
        bootstrapCentralManager: Bool = true
    ) {
        self.waveformRingBuffer = waveformRingBuffer
        var cc: AsyncStream<ConnectionState>.Continuation!
        self.connectionStateStream = AsyncStream { cc = $0 }; self.connectionStateContinuation = cc
        var dc: AsyncStream<DeviceInfo>.Continuation!
        self.discoveredDevicesStream = AsyncStream { dc = $0 }; self.discoveredDevicesContinuation = dc
        var hc: AsyncStream<HeartRateSample>.Continuation!
        self.heartRateStream = AsyncStream { hc = $0 }; self.heartRateContinuation = hc
        super.init()
        if bootstrapCentralManager {
            _centralManager = CBCentralManager(delegate: self, queue: bleQueue)
        }
    }

    // MARK: - Public API

    public func startScanning() {
        bleQueue.async { [weak self] in
            guard let self, let cm = self._centralManager, cm.state == .poweredOn else { return }
            self._discoveredPeripherals.removeAll()
            cm.scanForPeripherals(withServices: [self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            self.emitState(.scanning)
        }
    }

    public func stopScanning() {
        bleQueue.async { [weak self] in self?._centralManager?.stopScan(); self?.emitState(.idle) }
    }

    public func connect(to peripheralID: UUID) {
        bleQueue.async { [weak self] in
            guard let self, let cm = self._centralManager,
                  let (p, _) = self._discoveredPeripherals[peripheralID] else { return }
            self.connectionStateMachine.resetBackoff()
            self.emitState(.connecting)
            cm.stopScan()
            cm.connect(p, options: nil)
        }
    }

    public func disconnect() {
        bleQueue.async { [weak self] in
            guard let self, let cm = self._centralManager, let p = self._connectedPeripheral else { return }
            self.emitState(.disconnecting)
            cm.cancelPeripheralConnection(p)
        }
    }

    // MARK: - Command write (0003 Control, Write With Response)

    /// Send a control command via Control/Write (0003). Uses Write With Response
    /// for ATT-level acknowledgement.
    public func sendCommand(_ opcode: UInt8, payload: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            bleQueue.async { [weak self] in
                guard let self else { continuation.resume(throwing: AppError.connectionLost); return }
                guard let peripheral = self._connectedPeripheral,
                      let writeChar = self._writeCharacteristic else {
                    continuation.resume(throwing: AppError.deviceNotFound); return
                }
                HRSenseLogging.debug(.protoCmd, "WRITE(0003) opcode=0x\(String(opcode, radix: 16)) len=\(payload.count)")
                peripheral.writeValue(payload, for: writeChar, type: .withResponse)
                continuation.resume(returning: payload)
            }
        }
    }

    /// Send a control command and wait for an asynchronous response frame
    /// (command, ack, or event) delivered via the notify channel.
    ///
    /// The request is sent via Control/Write (0003). The response arrives on the
    /// Data/Notify (0002) channel as a decoded `DecodedFrame`. This method bridges
    /// the two channels: it writes on 0003, then blocks the caller (via
    /// CheckedContinuation) until the next matching response arrives on 0002.
    ///
    /// - Parameters:
    ///   - command: the encoded command payload (with opcode).
    ///   - timeout: maximum wait duration in seconds.
    /// - Returns: the decoded response frame.
    /// - Throws: AppError.commandTimeout if no response within the timeout.
    public func sendCommandAndWait(_ command: Command, timeout: TimeInterval = 5.0) async throws -> DecodedFrame {
        let body = CommandCodec.encode(command)
        let seq = nextSeq()
        let fragments = FrameEncoder.encode(type: .command, body: body, seq: seq, mtu: mtu)

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<DecodedFrame, Error>) in
            bleQueue.async { [weak self] in
                guard let self else { cont.resume(throwing: AppError.connectionLost); return }
                guard self._connectedPeripheral != nil, self._writeCharacteristic != nil else {
                    cont.resume(throwing: AppError.deviceNotFound); return
                }

                // Register the continuation — the next command/ack/event on notify will resume it.
                self.commandResponseContinuation = cont

                // Write each fragment on the Control (0003) characteristic.
                for frag in fragments {
                    self._connectedPeripheral!.writeValue(Data(frag), for: self._writeCharacteristic!, type: .withResponse)
                }
                HRSenseLogging.debug(.protoCmd, "WRITE(0003) CMD opcode=0x\(String(command.opCode.rawValue, radix: 16)) seq=\(seq) fragments=\(fragments.count)")
            }

            // Timeout: cancel if no response within timeout window.
            bleQueue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self, let existing = self.commandResponseContinuation else { return }
                self.commandResponseContinuation = nil
                existing.resume(throwing: AppError.commandTimeout(opcode: command.opCode.rawValue))
            }
        }
    }

    /// Rolling frame sequence number (0–255).
    private var _seq: UInt8 = 0
    private func nextSeq() -> UInt8 {
        let s = _seq
        _seq = _seq &+ 1
        return s
    }

    // MARK: - OTA window write (0005 OTA Data, Write Without Response)

    /// Write a firmware image chunk via OTA Data (0005).
    ///
    /// Uses Write Without Response — flow control is managed by the caller
    /// via `OTA_WINDOW_ACK` responses from the device.
    ///
    /// - Parameter chunk: raw firmware bytes. Max length determined by MTU.
    /// - Returns: true if the write was queued successfully.
    public func sendOTAChunk(_ chunk: Data) {
        bleQueue.async { [weak self] in
            guard let self,
                  let peripheral = self._connectedPeripheral,
                  let otaChar = self._otaDataCharacteristic else { return }
            HRSenseLogging.debug(.ota, "OTA_WRITE(0005) len=\(chunk.count)")
            peripheral.writeValue(chunk, for: otaChar, type: .withoutResponse)
        }
    }

    /// Whether the OTA Data (0005) characteristic has been discovered.
    public var otaChannelReady: Bool {
        bleQueue.sync { _otaDataCharacteristic != nil }
    }

    // MARK: - Private

    private func emitState(_ state: ConnectionState) {
        _state = state
        connectionStateMachine.transition(to: state)
        connectionStateContinuation?.yield(state)
    }

    private func handleNotifyData(_ data: Data) {
        metricsCollector.recordBytesReceived(data.count)
        HRSenseLogging.debug(.bleRaw, HexFormat.canonicalHexDump(data))
        for frame in frameAssembler.feed(data) {
            consume(frame: frame, receivedBytes: data.count)
        }
    }

    func consume(frame: DecodedFrame, receivedBytes: Int) {
        switch frame {
        case .data(let sample):
            metricsCollector.recordSampleReceived()
            heartRateContinuation?.yield(dataParser.parseSample(sample))
        case .command(let command):
            // Device→App commands (e.g. HELLO_ACK, INFO, ERROR)
            HRSenseLogging.info(.protoCmd, "NOTIFY command opcode=0x\(String(command.opCode.rawValue, radix: 16))")
            if let cont = commandResponseContinuation {
                commandResponseContinuation = nil
                cont.resume(returning: .command(command))
            }
        case .ack(let ack):
            HRSenseLogging.info(.protoCmd, "NOTIFY ack seq=\(ack.seq) opcode=0x\(String(ack.opcode, radix: 16))")
            if let cont = commandResponseContinuation {
                commandResponseContinuation = nil
                cont.resume(returning: .ack(ack))
            }
        case .event:
            HRSenseLogging.info(.protoCmd, "NOTIFY event")
        case .waveform(let block):
            HRSenseLogging.debug(.bleRaw, "NOTIFY waveform blockSeq=\(block.blockSeq)")
            waveformRingBuffer?.recordBlock(
                bytes: receivedBytes,
                blockSeq: block.blockSeq,
                sampleCount: block.sampleCount
            )
            let samples = dataParser.parseWaveformBlock(block)
            if !samples.isEmpty {
                waveformRingBuffer?.push(samples)
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLECentralDataSource: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOff { emitState(.disconnected) }
    }
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Unknown"
        let info = DeviceInfo(peripheralIdentifier: peripheral.identifier, name: name,
                              model: "", firmwareVersion: "", protocolVersion: 0, capabilities: 0)
        _discoveredPeripherals[peripheral.identifier] = (peripheral, info)
        discoveredDevicesContinuation?.yield(info)
    }
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        _connectedPeripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        emitState(.disconnected)
    }
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        _connectedPeripheral = nil; _notifyCharacteristic = nil; _writeCharacteristic = nil; _otaDataCharacteristic = nil
        // Cancel any pending command response
        if let cont = commandResponseContinuation {
            commandResponseContinuation = nil
            cont.resume(throwing: AppError.connectionLost)
        }
        // Reset frame assembler and data parser for the next connection
        frameAssembler.reset()
        dataParser.resetT0()
        emitState(.disconnected)
    }
}

// MARK: - CBPeripheralDelegate

extension BLECentralDataSource: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let svcs = peripheral.services else { return }
        for svc in svcs where svc.uuid == serviceUUID {
            // Discover all 4 characteristics (0002 notify, 0003 write, 0004 info, 0005 ota)
            peripheral.discoverCharacteristics([notifyCharUUID, writeCharUUID, infoCharUUID, otaDataCharUUID], for: svc)
        }
    }
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let chars = service.characteristics else { return }
        for c in chars {
            switch c.uuid {
            case notifyCharUUID: _notifyCharacteristic = c; peripheral.setNotifyValue(true, for: c)
            case writeCharUUID: _writeCharacteristic = c
            case infoCharUUID: peripheral.readValue(for: c)
            case otaDataCharUUID: _otaDataCharacteristic = c
            default: break
            }
        }
        // Service discovery complete — ready for handshake
        emitState(.handshaking)
    }
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value, characteristic.uuid == notifyCharUUID else { return }
        handleNotifyData(data)
    }
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {}
}
