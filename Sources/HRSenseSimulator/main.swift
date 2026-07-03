import Foundation
import HRSenseSimulatorKit

let parsedOptions = SimulatorLaunchOptions.parse(arguments: CommandLine.arguments)
let launchOptions = SimulatorLaunchOptions(
    launchMode: .headless,
    scenarioPath: parsedOptions.scenarioPath,
    generatorMode: parsedOptions.generatorMode,
    autoStartAdvertising: parsedOptions.autoStartAdvertising,
    autoStartStream: parsedOptions.autoStartStream
)

let runner = SimulatorHeadlessRunner(launchOptions: launchOptions)

do {
    try runner.start()
    dispatchMain()
} catch {
    fputs("HRSenseSimulator failed: \(error)\n", stderr)
    Foundation.exit(1)
}
