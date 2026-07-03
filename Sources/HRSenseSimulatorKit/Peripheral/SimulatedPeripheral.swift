import Foundation
import CoreBluetooth
import HRSenseProtocol

/// Wraps CBPeripheralManager to act as a BLE peripheral (simulated device).
///
/// GATT characteristics (doc 03 §3.1):
///   0002 Data/Notify   — device→App HR/waveform/events
///   0003 Control/Write  — App→device commands (Write + WriteWithoutResponse)
///   0004 Info            — readable device metadata
///   0005 OTA Data        — App→device firmware image (WriteWithoutResponse)
public final class SimulatedPeripheral: NSObject, @unchecked Sendable {

    // Synchronization: all mutable state is accessed only on the `bleQueue`.
    private let bleQueue = DispatchQueue(label: "com.hrsense.simulator.ble")

    // MARK: - Public state (read via bleQueue or caller-synchronised)

    private var _peripheralManager: CBPeripheralManager?

    public var peripheralManager: CBPeripheralManager? {
        bleQueue.sync { _peripheralManager }
    }

    private var _isAdvertising: Bool = false
    public var isAdvertising: Bool {
        bleQueue.sync { _isAdvertising }
    }

    private var _centralSubscribed: Bool = false
    public var centralSubscribed: Bool {
        bleQueue.sync { _centralSubscribed }
    }

    private var _deviceState: DeviceState = .advertising
    public var deviceState: DeviceState {
        bleQueue.sync { _deviceState }
    }

    /// Current data generator.
    public var generator: (any DataGeneratorProtocol)?

    /// Fault injector for outbound data.
    public let faultInjector = FaultInjector()

    /// Command processor for handling incoming commands.
    public let commandProcessor: CommandProcessor

    // MARK: - BLE identifiers

    private let serviceUUID: CBUUID
    private let notifyCharUUID: CBUUID
    private let writeCharUUID: CBUUID
    private let infoCharUUID: CBUUID
    private let otaDataCharUUID: CBUUID

    private var _notifyCharacteristic: CBMutableCharacteristic?
    private var _infoCharacteristic: CBMutableCharacteristic?

    // MARK: - OTA handler (M6)

    /// OTA event handler — routes OTA commands (0003) and image data (0005).
    public var otaEventHandler: OTAEventHandler?

    // MARK: - Callbacks

    /// Fired when a subscribed central sends a command write.
    public var onCommandReceived: (([Data]) -> Void)?

    /// Fired when the device state changes.
    public var onStateChanged: ((DeviceState) -> Void)?

    // MARK: - Init

    public init(config: SimulatorConfig = SimulatorConfig()) {
        self.serviceUUID = CBUUID(string: "48525330-0001-4B8E-9F2A-1D3C5E7B9A10")
        self.notifyCharUUID = CBUUID(string: "48525330-0002-4B8E-9F2A-1D3C5E7B9A10")
        self.writeCharUUID = CBUUID(string: "48525330-0003-4B8E-9F2A-1D3C5E7B9A10")
        self.infoCharUUID = CBUUID(string: "48525330-0004-4B8E-9F2A-1D3C5E7B9A10")
        self.otaDataCharUUID = CBUUID(string: "48525330-0005-4B8E-9F2A-1D3C5E7B9A10")

        self.commandProcessor = CommandProcessor(config: config)

        super.init()

        _peripheralManager = CBPeripheralManager(delegate: self, queue: bleQueue)
    }

    // MARK: - Public API

    /// Start advertising the HRSense service.
    public func startAdvertising() {
        bleQueue.async { [weak self] in
            guard let self, let pm = self._peripheralManager, pm.state == .poweredOn else { return }

            let notifyChar = CBMutableCharacteristic(
                type: self.notifyCharUUID,
                properties: [.notify],
                value: nil,
                permissions: [.readable]
            )
            let writeChar = CBMutableCharacteristic(
                type: self.writeCharUUID,
                properties: [.write, .writeWithoutResponse],
                value: nil,
                permissions: [.writeable]
            )
            let infoChar = CBMutableCharacteristic(
                type: self.infoCharUUID,
                properties: [.read],
                value: nil,
                permissions: [.readable]
            )
            // OTA Data (0005) — Write Without Response only, for high-throughput image chunks
            let otaDataChar = CBMutableCharacteristic(
                type: self.otaDataCharUUID,
                properties: [.writeWithoutResponse],
                value: nil,
                permissions: [.writeable]
            )

            self._notifyCharacteristic = notifyChar
            self._infoCharacteristic = infoChar

            let service = CBMutableService(type: self.serviceUUID, primary: true)
            service.characteristics = [notifyChar, writeChar, infoChar, otaDataChar]

            pm.add(service)

            let advertisementData: [String: Any] = [
                CBAdvertisementDataServiceUUIDsKey: [self.serviceUUID],
                CBAdvertisementDataLocalNameKey: "HRSense-Sim",
            ]
            pm.startAdvertising(advertisementData)
            self._isAdvertising = true
            self._deviceState = .advertising
        }
    }

    /// Stop advertising.
    public func stopAdvertising() {
        bleQueue.async { [weak self] in
            guard let self, let pm = self._peripheralManager else { return }
            pm.stopAdvertising()
            self._isAdvertising = false
        }
    }

    /// Push a data sample via notify. Returns true if the central is subscribed.
    @discardableResult
    public func pushSample(_ sample: DeviceSample) -> Bool {
        bleQueue.sync {
            guard _centralSubscribed,
                  let notifyChar = _notifyCharacteristic,
                  let pm = _peripheralManager
            else { return false }

            let frames = commandProcessor.encodeSample(sample)
            for frame in frames {
                guard let data = faultInjector.apply(frame) else { continue }
                pm.updateValue(data, for: notifyChar, onSubscribedCentrals: nil)
            }
            return true
        }
    }

    /// Push raw command/response fragments via notify.
    public func pushResponse(_ fragments: [Data]) {
        bleQueue.async { [weak self] in
            guard let self,
                  self._centralSubscribed,
                  let notifyChar = self._notifyCharacteristic,
                  let pm = self._peripheralManager
            else { return }

            for frag in fragments {
                guard let data = self.faultInjector.apply(frag) else { continue }
                pm.updateValue(data, for: notifyChar, onSubscribedCentrals: nil)
            }
        }
    }
}

// MARK: - CBPeripheralManagerDelegate

extension SimulatedPeripheral: CBPeripheralManagerDelegate {

    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            startAdvertising()
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager,
                                   central: CBCentral,
                                   didSubscribeTo characteristic: CBCharacteristic) {
        _centralSubscribed = true
        _deviceState = .connected
        commandProcessor.didConnect()
        onStateChanged?(_deviceState)
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager,
                                   central: CBCentral,
                                   didUnsubscribeFrom characteristic: CBCharacteristic) {
        _centralSubscribed = false
        commandProcessor.didDisconnect()
        _deviceState = .advertising
        onStateChanged?(_deviceState)
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager,
                                   didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            // Route by characteristic: 0003 = commands, 0005 = OTA image data
            if request.characteristic.uuid == otaDataCharUUID, let value = request.value {
                // OTA image chunk received via dedicated high-throughput channel
                HRSenseLogging.debug(.ota, "OTA_WRITE(0005) received: len=\(value.count)")
                // OTA data is handled by the OTARepositoryImpl on the App side;
                // on the device side (simulator), OTA data chunks are processed
                // by OTAEventHandler.receiveOTAChunk when called from the command processor
                peripheral.respond(to: request, withResult: .success)
                continue
            }

            guard request.characteristic.uuid == writeCharUUID,
                  let value = request.value else {
                peripheral.respond(to: request, withResult: .requestNotSupported)
                continue
            }

            let assembler = FrameAssembler()
            let decoded = assembler.feed(value)
            for frame in decoded {
                if case let .command(cmd) = frame {
                    let responses = commandProcessor.process(command: cmd, seq: 0)
                    onCommandReceived?(responses)
                    if !responses.isEmpty {
                        pushResponse(responses)
                    }
                }
            }

            peripheral.respond(to: request, withResult: .success)
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager,
                                   didReceiveRead request: CBATTRequest) {
        if request.characteristic.uuid == infoCharUUID {
            let info: [String: String] = [
                "model": "HRSense-Sim",
                "firmwareVersion": "1.0.0-sim",
                "protocolVersion": "1",
            ]
            let infoData = (try? JSONSerialization.data(withJSONObject: info)) ?? Data()
            request.value = infoData
            peripheral.respond(to: request, withResult: .success)
        } else {
            peripheral.respond(to: request, withResult: .requestNotSupported)
        }
    }

    public func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // Ready to send more data — can be used for flow control
    }
}
