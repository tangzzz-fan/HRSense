import XCTest
@testable import HRSenseCore
@testable import HRSenseData

final class SleepInferenceRepositoryImplTests: XCTestCase {
    func test_inferSleepStageReturnsWakeForHighStressWindow() async throws {
        let repository = SleepInferenceRepositoryImpl()

        let prediction = try await repository.inferSleepStage(
            input: SleepWindowInput(
                metrics: HRVMetrics(
                    rmssd: 18,
                    hr: 92,
                    lfPower: 120,
                    hfPower: 80,
                    lfHfRatio: 2.1,
                    sampleEntropy: 0.8,
                    stressIndex: 640
                ),
                timeContext: SleepTimeContext(
                    windowStart: Date(timeIntervalSince1970: 1_725_000_000),
                    windowEnd: Date(timeIntervalSince1970: 1_725_000_300),
                    minutesSinceSessionStart: 10,
                    localClockMinutes: 23 * 60
                )
            )
        )

        XCTAssertEqual(prediction.stage, .wake)
        XCTAssertEqual(prediction.modelVersion, "sleep-stage-fallback-v1")
        XCTAssertEqual(prediction.probabilities[.wake] ?? 0, 0.82, accuracy: 0.0001)
    }

    func test_inferSleepStageReturnsDeepForHighParasympatheticWindow() async throws {
        let repository = SleepInferenceRepositoryImpl()

        let prediction = try await repository.inferSleepStage(
            input: SleepWindowInput(
                metrics: HRVMetrics(
                    rmssd: 82,
                    hr: 52,
                    lfPower: 320,
                    hfPower: 460,
                    lfHfRatio: 0.9,
                    sampleEntropy: 1.1,
                    stressIndex: 120
                ),
                timeContext: SleepTimeContext(
                    windowStart: Date(timeIntervalSince1970: 1_725_000_000),
                    windowEnd: Date(timeIntervalSince1970: 1_725_000_300),
                    minutesSinceSessionStart: 40,
                    localClockMinutes: 2 * 60 + 30
                ),
                cxxFeatures: SleepCXXFeatures(hrTrend: -0.18, circadianVariation: 0.12)
            )
        )

        XCTAssertEqual(prediction.stage, .deep)
        XCTAssertEqual(prediction.probabilities[.deep] ?? 0, 0.76, accuracy: 0.0001)
    }

    func test_sleepWindowInputFlattensMetricsTimeAndCxxFeatures() {
        let input = SleepWindowInput(
            metrics: HRVMetrics(
                rmssd: 18,
                meanRR: 800,
                hr: 75,
                stressIndex: 220
            ),
            timeContext: SleepTimeContext(
                windowStart: Date(timeIntervalSince1970: 1_725_000_000),
                windowEnd: Date(timeIntervalSince1970: 1_725_000_300),
                minutesSinceSessionStart: 35,
                localClockMinutes: 90
            ),
            cxxFeatures: SleepCXXFeatures(hrTrend: -0.25, circadianVariation: 0.42)
        )

        let flattened = input.toFeatureVector()

        XCTAssertEqual(input.contractVersion, SleepWindowInput.currentContractVersion)
        XCTAssertEqual(flattened.count, 18)
        XCTAssertEqual(flattened[14], 35, accuracy: 0.0001)
        XCTAssertEqual(flattened[15], 90, accuracy: 0.0001)
        XCTAssertEqual(flattened[16], -0.25, accuracy: 0.0001)
        XCTAssertEqual(flattened[17], 0.42, accuracy: 0.0001)
    }
}
