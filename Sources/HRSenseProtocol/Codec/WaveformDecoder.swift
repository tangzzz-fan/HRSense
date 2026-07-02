import Foundation

/// Decodes waveform data from a DecodedFrame (DataKind=0x02).
///
/// Extracted from DataCodec / FrameAssembler path — when the parser sees
/// a `.data` frame with DataKind=0x02, it routes through WaveformDecoder
/// instead of the standard DeviceSample decoder.
public enum WaveformDecoder {

    /// Attempt to decode a waveform block from a data frame body.
    /// The body must start with DataKind=0x02.
    /// - Parameter body: raw frame body bytes (after Ver + Type, before CRC).
    /// - Returns: a WaveformBlock, or nil on parse error.
    public static func decode(body: [UInt8]) -> WaveformBlock? {
        guard body.count >= 2 else { return nil }
        guard body[0] == DataKind.waveform.rawValue else { return nil }
        let tlvBytes = Array(body.dropFirst(1))
        return WaveformCodec.decode(body: tlvBytes)
    }
}
