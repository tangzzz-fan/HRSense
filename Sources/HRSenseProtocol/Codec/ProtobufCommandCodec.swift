import Foundation
import SwiftProtobuf

/// Protobuf-backed command payload codec.
///
/// The command envelope stays stable:
/// `OpCode(1B) | Flags(1B) | Payload(...)`
///
/// The only change is the structured payload encoding branch selected by
/// `FrameType.protobufCommand`.
public enum ProtobufCommandCodec {
    public static func encode(_ command: Command) throws -> [UInt8] {
        var result: [UInt8] = [command.opCode.rawValue, command.flags.rawValue]
        let payload = try encodePayload(for: command)
        result.append(contentsOf: payload)
        return result
    }

    public static func decode(body: [UInt8]) -> Command? {
        guard body.count >= 2 else { return nil }
        guard let opCode = CommandOpCode(rawValue: body[0]) else { return nil }

        let flags = CommandFlags(rawValue: body[1])
        let payload = Data(body.dropFirst(2))

        let params: [TLVRecord]
        do {
            params = try decodePayload(opCode: opCode, payload: payload)
        } catch {
            return nil
        }

        return Command(opCode: opCode, flags: flags, params: params)
    }

    private static func encodePayload(for command: Command) throws -> [UInt8] {
        switch command.opCode {
        case .hello:
            var message = HRSHelloRequest()
            message.supportedProtocolVersions = command.params
                .first(where: { $0.tag == .heartRate })?
                .value
                .map(UInt32.init) ?? []
            message.appCapabilities = capabilityRawValue(from: command.params)
            message.schemaVersion = ProtobufSchemaVersion.current
            return Array(try message.serializedData())

        case .helloAck, .info:
            var deviceInfo = HRSDeviceInfo()
            deviceInfo.model = stringValue(for: .battery, in: command.params)
            deviceInfo.firmwareVersion = stringValue(for: .sensorStatus, in: command.params)
            deviceInfo.protocolVersion = UInt32(version(from: command.params))
            deviceInfo.capabilities = capabilityRawValue(from: command.params)

            var message = HRSHelloAck()
            message.negotiatedProtocolVersion = UInt32(version(from: command.params))
            message.deviceCapabilities = capabilityRawValue(from: command.params)
            message.deviceInfo = deviceInfo
            message.schemaVersion = ProtobufSchemaVersion.current
            return Array(try message.serializedData())

        default:
            return []
        }
    }

    private static func decodePayload(opCode: CommandOpCode, payload: Data) throws -> [TLVRecord] {
        switch opCode {
        case .hello:
            let message = try HRSHelloRequest(serializedBytes: payload)
            let versions = message.supportedProtocolVersions.compactMap(UInt8.init(exactly:))
            let capabilityBytes = littleEndianBytes(of: message.appCapabilities)
            return [
                TLVRecord(tag: .heartRate, value: versions),
                TLVRecord(tag: .capabilities, value: capabilityBytes),
            ]

        case .helloAck, .info:
            let message = try HRSHelloAck(serializedBytes: payload)
            let version = UInt8(clamping: message.negotiatedProtocolVersion)
            let capabilityBytes = littleEndianBytes(of: message.deviceCapabilities)
            let modelBytes = Array(message.deviceInfo.model.utf8)
            let firmwareBytes = Array(message.deviceInfo.firmwareVersion.utf8)
            return [
                TLVRecord(tag: .heartRate, value: [version]),
                TLVRecord(tag: .capabilities, value: capabilityBytes),
                TLVRecord(tag: .battery, value: modelBytes),
                TLVRecord(tag: .sensorStatus, value: firmwareBytes),
            ]

        default:
            return []
        }
    }

    private static func capabilityRawValue(from params: [TLVRecord]) -> UInt32 {
        let rawBytes = params.first(where: { $0.tag == .capabilities })?.value ?? []
        return Capabilities(bytesLE: rawBytes).rawValue
    }

    private static func version(from params: [TLVRecord]) -> UInt8 {
        params.first(where: { $0.tag == .heartRate })?.value.first ?? ProtocolVersion.v1
    }

    private static func stringValue(for tag: TLVTag, in params: [TLVRecord]) -> String {
        let bytes = params.first(where: { $0.tag == tag })?.value ?? []
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    private static func littleEndianBytes(of rawValue: UInt32) -> [UInt8] {
        Capabilities(rawValue: rawValue).bytesLE
    }
}

public enum ProtobufSchemaVersion {
    public static let current: UInt32 = 1
}
