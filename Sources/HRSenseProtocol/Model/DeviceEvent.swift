import Foundation

/// Device-initiated event (Type=0x04).
/// Used when the device has `DEVICE_EVENTS` capability.
public struct DeviceEvent: Equatable, Sendable {
    public enum EventKind: UInt8, Equatable, Sendable {
        case batteryLevelChanged   = 0x01
        case sensorContactChanged  = 0x02
        case error                 = 0x0F
    }

    public let kind: EventKind
    /// TLV-encoded event payload.
    public let payload: [UInt8]
    /// Timestamp (device-relative ms).
    public let timestamp: UInt32

    public init(kind: EventKind, payload: [UInt8], timestamp: UInt32) {
        self.kind = kind
        self.payload = payload
        self.timestamp = timestamp
    }
}
