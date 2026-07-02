import Foundation

/// Encode / decode L3 command frames.
///
/// Command frame body layout:
///   OpCode(1B) | Flags(1B) | TLV Params ...
public enum CommandCodec {
    /// Encode a Command into frame body bytes.
    public static func encode(_ command: Command) -> [UInt8] {
        var result: [UInt8] = []
        result.append(command.opCode.rawValue)
        result.append(command.flags.rawValue)
        result.append(contentsOf: TLVEncoder.encode(command.params))
        return result
    }

    /// Decode frame body bytes into a Command.
    /// Returns nil on parse failure.
    public static func decode(body: [UInt8]) -> Command? {
        guard body.count >= 2 else { return nil }
        guard let opCode = CommandOpCode(rawValue: body[0]) else { return nil }
        let flags = CommandFlags(rawValue: body[1])
        let tlvBytes = Array(body.dropFirst(2))
        let params: [TLVRecord]
        if tlvBytes.isEmpty {
            params = []
        } else {
            do {
                params = try TLVDecoder.decode(tlvBytes)
            } catch {
                // TLV parse error — record as empty params (forward compat)
                params = []
            }
        }
        return Command(opCode: opCode, flags: flags, params: params)
    }
}
