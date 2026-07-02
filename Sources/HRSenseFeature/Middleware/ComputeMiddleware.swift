import Foundation
import HRSenseCore
import TGReduxKit

/// Middleware for compute operations (HRV, feature extraction).
/// M4 placeholder — full implementation in M8.
public func makeComputeMiddleware(
    computeRepo: any ComputeRepository
) -> Middleware<AppState, Action> {
    { store, action, next in
        next(action)
    }
}
