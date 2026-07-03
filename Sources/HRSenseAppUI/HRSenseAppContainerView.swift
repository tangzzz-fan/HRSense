import SwiftUI
import HRSenseFeature
import TGReduxKit

@MainActor
public struct HRSenseAppContainerView: View {
    @State private var store: Store<AppState, Action>
#if DEBUG
    @StateObject private var diagnosticPanelModel: DiagnosticPanelModel
    @State private var isShowingDiagnostics = false
#endif

    public init() {
        let shell = AppComposition.makeAppShell()
        self.store = shell.store
#if DEBUG
        self._diagnosticPanelModel = StateObject(wrappedValue: shell.diagnosticPanelModel)
#endif
    }

    public var body: some View {
        RootView()
            .provideStore(store)
#if DEBUG
            .environmentObject(diagnosticPanelModel)
            .overlay(alignment: .topTrailing) {
                Button {
                    isShowingDiagnostics = true
                } label: {
                    Image(systemName: "stethoscope")
                        .font(.headline)
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding()
                .accessibilityLabel("Open Diagnostics")
            }
            .sheet(isPresented: $isShowingDiagnostics) {
                DiagnosticPanelView()
                    .environmentObject(diagnosticPanelModel)
            }
#endif
    }
}
