import Foundation

/// The fully-decoded frame delivered by FrameAssembler after reassembly.
public enum DecodedFrame: Equatable, Sendable {
    /// L3 command frame (App→Dev or Dev→App).
    case command(Command)
    /// L4 data frame (DeviceSample).
    case data(DeviceSample)
    /// ACK frame.
    case ack(ACKPayload)
    /// Device-initiated event.
    case event(DeviceEvent)
}
