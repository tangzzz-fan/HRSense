import Foundation
import HRSenseCore
import TGReduxKit

/// Middleware that orchestrates BLE connection lifecycle.
public func makeConnectionMiddleware(
    deviceRepo: any DeviceRepository
) -> Middleware<AppState, Action> {
    { store, action, next in
        switch action {
        case .startScanning:
            next(action)
            Task {
                await deviceRepo.startScanning()
                for await device in deviceRepo.discoveredDevicesStream {
                    await MainActor.run { store.dispatch(.deviceDiscovered(device)) }
                }
            }

        case .stopScanning:
            deviceRepo.stopScanning()
            next(action)

        case .connect(let deviceID):
            next(action)
            Task {
                do {
                    try await deviceRepo.connect(to: deviceID)
                } catch {
                    await MainActor.run {
                        store.dispatch(.errorOccurred(.connectionTimeout))
                    }
                }
            }

        case .disconnect:
            deviceRepo.disconnect()
            next(action)

        case .connectionStateChanged(.disconnected):
            next(action)
            // Automatic reconnection after backoff
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await deviceRepo.startScanning()
            }

        default:
            next(action)
        }
    }
}
