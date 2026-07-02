/// Device state machine (pure function).
///
/// Defined in docs/05-simulator-macos §2.2:
///   Advertising → Connected → HandshakeDone → Streaming
///   Connected → HandshakeDone (HELLO → HELLO_ACK)
///   HandshakeDone → Streaming (START_STREAM)
///   Streaming → HandshakeDone (STOP_STREAM)
///   Any state → Advertising (disconnect)
public enum DeviceState: Equatable, Sendable {
    case advertising
    case connected
    case handshakeDone
    case streaming
}

/// Events that drive state transitions.
public enum DeviceStateEvent: Equatable, Sendable {
    case centralConnected
    case handshakeCompleted
    case streamStarted
    case streamStopped
    case disconnected
}

extension DeviceState {
    /// Pure-function transition: given current state and an event, return the next state.
    public func transition(on event: DeviceStateEvent) -> DeviceState {
        switch (self, event) {
        case (.advertising, .centralConnected):
            return .connected
        case (.connected, .handshakeCompleted):
            return .handshakeDone
        case (.handshakeDone, .streamStarted):
            return .streaming
        case (.streaming, .streamStopped):
            return .handshakeDone
        case (_, .disconnected):
            return .advertising
        default:
            // Invalid transition — stay in current state
            return self
        }
    }
}
