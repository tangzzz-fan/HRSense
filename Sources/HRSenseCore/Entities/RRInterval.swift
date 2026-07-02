import Foundation

/// Domain value object: a single RR interval.
public struct RRInterval: Equatable, Sendable {
    public let timestamp: Date
    /// Interval in milliseconds.
    public let intervalMs: Int

    public init(timestamp: Date, intervalMs: Int) {
        self.timestamp = timestamp
        self.intervalMs = intervalMs
    }
}
