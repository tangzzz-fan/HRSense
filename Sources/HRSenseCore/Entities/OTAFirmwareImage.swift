import Foundation

/// Domain entity: OTA firmware image metadata.
public struct OTAFirmwareImage: Equatable, Sendable {
    /// Total image size in bytes.
    public let imageSize: UInt32
    /// CRC-32 of the complete image.
    public let imageCRC32: UInt32
    /// Target firmware version string.
    public let newVersion: String

    public init(imageSize: UInt32, imageCRC32: UInt32, newVersion: String) {
        self.imageSize = imageSize
        self.imageCRC32 = imageCRC32
        self.newVersion = newVersion
    }
}
