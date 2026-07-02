import Foundation

/// Tracks throughput metrics for waveform streaming.
/// Thread-safe.
public final class ThroughputTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _blocksSent: Int = 0
    private var _bytesSent: Int = 0
    private var _blocksLost: Int = 0
    private var _startTime: Date? = nil
    private var _lastBlockTime: Date = Date.distantPast

    public init() {}

    public func start() {
        lock.withLock {
            _startTime = Date()
            _blocksSent = 0
            _bytesSent = 0
            _blocksLost = 0
        }
    }

    public func recordBlock(bytes: Int) {
        lock.withLock {
            _blocksSent += 1
            _bytesSent += bytes
            _lastBlockTime = Date()
        }
    }

    public func recordLoss(count: Int) {
        lock.withLock { _blocksLost += count }
    }

    /// Compute current throughput in bytes/second.
    public var throughputBytesPerSec: Double {
        lock.withLock {
            guard let start = _startTime else { return 0 }
            let elapsed = Date().timeIntervalSince(start)
            guard elapsed > 0 else { return 0 }
            return Double(_bytesSent) / elapsed
        }
    }

    /// Block loss rate (0.0–1.0).
    public var blockLossRate: Double {
        lock.withLock {
            let total = _blocksSent + _blocksLost
            guard total > 0 else { return 0 }
            return Double(_blocksLost) / Double(total)
        }
    }

    public var blocksSent: Int { lock.withLock { _blocksSent } }
    public var blocksLost: Int { lock.withLock { _blocksLost } }
}
