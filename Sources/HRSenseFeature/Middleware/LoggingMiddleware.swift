import Foundation
import HRSenseCore
import HRSenseProtocol
import TGReduxKit

/// Redux Middleware that logs every Action → State transition.
///
/// Maintains a ring buffer of the last N state transitions so that
/// crash reports can include recent state history.
public final class StateTransitionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    private var transitions: [String] = []

    public init(capacity: Int = 50) {
        self.capacity = capacity
    }

    public func record(_ transition: String) {
        lock.withLock {
            transitions.append(transition)
            if transitions.count > capacity {
                transitions.removeFirst(transitions.count - capacity)
            }
        }
    }

    public var recentTransitions: [String] {
        lock.withLock { Array(transitions) }
    }

    /// The singleton — used by both middleware and crash reporter.
    public static let shared = StateTransitionRecorder()
}

/// Factory: produces a Redux Logging Middleware.
public func makeLoggingMiddleware() -> Middleware<AppState, Action> {
    { store, action, next in
        next(action)
        let after = store.state

        let entry = "\(action) → connection=\(after.connection) hr=\(after.live.currentHeartRate ?? 0) err=\(after.error.map { String(describing: $0) } ?? "nil")"
        StateTransitionRecorder.shared.record(entry)

        if shouldEmitBackgroundLog(action: action, lifecycle: after.lifecycle) {
            HRSenseLogging.info(.state, entry)
        }
    }
}

private func shouldEmitBackgroundLog(action: Action, lifecycle: AppLifecycleState) -> Bool {
    guard lifecycle == .background else { return true }

    switch action {
    case .errorOccurred, .restoreInitiated, .restoreConnectionRestored, .restoreFailed, .connectionStateChanged:
        return true
    default:
        return false
    }
}
