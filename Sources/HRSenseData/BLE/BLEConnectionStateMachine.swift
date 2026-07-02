import Foundation
import HRSenseCore

/// BLE connection state machine with exponential backoff for reconnection.
///
/// Manages transitions: idle → scanning → connecting → handshaking → connected → disconnecting → disconnected.
/// Reconnection uses exponential backoff: 1s → 2s → 4s → … → 60s (capped).
/// Reset to 1s on successful connection.
public final class BLEConnectionStateMachine: @unchecked Sendable {
    private let lock = NSLock()

    private var _state: HRSenseCore.ConnectionState = .idle
    private var _backoffSeconds: Int = 1
    private let maxBackoffSeconds: Int = 60

    public init() {}

    public var state: HRSenseCore.ConnectionState {
        lock.withLock { _state }
    }

    @discardableResult
    public func transition(to newState: HRSenseCore.ConnectionState) -> HRSenseCore.ConnectionState {
        lock.withLock {
            _state = newState
            if newState == .connected {
                _backoffSeconds = 1
            }
            return _state
        }
    }

    public func nextBackoff() -> Int {
        lock.withLock {
            let current = _backoffSeconds
            _backoffSeconds = min(_backoffSeconds * 2, maxBackoffSeconds)
            return current
        }
    }

    public func resetBackoff() {
        lock.withLock { _backoffSeconds = 1 }
    }
}
