import Foundation

/// Repository protocol for CoreML inference (M8 placeholder).
public protocol InferenceRepository: AnyObject, Sendable {
    /// Run inference on a feature vector.
    func runInference(features: [Float]) async throws -> InferenceResult
}
