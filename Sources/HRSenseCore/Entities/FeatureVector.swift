import Foundation

/// 14-dimensional feature vector for CoreML stress classification.
///
/// Contract version: incremented when feature order or count changes.
public struct FeatureVector: Equatable, Sendable {
    /// 14 Float32 values matching the training-time feature order.
    /// Index 0=SDNN .. 13=stressIndex (see HRVMetrics.toFeatureVector()).
    public let values: [Float]

    /// Contract version — must match the training pipeline version.
    public let contractVersion: Int

    public static let dim = 14
    public static let currentContractVersion = 1

    public init(values: [Float], contractVersion: Int = currentContractVersion) {
        assert(values.count == Self.dim, "FeatureVector must have \(Self.dim) elements")
        self.values = values
        self.contractVersion = contractVersion
    }

    /// Create from HRVMetrics.
    public init(metrics: HRVMetrics) {
        self.values = metrics.toFeatureVector()
        self.contractVersion = Self.currentContractVersion
    }
}
