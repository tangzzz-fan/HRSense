import Foundation
import HRSenseCore
import HRSenseComputeCxx

/// Thin adapter layer between Swift and the C ABI compute functions.
///
/// This is the ONLY file that imports HRSenseComputeCxx — all upper layers
/// consume HRV metrics through ComputeRepository and this bridge.
///
/// Memory model: caller allocates, C function fills. No C++ types leak.
public struct ComputeBridge: Sendable {

    public init() {}

    /// Compute HRV metrics from an array of RR intervals (ms).
    /// - Parameter rrIntervalsMs: array of RR intervals in milliseconds.
    /// - Returns: fully populated HRVMetrics, or throws ComputeError.
    public func computeHRV(from rrIntervalsMs: [UInt16]) throws -> HRVMetrics {
        guard rrIntervalsMs.count >= 2 else {
            throw ComputeError.tooFewIntervals
        }

        var metrics = hrs_hrv_metrics_t()
        let result = rrIntervalsMs.withUnsafeBufferPointer { buf in
            hrs_compute_hrv(buf.baseAddress, buf.count, &metrics)
        }
        guard result == 0 else {
            throw ComputeError.computationFailed
        }

        return HRVMetrics(
            sdnn: metrics.sdnn,
            rmssd: metrics.rmssd,
            pnn50: metrics.pnn50,
            meanRR: metrics.mean_rr,
            hr: metrics.hr,
            lfPower: metrics.lf_power,
            hfPower: metrics.hf_power,
            lfHfRatio: metrics.lf_hf_ratio,
            totalPower: metrics.total_power,
            sd1: metrics.sd1,
            sd2: metrics.sd2,
            sampleEntropy: metrics.sample_entropy,
            dfaAlpha1: metrics.dfa_alpha1,
            stressIndex: metrics.stress_index
        )
    }

    /// Extract a 14-element feature vector from HRV metrics.
    public func extractFeatures(from metrics: HRVMetrics) -> [Float] {
        let values = metrics.toFeatureVector()
        // Cross-validate via C ABI
        var cMetrics = hrs_hrv_metrics_t()
        cMetrics.sdnn = metrics.sdnn
        cMetrics.rmssd = metrics.rmssd
        cMetrics.pnn50 = metrics.pnn50
        cMetrics.mean_rr = metrics.meanRR
        cMetrics.hr = metrics.hr
        cMetrics.lf_power = metrics.lfPower
        cMetrics.hf_power = metrics.hfPower
        cMetrics.lf_hf_ratio = metrics.lfHfRatio
        cMetrics.total_power = metrics.totalPower
        cMetrics.sd1 = metrics.sd1
        cMetrics.sd2 = metrics.sd2
        cMetrics.sample_entropy = metrics.sampleEntropy
        cMetrics.dfa_alpha1 = metrics.dfaAlpha1
        cMetrics.stress_index = metrics.stressIndex

        var cFeatures: [Float] = Array(repeating: 0, count: 14)
        hrs_extract_features(&cMetrics, &cFeatures)
        return cFeatures
    }

    /// Compute HRV + extract features in one call.
    public func computeAndExtract(from rrIntervalsMs: [UInt16]) throws -> FeatureVector {
        let metrics = try computeHRV(from: rrIntervalsMs)
        let features = extractFeatures(from: metrics)
        return FeatureVector(values: features)
    }
}

// MARK: - Error

public enum ComputeError: Error, Equatable, Sendable {
    case tooFewIntervals
    case computationFailed
}
