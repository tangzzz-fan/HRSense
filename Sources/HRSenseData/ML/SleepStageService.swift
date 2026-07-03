import Foundation
import HRSenseCore

/// Phase 5 bootstrap service.
///
/// This service intentionally starts with a deterministic rule fallback so the
/// sleep pipeline can be wired before a real CoreML asset is integrated.
public final class SleepStageService: @unchecked Sendable {
    private let activeModelVersion: String
    private let nowProvider: @Sendable () -> Date

    public init(
        activeModelVersion: String = "sleep-stage-fallback-v1",
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.activeModelVersion = activeModelVersion
        self.nowProvider = nowProvider
    }

    public func predict(input: SleepWindowInput) -> SleepStagePrediction {
        let probabilities = makeProbabilities(input: input)
        let best = probabilities.max { lhs, rhs in lhs.value < rhs.value } ?? (.light, 1.0)

        return SleepStagePrediction(
            stage: best.key,
            confidence: best.value,
            probabilities: probabilities,
            modelVersion: activeModelVersion,
            timestamp: nowProvider()
        )
    }

    private func makeProbabilities(input: SleepWindowInput) -> [SleepStage: Float] {
        let metrics = input.metrics
        let minutesSinceSessionStart = input.timeContext.minutesSinceSessionStart
        let localClockMinutes = input.timeContext.localClockMinutes
        let hrTrend = input.cxxFeatures.hrTrend
        let circadianVariation = input.cxxFeatures.circadianVariation

        if metrics.hr >= 82 || metrics.stressIndex >= 550 {
            return [.wake: 0.82, .light: 0.10, .rem: 0.05, .deep: 0.03]
        }

        if metrics.rmssd >= 65,
           metrics.hfPower >= metrics.lfPower,
           metrics.hr <= 58,
           hrTrend <= 0 {
            return [.deep: 0.76, .light: 0.14, .rem: 0.07, .wake: 0.03]
        }

        if metrics.sampleEntropy >= 1.25,
           metrics.hr <= 72,
           metrics.lfHfRatio < 1.5,
           circadianVariation >= 0.2,
           localClockMinutes >= 60,
           minutesSinceSessionStart >= 30 {
            return [.rem: 0.68, .light: 0.18, .deep: 0.08, .wake: 0.06]
        }

        return [.light: 0.64, .rem: 0.18, .deep: 0.12, .wake: 0.06]
    }
}
