import Foundation

/// CRC-16/CCITT-FALSE implementation.
///
/// Parameters:
///   - Polynomial:  0x1021
///   - Init:        0xFFFF
///   - RefIn:       false
///   - RefOut:      false
///   - XorOut:      0x0000
///
/// Golden value: CRC16("123456789") == 0x29B1
public enum CRC16 {
    /// Compute CRC-16/CCITT-FALSE over `bytes`.
    /// - Parameter bytes: The data to checksum.
    /// - Returns: 16-bit CRC value.
    public static func compute(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for b in bytes {
            crc ^= UInt16(b) << 8
            for _ in 0..<8 {
                if (crc & 0x8000) != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc = crc << 1
                }
                crc &= 0xFFFF
            }
        }
        return crc
    }

    /// Convenience: compute over `Data`.
    public static func compute(_ data: Data) -> UInt16 {
        compute([UInt8](data))
    }

    /// Convenience: compute over a `[UInt8]` buffer slice.
    public static func compute(_ bytes: ArraySlice<UInt8>) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for b in bytes {
            crc ^= UInt16(b) << 8
            for _ in 0..<8 {
                if (crc & 0x8000) != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc = crc << 1
                }
                crc &= 0xFFFF
            }
        }
        return crc
    }
}
