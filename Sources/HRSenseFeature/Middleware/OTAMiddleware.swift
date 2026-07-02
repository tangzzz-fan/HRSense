import Foundation
import HRSenseCore
import TGReduxKit

/// Middleware that orchestrates the OTA firmware update flow.
/// Bridges OTARepository → Redux State via dispatched actions.
public func makeOTAMiddleware(
    otaRepo: any OTARepository
) -> Middleware<AppState, Action> {
    { store, action, next in
        next(action)

        switch action {
        case .otaStateChanged(let otaState):
            if case .transferring = otaState.phase {
                // OTA flow running — no additional middleware action needed here
            }

        default:
            break
        }
    }
}
