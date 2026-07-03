import XCTest
@testable import HRSenseCore

final class ConnectionStateTests: XCTestCase {
    func test_equatable() {
        XCTAssertEqual(ConnectionState.idle, ConnectionState.idle)
        XCTAssertNotEqual(ConnectionState.idle, ConnectionState.connected)
        XCTAssertNotEqual(ConnectionState.restored, ConnectionState.restoredConnected)
    }

    func test_description_includesRestorationStates() {
        XCTAssertEqual(ConnectionState.restored.description, "restored")
        XCTAssertEqual(ConnectionState.restoredValidating.description, "restoredValidating")
        XCTAssertEqual(ConnectionState.restoredConnected.description, "restoredConnected")
    }
}
