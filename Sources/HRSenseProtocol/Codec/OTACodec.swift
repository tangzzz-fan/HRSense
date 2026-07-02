import Foundation

/// Encode / decode OTA command frames.
///
/// OTA commands use TLV encoding for extensibility.
/// Full implementation for M6 OTA/DFU pipeline.
public enum OTACodec {

    /// Encode an OTACommand into frame body bytes.
    public static func encode(_ command: OTACommand) -> [UInt8] {
        var result: [UInt8] = []
        result.append(command.opCode.rawValue)
        // Payload length (u8 — max 255 bytes for OTA command bodies)
        result.append(UInt8(min(command.payload.count, 255)))
        result.append(contentsOf: command.payload.prefix(255))
        return result
    }

    /// Decode frame body bytes into an OTACommand.
    public static func decode(body: [UInt8]) -> OTACommand? {
        guard body.count >= 2 else { return nil }
        guard let opCode = OTAOpCode(rawValue: body[0]) else { return nil }
        let length = Int(body[1])
        let payload = body.count >= 2 + length ? Array(body[2..<2 + length]) : Array(body.dropFirst(2))
        return OTACommand(opCode: opCode, payload: payload)
    }

    /// Parse imageSize from OTA_START payload.
    public static func parseStartPayload(_ payload: [UInt8]) -> (imageSize: UInt32, imageCRC32: UInt32, version: String)? {
        guard payload.count >= 8 else { return nil }
        let sz = UInt32(payload[0]) | (UInt32(payload[1]) << 8) | (UInt32(payload[2]) << 16) | (UInt32(payload[3]) << 24)
        let crc = UInt32(payload[4]) | (UInt32(payload[5]) << 8) | (UInt32(payload[6]) << 16) | (UInt32(payload[7]) << 24)
        let versionBytes = payload.dropFirst(8)
        let version = String(decoding: versionBytes, as: UTF8.self)
        return (sz, crc, version)
    }
}
