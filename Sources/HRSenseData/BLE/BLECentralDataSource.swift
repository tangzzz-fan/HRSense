import Foundation
import CoreBluetooth
import HRSenseProtocol
import HRSenseCore

/// The single file in the project that imports CoreBluetooth.
///
/// Wraps CBCentralManager and bridges delegate callbacks into AsyncStreams
/// for consumption by upper layers.
public final class BLECentralDataSource: NSObject, @unchecked Sendable {

    // All CBUUID/CoreBluetooth state is isolated to bleQueue.
    private let bleQueue = DispatchQueue(label: "com.hrsense.app.ble")

    private let serviceUUID = CBUUID(string: "48525330-0001-4B8E-9F2A-1D3C5E7B9A10")
    private let notifyCharUUID = CBUUID(string: "48525330-0002-4B8E-9F2A-1D3C5E7B9A10")
    private let writeCharUUID = CBUUID(string: "48525330-0003-4B8E-9F2A-1D3C5E7B9A10")
    private let infoCharUUID = CBUUID(string: "48525330-0004-4B8E-9F2A-1D3C5E7B9A10")

    private var _centralManager: CBCentralManager?
    private var _state: ConnectionState = .idle
    private var _discoveredPeripherals: [UUID: (CBPeripheral, DeviceInfo)] = [:]
    private var _connectedPeripheral: CBPeripheral?
    private var _notifyCharacteristic: CBCharacteristic?
    private var _writeCharacteristic: CBCharacteristic?

    private var connectionStateContinuation: AsyncStream<ConnectionState>.Continuation?
    private var discoveredDevicesContinuation: AsyncStream<DeviceInfo>.Continuation?
    private var heartRateContinuation: AsyncStream<HeartRateSample>.Continuation?

    public let connectionStateStream: AsyncStream<ConnectionState>
    public let discoveredDevicesStream: AsyncStream<DeviceInfo>
    public let heartRateStream: AsyncStream<HeartRateSample>

    public let dataParser = BLEDataParser()
    public let metricsCollector = MetricsCollector()
    public let connectionStateMachine = BLEConnectionStateMachine()
    public var mtu: Int = 185

    public override init() {
        var cc: AsyncStream<ConnectionState>.Continuation!
        self.connectionStateStream = AsyncStream { cc = $0 }; self.connectionStateContinuation = cc
        var dc: AsyncStream<DeviceInfo>.Continuation!
        self.discoveredDevicesStream = AsyncStream { dc = $0 }; self.discoveredDevicesContinuation = dc
        var hc: AsyncStream<HeartRateSample>.Continuation!
        self.heartRateStream = AsyncStream { hc = $0 }; self.heartRateContinuation = hc
        super.init()
        _centralManager = CBCentralManager(delegate: self, queue: bleQueue)
    }

    public func startScanning() {
        bleQueue.async { [weak self] in
            guard let self, let cm = self._centralManager, cm.state == .poweredOn else { return }
            self._discoveredPeripherals.removeAll()
            cm.scanForPeripherals(withServices: [self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            self.emitState(.scanning)
        }
    }

    public func stopScanning() {
        bleQueue.async { [weak self] in
            self?._centralManager?.stopScan()
            self?.emitState(.idle)
        }
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

    public func sendCommand(_ opcode: UInt8, payload: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            bleQueue.async { [weak self] in
                guard let self else { continuation.resume(throwing: AppError.connectionLost); return }
                guard let peripheral = self._connectedPeripheral,
                      let writeChar = self._writeCharacteristic else {
                    continuation.resume(throwing: AppError.deviceNotFound); return
                }
                peripheral.writeValue(payload, for: writeChar, type: .withResponse)
                continuation.resume(returning: payload)
            }
        }
    }

    private func emitState(_ state: ConnectionState) {
        _state = state
        connectionStateMachine.transition(to: state)
        connectionStateContinuation?.yield(state)
    }

    private func handleNotifyData(_ data: Data) {
        metricsCollector.recordBytesReceived(data.count)
        let assembler = FrameAssembler()
        for frame in assembler.feed(data) {
            switch frame {
            case .data(let sample):
                metricsCollector.recordSampleReceived()
                heartRateContinuation?.yield(dataParser.parseSample(sample))
            case .command, .ack, .event:
                break // Routed by DeviceRepositoryImpl in M4
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
        _connectedPeripheral = nil; _notifyCharacteristic = nil; _writeCharacteristic = nil
        emitState(.disconnected)
    }
}

// MARK: - CBPeripheralDelegate

extension BLECentralDataSource: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let svcs = peripheral.services else { return }
        for svc in svcs where svc.uuid == serviceUUID {
            peripheral.discoverCharacteristics([notifyCharUUID, writeCharUUID, infoCharUUID], for: svc)
        }
    }
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let chars = service.characteristics else { return }
        for c in chars {
            switch c.uuid {
            case notifyCharUUID: _notifyCharacteristic = c; peripheral.setNotifyValue(true, for: c)
            case writeCharUUID: _writeCharacteristic = c
            case infoCharUUID: peripheral.readValue(for: c)
            default: break
            }
        }
    }
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value, characteristic.uuid == notifyCharUUID else { return }
        handleNotifyData(data)
    }
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {}
}
