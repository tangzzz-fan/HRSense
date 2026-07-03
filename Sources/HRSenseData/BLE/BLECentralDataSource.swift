import Foundation
import CoreBluetooth
import HRSenseProtocol
import HRSenseCore

struct HandshakeReadinessGate {
    private(set) var hasNotifyCharacteristic = false
    private(set) var hasWriteCharacteristic = false
    private(set) var isNotifySubscriptionActive = false
    private(set) var hasEmittedHandshaking = false

    mutating func markNotifyCharacteristicDiscovered() {
        hasNotifyCharacteristic = true
    }

    mutating func markWriteCharacteristicDiscovered() {
        hasWriteCharacteristic = true
    }

    mutating func updateNotifySubscription(isActive: Bool) -> Bool {
        isNotifySubscriptionActive = isActive
        return emitHandshakingIfReady()
    }

    mutating func reset() {
        hasNotifyCharacteristic = false
        hasWriteCharacteristic = false
        isNotifySubscriptionActive = false
        hasEmittedHandshaking = false
    }

    private mutating func emitHandshakingIfReady() -> Bool {
        guard hasNotifyCharacteristic,
              hasWriteCharacteristic,
              isNotifySubscriptionActive,
              !hasEmittedHandshaking else {
            return false
        }
        hasEmittedHandshaking = true
        return true
    }
}

struct PendingCommandIdentity: Equatable {
    let token: UInt64
    let opcode: UInt8
}

struct PendingCommandTimeoutCoordinator {
    private(set) var pendingIdentity: PendingCommandIdentity?
    private var nextToken: UInt64 = 0

    mutating func register(opcode: UInt8) -> PendingCommandIdentity {
        let identity = PendingCommandIdentity(token: nextToken, opcode: opcode)
        nextToken &+= 1
        pendingIdentity = identity
        return identity
    }

    mutating func clear(_ identity: PendingCommandIdentity? = nil) {
        guard let identity else {
            pendingIdentity = nil
            return
        }
        guard pendingIdentity == identity else { return }
        pendingIdentity = nil
    }

    func canTimeout(_ identity: PendingCommandIdentity) -> Bool {
        pendingIdentity == identity
    }
}

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
    private var _handshakeReadinessGate = HandshakeReadinessGate()
    private var _pendingCommandCoordinator = PendingCommandTimeoutCoordinator()

    private var connectionStateContinuation: AsyncStream<ConnectionState>.Continuation?
    private var discoveredDevicesContinuation: AsyncStream<DeviceInfo>.Continuation?
    private var heartRateContinuation: AsyncStream<HeartRateSample>.Continuation?
    private var commandResponseContinuation: CheckedContinuation<DecodedFrame, Error>?
    private var otaResponseContinuation: CheckedContinuation<OTACommand, Error>?
    private var expectedOTAResponseOpCodes: Set<OTAOpCode> = []

    public let connectionStateStream: AsyncStream<ConnectionState>
    public let discoveredDevicesStream: AsyncStream<DeviceInfo>
    public let heartRateStream: AsyncStream<HeartRateSample>
    public let waveformRingBuffer: (any WaveformRingBufferProtocol)?

    public let dataParser = BLEDataParser()
    public let metricsCollector = MetricsCollector()
    public let connectionStateMachine = BLEConnectionStateMachine()
    public var mtu: Int = 185

    public var connectionState: ConnectionState {
        bleQueue.sync { _state }
    }

    public var connectedPeripheralIdentifier: UUID? {
        bleQueue.sync { _connectedPeripheral?.identifier }
    }

    public var connectedDeviceInfo: DeviceInfo? {
        bleQueue.sync {
            guard let identifier = _connectedPeripheral?.identifier else { return nil }
            return _discoveredPeripherals[identifier]?.1
        }
    }

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
            self._handshakeReadinessGate.reset()
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

    public func completeHandshake(with deviceInfo: DeviceInfo) {
        bleQueue.async { [weak self] in
            guard let self else { return }
            if let peripheral = self._connectedPeripheral {
                self._discoveredPeripherals[peripheral.identifier] = (peripheral, deviceInfo)
            }
            self.emitState(.connected)
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

                let identity = self._pendingCommandCoordinator.register(opcode: command.opCode.rawValue)
                self.metricsCollector.recordCommandSent()

                // Register the continuation — the next command/ack/event on notify will resume it.
                self.commandResponseContinuation = cont

                // Write each fragment on the Control (0003) characteristic.
                for frag in fragments {
                    self._connectedPeripheral!.writeValue(Data(frag), for: self._writeCharacteristic!, type: .withResponse)
                }
                HRSenseLogging.debug(.protoCmd, "WRITE(0003) CMD opcode=0x\(String(command.opCode.rawValue, radix: 16)) seq=\(seq) fragments=\(fragments.count)")

                // Timeout: cancel only if this exact request is still pending.
                self.bleQueue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    guard let self else { return }
                    guard self._pendingCommandCoordinator.canTimeout(identity) else {
                        HRSenseLogging.debug(.protoCmd, "TIMEOUT ignored for stale opcode=0x\(String(identity.opcode, radix: 16)) token=\(identity.token)")
                        return
                    }
                    guard let existing = self.commandResponseContinuation else { return }
                    self._pendingCommandCoordinator.clear(identity)
                    self.commandResponseContinuation = nil
                    self.metricsCollector.recordCommandTimeout()
                    existing.resume(throwing: AppError.commandTimeout(opcode: identity.opcode))
                }
            }
        }
    }

    // MARK: - OTA control (0003 Control, raw OTA command body)

    /// Send a raw OTA control command via Control/Write (0003) without waiting
    /// for a notify response. Used by OTA_WINDOW_BEGIN, whose response arrives
    /// later only after the OTA data chunk is written on 0005.
    public func sendOTAControl(_ command: OTACommand) async throws {
        let payload = Data(OTACodec.encode(command))
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            bleQueue.async { [weak self] in
                guard let self else { continuation.resume(throwing: AppError.connectionLost); return }
                guard let peripheral = self._connectedPeripheral,
                      let writeChar = self._writeCharacteristic else {
                    continuation.resume(throwing: AppError.deviceNotFound); return
                }
                HRSenseLogging.debug(.ota, "WRITE(0003) OTA opcode=0x\(String(command.opCode.rawValue, radix: 16)) len=\(payload.count)")
                peripheral.writeValue(payload, for: writeChar, type: .withResponse)
                continuation.resume()
            }
        }
    }

    /// Send a raw OTA control command via Control/Write (0003) and wait for the
    /// matching notify response on the Data/Notify (0002) channel.
    public func sendOTAControlAndWait(_ command: OTACommand, timeout: TimeInterval = 5.0) async throws -> OTACommand {
        let expectedOpCode = otaResponseOpCode(for: command.opCode)
        let payload = Data(OTACodec.encode(command))

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<OTACommand, Error>) in
            bleQueue.async { [weak self] in
                guard let self else { continuation.resume(throwing: AppError.connectionLost); return }
                guard let peripheral = self._connectedPeripheral,
                      let writeChar = self._writeCharacteristic else {
                    continuation.resume(throwing: AppError.deviceNotFound); return
                }
                guard let expectedOpCode else {
                    continuation.resume(throwing: AppError.protocolError(detail: "Unsupported OTA response mapping"))
                    return
                }

                self.otaResponseContinuation = continuation
                self.expectedOTAResponseOpCodes = [expectedOpCode]
                self.metricsCollector.recordCommandSent()

                HRSenseLogging.debug(.ota, "WRITE(0003) OTA opcode=0x\(String(command.opCode.rawValue, radix: 16)) wait=0x\(String(expectedOpCode.rawValue, radix: 16))")
                peripheral.writeValue(payload, for: writeChar, type: .withResponse)

                self.bleQueue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    guard let self else { return }
                    guard let pending = self.otaResponseContinuation else { return }
                    guard !self.expectedOTAResponseOpCodes.isEmpty else { return }
                    self.otaResponseContinuation = nil
                    self.expectedOTAResponseOpCodes = []
                    self.metricsCollector.recordCommandTimeout()
                    pending.resume(throwing: AppError.commandTimeout(opcode: command.opCode.rawValue))
                }
            }
        }
    }

    /// Wait for the next OTA_WINDOW_ACK arriving on the notify channel.
    public func waitForOTAWindowAck(timeout: TimeInterval = 5.0) async throws -> OTACommand {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<OTACommand, Error>) in
            bleQueue.async { [weak self] in
                guard let self else { continuation.resume(throwing: AppError.connectionLost); return }
                guard self._connectedPeripheral != nil, self._notifyCharacteristic != nil else {
                    continuation.resume(throwing: AppError.deviceNotFound); return
                }

                self.otaResponseContinuation = continuation
                self.expectedOTAResponseOpCodes = [.otaWindowAck]
                self.metricsCollector.recordCommandSent()

                self.bleQueue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    guard let self else { return }
                    guard let pending = self.otaResponseContinuation else { return }
                    guard self.expectedOTAResponseOpCodes == [.otaWindowAck] else { return }
                    self.otaResponseContinuation = nil
                    self.expectedOTAResponseOpCodes = []
                    self.metricsCollector.recordCommandTimeout()
                    pending.resume(throwing: AppError.commandTimeout(opcode: OTAOpCode.otaWindowAck.rawValue))
                }
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
        if let otaCommand = decodeRawOTANotify(data) {
            consume(otaCommand: otaCommand)
            return
        }
        for frame in frameAssembler.feed(data) {
            consume(frame: frame, receivedBytes: data.count)
        }
    }

    private func decodeRawOTANotify(_ data: Data) -> OTACommand? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2,
              let opCode = OTAOpCode(rawValue: bytes[0]),
              bytes.count == Int(bytes[1]) + 2 else {
            return nil
        }
        guard let command = OTACodec.decode(body: bytes),
              command.opCode == opCode else {
            return nil
        }
        return command
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
                _pendingCommandCoordinator.clear()
                commandResponseContinuation = nil
                cont.resume(returning: .command(command))
            }
        case .ack(let ack):
            HRSenseLogging.info(.protoCmd, "NOTIFY ack seq=\(ack.seq) opcode=0x\(String(ack.opcode, radix: 16))")
            if let cont = commandResponseContinuation {
                _pendingCommandCoordinator.clear()
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

    private func consume(otaCommand: OTACommand) {
        HRSenseLogging.info(.ota, "NOTIFY OTA opcode=0x\(String(otaCommand.opCode.rawValue, radix: 16))")
        if expectedOTAResponseOpCodes.contains(otaCommand.opCode),
           let continuation = otaResponseContinuation {
            otaResponseContinuation = nil
            expectedOTAResponseOpCodes = []
            continuation.resume(returning: otaCommand)
        }
    }

    private func otaResponseOpCode(for requestOpCode: OTAOpCode) -> OTAOpCode? {
        switch requestOpCode {
        case .otaStart:
            return .otaStartAck
        case .otaValidate:
            return .otaValidateResult
        case .otaApply:
            return .otaApply
        case .otaWindowBegin, .otaStartAck, .otaWindowAck, .otaValidateResult, .otaAbort:
            return nil
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
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "HRSense Peripheral"
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
        _connectedPeripheral = nil
        _notifyCharacteristic = nil
        _writeCharacteristic = nil
        _otaDataCharacteristic = nil
        _handshakeReadinessGate.reset()
        _pendingCommandCoordinator.clear()
        // Cancel any pending command response
        if let cont = commandResponseContinuation {
            commandResponseContinuation = nil
            cont.resume(throwing: AppError.connectionLost)
        }
        if let otaCont = otaResponseContinuation {
            otaResponseContinuation = nil
            expectedOTAResponseOpCodes = []
            otaCont.resume(throwing: AppError.connectionLost)
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
            case notifyCharUUID:
                _notifyCharacteristic = c
                _handshakeReadinessGate.markNotifyCharacteristicDiscovered()
                peripheral.setNotifyValue(true, for: c)
            case writeCharUUID:
                _writeCharacteristic = c
                _handshakeReadinessGate.markWriteCharacteristicDiscovered()
            case infoCharUUID: peripheral.readValue(for: c)
            case otaDataCharUUID: _otaDataCharacteristic = c
            default: break
            }
        }
        HRSenseLogging.info(
            .state,
            "BLE characteristics discovered: notify=\(_notifyCharacteristic != nil) write=\(_writeCharacteristic != nil) ota=\(_otaDataCharacteristic != nil)"
        )
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == notifyCharUUID else { return }

        if let error {
            HRSenseLogging.error(.state, "BLE notify subscription failed: \(error.localizedDescription)")
            return
        }

        HRSenseLogging.info(.state, "BLE notify subscription updated: isNotifying=\(characteristic.isNotifying)")
        if _handshakeReadinessGate.updateNotifySubscription(isActive: characteristic.isNotifying) {
            emitState(.handshaking)
        }
    }
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value, characteristic.uuid == notifyCharUUID else { return }
        handleNotifyData(data)
    }
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {}
}
