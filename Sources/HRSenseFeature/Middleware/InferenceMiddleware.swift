import Foundation
import HRSenseCore
import TGReduxKit

/// Middleware for CoreML inference.
/// M4 placeholder — full implementation in M8.
public func makeInferenceMiddleware(
    inferenceRepo: any InferenceRepository
) -> Middleware<AppState, Action> {
    { store, action, next in
        next(action)
    }
}
