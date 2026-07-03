import SwiftUI
import HRSenseSimulatorKit
import HRSenseSimulatorUI

@main
struct HRSenseSimulatorApp: App {
    private let launchOptions = SimulatorLaunchOptions.parse(arguments: CommandLine.arguments)

    var body: some Scene {
        WindowGroup {
            SimulatorRootView(launchOptions: launchOptions)
        }
    }
}
