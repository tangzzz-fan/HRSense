import XCTest
@testable import HRSenseData

final class HandshakeReadinessGateTests: XCTestCase {
    func test_doesNotEmitHandshakingBeforeNotifySubscriptionBecomesActive() {
        var gate = HandshakeReadinessGate()
        gate.markNotifyCharacteristicDiscovered()
        gate.markWriteCharacteristicDiscovered()

        XCTAssertFalse(gate.updateNotifySubscription(isActive: false))
        XCTAssertFalse(gate.hasEmittedHandshaking)
    }

    func test_emitsHandshakingOnceWhenWriteAndNotifyAreReady() {
        var gate = HandshakeReadinessGate()
        gate.markNotifyCharacteristicDiscovered()
        gate.markWriteCharacteristicDiscovered()

        XCTAssertTrue(gate.updateNotifySubscription(isActive: true))
        XCTAssertTrue(gate.hasEmittedHandshaking)
        XCTAssertFalse(gate.updateNotifySubscription(isActive: true))
    }

    func test_resetClearsReadinessState() {
        var gate = HandshakeReadinessGate()
        gate.markNotifyCharacteristicDiscovered()
        gate.markWriteCharacteristicDiscovered()
        _ = gate.updateNotifySubscription(isActive: true)

        gate.reset()

        XCTAssertFalse(gate.hasNotifyCharacteristic)
        XCTAssertFalse(gate.hasWriteCharacteristic)
        XCTAssertFalse(gate.isNotifySubscriptionActive)
        XCTAssertFalse(gate.hasEmittedHandshaking)
    }
}
