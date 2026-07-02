import Foundation

/// Encodes frames into GATT fragment sequences.
///
/// A frame is:
///   [Ver(1B)] [Type(1B)] [Frame Body (variable)] [CRC16 LE(2B)]
///
/// The encoded frame is then split into fragments, each prepended with
/// a FragmentHeader(1B) + seq(1B).
public enum FrameEncoder {
    /// Encode a frame body (Type + Body) into fragments.
    /// - Parameters:
    ///   - type: frame type (command / data / ack / event).
    ///   - body: the frame body bytes (for L3: opcode+flags+tlv; for L4: datakind+tlv).
    ///   - seq: frame sequence number (0–255).
    ///   - mtu: current MTU (payload capacity per GATT write).
    ///   - version: protocol version (default v1 = 0x01).
    /// - Returns: array of Data fragments, each sized ≤ mtu.
    public static func encode(
        type: FrameType,
        body: [UInt8],
        seq: UInt8,
        mtu: Int,
        version: UInt8 = ProtocolVersion.v1
    ) -> [Data] {
        // 1. Build full frame: Ver + Type + Body + CRC16
        var frame: [UInt8] = []
        frame.append(version)
        frame.append(type.rawValue)
        frame.append(contentsOf: body)
        let crc = CRC16.compute(frame)
        var crcLE = crc.littleEndian
        Swift.withUnsafeBytes(of: &crcLE) { ptr in
            frame.append(contentsOf: ptr)
        }

        // 2. Split into fragments
        // Each fragment: 1B FragHdr + 1B seq + payload
        let headerSize = 2
        let maxPayload = max(mtu - headerSize, 1)
        let totalLen = frame.count
        let fragCount = (totalLen + maxPayload - 1) / maxPayload

        var fragments: [Data] = []
        for i in 0..<max(fragCount, 0) {
            let start = i * maxPayload
            let end = min(start + maxPayload, totalLen)
            if start >= totalLen { break }

            let isStart = (i == 0)
            let isEnd = (i == fragCount - 1)
            let fragIdx = UInt8(i & 0x3F)

            let hdr = FragmentHeader(start: isStart, end: isEnd, fragIndex: fragIdx)

            var frag: [UInt8] = []
            frag.append(hdr.rawValue)
            frag.append(seq)
            frag.append(contentsOf: frame[start..<end])
            fragments.append(Data(frag))
        }

        return fragments
    }
}
