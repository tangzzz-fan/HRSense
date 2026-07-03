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
    private let devInfoCont: AsyncStream<DeviceInfo>.Continuation
    private let restoreCont: AsyncStream<[UUID]>.Continuation

    let connectionStateStream: AsyncStream<ConnectionState>
    let discoveredDevicesStream: AsyncStream<DeviceInfo>
    let heartRateStream: AsyncStream<HeartRateSample>
    let deviceInfoStream: AsyncStream<DeviceInfo>
    let restoredPeripheralIDsStream: AsyncStream<[UUID]>

    // Spy
    var scanCallCount = 0
    var connectCallIDs: [UUID] = []
    var disconnectCallCount = 0
    var connectedIDs: [UUID] = []
    var handshakeCallCount = 0
    var restoreCallCount = 0
    var emitConnectedAfterHandshake = false
    var handshakeResult: Result<DeviceInfo, Error> = .success(
        DeviceInfo(peripheralIdentifier: UUID(), name: "Test", model: "M1",
                   firmwareVersion: "1.0", protocolVersion: 1, capabilities: 0)
    )
    var restoreResult: Result<DeviceInfo, Error> = .success(
        DeviceInfo(peripheralIdentifier: UUID(), name: "Test", model: "M1",
                   firmwareVersion: "1.0", protocolVersion: 1, capabilities: 0)
    )

    init() {
        var cc: AsyncStream<ConnectionState>.Continuation!
        self.connectionStateStream = AsyncStream { cc = $0 }; self.connCont = cc!
        var dc: AsyncStream<DeviceInfo>.Continuation!
        self.discoveredDevicesStream = AsyncStream { dc = $0 }; self.discCont = dc!
        var hc: AsyncStream<HeartRateSample>.Continuation!
        self.heartRateStream = AsyncStream { hc = $0 }; self.hrCont = hc!
        var dic: AsyncStream<DeviceInfo>.Continuation!
        self.deviceInfoStream = AsyncStream { dic = $0 }; self.devInfoCont = dic!
        var ric: AsyncStream<[UUID]>.Continuation!
        self.restoredPeripheralIDsStream = AsyncStream { ric = $0 }; self.restoreCont = ric!
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

    func performHandshake() async throws -> DeviceInfo {
        handshakeCallCount += 1
        switch handshakeResult {
        case .success(let info):
            devInfoCont.yield(info)
            if emitConnectedAfterHandshake {
                emitConnectionState(.connected)
            }
            return info
        case .failure(let error):
            throw error
        }
    }

    func restoreConnection(cachedDevice: DeviceInfo?) async throws -> DeviceInfo {
        restoreCallCount += 1
        switch restoreResult {
        case .success(let info):
            devInfoCont.yield(info)
            emitConnectionState(.restoredConnected)
            return info
        case .failure(let error):
            throw error
        }
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

    func emitDeviceInfo(_ info: DeviceInfo) {
        devInfoCont.yield(info)
    }

    func emitRestoredPeripheralIDs(_ ids: [UUID]) {
        restoreCont.yield(ids)
    }
}

final class FakeComputeRepository: ComputeRepository, @unchecked Sendable {
    var computeCallCount = 0
    var sleepFeatureCallCount = 0
    var shouldThrow = false
    var nextSleepFeatures = SleepCXXFeatures(hrTrend: -0.25, circadianVariation: 0.42)
    var lastHeartRates: [Int] = []
    var lastHRVWindowValues: [Double] = []

    func computeHRV(from rrIntervalsMs: [Int]) throws -> HRVMetrics {
        computeCallCount += 1
        if shouldThrow { throw AppError.computeFailed }
        return HRVMetrics(sdnn: 50, rmssd: 30)
    }

    func computeSleepFeatures(
        heartRates: [Int],
        hrvWindowValues: [Double]
    ) throws -> SleepCXXFeatures {
        sleepFeatureCallCount += 1
        lastHeartRates = heartRates
        lastHRVWindowValues = hrvWindowValues
        if shouldThrow { throw AppError.computeFailed }
        return nextSleepFeatures
    }
}

final class FakeInferenceRepository: InferenceRepository, @unchecked Sendable {
    var inferenceCallCount = 0
    var lastReceivedFeatures: [Float] = []
    var shouldThrow = false

    func runInference(features: [Float]) async throws -> InferenceResult {
        inferenceCallCount += 1
        lastReceivedFeatures = features
        if shouldThrow { throw AppError.inferenceFailed }
        return InferenceResult(label: "Baseline", probabilities: ["Baseline": 0.75], modelVersion: "1.0")
    }
}

final class FakeSleepInferenceRepository: SleepInferenceRepository, @unchecked Sendable {
    var inferenceCallCount = 0
    var lastReceivedInput: SleepWindowInput?
    var shouldThrow = false
    var nextPrediction = SleepStagePrediction(
        stage: .light,
        confidence: 0.64,
        probabilities: [.light: 0.64, .rem: 0.18, .deep: 0.12, .wake: 0.06],
        modelVersion: "sleep-stage-fallback-v1"
    )

    func inferSleepStage(input: SleepWindowInput) async throws -> SleepStagePrediction {
        inferenceCallCount += 1
        lastReceivedInput = input
        if shouldThrow { throw AppError.sleepInferenceFailed }
        return nextPrediction
    }
}

actor FakePersistenceStore: PersistenceStore {
    private(set) var savedSleepSessions: [SleepSession] = []
    var shouldThrowOnSleepSave = false

    func saveSession(_ session: Session) async throws {}
    func saveHeartRateSamples(_ samples: [HeartRateSampleRecord]) async throws {}
    func saveRRSamples(_ samples: [RRSampleRecord]) async throws {}
    func saveHRVMetrics(_ records: [HRVMetricRecord]) async throws {}
    func saveInferenceRecords(_ records: [InferenceRecord]) async throws {}

    func saveSleepSession(_ session: SleepSession) async throws {
        if shouldThrowOnSleepSave {
            throw AppError.persistenceFailed(reason: "Fake persistence failure")
        }
        savedSleepSessions.append(session)
    }

    func saveWaveformBlobRefs(_ refs: [WaveformBlobRef]) async throws {}
    func saveEventRecords(_ records: [EventRecord]) async throws {}

    func querySessions(_ query: SessionQuery) async throws -> [Session] { [] }
    func queryHeartRate(_ query: HeartRateQuery) async throws -> [HeartRateSampleRecord] { [] }
    func queryHRVMetrics(_ query: HRVMetricQuery) async throws -> [HRVMetricRecord] { [] }
    func querySleepSessions(_ query: SleepSessionQuery) async throws -> [SleepSession] {
        var sessions = savedSleepSessions
        if let range = query.dateRange {
            sessions = sessions.filter { range.contains($0.date) }
        }
        if let limit = query.limit {
            sessions = Array(sessions.prefix(limit))
        }
        return sessions
    }

    func aggregateHeartRate(
        sessionID: UUID,
        interval: HeartRateAggregationInterval,
        range: TimeRange?
    ) async throws -> [HeartRateAggregationBucket] {
        []
    }

    func purgeExpiredData(
        now: Date,
        policy: RetentionPolicy
    ) async throws -> StoragePurgeResult {
        StoragePurgeResult()
    }

    func seedSleepSessions(_ sessions: [SleepSession]) {
        savedSleepSessions = sessions
    }
}
