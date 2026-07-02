import Foundation

/// Encode / decode OTA command frames.
/// M1 placeholder — full implementation in M6.
public enum OTACodec {
    /// Encode an OTACommand into frame body bytes.
    public static func encode(_ command: OTACommand) -> [UInt8] {
        var result: [UInt8] = []
        result.append(command.opCode.rawValue)
        result.append(contentsOf: command.payload)
        return result
    }

    /// Decode frame body bytes into an OTACommand.
    public static func decode(body: [UInt8]) -> OTACommand? {
        guard body.count >= 1 else { return nil }
        guard let opCode = OTAOpCode(rawValue: body[0]) else { return nil }
        let payload = Array(body.dropFirst())
        return OTACommand(opCode: opCode, payload: payload)
    }
}
