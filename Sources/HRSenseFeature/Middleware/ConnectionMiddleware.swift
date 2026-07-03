import Foundation
import HRSenseCore
import HRSenseProtocol
import TGReduxKit

/// Middleware that orchestrates BLE connection lifecycle.
///
/// Subscribes to the DeviceRepository's connection state stream and dispatches
/// state changes to the Redux store. Handles the full connect→handshake→connected
/// flow, plus automatic reconnection with exponential backoff on disconnect.
///
/// - Parameters:
///   - deviceRepo: the BLE device repository.
///   - backoffProvider: closure that returns the next backoff delay in seconds.
///     Called before each reconnection attempt. Should implement exponential
///     backoff (1s → 2s → 4s → … → 60s capped) and reset on successful connection.
public func makeConnectionMiddleware(
    deviceRepo: any DeviceRepository,
    backoffProvider: (@Sendable () -> Int)?
) -> Middleware<AppState, Action> {
    var streamTaskStarted = false

    return { store, action, next in
        // One-time: subscribe to BLE connection state stream
        if !streamTaskStarted {
            streamTaskStarted = true
            Task {
                for await state in deviceRepo.connectionStateStream {
                    await MainActor.run {
                        store.dispatch(.connectionStateChanged(state))
                    }
                }
            }
            // Subscribe to device info stream (updated after handshake)
            Task {
                for await info in deviceRepo.deviceInfoStream {
                    await MainActor.run {
                        store.dispatch(.deviceInfoUpdated(info))
                    }
                }
            }
        }

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
                    // Wait for handshaking state (service discovery done), then perform handshake
                    _ = try await deviceRepo.performHandshake()
                    // State transitions to .connected are handled by the state stream subscription above
                } catch {
                    await MainActor.run {
                        store.dispatch(.errorOccurred(error is AppError ? (error as! AppError) : .connectionTimeout))
                    }
                }
            }

        case .disconnect:
            deviceRepo.disconnect()
            next(action)

        case .connectionStateChanged(.disconnected):
            next(action)
            // Automatic reconnection with exponential backoff
            let delay = backoffProvider?() ?? 1
            HRSenseLogging.info(.state, "Reconnecting in \(delay)s (backoff)")
            Task { @MainActor [delay] in
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
                await deviceRepo.startScanning()
            }

        case .connectionStateChanged(.handshaking):
            next(action)
            // Handshake is triggered by the .connect handler above; nothing extra needed here

        default:
            next(action)
        }
    }
}
