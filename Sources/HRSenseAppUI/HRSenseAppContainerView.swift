import SwiftUI
import HRSenseFeature
import TGReduxKit

@MainActor
public struct HRSenseAppContainerView: View {
    @State private var store: Store<AppState, Action>

    public init() {
        self.store = AppComposition.makeStore()
    }

    public var body: some View {
        RootView()
            .provideStore(store)
    }
}
