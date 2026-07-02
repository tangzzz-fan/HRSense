import Foundation

// MARK: - Logging façade

/// Log category for HRSenseProtocol.
public enum HRSenseLogCategory: String, Sendable, CaseIterable {
    case framing
    case crc
    case tlv
    case codec
    case command
    case data
    case ack
    case event
    case ota
    case waveform
}

/// Log severity level.
public enum HRSenseLogLevel: Int, Sendable, Comparable {
    case debug   = 0
    case info    = 1
    case warning = 2
    case error   = 3

    public static func < (lhs: HRSenseLogLevel, rhs: HRSenseLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Minimal logging interface — concrete logger injected by the app/simulator.
public protocol HRSenseLogger: Sendable {
    func log(_ level: HRSenseLogLevel, category: HRSenseLogCategory, _ message: @autoclosure () -> String)
}

/// Default no-op logger.
public struct NoOpLogger: HRSenseLogger, Sendable {
    public init() {}
    public func log(_ level: HRSenseLogLevel, category: HRSenseLogCategory, _ message: @autoclosure () -> String) {}
}

/// Thread-safe global logger reference — replace during app startup.
/// Replaced at startup time exclusively; read-heavy at runtime.
public final class LoggingRegistry: @unchecked Sendable {
    private var _logger: HRSenseLogger = NoOpLogger()
    private let lock = NSLock()

    public var logger: HRSenseLogger {
        get { lock.withLock { _logger } }
        set { lock.withLock { _logger = newValue } }
    }

    public static let shared = LoggingRegistry()

    private init() {}
}

/// Static convenience accessors — delegate to the thread-safe shared registry.
public enum HRSenseLogging {
    public static func debug(_ category: HRSenseLogCategory, _ message: @autoclosure () -> String) {
        LoggingRegistry.shared.logger.log(.debug, category: category, message())
    }
    public static func info(_ category: HRSenseLogCategory, _ message: @autoclosure () -> String) {
        LoggingRegistry.shared.logger.log(.info, category: category, message())
    }
    public static func warn(_ category: HRSenseLogCategory, _ message: @autoclosure () -> String) {
        LoggingRegistry.shared.logger.log(.warning, category: category, message())
    }
    public static func error(_ category: HRSenseLogCategory, _ message: @autoclosure () -> String) {
        LoggingRegistry.shared.logger.log(.error, category: category, message())
    }
}
