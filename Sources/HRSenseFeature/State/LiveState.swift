import Foundation
import HRSenseCore

/// Live sensor data sub-state — kept bounded for UI rendering.
public struct LiveState: Equatable, Sendable {
    /// Most recent heart rate value (nil if no data yet).
    public var currentHeartRate: Int?
    /// Recent samples ring buffer (max ~600, ~10 min @ 1 Hz).
    public var recentSamples: [HeartRateSample]
    /// Last update timestamp.
    public var lastUpdated: Date?

    public init(
        currentHeartRate: Int? = nil,
        recentSamples: [HeartRateSample] = [],
        lastUpdated: Date? = nil
    ) {
        self.currentHeartRate = currentHeartRate
        self.recentSamples = recentSamples
        self.lastUpdated = lastUpdated
    }
}
