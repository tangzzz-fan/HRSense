import Foundation

/// Encode / decode waveform blocks (DataKind=0x02).
///
/// Wire format (TLV, v1 protocol doc 03 §6.3):
///   Tag 0x10: waveformType    (u8)
///   Tag 0x11: sampleRateHz    (u16 LE)
///   Tag 0x12: blockSeq        (u32 LE)
///   Tag 0x13: startTimestampMs(u32 LE)
///   Tag 0x14: sampleBits      (u8)
///   Tag 0x15: samples         (i16[] LE, packed)
public enum WaveformCodec {

    /// Encode a WaveformBlock into TLV frame body bytes (without DataKind prefix).
    /// DataKind is prepended by the frame encoder / DataCodec layer.
    public static func encode(_ block: WaveformBlock) -> [UInt8] {
        var result: [UInt8] = []
        result.append(TLVTag.waveformType.rawValue)
        result.append(1)
        result.append(block.waveformType)

        result.append(TLVTag.sampleRate.rawValue)
        result.append(2)
        var sr = block.sampleRateHz.littleEndian
        Swift.withUnsafeBytes(of: &sr) { result.append(contentsOf: $0) }

        result.append(TLVTag.blockSeq.rawValue)
        result.append(4)
        var bs = block.blockSeq.littleEndian
        Swift.withUnsafeBytes(of: &bs) { result.append(contentsOf: $0) }

        result.append(TLVTag.startTimestamp.rawValue)
        result.append(4)
        var st = block.startTimestampMs.littleEndian
        Swift.withUnsafeBytes(of: &st) { result.append(contentsOf: $0) }

        result.append(TLVTag.sampleBits.rawValue)
        result.append(1)
        result.append(block.sampleBits)

        // Samples: i16 LE array. Count is implicit in value length.
        let sampleBytes = block.samples.count * 2
        result.append(TLVTag.samples.rawValue)
        result.append(UInt8(sampleBytes & 0xFF))
        for s in block.samples {
            var sv = s.littleEndian
            Swift.withUnsafeBytes(of: &sv) { result.append(contentsOf: $0) }
        }

        return result
    }

    /// Decode TLV bytes into a WaveformBlock.
    public static func decode(body: [UInt8]) -> WaveformBlock? {
        guard let records = try? TLVDecoder.decode(body) else { return nil }

        var wType: UInt8 = 1
        var sampleRateHz: UInt16 = 128
        var blockSeq: UInt32 = 0
        var startTimestampMs: UInt32 = 0
        var sampleBits: UInt8 = 16
        var samples: [Int16] = []

        for r in records {
            switch r.tag {
            case .waveformType:
                wType = r.value.first ?? 1
            case .sampleRate:
                sampleRateHz = decodeU16LE(r.value)
            case .blockSeq:
                blockSeq = decodeU32LE(r.value)
            case .startTimestamp:
                startTimestampMs = decodeU32LE(r.value)
            case .sampleBits:
                sampleBits = r.value.first ?? 16
            case .samples:
                var vals: [Int16] = []
                let bytes = r.value
                var i = 0
                while i + 1 < bytes.count {
                    let sv = Int16(bitPattern: UInt16(bytes[i]) | (UInt16(bytes[i + 1]) << 8))
                    vals.append(sv)
                    i += 2
                }
                samples = vals
            default:
                break
            }
        }

        return WaveformBlock(
            waveformType: wType, sampleRateHz: sampleRateHz, blockSeq: blockSeq,
            startTimestampMs: startTimestampMs, sampleBits: sampleBits, samples: samples
        )
    }

    /// Detect if we lost blocks between prevSeq and currentSeq.
    /// Returns the number of missing blocks (0 = consecutive).
    /// Handles u32 wrap-around correctly via wrapping subtraction.
    public static func detectBlockLoss(prevSeq: UInt32, currentSeq: UInt32) -> Int {
        // u32 wrapping diff correctly handles overflow:
        // 0xFFFFFFFE → 2: diff = 2 &- 0xFFFFFFFE = 4; gap = 3
        // 0xFFFFFFFF → 0: diff = 0 &- 0xFFFFFFFF = 1; gap = 0
        let diff = currentSeq.subtractingReportingOverflow(prevSeq).partialValue
        return max(0, Int(diff) - 1)
    }

    private static func decodeU16LE(_ bytes: [UInt8]) -> UInt16 {
        guard bytes.count >= 2 else { return bytes.first.map { UInt16($0) } ?? 0 }
        return UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
    }

    private static func decodeU32LE(_ bytes: [UInt8]) -> UInt32 {
        guard bytes.count >= 4 else {
            var v: UInt32 = 0
            for (i, b) in bytes.enumerated() { v |= UInt32(b) << (i * 8) }
            return v
        }
        return UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
    }
}
