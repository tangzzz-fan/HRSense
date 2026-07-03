/// Domain enum: BLE connection state as observed by the App.
/// M3 baseline: idle/scanning/connecting/handshaking/connected/disconnecting/disconnected.
/// M10 will extend with restoring state.
public enum ConnectionState: Equatable, Sendable {
    case idle
    case scanning
    case connecting
    case handshaking
    case connected
    case restored
    case restoredValidating
    case restoredConnected
    case disconnecting
    case disconnected
}

extension ConnectionState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .idle: "idle"
        case .scanning: "scanning"
        case .connecting: "connecting"
        case .handshaking: "handshaking"
        case .connected: "connected"
        case .restored: "restored"
        case .restoredValidating: "restoredValidating"
        case .restoredConnected: "restoredConnected"
        case .disconnecting: "disconnecting"
        case .disconnected: "disconnected"
        }
    }
}
