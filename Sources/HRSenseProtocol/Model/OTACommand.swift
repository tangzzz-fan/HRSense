import Foundation

/// OTA command opcodes (doc 07 + protocol contract doc 03 §5.2).
///
/// Request range: 0x20–0x2F, Response range: 0xA0–0xAF.
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

/// OTA status codes returned by the device.
public enum OTAStatusCode: UInt8, Equatable, Sendable {
    case success          = 0x00
    case invalidImage     = 0x01
    case crcMismatch      = 0x02
    case lowBattery       = 0x03
    case downgradeDenied  = 0x04
    case windowOutOfOrder = 0x05
    case timeout          = 0x06
    case applyFailed      = 0x07
}

/// OTA command — rich model with associated payloads.
public struct OTACommand: Equatable, Sendable {
    public let opCode: OTAOpCode
    /// TLV-encoded payload (decoded in M6).
    public let payload: [UInt8]

    public init(opCode: OTAOpCode, payload: [UInt8] = []) {
        self.opCode = opCode
        self.payload = payload
    }

    // MARK: - Factory methods

    /// Build OTA_START: begin firmware transfer.
    /// Payload: imageSize(u32 LE) + imageCRC32(u32 LE) + newVersion(string).
    public static func otaStart(imageSize: UInt32, imageCRC32: UInt32, newVersion: String) -> OTACommand {
        var payload: [UInt8] = []
        var sz = imageSize.littleEndian; Swift.withUnsafeBytes(of: &sz) { payload.append(contentsOf: $0) }
        var crc = imageCRC32.littleEndian; Swift.withUnsafeBytes(of: &crc) { payload.append(contentsOf: $0) }
        payload.append(contentsOf: newVersion.utf8)
        return OTACommand(opCode: .otaStart, payload: payload)
    }

    /// Build OTA_WINDOW_BEGIN: start a data window.
    /// Payload: windowOffset(u32 LE) + windowSize(u16 LE).
    public static func otaWindowBegin(offset: UInt32, size: UInt16) -> OTACommand {
        var payload: [UInt8] = []
        var off = offset.littleEndian; Swift.withUnsafeBytes(of: &off) { payload.append(contentsOf: $0) }
        var sz = size.littleEndian; Swift.withUnsafeBytes(of: &sz) { payload.append(contentsOf: $0) }
        return OTACommand(opCode: .otaWindowBegin, payload: payload)
    }

    /// Build OTA_VALIDATE: request full-image CRC32 verification.
    public static func otaValidate(expectedCRC32: UInt32) -> OTACommand {
        var payload: [UInt8] = []
        var crc = expectedCRC32.littleEndian; Swift.withUnsafeBytes(of: &crc) { payload.append(contentsOf: $0) }
        return OTACommand(opCode: .otaValidate, payload: payload)
    }

    /// Build OTA_APPLY: command device to apply the new firmware.
    public static func otaApply() -> OTACommand {
        OTACommand(opCode: .otaApply)
    }

    /// Build OTA_ABORT: cancel the current transfer.
    public static func otaAbort() -> OTACommand {
        OTACommand(opCode: .otaAbort)
    }

    /// Build OTA_START_ACK response.
    ///
    /// Payload layout:
    ///   status(u8) + resumeOffset(u32 LE) + maxChunkSize(u16 LE) + maxWindow(u8)
    public static func otaStartAck(
        status: OTAStatusCode,
        resumeOffset: UInt32? = nil,
        maxChunkSize: UInt16? = nil,
        maxWindow: UInt8? = nil
    ) -> OTACommand {
        var payload: [UInt8] = [status.rawValue]
        if let off = resumeOffset ?? ((maxChunkSize != nil || maxWindow != nil) ? 0 : nil) {
            var o = off.littleEndian; Swift.withUnsafeBytes(of: &o) { payload.append(contentsOf: $0) }
        }
        if let chunkSize = maxChunkSize {
            var size = chunkSize.littleEndian; Swift.withUnsafeBytes(of: &size) { payload.append(contentsOf: $0) }
        }
        if let maxWindow {
            payload.append(maxWindow)
        }
        return OTACommand(opCode: .otaStartAck, payload: payload)
    }

    public static func parseStartAckPayload(
        _ payload: [UInt8]
    ) -> (status: OTAStatusCode, resumeOffset: UInt32?, maxChunkSize: UInt16?, maxWindow: UInt8?)? {
        guard let statusByte = payload.first,
              let status = OTAStatusCode(rawValue: statusByte) else {
            return nil
        }

        let resumeOffset: UInt32?
        if payload.count >= 5 {
            resumeOffset = UInt32(payload[1]) |
                (UInt32(payload[2]) << 8) |
                (UInt32(payload[3]) << 16) |
                (UInt32(payload[4]) << 24)
        } else {
            resumeOffset = nil
        }

        let maxChunkSize: UInt16?
        if payload.count >= 7 {
            maxChunkSize = UInt16(payload[5]) | (UInt16(payload[6]) << 8)
        } else {
            maxChunkSize = nil
        }

        let maxWindow = payload.count >= 8 ? payload[7] : nil
        return (status, resumeOffset, maxChunkSize, maxWindow)
    }

    /// Build OTA_WINDOW_ACK response.
    ///
    /// Payload layout follows `docs/07-ota-dfu.md`:
    ///   recvOffset(u32 LE) + windowCRC32(u32 LE) + status(u8)
    public static func otaWindowAck(status: OTAStatusCode, offset: UInt32, windowCRC32: UInt32) -> OTACommand {
        var payload: [UInt8] = []
        var off = offset.littleEndian; Swift.withUnsafeBytes(of: &off) { payload.append(contentsOf: $0) }
        var crc = windowCRC32.littleEndian; Swift.withUnsafeBytes(of: &crc) { payload.append(contentsOf: $0) }
        payload.append(status.rawValue)
        return OTACommand(opCode: .otaWindowAck, payload: payload)
    }

    public static func parseWindowAckPayload(_ payload: [UInt8]) -> (recvOffset: UInt32, windowCRC32: UInt32, status: OTAStatusCode)? {
        guard payload.count >= 9 else { return nil }
        let offset = UInt32(payload[0]) | (UInt32(payload[1]) << 8) | (UInt32(payload[2]) << 16) | (UInt32(payload[3]) << 24)
        let crc = UInt32(payload[4]) | (UInt32(payload[5]) << 8) | (UInt32(payload[6]) << 16) | (UInt32(payload[7]) << 24)
        guard let status = OTAStatusCode(rawValue: payload[8]) else { return nil }
        return (offset, crc, status)
    }
}
