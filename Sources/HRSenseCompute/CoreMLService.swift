import Foundation
import CoreML

/// Thin wrapper around a CoreML model file.
///
/// M8 baseline: loads a placeholder model (14 features → 2 classes: Baseline/Stress).
/// Swappable for real trained models with the same input/output spec.
public final class CoreMLService: @unchecked Sendable {
    public struct Configuration: Sendable {
        public let expectedFeatureCount: Int
        public let fallbackModelVersion: String
        public let inputFeatureName: String
        public let classLabelOutputName: String
        public let classProbabilityOutputName: String
        public let fallbackPredictor: (@Sendable ([Float]) -> PredictionResult?)?

        public init(
            expectedFeatureCount: Int,
            fallbackModelVersion: String,
            inputFeatureName: String = "features",
            classLabelOutputName: String = "classLabel",
            classProbabilityOutputName: String = "classProbability",
            fallbackPredictor: (@Sendable ([Float]) -> PredictionResult?)? = nil
        ) {
            self.expectedFeatureCount = expectedFeatureCount
            self.fallbackModelVersion = fallbackModelVersion
            self.inputFeatureName = inputFeatureName
            self.classLabelOutputName = classLabelOutputName
            self.classProbabilityOutputName = classProbabilityOutputName
            self.fallbackPredictor = fallbackPredictor
        }

        public static let stressClassifier = Configuration(
            expectedFeatureCount: 14,
            fallbackModelVersion: "fallback-rule-engine",
            fallbackPredictor: { features in
                let rmssd = features[1]
                let hr = features[4]
                let isStress = hr > 90 || rmssd < 30
                return PredictionResult(
                    label: isStress ? "Stress" : "Baseline",
                    probabilities: isStress
                        ? ["Baseline": 0.3, "Stress": 0.7]
                        : ["Baseline": 0.7, "Stress": 0.3],
                    inferenceTimeMs: 0.05
                )
            }
        )

        public static let sleepStageClassifier = Configuration(
            expectedFeatureCount: 18,
            fallbackModelVersion: "sleep-stage-fallback-v1"
        )
    }

    private let model: MLModel?
    private let configuration: Configuration
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
        selectionStrategy: any ModelSelectionStrategy = DefaultModelSelectionStrategy(),
        configuration: Configuration = .stressClassifier
    ) {
        self.configuration = configuration
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
            self.activeModelVersion = configuration.fallbackModelVersion
        }
    }

    /// Run inference on a feature vector whose shape is defined by `configuration`.
    /// Returns a PredictionResult, or nil if the feature vector shape is invalid.
    public func predict(features: [Float]) -> PredictionResult? {
        guard features.count == configuration.expectedFeatureCount else { return nil }

        guard let model = model else {
            return configuration.fallbackPredictor?(features)
        }

        let start = CFAbsoluteTimeGetCurrent()

        do {
            let multiArray = try MLMultiArray(
                shape: [NSNumber(value: configuration.expectedFeatureCount)],
                dataType: .float32
            )
            for (index, feature) in features.enumerated() {
                multiArray[index] = NSNumber(value: feature)
            }
            let input = try MLDictionaryFeatureProvider(dictionary: [
                configuration.inputFeatureName: multiArray
            ])
            let output = try model.prediction(from: input)

            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0

            var label = "Unknown"
            var probs: [String: Double] = [:]
            if let classLabel = output.featureValue(for: configuration.classLabelOutputName)?.stringValue {
                label = classLabel
            }
            if let probDict = output.featureValue(for: configuration.classProbabilityOutputName)?.dictionaryValue {
                for (k, v) in probDict {
                    probs[String(describing: k)] = v.doubleValue
                }
            }

            if probs.isEmpty {
                probs = [label: 1]
            }

            return PredictionResult(label: label, probabilities: probs, inferenceTimeMs: elapsed)
        } catch {
            return configuration.fallbackPredictor?(features)
        }
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
