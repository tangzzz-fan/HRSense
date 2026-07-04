import XCTest
@testable import HRSenseFeature
@testable import HRSenseCore
import TGReduxKit

@MainActor
final class ComputeMiddlewareTests: XCTestCase {

    func makeStore(
        computeRepo: FakeComputeRepository,
        window: TimeInterval = 300,
        step: TimeInterval = 0.1
    ) -> Store<AppState, Action> {
        Store(
            initialState: AppState(),
            reducer: AppReducer.reduce,
            middlewares: [makeComputeMiddleware(computeRepo: computeRepo, windowDuration: window, stepInterval: step)]
        )
    }

    // MARK: - RR accumulation

    func test_rrAccumulation_triggersCompute() async {
        let computeRepo = FakeComputeRepository()
        let store = makeStore(computeRepo: computeRepo)
        let samples = [
            HeartRateSample(timestamp: Date(), heartRate: 72, rrIntervals: [800, 820]),
            HeartRateSample(timestamp: Date(), heartRate: 73, rrIntervals: [790, 810]),
        ]
        store.dispatch(.heartRateReceived(samples))
        await assertEventually {
            computeRepo.computeCallCount == 1
        }
        XCTAssertEqual(computeRepo.computeCallCount, 1)
    }

    func test_computeDispatchesFeaturesExtracted() async {
        let computeRepo = FakeComputeRepository()
        let store = makeStore(computeRepo: computeRepo)
        let samples = [
            HeartRateSample(timestamp: Date(), heartRate: 72, rrIntervals: [800, 820]),
            HeartRateSample(timestamp: Date(), heartRate: 73, rrIntervals: [790, 810]),
        ]
        store.dispatch(.heartRateReceived(samples))
        await assertEventually {
            store.state.metrics.computationStatus == .ready &&
            store.state.metrics.latestHRV != nil &&
            store.state.inference.latestFeatures != nil
        }
        XCTAssertEqual(store.state.metrics.computationStatus, .ready)
        XCTAssertNotNil(store.state.metrics.latestHRV)
        XCTAssertNotNil(store.state.inference.latestFeatures)
        XCTAssertEqual(store.state.inference.latestFeatures?.values.count, FeatureVector.dim)
    }

    // MARK: - Clear samples

    func test_clearSamples_resetsBuffer() async {
        let computeRepo = FakeComputeRepository()
        let store = makeStore(computeRepo: computeRepo)
        let samples = [HeartRateSample(timestamp: Date(), heartRate: 72, rrIntervals: [800, 820])]
        store.dispatch(.heartRateReceived(samples))
        store.dispatch(.clearSamples)
        let samples2 = [HeartRateSample(timestamp: Date(), heartRate: 73, rrIntervals: [])]
        store.dispatch(.heartRateReceived(samples2))
        await assertEventually {
            computeRepo.computeCallCount == 1
        }
        XCTAssertEqual(computeRepo.computeCallCount, 1)
    }

    // MARK: - Error handling

    func test_computeError_dispatchesError() async {
        let computeRepo = FakeComputeRepository()
        computeRepo.shouldThrow = true
        let store = makeStore(computeRepo: computeRepo)
        let samples = [
            HeartRateSample(timestamp: Date(), heartRate: 72, rrIntervals: [800, 820]),
            HeartRateSample(timestamp: Date(), heartRate: 73, rrIntervals: [790, 810]),
        ]
        store.dispatch(.heartRateReceived(samples))
        await assertEventually {
            store.state.error == .computeFailed
        }
        XCTAssertEqual(store.state.error, .computeFailed)
    }

    // MARK: - Step interval

    func test_stepInterval_preventsRecompute() async {
        let computeRepo = FakeComputeRepository()
        let store = Store(
            initialState: AppState(),
            reducer: AppReducer.reduce,
            middlewares: [makeComputeMiddleware(computeRepo: computeRepo, windowDuration: 300, stepInterval: 60)]
        )
        let samples = [
            HeartRateSample(timestamp: Date(), heartRate: 72, rrIntervals: [800, 820]),
            HeartRateSample(timestamp: Date(), heartRate: 73, rrIntervals: [790, 810]),
        ]
        store.dispatch(.heartRateReceived(samples))
        store.dispatch(.heartRateReceived(samples))
        await assertEventually {
            computeRepo.computeCallCount == 1
        }
        XCTAssertEqual(computeRepo.computeCallCount, 1)
    }

    func test_computeStarted_setsComputingBeforeReady() async {
        let computeRepo = FakeComputeRepository()
        let store = makeStore(computeRepo: computeRepo, step: 60)
        let samples = [
            HeartRateSample(timestamp: Date(), heartRate: 72, rrIntervals: [800, 820]),
            HeartRateSample(timestamp: Date(), heartRate: 73, rrIntervals: [790, 810]),
        ]

        store.dispatch(.heartRateReceived(samples))

        XCTAssertEqual(store.state.metrics.computationStatus, .computing)
        await assertEventually {
            store.state.metrics.computationStatus == .ready
        }
        XCTAssertEqual(store.state.metrics.computationStatus, .ready)
    }
}
