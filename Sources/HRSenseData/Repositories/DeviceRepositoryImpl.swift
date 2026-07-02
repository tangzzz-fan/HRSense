import Foundation
import HRSenseCore

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

    public init(bleDataSource: BLECentralDataSource) {
        self.bleDataSource = bleDataSource
        self.metricsCollector = bleDataSource.metricsCollector
    }

    public func startScanning() async {
        bleDataSource.startScanning()
    }

    public func stopScanning() {
        bleDataSource.stopScanning()
    }

    public func connect(to deviceID: UUID) async throws {
        bleDataSource.connect(to: deviceID)
    }

    public func disconnect() {
        bleDataSource.disconnect()
    }

    public func sendCommand(_ opcode: UInt8, payload: Data) async throws -> Data {
        try await bleDataSource.sendCommand(opcode, payload: payload)
    }
}
