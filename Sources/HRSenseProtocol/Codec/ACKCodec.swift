import Foundation

/// Encode / decode ACK frames (Type=0x03).
///
/// ACK frame body: seq(1B) | opcode(1B) | status(1B)
public enum ACKCodec {
    /// Encode an ACKPayload into frame body bytes.
    public static func encode(_ ack: ACKPayload) -> [UInt8] {
        [ack.seq, ack.opcode, ack.status]
    }

    /// Decode frame body bytes into an ACKPayload.
    /// Returns nil if body is too short.
    public static func decode(body: [UInt8]) -> ACKPayload? {
        guard body.count >= 3 else { return nil }
        return ACKPayload(seq: body[0], opcode: body[1], status: body[2])
    }
}
