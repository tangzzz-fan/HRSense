import XCTest
@testable import HRSenseFeature
@testable import HRSenseCore
import TGReduxKit

@MainActor
final class SleepMiddlewareTests: XCTestCase {
    private func makeStore(
        computeRepo: FakeComputeRepository = FakeComputeRepository(),
        sleepRepo: FakeSleepInferenceRepository,
        persistenceStore: FakePersistenceStore? = nil,
        now: Date = Date(timeIntervalSince1970: 1_725_000_000)
    ) -> Store<AppState, Action> {
        Store(
            initialState: AppState(),
            reducer: AppReducer.reduce,
            middlewares: [
                makeSleepMiddleware(
                    computeRepository: computeRepo,
                    sleepInferenceRepository: sleepRepo,
                    persistenceStore: persistenceStore,
                    windowDuration: 300,
                    nowProvider: { now }
                )
            ]
        )
    }

    func test_connectionStateChangesToggleSleepMonitoring() {
        let computeRepo = FakeComputeRepository()
        let sleepRepo = FakeSleepInferenceRepository()
        let now = Date(timeIntervalSince1970: 1_725_000_000)
        let store = makeStore(computeRepo: computeRepo, sleepRepo: sleepRepo, now: now)

        store.dispatch(.connectionStateChanged(.connected))
        XCTAssertTrue(store.state.sleep.isMonitoring)
        XCTAssertEqual(store.state.sleep.monitoringStartedAt, now)
        XCTAssertEqual(store.state.sleep.status, .monitoring)

        store.dispatch(.connectionStateChanged(.disconnected))
        XCTAssertFalse(store.state.sleep.isMonitoring)
        XCTAssertEqual(store.state.sleep.status, .idle)
    }

    func test_historyLoadRequestedQueriesPersistenceAndUpdatesState() async throws {
        let computeRepo = FakeComputeRepository()
        let sleepRepo = FakeSleepInferenceRepository()
        let persistenceStore = FakePersistenceStore()
        let session = SleepSession(
            date: Date(timeIntervalSince1970: 1_725_000_000),
            stages: [
                SleepStageSegment(
                    stage: .deep,
                    startAt: Date(timeIntervalSince1970: 1_725_000_000),
                    endAt: Date(timeIntervalSince1970: 1_725_000_600)
                )
            ],
            modelVersion: "sleep-stage-fallback-v1"
        )
        await persistenceStore.seedSleepSessions([session])

        let store = makeStore(
            computeRepo: computeRepo,
            sleepRepo: sleepRepo,
            persistenceStore: persistenceStore
        )

        store.dispatch(.sleep(.historyLoadRequested(limit: 7)))
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(store.state.sleep.recentSessions, [session])
    }

    func test_hrvComputedBuildsWindowRunsInferenceAndPersistsSession() async throws {
        let computeRepo = FakeComputeRepository()
        computeRepo.nextSleepFeatures = SleepCXXFeatures(hrTrend: -0.33, circadianVariation: 0.0)
        let sleepRepo = FakeSleepInferenceRepository()
        let persistenceStore = FakePersistenceStore()
        let monitoringStart = Date(timeIntervalSince1970: 1_725_000_000)
        sleepRepo.nextPrediction = SleepStagePrediction(
            stage: .rem,
            confidence: 0.68,
            probabilities: [.rem: 0.68, .light: 0.18, .deep: 0.08, .wake: 0.06],
            modelVersion: "sleep-stage-fallback-v1",
            timestamp: monitoringStart.addingTimeInterval(300)
        )

        let store = makeStore(
            computeRepo: computeRepo,
            sleepRepo: sleepRepo,
            persistenceStore: persistenceStore,
            now: monitoringStart
        )

        store.dispatch(.connectionStateChanged(.connected))
        store.dispatch(.heartRateReceived([
            HeartRateSample(
                timestamp: monitoringStart.addingTimeInterval(60),
                heartRate: 61,
                rrIntervals: [980, 990]
            ),
            HeartRateSample(
                timestamp: monitoringStart.addingTimeInterval(300),
                heartRate: 58,
                rrIntervals: [1010, 995]
            ),
        ]))

        store.dispatch(.hrvComputed(
            HRVMetrics(
                rmssd: 70,
                hr: 57,
                lfPower: 300,
                hfPower: 460,
                lfHfRatio: 0.9,
                sampleEntropy: 1.35,
                stressIndex: 110
            )
        ))

        XCTAssertEqual(store.state.sleep.status, .inferring)
        try? await Task.sleep(nanoseconds: 300_000_000)

        let windowInput = try XCTUnwrap(store.state.sleep.latestWindowInput)
        let session = try XCTUnwrap(store.state.sleep.currentSession)

        XCTAssertEqual(sleepRepo.inferenceCallCount, 1)
        XCTAssertEqual(computeRepo.sleepFeatureCallCount, 1)
        XCTAssertEqual(computeRepo.lastHeartRates, [61, 58])
        XCTAssertEqual(computeRepo.lastHRVWindowValues.count, 1)
        XCTAssertEqual(computeRepo.lastHRVWindowValues.first ?? 0, 70, accuracy: 0.0001)
        XCTAssertEqual(windowInput.timeContext.minutesSinceSessionStart, 5)
        XCTAssertEqual(windowInput.timeContext.windowStart, monitoringStart.addingTimeInterval(60))
        XCTAssertEqual(windowInput.timeContext.windowEnd, monitoringStart.addingTimeInterval(300))
        XCTAssertEqual(windowInput.cxxFeatures.hrTrend, -0.33, accuracy: 0.0001)
        XCTAssertEqual(windowInput.cxxFeatures.circadianVariation, 0.0, accuracy: 0.0001)
        XCTAssertEqual(store.state.sleep.lastInference?.stage, .rem)
        XCTAssertEqual(store.state.sleep.status, .ready)
        XCTAssertEqual(session.stages.count, 1)
        XCTAssertEqual(session.stages.first?.stage, .rem)
        XCTAssertEqual(store.state.sleep.lastPersistedSessionID, session.id)

        let persistedSessions = try await persistenceStore.querySleepSessions(SleepSessionQuery())
        XCTAssertEqual(persistedSessions.count, 1)
        XCTAssertEqual(persistedSessions.first?.id, session.id)
    }

    func test_repeatedSameStageMergesIntoSingleSegment() async throws {
        let computeRepo = FakeComputeRepository()
        let sleepRepo = FakeSleepInferenceRepository()
        let persistenceStore = FakePersistenceStore()
        let monitoringStart = Date(timeIntervalSince1970: 1_725_000_000)
        let store = makeStore(
            computeRepo: computeRepo,
            sleepRepo: sleepRepo,
            persistenceStore: persistenceStore,
            now: monitoringStart
        )

        store.dispatch(.connectionStateChanged(.connected))
        store.dispatch(.heartRateReceived([
            HeartRateSample(timestamp: monitoringStart.addingTimeInterval(30), heartRate: 62, rrIntervals: [960]),
            HeartRateSample(timestamp: monitoringStart.addingTimeInterval(300), heartRate: 59, rrIntervals: [980]),
        ]))

        sleepRepo.nextPrediction = SleepStagePrediction(
            stage: .light,
            confidence: 0.64,
            probabilities: [.light: 0.64],
            modelVersion: "sleep-stage-fallback-v1",
            timestamp: monitoringStart.addingTimeInterval(300)
        )
        store.dispatch(.hrvComputed(HRVMetrics(rmssd: 42, hr: 60)))
        try? await Task.sleep(nanoseconds: 250_000_000)

        store.dispatch(.heartRateReceived([
            HeartRateSample(timestamp: monitoringStart.addingTimeInterval(600), heartRate: 57, rrIntervals: [1000]),
        ]))
        sleepRepo.nextPrediction = SleepStagePrediction(
            stage: .light,
            confidence: 0.66,
            probabilities: [.light: 0.66],
            modelVersion: "sleep-stage-fallback-v1",
            timestamp: monitoringStart.addingTimeInterval(600)
        )
        store.dispatch(.hrvComputed(HRVMetrics(rmssd: 45, hr: 58)))
        try? await Task.sleep(nanoseconds: 250_000_000)

        let session = try XCTUnwrap(store.state.sleep.currentSession)
        XCTAssertEqual(session.stages.count, 1)
        XCTAssertEqual(session.stages.first?.stage, .light)
        XCTAssertEqual(session.stages.first?.endAt, monitoringStart.addingTimeInterval(600))
        XCTAssertEqual(computeRepo.lastHRVWindowValues.count, 2)
        XCTAssertEqual(computeRepo.lastHRVWindowValues[0], 42, accuracy: 0.0001)
        XCTAssertEqual(computeRepo.lastHRVWindowValues[1], 45, accuracy: 0.0001)
    }
}
