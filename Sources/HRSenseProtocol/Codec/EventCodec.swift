import Foundation

/// Encode / decode device event frames (Type=0x04).
///
/// Event frame body: EventKind(1B) | Timestamp(u32 LE) | Payload ...
public enum EventCodec {
    /// Encode a DeviceEvent into frame body bytes.
    public static func encode(_ event: DeviceEvent) -> [UInt8] {
        var result: [UInt8] = []
        result.append(event.kind.rawValue)
        var ts = event.timestamp.littleEndian
        Swift.withUnsafeBytes(of: &ts) { result.append(contentsOf: $0) }
        result.append(contentsOf: event.payload)
        return result
    }

    /// Decode frame body bytes into a DeviceEvent.
    /// Returns nil on parse failure.
    public static func decode(body: [UInt8]) -> DeviceEvent? {
        guard body.count >= 5 else { return nil } // kind + u32 ts minimum
        guard let kind = DeviceEvent.EventKind(rawValue: body[0]) else { return nil }
        let ts = UInt32(body[1]) | (UInt32(body[2]) << 8) | (UInt32(body[3]) << 16) | (UInt32(body[4]) << 24)
        let payload = Array(body.dropFirst(5))
        return DeviceEvent(kind: kind, payload: payload, timestamp: ts)
    }
}
