import Foundation

/// Domain event produced by the device (Type=0x04 frames).
public struct DeviceEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case batteryLevelChanged(percent: UInt8)
        case sensorContactChanged(status: UInt8)
        case error(code: UInt8)
    }

    public let kind: Kind
    public let timestamp: Date

    public init(kind: Kind, timestamp: Date) {
        self.kind = kind
        self.timestamp = timestamp
    }
}
