import Foundation
import HRSenseCore

/// M3 stub — full implementation in M8 (CoreML).
public final class InferenceRepositoryImpl: InferenceRepository, @unchecked Sendable {
    public init() {}

    public func runInference(features: [Float]) async throws -> InferenceResult {
        // Stub — returns placeholder result
        return InferenceResult(label: "Baseline", confidence: 0.5)
    }
}
