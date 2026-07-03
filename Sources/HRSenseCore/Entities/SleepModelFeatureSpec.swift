import Foundation

/// Canonical feature contract for the future sleep-stage CoreML model.
///
/// Keep this schema stable across:
/// - model training/export
/// - runtime feature assembly
/// - debugging / gap documentation
public enum SleepModelFeatureSpec {
    public struct Feature: Equatable, Sendable {
        public let index: Int
        public let name: String
        public let source: String

        public init(index: Int, name: String, source: String) {
            self.index = index
            self.name = name
            self.source = source
        }
    }

    public static let contractVersion = 1

    public static let orderedFeatures: [Feature] = [
        Feature(index: 0, name: "sdnn", source: "HRVMetrics"),
        Feature(index: 1, name: "rmssd", source: "HRVMetrics"),
        Feature(index: 2, name: "pnn50", source: "HRVMetrics"),
        Feature(index: 3, name: "mean_rr", source: "HRVMetrics"),
        Feature(index: 4, name: "heart_rate", source: "HRVMetrics"),
        Feature(index: 5, name: "lf_power", source: "HRVMetrics"),
        Feature(index: 6, name: "hf_power", source: "HRVMetrics"),
        Feature(index: 7, name: "lf_hf_ratio", source: "HRVMetrics"),
        Feature(index: 8, name: "total_power", source: "HRVMetrics"),
        Feature(index: 9, name: "sd1", source: "HRVMetrics"),
        Feature(index: 10, name: "sd2", source: "HRVMetrics"),
        Feature(index: 11, name: "sample_entropy", source: "HRVMetrics"),
        Feature(index: 12, name: "dfa_alpha1", source: "HRVMetrics"),
        Feature(index: 13, name: "stress_index", source: "HRVMetrics"),
        Feature(index: 14, name: "minutes_since_session_start", source: "SleepTimeContext"),
        Feature(index: 15, name: "local_clock_minutes", source: "SleepTimeContext"),
        Feature(index: 16, name: "hr_trend", source: "SleepCXXFeatures"),
        Feature(index: 17, name: "circadian_variation", source: "SleepCXXFeatures"),
    ]

    public static let orderedFeatureNames = orderedFeatures.map(\.name)
    public static let featureCount = orderedFeatures.count

    public static func encode(_ input: SleepWindowInput) -> [Float] {
        input.metrics.toFeatureVector() + [
            Float(input.timeContext.minutesSinceSessionStart),
            Float(input.timeContext.localClockMinutes),
            Float(input.cxxFeatures.hrTrend),
            Float(input.cxxFeatures.circadianVariation),
        ]
    }
}
