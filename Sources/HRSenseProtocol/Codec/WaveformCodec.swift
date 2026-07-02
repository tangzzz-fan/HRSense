import Foundation

/// Encode / decode waveform blocks.
/// M1 placeholder — full implementation in M5.
public enum WaveformCodec {
    /// Encode a WaveformBlock into frame body bytes.
    public static func encode(_ block: WaveformBlock) -> [UInt8] {
        // Minimal wire format for testing round-trip property
        var result: [UInt8] = []
        result.append(block.waveformType)
        var sr = block.sampleRateHz.littleEndian; Swift.withUnsafeBytes(of: &sr) { result.append(contentsOf: $0) }
        var bs = block.blockSeq.littleEndian; Swift.withUnsafeBytes(of: &bs) { result.append(contentsOf: $0) }
        var st = block.startTimestampMs.littleEndian; Swift.withUnsafeBytes(of: &st) { result.append(contentsOf: $0) }
        result.append(block.sampleBits)
        let count = UInt16(block.samples.count).littleEndian
        Swift.withUnsafeBytes(of: count) { result.append(contentsOf: $0) }
        for s in block.samples {
            var sv = s.littleEndian
            Swift.withUnsafeBytes(of: &sv) { result.append(contentsOf: $0) }
        }
        return result
    }

    /// Decode frame body bytes into a WaveformBlock.
    public static func decode(body: [UInt8]) -> WaveformBlock? {
        guard body.count >= 14 else { return nil }
        let wType = body[0]
        let sr = UInt16(body[1]) | (UInt16(body[2]) << 8)
        let bs = UInt32(body[3]) | (UInt32(body[4]) << 8) | (UInt32(body[5]) << 16) | (UInt32(body[6]) << 24)
        let st = UInt32(body[7]) | (UInt32(body[8]) << 8) | (UInt32(body[9]) << 16) | (UInt32(body[10]) << 24)
        let sampleBits = body[11]
        let count = Int(UInt16(body[12]) | (UInt16(body[13]) << 8))
        guard body.count >= 14 + count * 2 else { return nil }
        var samples: [Int16] = []
        for i in 0..<count {
            let off = 14 + i * 2
            let sv = Int16(bitPattern: UInt16(body[off]) | (UInt16(body[off + 1]) << 8))
            samples.append(sv)
        }
        return WaveformBlock(
            waveformType: wType, sampleRateHz: sr, blockSeq: bs,
            startTimestampMs: st, sampleBits: sampleBits, samples: samples
        )
    }
}
