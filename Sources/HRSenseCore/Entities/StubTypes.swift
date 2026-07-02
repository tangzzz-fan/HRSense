import Foundation

// MARK: - Stub types for M5/M8

/// Placeholder — full definition in M8.
public struct HRVMetrics: Equatable, Sendable {
    public let sdnn: Double
    public let rmssd: Double
    public init(sdnn: Double = 0, rmssd: Double = 0) {
        self.sdnn = sdnn; self.rmssd = rmssd
    }
}

/// Placeholder — full definition in M8.
public struct InferenceResult: Equatable, Sendable {
    public let label: String
    public let confidence: Float
    public init(label: String = "", confidence: Float = 0) {
        self.label = label; self.confidence = confidence
    }
}

/// Placeholder — full definition in M6.
public enum OTAPhase: Equatable, Sendable {
    case idle
    case preparing
    case transferring(progress: Double)
    case validating
    case applying
    case completed(newVersion: String)
    case failed(error: String)
}
