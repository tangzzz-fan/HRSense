import Foundation
import CoreML

/// Thin wrapper around a CoreML model file.
///
/// M8 baseline: loads a placeholder model (14 features → 2 classes: Baseline/Stress).
/// Swappable for real trained models with the same input/output spec.
public final class CoreMLService: @unchecked Sendable {
    private enum Constants {
        static let expectedFeatureCount = 14
        static let fallbackModelVersion = "fallback-rule-engine"
    }

    private let model: MLModel?
    public let activeModelDescriptor: ModelDescriptor?
    public let activeModelVersion: String

    public struct PredictionResult: Sendable {
        public let label: String
        public let probabilities: [String: Double]
        public let inferenceTimeMs: Double
    }

    /// Loads an explicitly provided model URL or resolves one through the catalog + strategy pair.
    public init(
        modelURL: URL? = nil,
        selectionRequest: ModelSelectionRequest = .stressClassifierV1,
        modelCatalog: any CoreMLModelCatalog = BundleCoreMLModelCatalog(),
        selectionStrategy: any ModelSelectionStrategy = DefaultModelSelectionStrategy()
    ) {
        let selectedDescriptor = Self.resolveDescriptor(
            modelURL: modelURL,
            selectionRequest: selectionRequest,
            modelCatalog: modelCatalog,
            selectionStrategy: selectionStrategy
        )

        if
            let selectedDescriptor,
            let loadedModel = Self.loadModel(at: selectedDescriptor.url)
        {
            self.model = loadedModel
            let resolvedVersion = CoreMLModelInspector.modelVersion(from: loadedModel.modelDescription.metadata)
                ?? selectedDescriptor.modelVersion
            self.activeModelDescriptor = ModelDescriptor(
                modelName: selectedDescriptor.modelName,
                modelVersion: resolvedVersion,
                task: selectedDescriptor.task,
                featureContractVersion: selectedDescriptor.featureContractVersion,
                url: selectedDescriptor.url
            )
            self.activeModelVersion = resolvedVersion
        } else {
            self.model = nil
            self.activeModelDescriptor = nil
            self.activeModelVersion = Constants.fallbackModelVersion
        }
    }

    /// Run inference on a 14-element feature vector.
    /// Returns a PredictionResult, or nil if the feature vector shape is invalid.
    public func predict(features: [Float]) -> PredictionResult? {
        guard features.count == Constants.expectedFeatureCount else { return nil }

        guard let model = model else {
            return fallbackPrediction(features: features)
        }

        let start = CFAbsoluteTimeGetCurrent()

        do {
            let multiArray = try MLMultiArray(
                shape: [NSNumber(value: Constants.expectedFeatureCount)],
                dataType: .float32
            )
            for (index, feature) in features.enumerated() {
                multiArray[index] = NSNumber(value: feature)
            }
            let input = try MLDictionaryFeatureProvider(dictionary: [
                "features": multiArray
            ])
            let output = try model.prediction(from: input)

            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0

            var label = "Baseline"
            var probs: [String: Double] = [:]
            if let classLabel = output.featureValue(for: "classLabel")?.stringValue {
                label = classLabel
            }
            if let probDict = output.featureValue(for: "classProbability")?.dictionaryValue {
                for (k, v) in probDict {
                    probs[String(describing: k)] = v.doubleValue
                }
            }

            if probs.isEmpty {
                probs = defaultProbabilities(for: label)
            }

            return PredictionResult(label: label, probabilities: probs, inferenceTimeMs: elapsed)
        } catch {
            return fallbackPrediction(features: features)
        }
    }

    /// Fallback: simple rule-based prediction when no model is loaded.
    private func fallbackPrediction(features: [Float]) -> PredictionResult {
        // Rule: if RMSSD (index 1) is low or HR (index 4) is high, classify "Stress"
        let rmssd = features[1]
        let hr = features[4]
        let isStress = hr > 90 || rmssd < 30
        return PredictionResult(
            label: isStress ? "Stress" : "Baseline",
            probabilities: defaultProbabilities(for: isStress ? "Stress" : "Baseline"),
            inferenceTimeMs: 0.05
        )
    }

    private func defaultProbabilities(for label: String) -> [String: Double] {
        if label == "Stress" {
            return ["Baseline": 0.3, "Stress": 0.7]
        }
        return ["Baseline": 0.7, "Stress": 0.3]
    }

    private static func loadModel(at url: URL) -> MLModel? {
        CoreMLModelInspector.loadModel(at: url)
    }

    private static func resolveDescriptor(
        modelURL: URL?,
        selectionRequest: ModelSelectionRequest,
        modelCatalog: any CoreMLModelCatalog,
        selectionStrategy: any ModelSelectionStrategy
    ) -> ModelDescriptor? {
        if let modelURL {
            return CoreMLModelInspector.inspectModel(at: modelURL) ?? ModelDescriptor(
                modelName: modelURL.deletingPathExtension().lastPathComponent,
                modelVersion: CoreMLModelInspector.modelVersionFallback(from: modelURL),
                task: selectionRequest.task.rawValue,
                featureContractVersion: selectionRequest.featureContractVersion,
                url: modelURL
            )
        }

        return selectionStrategy.selectModel(
            from: modelCatalog.discoverModels(),
            request: selectionRequest
        )
    }
}
