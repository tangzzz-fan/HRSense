import XCTest
@testable import HRSenseFeature
@testable import HRSenseCore
import TGReduxKit

@MainActor
final class ComputeMiddlewareTests: XCTestCase {

    func makeStore(
        computeRepo: FakeComputeRepository,
        inferenceRepo: FakeInferenceRepository,
        window: TimeInterval = 300,
        step: TimeInterval = 0.1
    ) -> Store<AppState, Action> {
        Store(
            initialState: AppState(),
            reducer: AppReducer.reduce,
            middlewares: [makeComputeMiddleware(computeRepo: computeRepo, inferenceRepo: inferenceRepo, windowDuration: window, stepInterval: step)]
        )
    }

    // MARK: - RR accumulation

    func test_rrAccumulation_triggersCompute() async {
        let computeRepo = FakeComputeRepository()
        let inferenceRepo = FakeInferenceRepository()
        let store = makeStore(computeRepo: computeRepo, inferenceRepo: inferenceRepo)
        let samples = [
            HeartRateSample(timestamp: Date(), heartRate: 72, rrIntervals: [800, 820]),
            HeartRateSample(timestamp: Date(), heartRate: 73, rrIntervals: [790, 810]),
        ]
        store.dispatch(.heartRateReceived(samples))
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(computeRepo.computeCallCount, 1)
    }

    func test_computeTriggersInference() async {
        let computeRepo = FakeComputeRepository()
        let inferenceRepo = FakeInferenceRepository()
        let store = makeStore(computeRepo: computeRepo, inferenceRepo: inferenceRepo)
        let samples = [
            HeartRateSample(timestamp: Date(), heartRate: 72, rrIntervals: [800, 820]),
            HeartRateSample(timestamp: Date(), heartRate: 73, rrIntervals: [790, 810]),
        ]
        store.dispatch(.heartRateReceived(samples))
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(inferenceRepo.inferenceCallCount, 1)
        XCTAssertEqual(store.state.metrics.computationStatus, .ready)
        XCTAssertNotNil(store.state.metrics.latestHRV)
    }

    // MARK: - Clear samples

    func test_clearSamples_resetsBuffer() async {
        let computeRepo = FakeComputeRepository()
        let inferenceRepo = FakeInferenceRepository()
        let store = makeStore(computeRepo: computeRepo, inferenceRepo: inferenceRepo)
        let samples = [HeartRateSample(timestamp: Date(), heartRate: 72, rrIntervals: [800, 820])]
        store.dispatch(.heartRateReceived(samples))
        store.dispatch(.clearSamples)
        let samples2 = [HeartRateSample(timestamp: Date(), heartRate: 73, rrIntervals: [])]
        store.dispatch(.heartRateReceived(samples2))
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(computeRepo.computeCallCount, 1)
    }

    // MARK: - Error handling

    func test_computeError_dispatchesError() async {
        let computeRepo = FakeComputeRepository()
        computeRepo.shouldThrow = true
        let inferenceRepo = FakeInferenceRepository()
        let store = makeStore(computeRepo: computeRepo, inferenceRepo: inferenceRepo)
        let samples = [
            HeartRateSample(timestamp: Date(), heartRate: 72, rrIntervals: [800, 820]),
            HeartRateSample(timestamp: Date(), heartRate: 73, rrIntervals: [790, 810]),
        ]
        store.dispatch(.heartRateReceived(samples))
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(store.state.error, .computeFailed)
    }

    // MARK: - Step interval

    func test_stepInterval_preventsRecompute() async {
        let computeRepo = FakeComputeRepository()
        let inferenceRepo = FakeInferenceRepository()
        let store = Store(
            initialState: AppState(),
            reducer: AppReducer.reduce,
            middlewares: [makeComputeMiddleware(computeRepo: computeRepo, inferenceRepo: inferenceRepo, windowDuration: 300, stepInterval: 60)]
        )
        let samples = [
            HeartRateSample(timestamp: Date(), heartRate: 72, rrIntervals: [800, 820]),
            HeartRateSample(timestamp: Date(), heartRate: 73, rrIntervals: [790, 810]),
        ]
        store.dispatch(.heartRateReceived(samples))
        store.dispatch(.heartRateReceived(samples))
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(computeRepo.computeCallCount, 1)
    }
}
