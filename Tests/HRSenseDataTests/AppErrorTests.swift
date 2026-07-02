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
}
