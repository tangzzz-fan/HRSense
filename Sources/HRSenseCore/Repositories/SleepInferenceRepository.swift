/// Repository protocol for sleep-stage inference (M9 phase 5).
/// Upper layers depend on this protocol rather than the concrete ML service.
public protocol SleepInferenceRepository: AnyObject, Sendable {
    /// Predict one sleep stage from the canonical sleep window contract.
    func inferSleepStage(input: SleepWindowInput) async throws -> SleepStagePrediction
}
