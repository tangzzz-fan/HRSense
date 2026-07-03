import XCTest
@testable import HRSenseFeature
@testable import HRSenseCore
import TGReduxKit

@MainActor
final class BLEStreamMiddlewareTests: XCTestCase {

    func makeStore(repo: FakeDeviceRepository, throttle: TimeInterval = 0.1) -> Store<AppState, Action> {
        Store(
            initialState: AppState(),
            reducer: AppReducer.reduce,
            middlewares: [makeBLEStreamMiddleware(deviceRepo: repo, throttleInterval: throttle)]
        )
    }

    // MARK: - Subscription

    func test_subscribesOnlyWhenConnected() async {
        let repo = FakeDeviceRepository()
        let store = makeStore(repo: repo)
        let sample = HeartRateSample(timestamp: Date(), heartRate: 72)
        repo.emitHeartRateSample(sample)
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(store.state.live.currentHeartRate)
    }

    func test_dispatchesHeartRateReceived_whenSamplesArrive() async {
        let repo = FakeDeviceRepository()
        let store = makeStore(repo: repo)
        store.dispatch(.connectionStateChanged(.connected))
        let sample = HeartRateSample(timestamp: Date(), heartRate: 72)
        repo.emitHeartRateSample(sample)
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(store.state.live.currentHeartRate, 72)
    }

    func test_dispatchesHeartRateReceived_afterRestoredConnected() async {
        let repo = FakeDeviceRepository()
        let store = makeStore(repo: repo)
        store.dispatch(.connectionStateChanged(.restoredConnected))
        let sample = HeartRateSample(timestamp: Date(), heartRate: 75)
        repo.emitHeartRateSample(sample)
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(store.state.live.currentHeartRate, 75)
    }

    // MARK: - Throttling

    func test_throttling_respectsInterval() async {
        let repo = FakeDeviceRepository()
        let store = makeStore(repo: repo, throttle: 0.5)
        store.dispatch(.connectionStateChanged(.connected))
        for i in 1...3 {
            repo.emitHeartRateSample(HeartRateSample(timestamp: Date(), heartRate: 60 + i))
        }
        try? await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertNotNil(store.state.live.currentHeartRate)
    }
}
