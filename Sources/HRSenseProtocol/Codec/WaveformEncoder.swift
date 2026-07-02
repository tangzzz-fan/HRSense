import Foundation

/// Encodes waveform blocks into GATT fragments optimised for high throughput.
///
/// Unlike DataCodec (which encodes DeviceSample → TLV → frame),
/// WaveformEncoder produces the full frame body (DataKind=0x02 + TLV) and
/// delegates to FrameEncoder for fragmentation.
///
/// Key throughput optimisations:
///   - MTU dynamic padding: computes max samples per block based on negotiated MTU
///   - Single-frame blocks: when block ≤ MTU, one notify = one complete frame
///   - Block-level loss detection: blockSeq enables gap detection without per-sample ACK
public enum WaveformEncoder {

    /// Encode a WaveformBlock into GATT fragments.
    /// - Parameters:
    ///   - block: the waveform data block.
    ///   - seq: frame sequence number (0–255).
    ///   - mtu: negotiated ATT MTU.
    /// - Returns: fragments ready for GATT notify.
    public static func encode(block: WaveformBlock, seq: UInt8, mtu: Int) -> [Data] {
        // Frame body: DataKind(1B) + TLV records
        var body: [UInt8] = []
        body.append(DataKind.waveform.rawValue)  // 0x02
        body.append(contentsOf: WaveformCodec.encode(block))

        return FrameEncoder.encode(type: .data, body: body, seq: seq, mtu: mtu)
    }

    /// Calculate maximum samples that fit in one block for a given MTU.
    /// - Parameters:
    ///   - mtu: negotiated ATT MTU.
    ///   - sampleBits: bits per sample (12 or 16).
    /// - Returns: max samples per block.
    public static func maxSamplesPerBlock(mtu: Int, sampleBits: Int = 16) -> Int {
        let headerOverhead = 2  // FragHdr + seq
        let frameOverhead = 4   // Ver + Type + CRC16
        let tlvOverhead = 2 * 6 // ~2 bytes per TLV tag+len (6 fields)
        let dataKindOverhead = 1
        let usablePerFrag = mtu - headerOverhead

        // Conservative: assume single-fragment block
        let payloadCapacity = usablePerFrag - frameOverhead - tlvOverhead - dataKindOverhead
        let bytesPerSample = sampleBits / 8
        return max(1, payloadCapacity / bytesPerSample)
    }
}
