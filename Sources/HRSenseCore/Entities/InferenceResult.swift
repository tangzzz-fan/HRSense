import Foundation

/// The result of a CoreML inference pass (M8).
public struct InferenceResult: Equatable, Sendable {
    /// Predicted class label (e.g. "Baseline", "Stress").
    public let label: String
    /// Class probabilities (label → probability).
    public let probabilities: [String: Float]
    /// Inference latency in milliseconds.
    public let inferenceTimeMs: Double
    /// Wall-clock timestamp of inference completion.
    public let timestamp: Date
    /// Model version string.
    public let modelVersion: String

    public init(
        label: String,
        probabilities: [String: Float] = [:],
        inferenceTimeMs: Double = 0,
        timestamp: Date = Date(),
        modelVersion: String = "1.0.0"
    ) {
        self.label = label
        self.probabilities = probabilities
        self.inferenceTimeMs = inferenceTimeMs
        self.timestamp = timestamp
        self.modelVersion = modelVersion
    }
}
