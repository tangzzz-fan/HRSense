import Foundation
import CoreML

/// Thin wrapper around a CoreML model file.
///
/// M8 baseline: loads a placeholder model (14 features → 2 classes: Baseline/Stress).
/// Swappable for real trained models with the same input/output spec.
public final class CoreMLService: @unchecked Sendable {

    private var model: MLModel?

    public struct PredictionResult: Sendable {
        public let label: String
        public let probabilities: [String: Double]
        public let inferenceTimeMs: Double
    }

    /// Try to load a model from the app bundle or a file URL.
    public init(modelURL: URL? = nil) {
        if let url = modelURL {
            do {
                let compiledURL = try MLModel.compileModel(at: url)
                self.model = try MLModel(contentsOf: compiledURL)
            } catch {
                // Model loading failed — use fallback dummy
                self.model = nil
            }
        }
    }

    /// Run inference on a 14-element feature vector.
    /// Returns a PredictionResult, or nil if no model is loaded.
    public func predict(features: [Float]) -> PredictionResult? {
        guard features.count == 14 else { return nil }

        // If no model loaded, return dummy result
        guard let model = model else {
            return fallbackPrediction(features: features)
        }

        let start = CFAbsoluteTimeGetCurrent()

        do {
            let multiArray = try? MLMultiArray(shape: [14], dataType: .float32)
            for i in 0..<features.count {
                multiArray?[i] = NSNumber(value: features[i])
            }
            guard let inputArray = multiArray else { return nil }
            let input = try MLDictionaryFeatureProvider(dictionary: [
                "features": inputArray
            ])
            let output = try model.prediction(from: input)

            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0

            // Parse output
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

            return PredictionResult(label: label, probabilities: probs, inferenceTimeMs: elapsed)
        } catch {
            return nil
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
            probabilities: ["Baseline": isStress ? 0.3 : 0.7, "Stress": isStress ? 0.7 : 0.3],
            inferenceTimeMs: 0.05
        )
    }
}
