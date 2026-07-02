import Foundation
import CoreBluetooth

/// Metrics collector for BLE data operations. Thread-safe.
public final class MetricsCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _totalSamplesReceived: Int = 0
    private var _samplesLost: Int = 0
    private var _reconnectCount: Int = 0
    private var _bytesReceived: Int = 0

    public init() {}

    public var totalSamplesReceived: Int { lock.withLock { _totalSamplesReceived } }
    public var samplesLost: Int { lock.withLock { _samplesLost } }
    public var reconnectCount: Int { lock.withLock { _reconnectCount } }
    public var bytesReceived: Int { lock.withLock { _bytesReceived } }

    public func recordSampleReceived() {
        lock.withLock { _totalSamplesReceived += 1 }
    }

    public func recordSamplesLost(_ count: Int) {
        lock.withLock { _samplesLost += count }
    }

    public func recordReconnect() {
        lock.withLock { _reconnectCount += 1 }
    }

    public func recordBytesReceived(_ count: Int) {
        lock.withLock { _bytesReceived += count }
    }

    public func snapshot() -> MetricsSnapshot {
        lock.withLock {
            MetricsSnapshot(
                totalSamplesReceived: _totalSamplesReceived,
                samplesLost: _samplesLost,
                reconnectCount: _reconnectCount,
                bytesReceived: _bytesReceived
            )
        }
    }
}

/// Immutable snapshot of current metrics.
public struct MetricsSnapshot: Equatable, Sendable {
    public let totalSamplesReceived: Int
    public let samplesLost: Int
    public let reconnectCount: Int
    public let bytesReceived: Int

    public init(totalSamplesReceived: Int, samplesLost: Int, reconnectCount: Int, bytesReceived: Int) {
        self.totalSamplesReceived = totalSamplesReceived
        self.samplesLost = samplesLost
        self.reconnectCount = reconnectCount
        self.bytesReceived = bytesReceived
    }
}
