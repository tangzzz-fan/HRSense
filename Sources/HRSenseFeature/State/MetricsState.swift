import Foundation
import HRSenseCore

/// Performance metrics sub-state.
public struct MetricsState: Equatable, Sendable {
    /// Latest HRV computation result.
    public var latestHRV: HRVMetrics?
    /// Computation status.
    public var computationStatus: ComputationStatus

    public enum ComputationStatus: Equatable, Sendable {
        case idle
        case computing
        case ready
    }

    public init(latestHRV: HRVMetrics? = nil, computationStatus: ComputationStatus = .idle) {
        self.latestHRV = latestHRV
        self.computationStatus = computationStatus
    }
}
