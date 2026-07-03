import Foundation
import HRSenseCore
import HRSenseCompute

/// Implements ComputeRepository using ComputeBridge (C ABI).
public final class ComputeRepositoryImpl: ComputeRepository, @unchecked Sendable {
    private let bridge = ComputeBridge()

    public init() {}

    public func computeHRV(from rrIntervalsMs: [Int]) throws -> HRVMetrics {
        try bridge.computeHRV(from: rrIntervalsMs.map { UInt16($0) })
    }
}
