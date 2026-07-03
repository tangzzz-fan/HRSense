import Foundation
import CoreBluetooth
import HRSenseProtocol

enum NotifyPayloadPriority: String, Equatable {
    case high
    case normal
}

struct PendingNotifyPayload: Equatable {
    let data: Data
    let priority: NotifyPayloadPriority
    let source: String
}

struct NotifyBackpressureBuffer {
    private var highPriorityPayloads: [PendingNotifyPayload] = []
    private var normalPriorityPayloads: [PendingNotifyPayload] = []

    var count: Int {
        highPriorityPayloads.count + normalPriorityPayloads.count
    }

    var isEmpty: Bool {
        count == 0
    }

    mutating func enqueue(_ payloads: [PendingNotifyPayload]) {
        for payload in payloads {
            switch payload.priority {
            case .high:
                highPriorityPayloads.append(payload)
            case .normal:
                normalPriorityPayloads.append(payload)
            }
        }
    }

    mutating func prepend(_ payload: PendingNotifyPayload) {
        switch payload.priority {
        case .high:
            highPriorityPayloads.insert(payload, at: 0)
        case .normal:
            normalPriorityPayloads.insert(payload, at: 0)
        }
    }

    mutating func popNext() -> PendingNotifyPayload? {
        if !highPriorityPayloads.isEmpty {
            return highPriorityPayloads.removeFirst()
        }
        if !normalPriorityPayloads.isEmpty {
            return normalPriorityPayloads.removeFirst()
        }
        return nil
    }

    mutating func reset() {
        highPriorityPayloads.removeAll(keepingCapacity: false)
        normalPriorityPayloads.removeAll(keepingCapacity: false)
    }
}

/// Wraps CBPeripheralManager to act as a BLE peripheral (simulated device).
///
/// GATT characteristics (doc 03 §3.1):
///   0002 Data/Notify   — device→App HR/waveform/events
///   0003 Control/Write  — App→device commands (Write + WriteWithoutResponse)
///   0004 Info            — readable device metadata
///   0005 OTA Data        — App→device firmware image (WriteWithoutResponse)
public final class SimulatedPeripheral: NSObject, @unchecked Sendable {

    struct ControlWriteRouter {
        private var assembler = FrameAssembler()

        mutating func process(_ value: Data, commandProcessor: CommandProcessor) -> [(Command, [Data])] {
            guard value.count >= 2 else { return [] }
            let seq = value[1]
            let decoded = assembler.feed(value)

            return decoded.compactMap { frame in
                guard case let .command(command) = frame else { return nil }
                let responses = commandProcessor.process(command: command, seq: seq)
                return (command, responses)
            }
        }

        mutating func reset() {
            assembler.reset()
        }
    }

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

    public var currentFirmwareVersion: String {
        bleQueue.sync { commandProcessor.firmwareVersion }
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
    private var controlWriteRouter = ControlWriteRouter()
    private var notifyBackpressureBuffer = NotifyBackpressureBuffer()

    // MARK: - OTA handler (M6)

    /// OTA event handler — routes OTA commands (0003) and image data (0005).
    public var otaEventHandler: OTAEventHandler?

    // MARK: - Callbacks

    /// Fired when a subscribed central sends a command write.
    public var onCommandReceived: (([Data]) -> Void)?

    /// Fired when the device state changes.
    public var onStateChanged: ((DeviceState) -> Void)?

    // MARK: - Init

    public init(
        config: SimulatorConfig = SimulatorConfig(),
        onStreamStart: (([UInt8]) -> Void)? = nil,
        onStreamStop: (() -> Void)? = nil
    ) {
        self.serviceUUID = CBUUID(string: "48525330-0001-4B8E-9F2A-1D3C5E7B9A10")
        self.notifyCharUUID = CBUUID(string: "48525330-0002-4B8E-9F2A-1D3C5E7B9A10")
        self.writeCharUUID = CBUUID(string: "48525330-0003-4B8E-9F2A-1D3C5E7B9A10")
        self.infoCharUUID = CBUUID(string: "48525330-0004-4B8E-9F2A-1D3C5E7B9A10")
        self.otaDataCharUUID = CBUUID(string: "48525330-0005-4B8E-9F2A-1D3C5E7B9A10")

        self.commandProcessor = CommandProcessor(
            config: config,
            onStreamStart: onStreamStart,
            onStreamStop: onStreamStop
        )
        self.otaEventHandler = OTAEventHandler(
            stateMachine: OTAStateMachine(currentVersion: config.firmwareVersion),
            mtu: config.mtu
        )

        super.init()

        self.otaEventHandler?.onRebootNeeded = { [weak self] newVersion in
            self?.handleOTAReboot(newVersion: newVersion)
        }

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
                CBAdvertisementDataLocalNameKey: self.commandProcessor.advertisingLocalName,
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

    /// Push a data sample via notify. Returns true if the payload was accepted
    /// into the local send pipeline.
    @discardableResult
    public func pushSample(_ sample: DeviceSample) -> Bool {
        bleQueue.sync {
            guard _centralSubscribed,
                  let notifyChar = _notifyCharacteristic,
                  let pm = _peripheralManager
            else { return false }

            let payloads = makeNotifyPayloads(
                from: commandProcessor.encodeSample(sample),
                priority: .high,
                source: "sample"
            )
            enqueueAndDrainNotifyPayloads(payloads, notifyChar: notifyChar, peripheralManager: pm)
            return true
        }
    }

    /// Push raw command/response fragments via notify.
    public func pushResponse(_ fragments: [Data]) {
        pushNotifyFragments(fragments, priority: .high, source: "response")
    }

    /// Push arbitrary notify fragments over the Data/Notify channel.
    public func pushNotifyFragments(_ fragments: [Data]) {
        pushNotifyFragments(fragments, priority: .normal, source: "waveform")
    }

    private func pushNotifyFragments(
        _ fragments: [Data],
        priority: NotifyPayloadPriority,
        source: String
    ) {
        bleQueue.async { [weak self] in
            guard let self else { return }
            guard self._centralSubscribed else {
                HRSenseLogging.error(.protoCmd, "NOTIFY dropped: no subscribed central")
                return
            }
            guard let notifyChar = self._notifyCharacteristic,
                  let pm = self._peripheralManager else {
                HRSenseLogging.error(.protoCmd, "NOTIFY dropped: notify characteristic unavailable")
                return
            }

            let payloads = self.makeNotifyPayloads(
                from: fragments,
                priority: priority,
                source: source
            )
            self.enqueueAndDrainNotifyPayloads(payloads, notifyChar: notifyChar, peripheralManager: pm)
        }
    }

    private func makeNotifyPayloads(
        from fragments: [Data],
        priority: NotifyPayloadPriority,
        source: String
    ) -> [PendingNotifyPayload] {
        fragments.compactMap { fragment in
            guard let data = faultInjector.apply(fragment) else { return nil }
            return PendingNotifyPayload(data: data, priority: priority, source: source)
        }
    }

    private func enqueueAndDrainNotifyPayloads(
        _ payloads: [PendingNotifyPayload],
        notifyChar: CBMutableCharacteristic,
        peripheralManager: CBPeripheralManager
    ) {
        guard !payloads.isEmpty else { return }
        notifyBackpressureBuffer.enqueue(payloads)
        drainPendingNotifyPayloads(notifyChar: notifyChar, peripheralManager: peripheralManager)
    }

    private func drainPendingNotifyPayloads(
        notifyChar: CBMutableCharacteristic,
        peripheralManager: CBPeripheralManager
    ) {
        guard _centralSubscribed else {
            notifyBackpressureBuffer.reset()
            return
        }

        while let payload = notifyBackpressureBuffer.popNext() {
            let didQueue = peripheralManager.updateValue(
                payload.data,
                for: notifyChar,
                onSubscribedCentrals: nil
            )
            if didQueue {
                HRSenseLogging.info(
                    .protoCmd,
                    "NOTIFY sent source=\(payload.source) priority=\(payload.priority.rawValue) len=\(payload.data.count) pending=\(notifyBackpressureBuffer.count)"
                )
                continue
            }

            notifyBackpressureBuffer.prepend(payload)
            HRSenseLogging.info(
                .protoCmd,
                "NOTIFY backpressure source=\(payload.source) priority=\(payload.priority.rawValue) pending=\(notifyBackpressureBuffer.count)"
            )
            return
        }
    }

    private func pushOTAResponses(_ commands: [OTACommand]) {
        let fragments = commands.map { Data(OTACodec.encode($0)) }
        pushNotifyFragments(fragments)
    }

    private func handleOTAReboot(newVersion: String) {
        bleQueue.async { [weak self] in
            guard let self, let pm = self._peripheralManager else { return }

            self.commandProcessor.updateFirmwareVersion(newVersion)
            self._centralSubscribed = false
            self.notifyBackpressureBuffer.reset()
            self.controlWriteRouter.reset()
            self.commandProcessor.didDisconnect()
            self._deviceState = .advertising
            self.onStateChanged?(self._deviceState)

            pm.stopAdvertising()
            self._isAdvertising = false

            self.bleQueue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                self.startAdvertising()
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
        notifyBackpressureBuffer.reset()
        _centralSubscribed = true
        _deviceState = .connected
        commandProcessor.didConnect()
        HRSenseLogging.info(.state, "Central subscribed to notify characteristic: \(characteristic.uuid.uuidString)")
        onStateChanged?(_deviceState)
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager,
                                   central: CBCentral,
                                   didUnsubscribeFrom characteristic: CBCharacteristic) {
        _centralSubscribed = false
        notifyBackpressureBuffer.reset()
        commandProcessor.didDisconnect()
        controlWriteRouter.reset()
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
                if let responses = otaEventHandler?.receiveOTAChunk(packet: [UInt8](value)),
                   !responses.isEmpty {
                    pushOTAResponses(responses)
                }
                peripheral.respond(to: request, withResult: .success)
                continue
            }

            guard request.characteristic.uuid == writeCharUUID,
                  let value = request.value else {
                peripheral.respond(to: request, withResult: .requestNotSupported)
                continue
            }

            let routedCommands = controlWriteRouter.process(value, commandProcessor: commandProcessor)
            if !routedCommands.isEmpty {
                for (command, responses) in routedCommands {
                    HRSenseLogging.info(.protoCmd, "WRITE(0003) decoded opcode=0x\(String(command.opCode.rawValue, radix: 16))")
                    onCommandReceived?(responses)
                    if !responses.isEmpty {
                        pushResponse(responses)
                    }
                }
                peripheral.respond(to: request, withResult: .success)
                continue
            }

            if let otaCommand = OTACodec.decode(body: [UInt8](value)) {
                HRSenseLogging.info(.ota, "WRITE(0003) OTA opcode=0x\(String(otaCommand.opCode.rawValue, radix: 16))")
                let responses = otaEventHandler?.handle(command: otaCommand) ?? []
                if !responses.isEmpty {
                    pushOTAResponses(responses)
                }
                peripheral.respond(to: request, withResult: .success)
                continue
            }

            peripheral.respond(to: request, withResult: .requestNotSupported)
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager,
                                   didReceiveRead request: CBATTRequest) {
        if request.characteristic.uuid == infoCharUUID {
            let info: [String: String] = [
                "model": commandProcessor.model,
                "firmwareVersion": commandProcessor.firmwareVersion,
                "protocolVersion": "\(commandProcessor.protocolVersion)",
            ]
            let infoData = (try? JSONSerialization.data(withJSONObject: info)) ?? Data()
            request.value = infoData
            peripheral.respond(to: request, withResult: .success)
        } else {
            peripheral.respond(to: request, withResult: .requestNotSupported)
        }
    }

    public func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        guard _centralSubscribed,
              let notifyChar = _notifyCharacteristic else { return }
        drainPendingNotifyPayloads(notifyChar: notifyChar, peripheralManager: peripheral)
    }
}
