/// Repository protocol for HRV computation (M5 placeholder).
/// Upper layers depend on this protocol; implementation in HRSenseData → HRSenseCompute.
public protocol ComputeRepository: AnyObject, Sendable {
    /// Compute HRV metrics from a sequence of RR intervals (ms).
    func computeHRV(from rrIntervalsMs: [Int]) throws -> HRVMetrics

    /// Compute sleep-specific auxiliary features from recent heart-rate and HRV history.
    func computeSleepFeatures(
        heartRates: [Int],
        hrvWindowValues: [Double]
    ) throws -> SleepCXXFeatures
}
