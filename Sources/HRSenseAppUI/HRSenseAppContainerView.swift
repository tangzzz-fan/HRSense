import SwiftUI
import HRSenseFeature
import HRSenseData
import TGReduxKit

public struct HRSenseAppContainerView: View {
    @State private var store: Store<AppState, Action>
    @State private var storeWrapper: StoreWrapper<AppState, Action>

    public init() {
        let bleDataSource = BLECentralDataSource()
        let deviceRepo = DeviceRepositoryImpl(bleDataSource: bleDataSource)
        let computeRepo = ComputeRepositoryImpl()
        let inferenceRepo = InferenceRepositoryImpl()

        let middleware: [Middleware<AppState, Action>] = [
            makeConnectionMiddleware(deviceRepo: deviceRepo),
            makeBLEStreamMiddleware(deviceRepo: deviceRepo),
            makeComputeMiddleware(computeRepo: computeRepo, inferenceRepo: inferenceRepo),
            makeInferenceMiddleware(inferenceRepo: inferenceRepo),
        ]

        let store = Store(
            initialState: AppState(),
            reducer: AppReducer.reduce,
            middlewares: middleware
        )

        self.store = store
        self.storeWrapper = StoreWrapper(state: store.state, dispatch: { store.dispatch($0) })
    }

    public var body: some View {
        RootView()
            .environmentObject(storeWrapper)
    }
}
