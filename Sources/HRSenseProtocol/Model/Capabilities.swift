/// Device capability bitmask (u32, little-endian).
///
/// Defined in v1 protocol contract (doc 03 §5.3.1).
/// Devices declare support; App declares consumption. Both sides operate on intersection.
public struct Capabilities: OptionSet, Equatable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let heartRate        = Capabilities(rawValue: 1 << 0)  // Required
    public static let rrIntervals      = Capabilities(rawValue: 1 << 1)
    public static let battery          = Capabilities(rawValue: 1 << 2)
    public static let sensorContact    = Capabilities(rawValue: 1 << 3)
    public static let motion           = Capabilities(rawValue: 1 << 4)
    public static let configurableRate = Capabilities(rawValue: 1 << 5)
    public static let reliableData     = Capabilities(rawValue: 1 << 6)
    public static let deviceEvents     = Capabilities(rawValue: 1 << 7)
    public static let batchSamples     = Capabilities(rawValue: 1 << 8)
    public static let otaDFU           = Capabilities(rawValue: 1 << 9)
    public static let waveform         = Capabilities(rawValue: 1 << 10)

    // Bits 11–31 reserved, must be zero.

    /// Encode as u32 little-endian bytes.
    public var bytesLE: [UInt8] {
        let v = rawValue.littleEndian
        return Swift.withUnsafeBytes(of: v) { Array($0) }
    }

    /// Decode from u32 little-endian bytes.
    public init(bytesLE: [UInt8]) {
        var val: UInt32 = 0
        let count = min(bytesLE.count, 4)
        for i in 0..<count {
            val |= UInt32(bytesLE[i]) << (i * 8)
        }
        self.rawValue = UInt32(littleEndian: val)
    }
}
