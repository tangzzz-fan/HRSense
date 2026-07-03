import XCTest
@testable import HRSenseData
@testable import HRSenseCore

final class BLECentralDataSourceConnectionTests: XCTestCase {
    func test_completeHandshake_transitionsStateMachineToConnected() async {
        let dataSource = BLECentralDataSource(bootstrapCentralManager: false)
        let expectedDevice = DeviceInfo(
            peripheralIdentifier: UUID(),
            name: "HRSense Simulator",
            model: "M2",
            firmwareVersion: "2.0.0",
            protocolVersion: 1,
            capabilities: 0x3
        )

        let expectation = expectation(description: "connected state emitted")

        Task {
            for await state in dataSource.connectionStateStream {
                if state == .connected {
                    expectation.fulfill()
                    break
                }
            }
        }

        dataSource.completeHandshake(with: expectedDevice)
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(dataSource.connectionStateMachine.state, .connected)
    }
}
