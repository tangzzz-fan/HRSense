import Foundation
import HRSenseCore

/// Bootstrap implementation for M9 phase 5 sleep-stage inference.
public final class SleepInferenceRepositoryImpl: SleepInferenceRepository, @unchecked Sendable {
    private let service: SleepStageService

    public init(service: SleepStageService = SleepStageService()) {
        self.service = service
    }

    public func inferSleepStage(input: SleepWindowInput) async throws -> SleepStagePrediction {
        service.predict(input: input)
    }
}
