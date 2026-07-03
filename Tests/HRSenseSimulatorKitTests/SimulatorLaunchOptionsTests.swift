import XCTest
@testable import HRSenseSimulatorKit

final class SimulatorLaunchOptionsTests: XCTestCase {

    func test_parseHeadlessScenarioAndMode() {
        let options = SimulatorLaunchOptions.parse(arguments: [
            "HRSenseSimulator",
            "--headless",
            "--scenario", "/tmp/example.json",
            "--mode", "anomaly"
        ])

        XCTAssertEqual(options.launchMode, .headless)
        XCTAssertEqual(options.scenarioPath, "/tmp/example.json")
        XCTAssertEqual(options.generatorMode, .anomaly)
        XCTAssertTrue(options.autoStartAdvertising)
        XCTAssertTrue(options.autoStartStream)
    }

    func test_parseAutoStartFlags() {
        let options = SimulatorLaunchOptions.parse(arguments: [
            "HRSenseSimulator",
            "--no-auto-advertising",
            "--no-auto-stream"
        ])

        XCTAssertEqual(options.launchMode, .ui)
        XCTAssertFalse(options.autoStartAdvertising)
        XCTAssertFalse(options.autoStartStream)
    }
}
