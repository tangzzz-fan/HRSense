import XCTest
@testable import HRSenseCore

final class SleepModelFeatureSpecTests: XCTestCase {
    func test_sleepFeatureContractRemainsStable() {
        XCTAssertEqual(SleepModelFeatureSpec.contractVersion, 1)
        XCTAssertEqual(SleepModelFeatureSpec.featureCount, 18)
        XCTAssertEqual(
            SleepModelFeatureSpec.orderedFeatureNames,
            [
                "sdnn",
                "rmssd",
                "pnn50",
                "mean_rr",
                "heart_rate",
                "lf_power",
                "hf_power",
                "lf_hf_ratio",
                "total_power",
                "sd1",
                "sd2",
                "sample_entropy",
                "dfa_alpha1",
                "stress_index",
                "minutes_since_session_start",
                "local_clock_minutes",
                "hr_trend",
                "circadian_variation",
            ]
        )
    }

    func test_sleepWindowInputEncodesWithFrozenFeatureOrder() {
        let input = SleepWindowInput(
            metrics: HRVMetrics(
                sdnn: 1,
                rmssd: 2,
                pnn50: 3,
                meanRR: 4,
                hr: 5,
                lfPower: 6,
                hfPower: 7,
                lfHfRatio: 8,
                totalPower: 9,
                sd1: 10,
                sd2: 11,
                sampleEntropy: 12,
                dfaAlpha1: 13,
                stressIndex: 14
            ),
            timeContext: SleepTimeContext(
                windowStart: Date(timeIntervalSince1970: 1_725_000_000),
                windowEnd: Date(timeIntervalSince1970: 1_725_000_300),
                minutesSinceSessionStart: 15,
                localClockMinutes: 120
            ),
            cxxFeatures: SleepCXXFeatures(hrTrend: -0.25, circadianVariation: 0.42)
        )

        XCTAssertEqual(input.contractVersion, SleepModelFeatureSpec.contractVersion)
        let expected: [Float] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 120, -0.25, 0.42]
        let actual = input.toFeatureVector()
        XCTAssertEqual(actual.count, expected.count)
        for (lhs, rhs) in zip(actual, expected) {
            XCTAssertEqual(lhs, rhs, accuracy: 0.0001)
        }
    }
}
