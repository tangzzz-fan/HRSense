import XCTest
@testable import HRSenseCore

final class ConnectionStateTests: XCTestCase {
    func test_equatable() {
        XCTAssertEqual(ConnectionState.idle, ConnectionState.idle)
        XCTAssertNotEqual(ConnectionState.idle, ConnectionState.connected)
    }
}
