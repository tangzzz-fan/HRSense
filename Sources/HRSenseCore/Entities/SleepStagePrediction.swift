import Foundation

/// Sleep-stage inference output used by M9 phase 5.
public struct SleepStagePrediction: Equatable, Sendable {
    public let stage: SleepStage
    public let confidence: Float
    public let probabilities: [SleepStage: Float]
    public let modelVersion: String
    public let timestamp: Date

    public init(
        stage: SleepStage,
        confidence: Float,
        probabilities: [SleepStage: Float],
        modelVersion: String,
        timestamp: Date = Date()
    ) {
        self.stage = stage
        self.confidence = confidence
        self.probabilities = probabilities
        self.modelVersion = modelVersion
        self.timestamp = timestamp
    }
}
