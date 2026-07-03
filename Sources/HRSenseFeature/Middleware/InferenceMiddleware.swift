import Foundation
import HRSenseCore
import TGReduxKit

/// Middleware for CoreML inference (M8).
///
/// Listens for featuresExtracted actions and triggers CoreML inference
/// via the InferenceRepository. Dispatches inferenceCompleted on success.
///
/// Note: The current pipeline triggers inference directly from
/// ComputeMiddleware (RR → HRV → features → inference). This middleware
/// provides the alternative two-step path: featuresExtracted → inferenceCompleted,
/// which allows inserting additional pre-processing or validation between
/// feature extraction and inference.
public func makeInferenceMiddleware(
    inferenceRepo: any InferenceRepository
) -> Middleware<AppState, Action> {
    { store, action, next in
        next(action)

        switch action {
        case .featuresExtracted(let features):
            store.dispatch(.inferenceStarted)
            Task {
                do {
                    let result = try await inferenceRepo.runInference(features: features.values)
                    await MainActor.run {
                        store.dispatch(.inferenceCompleted(result))
                    }
                } catch {
                    await MainActor.run {
                        store.dispatch(.errorOccurred(.inferenceFailed))
                    }
                }
            }

        default:
            break
        }
    }
}
