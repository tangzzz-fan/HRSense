import Foundation

/// CRC-32 (IEEE 802.3) for OTA image integrity verification.
///
/// Parameters:
///   Polynomial: 0xEDB88320 (reflected)
///   Init: 0xFFFFFFFF
///   RefIn: true, RefOut: true
///   XorOut: 0xFFFFFFFF
public enum CRC32: Sendable {

    /// Compute CRC-32 over `bytes`.
    public static func compute(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for b in bytes {
            crc ^= UInt32(b)
            for _ in 0..<8 {
                if (crc & 1) != 0 {
                    crc = (crc >> 1) ^ 0xEDB8_8320
                } else {
                    crc = crc >> 1
                }
            }
        }
        return ~crc
    }

    /// Compute over Data.
    public static func compute(_ data: Data) -> UInt32 {
        compute([UInt8](data))
    }

    /// Incremental CRC-32 update.
    /// - Parameters:
    ///   - crc: current CRC value (initially 0xFFFF_FFFF).
    ///   - bytes: new bytes to feed.
    /// - Returns: updated CRC value.
    public static func update(crc: UInt32, bytes: [UInt8]) -> UInt32 {
        var c = crc
        for b in bytes {
            c ^= UInt32(b)
            for _ in 0..<8 {
                if (c & 1) != 0 { c = (c >> 1) ^ 0xEDB8_8320 }
                else { c = c >> 1 }
            }
        }
        return c
    }

    /// Finalise incremental CRC.
    public static func finalise(crc: UInt32) -> UInt32 {
        return ~crc
    }

    /// Known test vector: CRC32("123456789") == 0xCBF43926
    public static var goldenValue: UInt32 { 0xCBF4_3926 }
}
