import XCTest
@testable import HRSenseData

final class PendingCommandTimeoutCoordinatorTests: XCTestCase {
    func test_staleIdentityCannotTimeoutNewPendingCommand() {
        var coordinator = PendingCommandTimeoutCoordinator()
        let first = coordinator.register(opcode: 0x01)
        let second = coordinator.register(opcode: 0x03)

        XCTAssertFalse(coordinator.canTimeout(first))
        XCTAssertTrue(coordinator.canTimeout(second))
    }

    func test_clearMatchingIdentityRemovesPendingCommand() {
        var coordinator = PendingCommandTimeoutCoordinator()
        let identity = coordinator.register(opcode: 0x01)

        coordinator.clear(identity)

        XCTAssertNil(coordinator.pendingIdentity)
        XCTAssertFalse(coordinator.canTimeout(identity))
    }

    func test_clearIgnoresStaleIdentity() {
        var coordinator = PendingCommandTimeoutCoordinator()
        let first = coordinator.register(opcode: 0x01)
        let second = coordinator.register(opcode: 0x03)

        coordinator.clear(first)

        XCTAssertEqual(coordinator.pendingIdentity, second)
    }
}
