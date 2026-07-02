import Foundation
import HRSenseCore

/// ML inference sub-state.
public struct InferenceState: Equatable, Sendable {
    /// Latest inference result.
    public var latestResult: InferenceResult?
    /// Inference pipeline status.
    public var status: InferenceStatus

    public enum InferenceStatus: Equatable, Sendable {
        case idle
        case running
        case completed
    }

    public init(latestResult: InferenceResult? = nil, status: InferenceStatus = .idle) {
        self.latestResult = latestResult
        self.status = status
    }
}
