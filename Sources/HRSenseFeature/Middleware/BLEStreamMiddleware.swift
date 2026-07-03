import Foundation
import HRSenseCore
import TGReduxKit

/// Middleware that subscribes to the BLE heart rate data stream and
/// dispatches heartRateReceived actions throttled to ≤2 Hz.
public func makeBLEStreamMiddleware(
    deviceRepo: any DeviceRepository,
    throttleInterval: TimeInterval = 0.5
) -> Middleware<AppState, Action> {
    { store, action, next in
        next(action)

        switch action {
        case .connectionStateChanged(.connected), .connectionStateChanged(.restoredConnected):
            Task {
                var lastDispatchTime = Date.distantPast
                var batch: [HeartRateSample] = []

                for await sample in deviceRepo.heartRateStream {
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

        default:
            break
        }
    }
}
