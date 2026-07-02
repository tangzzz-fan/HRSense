import Foundation
import HRSenseCore

/// M3 stub — full implementation in M5 (C++ compute bridge).
public final class ComputeRepositoryImpl: ComputeRepository, @unchecked Sendable {
    public init() {}

    public func computeHRV(from rrIntervalsMs: [Int]) throws -> HRVMetrics {
        // Stub — returns placeholder metrics
        guard rrIntervalsMs.count >= 2 else {
            throw AppError.computeFailed
        }
        _ = Double(rrIntervalsMs.reduce(0, +)) / Double(rrIntervalsMs.count)
        return HRVMetrics(sdnn: 0, rmssd: 0)
    }
}
