import Foundation

/// Time context attached to one sleep-stage inference window.
public struct SleepTimeContext: Equatable, Sendable {
    public let windowStart: Date
    public let windowEnd: Date
    public let minutesSinceSessionStart: Int
    public let localClockMinutes: Int

    public init(
        windowStart: Date,
        windowEnd: Date,
        minutesSinceSessionStart: Int,
        localClockMinutes: Int
    ) {
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.minutesSinceSessionStart = minutesSinceSessionStart
        self.localClockMinutes = localClockMinutes
    }

    public init(
        windowStart: Date,
        windowEnd: Date,
        sessionStart: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        let minutesSinceSessionStart = max(0, Int(windowEnd.timeIntervalSince(sessionStart) / 60.0))
        let components = calendar.dateComponents([.hour, .minute], from: windowStart)
        let localClockMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        self.init(
            windowStart: windowStart,
            windowEnd: windowEnd,
            minutesSinceSessionStart: minutesSinceSessionStart,
            localClockMinutes: localClockMinutes
        )
    }
}

/// Extra features produced by future C++ sleep-specific computation.
public struct SleepCXXFeatures: Equatable, Sendable {
    /// Planned C++ feature: windowed heart-rate linear trend.
    public let hrTrend: Double
    /// Planned C++ feature: multi-hour circadian HRV variation.
    public let circadianVariation: Double

    public init(
        hrTrend: Double = 0,
        circadianVariation: Double = 0
    ) {
        self.hrTrend = hrTrend
        self.circadianVariation = circadianVariation
    }
}

/// Canonical input contract for M9 phase 5 sleep-stage inference.
public struct SleepWindowInput: Equatable, Sendable {
    public static let currentContractVersion = 1

    public let metrics: HRVMetrics
    public let timeContext: SleepTimeContext
    public let cxxFeatures: SleepCXXFeatures
    public let contractVersion: Int

    public init(
        metrics: HRVMetrics,
        timeContext: SleepTimeContext,
        cxxFeatures: SleepCXXFeatures = SleepCXXFeatures(),
        contractVersion: Int = SleepWindowInput.currentContractVersion
    ) {
        self.metrics = metrics
        self.timeContext = timeContext
        self.cxxFeatures = cxxFeatures
        self.contractVersion = contractVersion
    }

    /// Flatten to a stable ordered vector for future CoreML model input.
    public func toFeatureVector() -> [Float] {
        metrics.toFeatureVector() + [
            Float(timeContext.minutesSinceSessionStart),
            Float(timeContext.localClockMinutes),
            Float(cxxFeatures.hrTrend),
            Float(cxxFeatures.circadianVariation),
        ]
    }
}
