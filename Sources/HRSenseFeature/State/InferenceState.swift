import Foundation
import HRSenseCore

/// ML inference sub-state.
public struct InferenceState: Equatable, Sendable {
    /// Latest extracted feature vector that is about to be inferred.
    public var latestFeatures: FeatureVector?
    /// Latest inference result.
    public var latestResult: InferenceResult?
    /// Inference pipeline status.
    public var status: InferenceStatus

    public enum InferenceStatus: Equatable, Sendable {
        case idle
        case running
        case completed
    }

    public init(
        latestFeatures: FeatureVector? = nil,
        latestResult: InferenceResult? = nil,
        status: InferenceStatus = .idle
    ) {
        self.latestFeatures = latestFeatures
        self.latestResult = latestResult
        self.status = status
    }
}
