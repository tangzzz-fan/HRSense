import Foundation

/// Canonical hex dump format — identical on App and Simulator for side-by-side diff.
public enum HexFormat: Sendable {

    /// Format bytes as a canonical hex string.
    ///
    /// Format: `<length> | XX XX XX XX ... XX |`
    /// Example: `4 | DE AD BE EF |`
    public static func canonicalHexDump(_ data: Data) -> String {
        canonicalHexDump([UInt8](data))
    }

    /// Format [UInt8] as canonical hex string.
    public static func canonicalHexDump(_ bytes: [UInt8]) -> String {
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        return "\(bytes.count) | \(hex) |"
    }

    /// Format with a label prefix.
    public static func hexDump(label: String, data: Data) -> String {
        "[\(label)] \(canonicalHexDump(data))"
    }

    /// Compact format: no length prefix, just hex bytes.
    public static func compactHex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }
}
