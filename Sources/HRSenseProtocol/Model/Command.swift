import Foundation

// MARK: - Command model types

/// L3 command opcodes.
/// OpCode convention: 0x00–0x0F general control, 0x80–0x8F general response,
/// 0x20–0x2F OTA request, 0xA0–0xAF OTA response.
public enum CommandOpCode: UInt8, Equatable, Sendable {
    case hello       = 0x01
    case helloAck    = 0x81
    case getInfo     = 0x02
    case info        = 0x82
    case startStream = 0x03
    case stopStream  = 0x04
    case setConfig   = 0x05
    case error       = 0x0F
}

/// Command flags byte.
///   bit7 = req/resp  (0=request, 1=response)
///   bit6 = needsACK
///   bit5..0 = reserved (must be 0)
public struct CommandFlags: Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public init(isResponse: Bool, needsACK: Bool = false) {
        var val: UInt8 = 0
        if isResponse { val |= 0x80 }
        if needsACK  { val |= 0x40 }
        self.rawValue = val
    }

    public var isResponse: Bool { (rawValue & 0x80) != 0 }
    public var needsACK: Bool   { (rawValue & 0x40) != 0 }
}

/// A v1 protocol command.
public struct Command: Equatable, Sendable {
    public let opCode: CommandOpCode
    public let flags: CommandFlags
    /// TLV-encoded parameters (may be empty for simple commands).
    public let params: [TLVRecord]

    public init(opCode: CommandOpCode, flags: CommandFlags, params: [TLVRecord]) {
        self.opCode = opCode
        self.flags = flags
        self.params = params
    }
}

// MARK: - Factory convenience methods

extension Command {
    /// Build a HELLO command (App→Dev).
    /// - Parameters:
    ///   - versions: supported protocol versions.
    ///   - capabilities: App side capabilities bitmap.
    ///   - needsACK: whether ACK is requested.
    public static func hello(
        versions: [UInt8] = ProtocolVersion.supportedVersions,
        capabilities: Capabilities,
        needsACK: Bool = false
    ) -> Command {
        Command(
            opCode: .hello,
            flags: CommandFlags(isResponse: false, needsACK: needsACK),
            params: [
                TLVRecord(tag: .heartRate, value: versions),  // reuse tag 0x01 for versions list in HELLO
            ]
        )
    }

    /// Build a HELLO_ACK response (Dev→App).
    public static func helloAck(
        version: UInt8 = ProtocolVersion.v1,
        capabilities: Capabilities,
        model: String,
        firmwareVersion: String
    ) -> Command {
        // Pack version + caps + model + fw into TLV params
        // tag 0x01 = protocol version, 0x07 = capabilities, 0x04 = model, 0x05 = fw
        var capsLE = capabilities.rawValue.littleEndian
        let capsBytes = Swift.withUnsafeBytes(of: &capsLE) { Array($0) }
        let modelBytes = Array(model.utf8)
        let fwBytes = Array(firmwareVersion.utf8)
        let params: [TLVRecord] = [
            TLVRecord(tag: .heartRate, value: [version]),
            TLVRecord(tag: .capabilities, value: capsBytes),
            TLVRecord(tag: .battery, value: modelBytes),
            TLVRecord(tag: .sensorStatus, value: fwBytes),
        ]
        return Command(
            opCode: .helloAck,
            flags: CommandFlags(isResponse: true),
            params: params
        )
    }

    /// Build a START_STREAM command.
    public static func startStream(sampleKinds: [UInt8] = [0x01]) -> Command {
        Command(
            opCode: .startStream,
            flags: CommandFlags(isResponse: false),
            params: [
                TLVRecord(tag: .sampleSeq, value: sampleKinds),
            ]
        )
    }

    /// Build a STOP_STREAM command.
    public static func stopStream() -> Command {
        Command(
            opCode: .stopStream,
            flags: CommandFlags(isResponse: false),
            params: []
        )
    }
}
