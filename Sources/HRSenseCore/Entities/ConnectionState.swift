/// Domain enum: BLE connection state as observed by the App.
/// M3 baseline: idle/scanning/connecting/handshaking/connected/disconnecting/disconnected.
/// M10 will extend with restoring state.
public enum ConnectionState: Equatable, Sendable {
    case idle
    case scanning
    case connecting
    case handshaking
    case connected
    case disconnecting
    case disconnected
}
