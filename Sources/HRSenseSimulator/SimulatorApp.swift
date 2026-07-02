import SwiftUI
import HRSenseSimulatorKit

@main
struct SimulatorApp: App {
    @State private var viewModel = SimulatorViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 320, minHeight: 400)
                .onAppear {
                    // Check for headless mode
                    let args = CommandLine.arguments
                    if args.contains("--headless") {
                        if let idx = args.firstIndex(of: "--scenario"), idx + 1 < args.count {
                            let path = args[idx + 1]
                            viewModel.startHeadless(scenarioPath: path)
                        } else {
                            viewModel.startHeadless()
                        }
                    }
                }
        }
    }
}

// Process command-line arguments for headless mode
func parseHeadlessArgs() -> (headless: Bool, scenarioPath: String?) {
    let args = CommandLine.arguments
    let headless = args.contains("--headless")
    var path: String? = nil
    if let idx = args.firstIndex(of: "--scenario"), idx + 1 < args.count {
        path = args[idx + 1]
    }
    return (headless, path)
}
