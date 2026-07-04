import Foundation

// MARK: - Top-level convenience entry points

/// Convenience encoder: Command → GATT fragments.
public func encodeCommand(_ cmd: Command, seq: UInt8, mtu: Int) -> [Data] {
    let body = CommandCodec.encode(cmd)
    return FrameEncoder.encode(type: .command, body: body, seq: seq, mtu: mtu)
}

/// Convenience encoder: Command → GATT fragments using Protobuf payload encoding.
public func encodeProtobufCommand(_ cmd: Command, seq: UInt8, mtu: Int) throws -> [Data] {
    let body = try ProtobufCommandCodec.encode(cmd)
    return FrameEncoder.encode(type: .protobufCommand, body: body, seq: seq, mtu: mtu)
}

/// Convenience encoder: DeviceSample → GATT fragments.
public func encodeData(_ sample: DeviceSample, seq: UInt8, mtu: Int) -> [Data] {
    let body = DataCodec.encode(sample)
    return FrameEncoder.encode(type: .data, body: body, seq: seq, mtu: mtu)
}

/// Convenience encoder: ACK → GATT fragments.
public func encodeACK(_ ack: ACKPayload, seq: UInt8, mtu: Int) -> [Data] {
    let body = ACKCodec.encode(ack)
    return FrameEncoder.encode(type: .ack, body: body, seq: seq, mtu: mtu)
}

/// Convenience encoder: DeviceEvent → GATT fragments.
public func encodeEvent(_ event: DeviceEvent, seq: UInt8, mtu: Int) -> [Data] {
    let body = EventCodec.encode(event)
    return FrameEncoder.encode(type: .event, body: body, seq: seq, mtu: mtu)
}
