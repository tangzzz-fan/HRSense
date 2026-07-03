import Foundation
import HRSenseCore

/// Test doubles for Feature layer testing.
/// These provide controllable AsyncStream-based fakes that middleware can subscribe to.

final class FakeDeviceRepository: DeviceRepository, @unchecked Sendable {

    // State
    var currentConnectionState: ConnectionState = .idle
    var connectionState: ConnectionState { currentConnectionState }

    // Streams
    private let connCont: AsyncStream<ConnectionState>.Continuation
    private let discCont: AsyncStream<DeviceInfo>.Continuation
    private let hrCont: AsyncStream<HeartRateSample>.Continuation

    let connectionStateStream: AsyncStream<ConnectionState>
    let discoveredDevicesStream: AsyncStream<DeviceInfo>
    let heartRateStream: AsyncStream<HeartRateSample>

    // Spy
    var scanCallCount = 0
    var connectCallIDs: [UUID] = []
    var disconnectCallCount = 0
    var connectedIDs: [UUID] = []

    init() {
        var cc: AsyncStream<ConnectionState>.Continuation!
        self.connectionStateStream = AsyncStream { cc = $0 }; self.connCont = cc!
        var dc: AsyncStream<DeviceInfo>.Continuation!
        self.discoveredDevicesStream = AsyncStream { dc = $0 }; self.discCont = dc!
        var hc: AsyncStream<HeartRateSample>.Continuation!
        self.heartRateStream = AsyncStream { hc = $0 }; self.hrCont = hc!
    }

    func startScanning() async {
        scanCallCount += 1
    }

    func stopScanning() {
    }

    func connect(to deviceID: UUID) async throws {
        connectCallIDs.append(deviceID)
    }

    func disconnect() {
        disconnectCallCount += 1
    }

    func sendCommand(_ opcode: UInt8, payload: Data) async throws -> Data {
        return payload
    }

    // Test helpers
    func emitConnectionState(_ state: ConnectionState) {
        currentConnectionState = state
        connCont.yield(state)
    }

    func emitDiscoveredDevice(_ device: DeviceInfo) {
        discCont.yield(device)
    }

    func emitHeartRateSample(_ sample: HeartRateSample) {
        hrCont.yield(sample)
    }
}

final class FakeComputeRepository: ComputeRepository, @unchecked Sendable {
    var computeCallCount = 0
    var shouldThrow = false

    func computeHRV(from rrIntervalsMs: [Int]) throws -> HRVMetrics {
        computeCallCount += 1
        if shouldThrow { throw AppError.computeFailed }
        return HRVMetrics(sdnn: 50, rmssd: 30)
    }
}

final class FakeInferenceRepository: InferenceRepository, @unchecked Sendable {
    var inferenceCallCount = 0

    func runInference(features: [Float]) async throws -> InferenceResult {
        inferenceCallCount += 1
        return InferenceResult(label: "Baseline", probabilities: ["Baseline": 0.75], modelVersion: "1.0")
    }
}
