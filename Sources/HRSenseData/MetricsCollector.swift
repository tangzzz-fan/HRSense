import Foundation

/// Enhanced MetricsCollector with rate-based KPIs for M7.
///
/// Aggregates all real-time metrics from BLE/OTA/compute paths.
/// Thread-safe. Feeds the DiagnosticPanelView.
public final class MetricsCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let startTime: Date = Date()

    private var _totalSamplesReceived: Int = 0
    private var _samplesLost: Int = 0
    private var _reconnectCount: Int = 0
    private var _bytesReceived: Int = 0
    private var _connectionAttempts: Int = 0
    private var _connectionSuccesses: Int = 0
    private var _commandsSent: Int = 0
    private var _commandTimeouts: Int = 0
    private var _otaAttempts: Int = 0
    private var _otaSuccesses: Int = 0

    public init() {}

    // MARK: - Raw counters

    public var totalSamplesReceived: Int { lock.withLock { _totalSamplesReceived } }
    public var samplesLost: Int { lock.withLock { _samplesLost } }
    public var reconnectCount: Int { lock.withLock { _reconnectCount } }
    public var bytesReceived: Int { lock.withLock { _bytesReceived } }

    public func recordSampleReceived()    { lock.withLock { _totalSamplesReceived += 1 } }
    public func recordSamplesLost(_ n: Int) { lock.withLock { _samplesLost += n } }
    public func recordReconnect()          { lock.withLock { _reconnectCount += 1 } }
    public func recordBytesReceived(_ n: Int) { lock.withLock { _bytesReceived += n } }

    public func recordConnectionAttempt()   { lock.withLock { _connectionAttempts += 1 } }
    public func recordConnectionSuccess()   { lock.withLock { _connectionSuccesses += 1 } }
    public func recordCommandSent()         { lock.withLock { _commandsSent += 1 } }
    public func recordCommandTimeout()      { lock.withLock { _commandTimeouts += 1 } }
    public func recordOTAAttempt()          { lock.withLock { _otaAttempts += 1 } }
    public func recordOTASuccess()          { lock.withLock { _otaSuccesses += 1 } }

    // MARK: - Computed rates

    /// Elapsed time since creation (seconds).
    public var elapsed: TimeInterval {
        Date().timeIntervalSince(startTime)
    }

    /// Connection success rate (0.0–1.0).
    public var connectionSuccessRate: Double {
        lock.withLock {
            _connectionAttempts == 0 ? 0 : Double(_connectionSuccesses) / Double(_connectionAttempts)
        }
    }

    /// Data sample loss rate (0.0–1.0).
    public var sampleLossRate: Double {
        lock.withLock {
            let total = _totalSamplesReceived + _samplesLost
            return total == 0 ? 0 : Double(_samplesLost) / Double(total)
        }
    }

    /// Command timeout rate (0.0–1.0).
    public var commandTimeoutRate: Double {
        lock.withLock {
            _commandsSent == 0 ? 0 : Double(_commandTimeouts) / Double(_commandsSent)
        }
    }

    /// Effective throughput (bytes/second).
    public var throughputBytesPerSec: Double {
        lock.withLock { elapsed > 0 ? Double(_bytesReceived) / elapsed : 0 }
    }

    /// OTA success rate (0.0–1.0).
    public var otaSuccessRate: Double {
        lock.withLock {
            _otaAttempts == 0 ? 0 : Double(_otaSuccesses) / Double(_otaAttempts)
        }
    }

    // MARK: - Snapshot

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

    /// Full KPI snapshot for the diagnostics panel.
    public func kpiSnapshot() -> KPISnapshot {
        lock.withLock {
            KPISnapshot(
                connectionSuccessRate: connectionSuccessRate,
                reconnectCount: _reconnectCount,
                commandTimeoutRate: commandTimeoutRate,
                sampleLossRate: sampleLossRate,
                throughputBytesPerSec: throughputBytesPerSec,
                otaSuccessRate: otaSuccessRate
            )
        }
    }
}

// MARK: - Value types

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

/// KPI snapshot for diagnostics display (6 key metrics).
public struct KPISnapshot: Equatable, Sendable {
    public let connectionSuccessRate: Double
    public let reconnectCount: Int
    public let commandTimeoutRate: Double
    public let sampleLossRate: Double
    public let throughputBytesPerSec: Double
    public let otaSuccessRate: Double

    public init(
        connectionSuccessRate: Double,
        reconnectCount: Int,
        commandTimeoutRate: Double,
        sampleLossRate: Double,
        throughputBytesPerSec: Double,
        otaSuccessRate: Double
    ) {
        self.connectionSuccessRate = connectionSuccessRate
        self.reconnectCount = reconnectCount
        self.commandTimeoutRate = commandTimeoutRate
        self.sampleLossRate = sampleLossRate
        self.throughputBytesPerSec = throughputBytesPerSec
        self.otaSuccessRate = otaSuccessRate
    }
}
