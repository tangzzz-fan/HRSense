import Foundation

/// The fully-decoded frame delivered by FrameAssembler after reassembly.
public enum DecodedFrame: Equatable, Sendable {
    /// L3 command frame (App→Dev or Dev→App).
    case command(Command)
    /// L4 data frame — heart rate sample (DataKind=0x01).
    case data(DeviceSample)
    /// L4 data frame — waveform block (DataKind=0x02).
    case waveform(WaveformBlock)
    /// ACK frame.
    case ack(ACKPayload)
    /// Device-initiated event.
    case event(DeviceEvent)
}
