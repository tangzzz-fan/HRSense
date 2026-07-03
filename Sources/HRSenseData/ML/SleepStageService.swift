import Foundation
import HRSenseCore
import HRSenseCompute

/// Phase 5 bootstrap service.
///
/// This service intentionally starts with a deterministic rule fallback so the
/// sleep pipeline can be wired before a real CoreML asset is integrated.
public final class SleepStageService: @unchecked Sendable {
    private let mlService: CoreMLService
    private let nowProvider: @Sendable () -> Date

    public init(
        modelURL: URL? = nil,
        modelCatalog: any CoreMLModelCatalog = BundleCoreMLModelCatalog(),
        selectionStrategy: any ModelSelectionStrategy = DefaultModelSelectionStrategy(),
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.mlService = CoreMLService(
            modelURL: modelURL ?? Self.resolveDefaultModelURL(),
            selectionRequest: .sleepStageClassifierV1,
            modelCatalog: modelCatalog,
            selectionStrategy: selectionStrategy,
            configuration: .sleepStageClassifier
        )
        self.nowProvider = nowProvider
    }

    public func predict(input: SleepWindowInput) -> SleepStagePrediction {
        if let modelPrediction = predictWithCoreML(input: input) {
            return modelPrediction
        }

        return fallbackPrediction(input: input)
    }

    private func predictWithCoreML(input: SleepWindowInput) -> SleepStagePrediction? {
        guard let prediction = mlService.predict(features: input.toFeatureVector()) else {
            return nil
        }
        guard let stage = mapStage(label: prediction.label) else {
            return nil
        }

        let probabilities = prediction.probabilities.reduce(into: [SleepStage: Float]()) { partial, entry in
            if let stage = mapStage(label: entry.key) {
                partial[stage] = Float(entry.value)
            }
        }

        let confidence = probabilities[stage] ?? 1
        return SleepStagePrediction(
            stage: stage,
            confidence: confidence,
            probabilities: probabilities,
            modelVersion: mlService.activeModelVersion,
            timestamp: nowProvider()
        )
    }

    private func fallbackPrediction(input: SleepWindowInput) -> SleepStagePrediction {
        let probabilities = makeFallbackProbabilities(input: input)
        let best = probabilities.max { lhs, rhs in lhs.value < rhs.value } ?? (.light, 1.0)

        return SleepStagePrediction(
            stage: best.key,
            confidence: best.value,
            probabilities: probabilities,
            modelVersion: "sleep-stage-fallback-v1",
            timestamp: nowProvider()
        )
    }

    private func makeFallbackProbabilities(input: SleepWindowInput) -> [SleepStage: Float] {
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

    private func mapStage(label: String) -> SleepStage? {
        switch label.lowercased() {
        case "wake":
            return .wake
        case "light":
            return .light
        case "deep":
            return .deep
        case "rem":
            return .rem
        default:
            return nil
        }
    }

    private static func resolveDefaultModelURL() -> URL? {
        if let bundledURL = Bundle.main.url(forResource: "SleepStageClassifier_v1", withExtension: "mlpackage") {
            return bundledURL
        }

        let workingDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let projectModelURL = workingDirectoryURL
            .appendingPathComponent("Models")
            .appendingPathComponent("SleepStageClassifier_v1.mlpackage")

        if FileManager.default.fileExists(atPath: projectModelURL.path) {
            return projectModelURL
        }

        return nil
    }
}
