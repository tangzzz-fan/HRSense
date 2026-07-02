/// Frame type identifiers.
///
/// Defined in v1 protocol contract (doc 03 §4.2):
///   - command = 0x01 (L3 session/command layer)
///   - data    = 0x02 (L4 application data layer)
///   - ack     = 0x03 (ACK frame)
///   - event   = 0x04 (device event frame)
public enum FrameType: UInt8, Equatable, Sendable, CaseIterable {
    case command = 0x01
    case data    = 0x02
    case ack     = 0x03
    case event   = 0x04
}
