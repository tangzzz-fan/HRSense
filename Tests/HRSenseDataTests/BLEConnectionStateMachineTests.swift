import XCTest
@testable import HRSenseData

final class BLEConnectionStateMachineTests: XCTestCase {

    func test_initialState() {
        let sm = BLEConnectionStateMachine()
        XCTAssertEqual(sm.state, .idle)
    }

    func test_transition() {
        let sm = BLEConnectionStateMachine()
        sm.transition(to: .connecting)
        XCTAssertEqual(sm.state, .connecting)
    }

    func test_backoffResetsOnConnected() {
        let sm = BLEConnectionStateMachine()
        _ = sm.nextBackoff()  // 1
        _ = sm.nextBackoff()  // 2
        sm.transition(to: .connected)
        XCTAssertEqual(sm.nextBackoff(), 1)
    }

    func test_backoffExponential() {
        let sm = BLEConnectionStateMachine()
        XCTAssertEqual(sm.nextBackoff(), 1)
        XCTAssertEqual(sm.nextBackoff(), 2)
        XCTAssertEqual(sm.nextBackoff(), 4)
        XCTAssertEqual(sm.nextBackoff(), 8)
    }

    func test_backoffCapsAt60() {
        let sm = BLEConnectionStateMachine()
        for _ in 0..<20 { _ = sm.nextBackoff() }
        XCTAssertEqual(sm.nextBackoff(), 60)
    }

    func test_resetBackoff() {
        let sm = BLEConnectionStateMachine()
        _ = sm.nextBackoff(); _ = sm.nextBackoff(); _ = sm.nextBackoff() // → 4
        sm.resetBackoff()
        XCTAssertEqual(sm.nextBackoff(), 1)
    }
}
