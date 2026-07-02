import Foundation
import HRSenseProtocol

/// In-memory OTA firmware image buffer with incremental CRC-32.
public final class OTAImageBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [UInt8]
    private var writtenCount: Int = 0
    private var _crc: UInt32 = 0xFFFF_FFFF

    /// Total image size in bytes.
    public let totalSize: Int

    public init(totalSize: Int) {
        self.totalSize = totalSize
        self.buffer = [UInt8](repeating: 0xFF, count: totalSize)
    }

    /// Write a chunk at given offset. Returns true on success.
    @discardableResult
    public func write(offset: Int, data: [UInt8]) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard offset >= 0, offset + data.count <= totalSize else { return false }
        for i in 0..<data.count {
            buffer[offset + i] = data[i]
        }
        _crc = CRC32.update(crc: _crc, bytes: data)
        writtenCount = max(writtenCount, offset + data.count)
        return true
    }

    /// Fraction written (0.0–1.0).
    public var progress: Double {
        lock.withLock { Double(writtenCount) / Double(totalSize) }
    }

    /// Last successfully written offset (for resume).
    public var resumeOffset: Int {
        lock.withLock { writtenCount }
    }

    /// Finalised CRC-32 of the complete image.
    public var finalCRC32: UInt32 {
        lock.withLock { CRC32.finalise(crc: _crc) }
    }

    /// The raw image data (for apply).
    public var data: [UInt8] {
        lock.withLock { buffer }
    }
}
