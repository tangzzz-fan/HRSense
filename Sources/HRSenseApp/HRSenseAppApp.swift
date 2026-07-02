import SwiftUI
import HRSenseFeature
import HRSenseCore
import HRSenseData
import TGReduxKit

/// iOS App entry point + composition root.
/// Wires HRSenseData repositories into HRSenseFeature Redux store.
@main
struct HRSenseApp: App {
    @State private var store: Store<AppState, Action>
    @State private var storeWrapper: StoreWrapper<AppState, Action>

    init() {
        // Composition root: wire real BLE data source → repository → store
        let bleDataSource = BLECentralDataSource()
        let deviceRepo = DeviceRepositoryImpl(bleDataSource: bleDataSource)
        let computeRepo = ComputeRepositoryImpl()
        let inferenceRepo = InferenceRepositoryImpl()

        let middleware: [Middleware<AppState, Action>] = [
            makeConnectionMiddleware(deviceRepo: deviceRepo),
            makeBLEStreamMiddleware(deviceRepo: deviceRepo),
            makeComputeMiddleware(computeRepo: computeRepo),
            makeInferenceMiddleware(inferenceRepo: inferenceRepo),
        ]

        let s = Store(
            initialState: AppState(),
            reducer: AppReducer.reduce,
            middlewares: middleware
        )
        self.store = s
        self.storeWrapper = StoreWrapper(state: s.state, dispatch: { s.dispatch($0) })
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(storeWrapper)
        }
    }
}
