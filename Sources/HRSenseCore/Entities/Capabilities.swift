/// Domain value: device capabilities expressed as a bitmask.
/// Mirrors the protocol-level Capabilities type but lives in Domain layer
/// to avoid upper layers depending on HRSenseProtocol directly.
public struct DeviceCapabilities: OptionSet, Equatable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let heartRate        = DeviceCapabilities(rawValue: 1 << 0)
    public static let rrIntervals      = DeviceCapabilities(rawValue: 1 << 1)
    public static let battery          = DeviceCapabilities(rawValue: 1 << 2)
    public static let sensorContact    = DeviceCapabilities(rawValue: 1 << 3)
    public static let motion           = DeviceCapabilities(rawValue: 1 << 4)
    public static let configurableRate = DeviceCapabilities(rawValue: 1 << 5)
    public static let reliableData     = DeviceCapabilities(rawValue: 1 << 6)
    public static let deviceEvents     = DeviceCapabilities(rawValue: 1 << 7)
    public static let batchSamples     = DeviceCapabilities(rawValue: 1 << 8)
    public static let otaDFU           = DeviceCapabilities(rawValue: 1 << 9)
    public static let waveform         = DeviceCapabilities(rawValue: 1 << 10)
}
