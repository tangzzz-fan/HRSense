import Foundation

/// ACK frame body (Type=0x03).
/// Carries the sequence number of the frame being acknowledged, the opcode,
/// and a status byte.
public struct ACKPayload: Equatable, Sendable {
    /// Sequence number of the frame being ACK'd.
    public let seq: UInt8
    /// The opcode this ACK is responding to.
    public let opcode: UInt8
    /// Status code: 0x00 = success, non-zero = error.
    public let status: UInt8

    public init(seq: UInt8, opcode: UInt8, status: UInt8 = 0x00) {
        self.seq = seq
        self.opcode = opcode
        self.status = status
    }

    public var isSuccess: Bool { status == 0x00 }
}
