import SwiftUI
import HRSenseSimulatorKit

/// Public root view used by the macOS App shell.
public struct SimulatorRootView: View {
    @State private var viewModel: SimulatorViewModel

    public init(launchOptions: SimulatorLaunchOptions = SimulatorLaunchOptions()) {
        _viewModel = State(wrappedValue: SimulatorViewModel(launchOptions: launchOptions))
    }

    public var body: some View {
        SimulatorDashboardView(viewModel: viewModel)
            .frame(minWidth: 320, minHeight: 400)
            .onAppear {
                viewModel.handleLaunchOnAppear()
            }
    }
}
