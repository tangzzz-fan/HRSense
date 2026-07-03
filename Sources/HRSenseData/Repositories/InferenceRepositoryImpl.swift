import Foundation
import HRSenseCore
import HRSenseCompute

/// Implements InferenceRepository using CoreMLService (M8).
///
/// Loads a CoreML model if available, falling back to a rule-based heuristic
/// when no model file is found. This allows the full pipeline to operate
/// end-to-end without requiring a real trained model during development.
public final class InferenceRepositoryImpl: InferenceRepository, @unchecked Sendable {
    private let mlService: CoreMLService

    public init(mlService: CoreMLService = CoreMLService()) {
        self.mlService = mlService
    }

    public convenience init(
        selectionRequest: ModelSelectionRequest,
        modelCatalog: any CoreMLModelCatalog = BundleCoreMLModelCatalog(),
        selectionStrategy: any ModelSelectionStrategy = DefaultModelSelectionStrategy()
    ) {
        self.init(
            mlService: CoreMLService(
                selectionRequest: selectionRequest,
                modelCatalog: modelCatalog,
                selectionStrategy: selectionStrategy
            )
        )
    }

    public func runInference(features: [Float]) async throws -> InferenceResult {
        let result = mlService.predict(features: features)

        if let prediction = result {
            return InferenceResult(
                label: prediction.label,
                probabilities: prediction.probabilities.mapValues { Float($0) },
                inferenceTimeMs: prediction.inferenceTimeMs,
                timestamp: Date(),
                modelVersion: mlService.activeModelVersion
            )
        }

        // If model failed to load and fallback returned nil, return default
        return InferenceResult(
            label: "Baseline",
            probabilities: ["Baseline": 0.7, "Stress": 0.3],
            inferenceTimeMs: 0,
            timestamp: Date(),
            modelVersion: mlService.activeModelVersion
        )
    }
}
