import XCTest
@testable import HRSenseSimulatorKit

final class DeviceStateMachineTests: XCTestCase {

    func test_initialState() {
        let state = DeviceState.advertising
        XCTAssertEqual(state, .advertising)
    }

    func test_advertisingToConnected() {
        let next = DeviceState.advertising.transition(on: .centralConnected)
        XCTAssertEqual(next, .connected)
    }

    func test_connectedToHandshakeDone() {
        let next = DeviceState.connected.transition(on: .handshakeCompleted)
        XCTAssertEqual(next, .handshakeDone)
    }

    func test_handshakeDoneToStreaming() {
        let next = DeviceState.handshakeDone.transition(on: .streamStarted)
        XCTAssertEqual(next, .streaming)
    }

    func test_streamingToHandshakeDone() {
        let next = DeviceState.streaming.transition(on: .streamStopped)
        XCTAssertEqual(next, .handshakeDone)
    }

    func test_anyStateToAdvertisingOnDisconnect() {
        let states: [DeviceState] = [.advertising, .connected, .handshakeDone, .streaming]
        for state in states {
            XCTAssertEqual(state.transition(on: .disconnected), .advertising,
                           "State \(state) should transition to .advertising on disconnect")
        }
    }

    func test_invalidTransition_returnsCurrent() {
        // connected → streamStarted is not valid (must go through handshakeDone)
        XCTAssertEqual(DeviceState.connected.transition(on: .streamStarted), .connected)
        // advertising → handshakeCompleted is not valid
        XCTAssertEqual(DeviceState.advertising.transition(on: .handshakeCompleted), .advertising)
    }
}
