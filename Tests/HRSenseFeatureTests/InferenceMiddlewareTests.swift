import XCTest
@testable import HRSenseFeature
@testable import HRSenseCore
import TGReduxKit

@MainActor
final class InferenceMiddlewareTests: XCTestCase {
    private func makeStore(
        inferenceRepo: FakeInferenceRepository
    ) -> Store<AppState, Action> {
        Store(
            initialState: AppState(),
            reducer: AppReducer.reduce,
            middlewares: [makeInferenceMiddleware(inferenceRepo: inferenceRepo)]
        )
    }

    func test_featuresExtracted_triggersInferenceCompleted() async {
        let inferenceRepo = FakeInferenceRepository()
        let store = makeStore(inferenceRepo: inferenceRepo)
        let featureVector = FeatureVector(values: Array(repeating: 1.0, count: FeatureVector.dim))

        store.dispatch(.featuresExtracted(featureVector))

        XCTAssertEqual(store.state.inference.latestFeatures, featureVector)
        XCTAssertEqual(store.state.inference.status, .running)
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(inferenceRepo.inferenceCallCount, 1)
        XCTAssertEqual(inferenceRepo.lastReceivedFeatures, featureVector.values)
        XCTAssertEqual(store.state.inference.status, .completed)
        XCTAssertEqual(store.state.inference.latestResult?.label, "Baseline")
    }

    func test_inferenceError_dispatchesErrorAndResetsRunningState() async {
        let inferenceRepo = FakeInferenceRepository()
        inferenceRepo.shouldThrow = true
        let store = makeStore(inferenceRepo: inferenceRepo)
        let featureVector = FeatureVector(values: Array(repeating: 2.0, count: FeatureVector.dim))

        store.dispatch(.featuresExtracted(featureVector))

        XCTAssertEqual(store.state.inference.status, .running)
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(store.state.error, .inferenceFailed)
        XCTAssertEqual(store.state.inference.status, .idle)
    }
}
