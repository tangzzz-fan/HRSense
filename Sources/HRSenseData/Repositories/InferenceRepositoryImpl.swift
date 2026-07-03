import Foundation
import HRSenseCore

/// M3 stub — full implementation in M8 (CoreML).
public final class InferenceRepositoryImpl: InferenceRepository, @unchecked Sendable {
    public init() {}

    public func runInference(features: [Float]) async throws -> InferenceResult {
        return InferenceResult(label: "Baseline", probabilities: ["Baseline": 0.7, "Stress": 0.3], modelVersion: "1.0.0")
    }
}
