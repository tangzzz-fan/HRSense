import Foundation
import HRSenseCore
import HRSenseProtocol

/// Implements DeviceRepository by orchestrating BLECentralDataSource + protocol pipeline.
///
/// Responsible for:
///   - Connection flow: connect → discover services → subscribe → HELLO → HELLO_ACK → START_STREAM
///   - Data reception loop: notify bytes → FrameAssembler → domain samples
///   - Disconnection handling + reconnection flow
public final class DeviceRepositoryImpl: DeviceRepository, @unchecked Sendable {

    private let bleDataSource: BLECentralDataSource
    public let metricsCollector: MetricsCollector

    public var connectionState: ConnectionState {
        bleDataSource.connectionStateMachine.state
    }

    public var connectionStateStream: AsyncStream<ConnectionState> {
        bleDataSource.connectionStateStream
    }

    public var discoveredDevicesStream: AsyncStream<DeviceInfo> {
        bleDataSource.discoveredDevicesStream
    }

    public var heartRateStream: AsyncStream<HeartRateSample> {
        bleDataSource.heartRateStream
    }

    public var restoredPeripheralIDsStream: AsyncStream<[UUID]> {
        bleDataSource.restoredPeripheralIDsStream
    }

    public let deviceInfoStream: AsyncStream<DeviceInfo>
    private let deviceInfoContinuation: AsyncStream<DeviceInfo>.Continuation

    public init(bleDataSource: BLECentralDataSource) {
        self.bleDataSource = bleDataSource
        self.metricsCollector = bleDataSource.metricsCollector
        var cont: AsyncStream<DeviceInfo>.Continuation!
        self.deviceInfoStream = AsyncStream { cont = $0 }
        self.deviceInfoContinuation = cont
    }

    public func startScanning() async {
        bleDataSource.startScanning()
    }

    public func stopScanning() {
        bleDataSource.stopScanning()
    }

    public func connect(to deviceID: UUID) async throws {
        metricsCollector.recordConnectionAttempt()
        bleDataSource.connect(to: deviceID)
    }

    public func disconnect() {
        bleDataSource.disconnect()
    }

    public func sendCommand(_ opcode: UInt8, payload: Data) async throws -> Data {
        try await bleDataSource.sendCommand(opcode, payload: payload)
    }

    // MARK: - Handshake (HELLO → HELLO_ACK → START_STREAM)

    /// Perform the full handshake sequence after BLE connection + service discovery.
    ///
    /// Flow (doc 03 §7):
    ///   1. Wait for connection state to reach `.handshaking` (service discovery complete).
    ///   2. Send HELLO (App→Dev) with protocol versions + capabilities.
    ///   3. Await HELLO_ACK (Dev→App) with device info + negotiated version + capabilities.
    ///   4. Parse device info, mark t0.
    ///   5. Send START_STREAM.
    ///   6. Transition to `.connected`.
    ///
    /// - Returns: the parsed DeviceInfo from HELLO_ACK.
    public func performHandshake() async throws -> DeviceInfo {
        try await waitUntilHandshakeReady(timeout: 5.0)

        // Step 1: Send HELLO
        HRSenseLogging.info(.protoCmd, "HANDSHAKE: sending HELLO")
        let appCaps = Capabilities(rawValue: AppCapabilities.current)
        let helloResp = try await bleDataSource.sendCommandAndWait(
            Command.hello(
                versions: ProtocolVersion.supportedVersions,
                capabilities: appCaps,
                needsACK: true
            ),
            timeout: 5.0
        )

        // Step 2: Parse HELLO_ACK
        guard case .command(let ack) = helloResp,
              ack.opCode == .helloAck,
              ack.flags.isResponse else {
            throw AppError.handshakeFailed(reason: "Invalid HELLO_ACK response")
        }
        HRSenseLogging.info(.protoCmd, "HANDSHAKE: received HELLO_ACK")

        // Extract device info from HELLO_ACK params
        var version: UInt8 = 1
        var caps: Capabilities = Capabilities(rawValue: 0)
        var model = ""
        var fw = ""

        for param in ack.params {
            switch param.tag {
            case .heartRate:  // tag 0x01 reused for protocol version
                if let v = param.value.first { version = v }
            case .capabilities:
                let bytes = Array(param.value.prefix(4))
                var rawValue: UInt32 = 0
                for (index, byte) in bytes.enumerated() {
                    rawValue |= UInt32(byte) << (index * 8)
                }
                caps = Capabilities(rawValue: rawValue)
            case .battery:    // tag 0x04 reused for model name
                model = String(bytes: param.value, encoding: .utf8) ?? ""
            case .sensorStatus:  // tag 0x05 reused for fw version
                fw = String(bytes: param.value, encoding: .utf8) ?? ""
            default:
                break
            }
        }

        let peripheralIdentifier = bleDataSource.connectedPeripheralIdentifier ?? UUID()
        let connectedDeviceName = bleDataSource.connectedDeviceInfo?.name ?? "HRSense Peripheral"

        // Use the actual peripheral identity from the connected BLE session.
        let deviceInfo = DeviceInfo(
            peripheralIdentifier: peripheralIdentifier,
            name: connectedDeviceName,
            model: model.isEmpty ? "Unknown" : model,
            firmwareVersion: fw.isEmpty ? "0.0.0" : fw,
            protocolVersion: version,
            capabilities: caps.rawValue
        )
        bleDataSource.dataParser.markT0()
        deviceInfoContinuation.yield(deviceInfo)
        metricsCollector.recordConnectionSuccess()
        HRSenseLogging.info(.protoCmd, "HANDSHAKE: device=\(model) fw=\(fw) version=\(version) caps=0x\(String(caps.rawValue, radix: 16))")

        // Step 3: Send START_STREAM
        HRSenseLogging.info(.protoCmd, "HANDSHAKE: sending START_STREAM")
        _ = try await bleDataSource.sendCommandAndWait(
            Command.startStream(sampleKinds: [DataKind.heartRate.rawValue, DataKind.waveform.rawValue]),
            timeout: 5.0
        )
        bleDataSource.completeHandshake(with: deviceInfo)

        return deviceInfo
    }

    public func restoreConnection(cachedDevice: DeviceInfo?) async throws -> DeviceInfo {
        metricsCollector.recordConnectionAttempt()

        guard bleDataSource.connectedPeripheralIdentifier != nil else {
            throw AppError.deviceNotFound
        }

        bleDataSource.beginRestoredConnectionValidation()

        let restoredInfo = try await readRestoredDeviceInfo(timeout: 3.0)
        if let cachedDevice, let restoredInfo {
            try validateRestoredDevice(restoredInfo, against: cachedDevice)
        }

        let deviceInfo = try await performHandshake()
        if let cachedDevice {
            try validateRestoredDevice(deviceInfo, against: cachedDevice)
        }

        bleDataSource.completeRestoration(with: deviceInfo)
        return deviceInfo
    }

    private func waitUntilHandshakeReady(timeout: TimeInterval) async throws {
        let deadline = ContinuousClock.now + .seconds(timeout)

        while ContinuousClock.now < deadline {
            let state = bleDataSource.connectionState
            switch state {
            case .handshaking, .connected:
                HRSenseLogging.info(.state, "HANDSHAKE gate ready: state=\(state)")
                return
            case .disconnected, .disconnecting:
                throw AppError.connectionLost
            default:
                break
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }

        throw AppError.connectionTimeout
    }

    private func readRestoredDeviceInfo(timeout: TimeInterval) async throws -> DeviceInfo? {
        let deadline = ContinuousClock.now + .seconds(timeout)

        while ContinuousClock.now < deadline {
            if let data = bleDataSource.latestDeviceInfoData,
               let info = parseRestoredDeviceInfo(from: data) {
                return info
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        return nil
    }

    private func parseRestoredDeviceInfo(from data: Data) -> DeviceInfo? {
        guard let rawObject = try? JSONSerialization.jsonObject(with: data),
              let object = rawObject as? [String: String] else {
            return nil
        }

        let peripheralIdentifier = bleDataSource.connectedPeripheralIdentifier ?? UUID()
        let name = bleDataSource.connectedDeviceInfo?.name ?? "HRSense Peripheral"
        let model = object["model"] ?? "Unknown"
        let firmwareVersion = object["firmwareVersion"] ?? "0.0.0"
        let protocolVersion = UInt8(object["protocolVersion"] ?? "") ?? 0

        return DeviceInfo(
            peripheralIdentifier: peripheralIdentifier,
            name: name,
            model: model,
            firmwareVersion: firmwareVersion,
            protocolVersion: protocolVersion,
            capabilities: bleDataSource.connectedDeviceInfo?.capabilities ?? 0
        )
    }

    private func validateRestoredDevice(_ restoredDevice: DeviceInfo, against cachedDevice: DeviceInfo) throws {
        guard restoredDevice.peripheralIdentifier == cachedDevice.peripheralIdentifier else {
            throw AppError.handshakeFailed(reason: "Restored peripheral identifier mismatch")
        }

        if !cachedDevice.model.isEmpty, !restoredDevice.model.isEmpty, restoredDevice.model != cachedDevice.model {
            throw AppError.handshakeFailed(reason: "Restored device model mismatch")
        }

        if cachedDevice.protocolVersion != 0,
           restoredDevice.protocolVersion != 0,
           restoredDevice.protocolVersion != cachedDevice.protocolVersion {
            throw AppError.handshakeFailed(reason: "Restored device protocol version mismatch")
        }

        if cachedDevice.capabilities != 0,
           restoredDevice.capabilities != 0,
           restoredDevice.capabilities != cachedDevice.capabilities {
            throw AppError.handshakeFailed(reason: "Restored device capabilities mismatch")
        }
    }
}

/// App-side capabilities to declare in HELLO.
private enum AppCapabilities {
    /// v1 app: heart rate + RR intervals + OTA + waveform support
    static let current: UInt32 = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 9) | (1 << 10)
}
