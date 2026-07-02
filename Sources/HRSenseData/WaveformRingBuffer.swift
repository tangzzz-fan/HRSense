import Foundation
import HRSenseCore

/// Fixed-capacity thread-safe ring buffer for waveform samples.
///
/// Holds ~30 seconds of waveform data (at 128 Hz: ~3840 samples; at 250 Hz: ~7500).
/// Evicts oldest data when capacity is exceeded.
public final class WaveformRingBuffer: WaveformRingBufferProtocol, @unchecked Sendable {
    /// Maximum capacity in samples.
    private let capacity: Int
    private let lock = NSLock()

    private var buffer: [WaveformSample] = []
    private var _totalPushed: Int = 0
    private var _totalBlocksReceived: Int = 0
    private var _totalBlocksLost: Int = 0
    private var _lastBlockSeq: UInt32 = 0
    private var _firstBlock: Bool = true
    private var _totalBytesReceived: Int = 0
    private var _startTime: Date? = nil

    /// Default ~30 seconds of waveform at 128 Hz.
    public init(capacity: Int = 3840) {
        self.capacity = capacity
    }

    public var totalPushed: Int { lock.withLock { _totalPushed } }

    public var metricsSnapshot: WaveformMetrics {
        lock.withLock {
            var m = WaveformMetrics()
            m.blockLossRate = _totalBlocksReceived > 0
                ? Double(_totalBlocksLost) / Double(_totalBlocksReceived + _totalBlocksLost) : 0
            if let start = _startTime {
                let elapsed = Date().timeIntervalSince(start)
                m.effectiveThroughputBytesPerSec = elapsed > 0 ? Double(_totalBytesReceived) / elapsed : 0
                m.samplesPerSec = elapsed > 0 ? Double(_totalPushed) / elapsed : 0
            }
            return m
        }
    }

    public func push(_ samples: [WaveformSample]) {
        lock.lock(); defer { lock.unlock() }
        if _startTime == nil { _startTime = Date() }
        buffer.append(contentsOf: samples)
        _totalPushed += samples.count
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
    }

    public func readRecent(durationMs: Double) -> [WaveformSample] {
        lock.lock(); defer { lock.unlock() }
        guard let lastTS = buffer.last?.timestamp else { return [] }
        let cutoff = lastTS.addingTimeInterval(-durationMs / 1000.0)
        return buffer.filter { $0.timestamp >= cutoff }
    }

    /// Record that a waveform block was received.
    public func recordBlock(bytes: Int, blockSeq: UInt32, sampleCount: Int) {
        lock.lock(); defer { lock.unlock() }
        _totalBlocksReceived += 1
        _totalBytesReceived += bytes
        if !_firstBlock {
            let loss = WaveformLossDetector.detectBlockLoss(prevSeq: _lastBlockSeq, currentSeq: blockSeq)
            _totalBlocksLost += loss
        }
        _firstBlock = false
        _lastBlockSeq = blockSeq
    }
}

private enum WaveformLossDetector {
    static func detectBlockLoss(prevSeq: UInt32, currentSeq: UInt32) -> Int {
        let diff = currentSeq.subtractingReportingOverflow(prevSeq).partialValue
        return max(0, Int(diff) - 1)
    }
}
