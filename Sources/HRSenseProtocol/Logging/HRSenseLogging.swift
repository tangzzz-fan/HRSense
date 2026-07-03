import Foundation
import os

// MARK: - Log categories (M7: 8 categories from doc 10 §2.2)

public enum HRSenseLogCategory: String, Sendable, CaseIterable {
    case bleRaw       // raw bytes (hex dump)
    case bleFrame     // fragment/reassembly/CRC/seq
    case bleConn      // scan/connect/disconnect/reconnect/MTU
    case protoCmd     // command/response/ACK/negotiation
    case state        // Redux state transitions
    case ota          // OTA phases/progress/errors
    case computeInfer // computation + inference timing
    case perf         // throughput/loss/frame rate

    // Legacy (M1) aliases — kept for existing protocol logging
    case framing
    case crc
    case tlv
    case codec
    case command
    case data
    case ack
    case event
    case waveform
}

// MARK: - Log level

public enum HRSenseLogLevel: Int, Sendable, Comparable {
    case debug   = 0
    case info    = 1
    case notice  = 2
    case error   = 3
    case fault   = 4

    public static func < (lhs: HRSenseLogLevel, rhs: HRSenseLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// System os.Logger level mapping.
    var osLogType: OSLogType {
        switch self {
        case .debug:  return .debug
        case .info:   return .info
        case .notice: return .default
        case .error:  return .error
        case .fault:  return .fault
        }
    }
}

// MARK: - Log filter (runtime-customisable)

public final class LogFilter: @unchecked Sendable {
    private let lock = NSLock()
    private var categoryStates: [HRSenseLogCategory: Bool] = [:]
    private var _minimumLevel: HRSenseLogLevel = .debug

    public init(enabledByDefault: Bool = true) {
        for cat in HRSenseLogCategory.allCases {
            categoryStates[cat] = enabledByDefault
        }
    }

    public func isEnabled(_ category: HRSenseLogCategory, level: HRSenseLogLevel) -> Bool {
        lock.withLock {
            (categoryStates[category] ?? true) && level >= _minimumLevel
        }
    }

    public func setEnabled(_ category: HRSenseLogCategory, enabled: Bool) {
        lock.withLock { categoryStates[category] = enabled }
    }

    public func isCategoryEnabled(_ category: HRSenseLogCategory) -> Bool {
        lock.withLock { categoryStates[category] ?? true }
    }

    public var minimumLevel: HRSenseLogLevel {
        lock.withLock { _minimumLevel }
    }

    public func setMinimumLevel(_ level: HRSenseLogLevel) {
        lock.withLock { _minimumLevel = level }
    }

    public func enableAll() {
        lock.withLock { for k in categoryStates.keys { categoryStates[k] = true } }
    }

    public func disableAll() {
        lock.withLock { for k in categoryStates.keys { categoryStates[k] = false } }
    }
}

// MARK: - Logger protocol

public protocol HRSenseLogger: Sendable {
    func log(_ level: HRSenseLogLevel, category: HRSenseLogCategory, _ message: @autoclosure () -> String)
}

// MARK: - OSLog-backed logger

public final class OSLogHRSenseLogger: HRSenseLogger, @unchecked Sendable {
    private let filter: LogFilter
    private var loggers: [HRSenseLogCategory: os.Logger] = [:]

    public init(subsystem: String = "com.hrsense", filter: LogFilter = LogFilter()) {
        self.filter = filter
        for cat in HRSenseLogCategory.allCases {
            loggers[cat] = os.Logger(subsystem: subsystem, category: cat.rawValue)
        }
    }

    public func log(_ level: HRSenseLogLevel, category: HRSenseLogCategory, _ message: @autoclosure () -> String) {
        guard filter.isEnabled(category, level: level) else { return }
        let msg = message()
        loggers[category]?.log(level: level.osLogType, "\(msg)")
    }
}

public struct NoOpLogger: HRSenseLogger, Sendable {
    public init() {}
    public func log(_ level: HRSenseLogLevel, category: HRSenseLogCategory, _ message: @autoclosure () -> String) {}
}

// MARK: - Registry (thread-safe singleton)

public final class LoggingRegistry: @unchecked Sendable {
    private var _logger: HRSenseLogger = NoOpLogger()
    private var _filter: LogFilter = LogFilter()
    private var _ringBuffer: LogRingBuffer = LogRingBuffer()
    private let lock = NSLock()

    public var logger: HRSenseLogger {
        get { lock.withLock { _logger } }
        set { lock.withLock { _logger = newValue } }
    }

    public var filter: LogFilter {
        get { lock.withLock { _filter } }
    }

    public var ringBuffer: LogRingBuffer {
        get { lock.withLock { _ringBuffer } }
    }

    public static let shared = LoggingRegistry()

    private init() {}
}

// MARK: - Convenience API

public enum HRSenseLogging {
    private static func record(_ level: HRSenseLogLevel, category: HRSenseLogCategory, _ message: String) {
        LoggingRegistry.shared.ringBuffer.append(
            LogEntry(
                category: category.rawValue,
                level: String(describing: level).uppercased(),
                message: message
            )
        )
        LoggingRegistry.shared.logger.log(level, category: category, message)
    }

    public static func debug(_ category: HRSenseLogCategory, _ message: @autoclosure () -> String) {
        record(.debug, category: category, message())
    }
    public static func info(_ category: HRSenseLogCategory, _ message: @autoclosure () -> String) {
        record(.info, category: category, message())
    }
    public static func notice(_ category: HRSenseLogCategory, _ message: @autoclosure () -> String) {
        record(.notice, category: category, message())
    }
    public static func error(_ category: HRSenseLogCategory, _ message: @autoclosure () -> String) {
        record(.error, category: category, message())
    }
    public static func fault(_ category: HRSenseLogCategory, _ message: @autoclosure () -> String) {
        record(.fault, category: category, message())
    }

    /// Legacy compatibility
    public static func warn(_ category: HRSenseLogCategory, _ message: @autoclosure () -> String) {
        record(.error, category: category, message())
    }

    /// Activate the OSLog-backed logger (call once at app startup).
    public static func activateOSLog(subsystem: String = "com.hrsense") {
        LoggingRegistry.shared.logger = OSLogHRSenseLogger(subsystem: subsystem)
    }
}
