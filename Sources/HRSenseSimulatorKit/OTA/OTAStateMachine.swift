import Foundation
import HRSenseProtocol

/// Device-side OTA state machine.
///
/// States: Idle → Preparing → Transferring → Validating → Applying → Rebooting
///
/// Single-direction flow — once in `applying`, no return path.
/// Reference: docs/07-ota-dfu.md.
public enum OTAState: Equatable, Sendable {
    case idle
    case preparing
    case transferring
    case validating
    case applying
    case rebooting

    /// Whether the state accepts OTA data windows.
    public var acceptsData: Bool {
        switch self {
        case .transferring: return true
        default: return false
        }
    }
}

/// Events that drive OTA state transitions.
public enum OTAStateEvent: Equatable, Sendable {
    case startReceived(imageSize: UInt32, imageCRC32: UInt32, newVersion: String)
    case windowTransferComplete
    case validateRequested
    case validationPassed
    case validationFailed
    case applyRequested
    case applyComplete
    case abortReceived
    case rebootComplete
}

/// Device-side OTA state machine — pure-function core.
public final class OTAStateMachine: @unchecked Sendable {
    private let lock = NSLock()
    private var _state: OTAState = .idle
    private var _currentVersion: String = "1.0.0"
    private var _targetVersion: String = ""
    private var _imageSize: UInt32 = 0
    private var _expectedCRC32: UInt32 = 0

    public init(currentVersion: String = "1.0.0") {
        self._currentVersion = currentVersion
    }

    public var state: OTAState { lock.withLock { _state } }
    public var currentVersion: String { lock.withLock { _currentVersion } }

    /// Transition the state machine. Returns the new state, or nil if invalid.
    @discardableResult
    public func handle(_ event: OTAStateEvent) -> OTAState {
        lock.lock(); defer { lock.unlock() }
        switch (_state, event) {
        case (.idle, .startReceived(let sz, let crc, let ver)):
            _imageSize = sz; _expectedCRC32 = crc; _targetVersion = ver
            _state = .preparing
        case (.preparing, .windowTransferComplete):
            _state = .transferring
        case (.transferring, .windowTransferComplete):
            break  // Stay in transferring
        case (.transferring, .validateRequested):
            _state = .validating
        case (.validating, .validationPassed):
            _state = .applying  // Await APPLY command
        case (.validating, .validationFailed):
            _state = .idle  // Back to idle on failure
        case (.applying, .applyRequested):
            break  // Already applying
        case (.applying, .applyComplete):
            _currentVersion = _targetVersion
            _state = .rebooting
        case (.rebooting, .rebootComplete):
            _state = .idle
        case (_, .abortReceived):
            _state = .idle
        default:
            break  // Invalid transition — ignore
        }
        return _state
    }

    public func reset() {
        lock.withLock { _state = .idle }
    }
}
