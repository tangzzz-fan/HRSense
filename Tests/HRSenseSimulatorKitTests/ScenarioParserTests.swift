import XCTest
@testable import HRSenseSimulatorKit
import Foundation

final class ScenarioParserTests: XCTestCase {

    func test_parseScenario() throws {
        let json = """
        {
          "name": "Test",
          "description": "A test scenario",
          "steps": [
            {"action": "startStream", "delayMs": 500, "heartRate": null, "fault": null},
            {"action": "wait", "delayMs": 1000, "heartRate": null, "fault": null},
            {"action": "stopStream", "delayMs": 0, "heartRate": null, "fault": null}
          ]
        }
        """
        let scenario = try ScenarioParser.parse(json: json)
        XCTAssertEqual(scenario.name, "Test")
        XCTAssertEqual(scenario.steps.count, 3)
        XCTAssertEqual(scenario.steps[0].action, .startStream)
        XCTAssertEqual(scenario.steps[0].delayMs, 500)
        XCTAssertEqual(scenario.steps[1].action, .wait)
        XCTAssertEqual(scenario.steps[2].action, .stopStream)
    }
}
