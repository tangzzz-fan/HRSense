import Foundation

/// Full HRV metrics (14 fields) produced by the C++ compute layer.
///
/// Index mapping (must match C ABI struct layout):
///   0  sdnn
///   1  rmssd
///   2  pnn50
///   3  meanRR
///   4  hr
///   5  lfPower
///   6  hfPower
///   7  lfHfRatio
///   8  totalPower
///   9  sd1
///   10 sd2
///   11 sampleEntropy
///   12 dfaAlpha1
///   13 stressIndex
public struct HRVMetrics: Equatable, Sendable {
    /// Standard deviation of NN intervals (ms).
    public var sdnn: Double
    /// Root mean square of successive differences (ms).
    public var rmssd: Double
    /// Percentage of adjacent NN intervals differing by >50ms.
    public var pnn50: Double
    /// Mean RR interval (ms).
    public var meanRR: Double
    /// Heart rate (bpm) = 60000 / meanRR.
    public var hr: Double
    /// Low-frequency power (0.04–0.15 Hz, ms²).
    public var lfPower: Double
    /// High-frequency power (0.15–0.40 Hz, ms²).
    public var hfPower: Double
    /// LF / HF ratio.
    public var lfHfRatio: Double
    /// Total power (ms²).
    public var totalPower: Double
    /// Poincaré plot SD1 (short-term variability).
    public var sd1: Double
    /// Poincaré plot SD2 (long-term variability).
    public var sd2: Double
    /// Sample entropy (m=2, r=0.2*SDNN).
    public var sampleEntropy: Double
    /// Detrended fluctuation analysis alpha1.
    public var dfaAlpha1: Double
    /// Baevsky's stress index.
    public var stressIndex: Double

    public init(
        sdnn: Double = 0, rmssd: Double = 0, pnn50: Double = 0,
        meanRR: Double = 0, hr: Double = 0,
        lfPower: Double = 0, hfPower: Double = 0, lfHfRatio: Double = 0,
        totalPower: Double = 0,
        sd1: Double = 0, sd2: Double = 0,
        sampleEntropy: Double = 0, dfaAlpha1: Double = 0,
        stressIndex: Double = 0
    ) {
        self.sdnn = sdnn; self.rmssd = rmssd; self.pnn50 = pnn50
        self.meanRR = meanRR; self.hr = hr
        self.lfPower = lfPower; self.hfPower = hfPower; self.lfHfRatio = lfHfRatio
        self.totalPower = totalPower
        self.sd1 = sd1; self.sd2 = sd2
        self.sampleEntropy = sampleEntropy; self.dfaAlpha1 = dfaAlpha1
        self.stressIndex = stressIndex
    }

    /// Convert to a 14-element [Float] feature vector for CoreML.
    public func toFeatureVector() -> [Float] {
        [Float(sdnn), Float(rmssd), Float(pnn50), Float(meanRR), Float(hr),
         Float(lfPower), Float(hfPower), Float(lfHfRatio), Float(totalPower),
         Float(sd1), Float(sd2), Float(sampleEntropy), Float(dfaAlpha1), Float(stressIndex)]
    }

    /// Reconstruct from a [Float] feature vector.
    public init(from features: [Float]) {
        let d: [Double] = features.map { Double($0) }
        self.init(
            sdnn: d[0], rmssd: d[1], pnn50: d[2], meanRR: d[3], hr: d[4],
            lfPower: d[5], hfPower: d[6], lfHfRatio: d[7], totalPower: d[8],
            sd1: d[9], sd2: d[10], sampleEntropy: d[11], dfaAlpha1: d[12],
            stressIndex: d[13]
        )
    }
}
