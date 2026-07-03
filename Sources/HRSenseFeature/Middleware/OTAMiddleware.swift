import Foundation
import HRSenseCore
import HRSenseProtocol
import TGReduxKit

/// Middleware that orchestrates the OTA firmware update flow.
///
/// Bridges OTARepository ↔ Redux store by subscribing to the repository's
/// progress stream and dispatching OTA state changes. Also handles the OTA
/// lifecycle: start, abort, completion, and error transitions.
public func makeOTAMiddleware(
    otaRepo: any OTARepository
) -> Middleware<AppState, Action> {
    var progressTaskStarted = false

    return { store, action, next in
        next(action)

        switch action {
        case .connectionStateChanged(.connected):
            // Start subscribing to OTA progress stream when connected
            if !progressTaskStarted {
                progressTaskStarted = true
                Task {
                    for await progress in otaRepo.progressStream {
                        let otaState = OTAState(phase: progress.phase, progress: progress.transferProgress)
                        await MainActor.run {
                            store.dispatch(.otaStateChanged(otaState))
                        }
                        // Stop listening once OTA completes or fails
                        switch progress.phase {
                        case .completed, .failed:
                            return
                        default:
                            break
                        }
                    }
                }
            }

        case .connectionStateChanged(.disconnected):
            progressTaskStarted = false
            // Abort OTA on disconnect
            otaRepo.cancelOTA()

        case .otaStateChanged(let otaState):
            switch otaState.phase {
            case .preparing:
                // OTA flow initiated — progress stream will feed updates
                break
            case .transferring:
                // Progress tracked via repository stream
                break
            case .validating, .applying:
                break
            case .completed, .failed:
                progressTaskStarted = false
            case .idle:
                break
            }

        default:
            break
        }
    }
}
