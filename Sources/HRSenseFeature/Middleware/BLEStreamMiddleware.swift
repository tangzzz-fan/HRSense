import Foundation
import HRSenseCore
import TGReduxKit

/// Middleware that subscribes to the BLE heart rate data stream and
/// dispatches heartRateReceived actions throttled to ≤2 Hz.
public func makeBLEStreamMiddleware(
    deviceRepo: any DeviceRepository,
    throttleInterval: TimeInterval = 0.5
) -> Middleware<AppState, Action> {
    var heartRateTask: Task<Void, Never>?

    return { store, action, next in
        next(action)

        switch action {
        case .connectionStateChanged(.connected), .connectionStateChanged(.restoredConnected):
            heartRateTask?.cancel()
            heartRateTask = Task {
                var lastDispatchTime = Date.distantPast
                var batch: [HeartRateSample] = []

                for await sample in deviceRepo.heartRateStream {
                    guard !Task.isCancelled else { break }
                    batch.append(sample)
                    let now = Date()
                    if now.timeIntervalSince(lastDispatchTime) >= throttleInterval {
                        let samples = batch
                        batch = []
                        lastDispatchTime = now
                        await MainActor.run {
                            store.dispatch(.heartRateReceived(samples))
                        }
                    }
                }
            }

        case .connectionStateChanged(.disconnected):
            heartRateTask?.cancel()
            heartRateTask = nil

        default:
            break
        }
    }
}
