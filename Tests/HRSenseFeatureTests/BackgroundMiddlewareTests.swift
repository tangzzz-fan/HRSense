import XCTest
@testable import HRSenseFeature
@testable import HRSenseCore
import TGReduxKit

@MainActor
final class BackgroundMiddlewareTests: XCTestCase {
    private func makeStore(initialState: AppState) -> Store<AppState, Action> {
        Store(
            initialState: initialState,
            reducer: AppReducer.reduce,
            middlewares: [makeBackgroundMiddleware()]
        )
    }

    func test_enteringBackground_stopsUserScanning() {
        let store = makeStore(initialState: AppState(connection: .scanning))

        store.dispatch(.didEnterBackground)

        XCTAssertEqual(store.state.lifecycle, .background)
        XCTAssertEqual(store.state.connection, .idle)
    }

    func test_backgroundDropsStressInferenceActions() {
        let store = makeStore(initialState: AppState(lifecycle: .background))
        let featureVector = FeatureVector(values: Array(repeating: 1.0, count: FeatureVector.dim))

        store.dispatch(.featuresExtracted(featureVector))
        store.dispatch(.inferenceStarted)

        XCTAssertNil(store.state.inference.latestFeatures)
        XCTAssertEqual(store.state.inference.status, .idle)
    }

    func test_backgroundDropsComputeWhenSleepMonitoringDisabled() {
        let store = makeStore(initialState: AppState(lifecycle: .background))

        store.dispatch(.computeStarted)

        XCTAssertEqual(store.state.metrics.computationStatus, .idle)
    }

    func test_backgroundAllowsComputeWhenSleepMonitoringEnabled() {
        let initialState = AppState(
            lifecycle: .background,
            sleep: SleepState(isMonitoring: true)
        )
        let store = makeStore(initialState: initialState)
        let metrics = HRVMetrics(rmssd: 45, hr: 58)

        store.dispatch(.computeStarted)
        store.dispatch(.hrvComputed(metrics))

        XCTAssertEqual(store.state.metrics.computationStatus, .ready)
        XCTAssertEqual(store.state.metrics.latestHRV, metrics)
    }

    func test_backgroundDropsWaveformRenderingActions() {
        let store = makeStore(initialState: AppState(lifecycle: .background))
        let sample = WaveformSample(type: .ecg, sampleRateHz: 128, timestamp: Date(), value: 0.5)

        store.dispatch(.waveformSamplesReceived([sample]))
        store.dispatch(.waveformMetricsUpdated(WaveformMetrics()))

        XCTAssertEqual(store.state.waveform.ecgSamples.count, 0)
        XCTAssertFalse(store.state.waveform.isStreaming)
    }
}
