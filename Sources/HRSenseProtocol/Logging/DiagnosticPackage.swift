import Foundation

/// A single log entry captured for diagnostic export.
public struct LogEntry: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let category: String
    public let level: String
    public let message: String

    public init(timestamp: Date = Date(), category: String, level: String, message: String) {
        self.timestamp = timestamp
        self.category = category
        self.level = level
        self.message = message
    }
}

/// Diagnostic package exportable as JSON.
public struct DiagnosticPackage: Codable, Equatable, Sendable {
    /// Recent log entries (ring buffer).
    public let logEntries: [LogEntry]
    /// State transition history (last N events).
    public let stateTransitions: [String]
    /// Metrics snapshot at export time.
    public let metricsSnapshot: MetricsSnapshotJSON
    /// App version, build, OS version.
    public let systemInfo: SystemInfo

    public init(
        logEntries: [LogEntry],
        stateTransitions: [String],
        metricsSnapshot: MetricsSnapshotJSON,
        systemInfo: SystemInfo
    ) {
        self.logEntries = logEntries
        self.stateTransitions = stateTransitions
        self.metricsSnapshot = metricsSnapshot
        self.systemInfo = systemInfo
    }

    /// Export as JSON Data.
    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

/// JSON-compatible metrics snapshot.
public struct MetricsSnapshotJSON: Codable, Equatable, Sendable {
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

/// System information for diagnostic context.
public struct SystemInfo: Codable, Equatable, Sendable {
    public let appVersion: String
    public let buildNumber: String
    public let osVersion: String
    public let deviceModel: String

    public static var current: SystemInfo {
        SystemInfo(
            appVersion: "1.0.0",
            buildNumber: "1",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: "Simulator"
        )
    }
}

/// Ring-buffer log collector — thread-safe, used by Logger + LoggingMiddleware.
public final class LogRingBuffer: @unchecked Sendable {
    private let capacity: Int
    private let lock = NSLock()
    private var buffer: [LogEntry] = []

    public init(capacity: Int = 500) {
        self.capacity = capacity
    }

    public func append(_ entry: LogEntry) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(entry)
        if buffer.count > capacity { buffer.removeFirst(buffer.count - capacity) }
    }

    public var entries: [LogEntry] {
        lock.withLock { buffer }
    }

    public func snapshot() -> [LogEntry] {
        lock.withLock { Array(buffer) }
    }
}
