import XCTest
@testable import HRSenseCore

final class AppErrorTests: XCTestCase {

    func test_equatable() {
        let a = AppError.connectionTimeout
        let b = AppError.connectionTimeout
        XCTAssertEqual(a, b)
    }

    func test_notEqual() {
        XCTAssertNotEqual(AppError.connectionTimeout, AppError.connectionLost)
    }

    func test_associatedValues() {
        let err = AppError.handshakeFailed(reason: "version mismatch")
        if case let .handshakeFailed(reason) = err {
            XCTAssertEqual(reason, "version mismatch")
        } else {
            XCTFail("Expected .handshakeFailed")
        }
    }

    func test_localizedDescription_forCommandTimeout() {
        let description = AppError.commandTimeout(opcode: 0x01).localizedDescription
        XCTAssertEqual(description, "Command 0x1 timed out while waiting for a response.")
    }

    func test_localizedDescription_forHandshakeFailure() {
        let description = AppError.handshakeFailed(reason: "notify subscription did not become active").localizedDescription
        XCTAssertEqual(description, "Handshake failed: notify subscription did not become active")
    }
}
