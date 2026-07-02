import Foundation

/// OTA command opcodes (doc 07 + protocol contract doc 03 §5.2).
public enum OTAOpCode: UInt8, Equatable, Sendable {
    case otaStart         = 0x20
    case otaStartAck      = 0xA0
    case otaWindowBegin   = 0x21
    case otaWindowAck     = 0xA1
    case otaValidate      = 0x23
    case otaValidateResult = 0xA3
    case otaApply         = 0x24
    case otaAbort         = 0x25
}

/// M1 placeholder — full OTA command payloads implemented in M6.
public struct OTACommand: Equatable, Sendable {
    public let opCode: OTAOpCode
    /// TLV-encoded payload.
    public let payload: [UInt8]

    public init(opCode: OTAOpCode, payload: [UInt8]) {
        self.opCode = opCode
        self.payload = payload
    }
}
