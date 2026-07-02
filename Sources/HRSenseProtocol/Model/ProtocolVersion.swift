/// Protocol version constants.
/// v1 = 0x01
public enum ProtocolVersion {
    public static let v1: UInt8 = 0x01

    /// Versions currently supported by this implementation.
    public static let supportedVersions: [UInt8] = [0x01]
}
