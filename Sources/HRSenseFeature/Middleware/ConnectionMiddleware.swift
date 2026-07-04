import Foundation
import HRSenseCore
import HRSenseProtocol
import TGReduxKit

private actor RestorationBootstrapCoordinator {
    private var startupScanTask: Task<Void, Never>?
    private var restoreInProgress = false

    func installStartupFallbackTask(_ task: Task<Void, Never>) {
        startupScanTask?.cancel()
        startupScanTask = task
        restoreInProgress = false
    }

    func cancelStartupFallback() {
        startupScanTask?.cancel()
        startupScanTask = nil
    }

    func beginRestoreAttempt() {
        startupScanTask?.cancel()
        startupScanTask = nil
        restoreInProgress = true
    }

    func finishRestoreAttempt() {
        restoreInProgress = false
    }

    func resolvePendingFallback() -> Bool {
        startupScanTask = nil
        return !restoreInProgress
    }
}

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
    restorationContextStore: any RestorationContextStore,
    backoffProvider: (@Sendable () -> Int)?,
    restorationGracePeriod: TimeInterval = 0.75
) -> Middleware<AppState, Action> {
    var streamTaskStarted = false
    let bootstrapCoordinator = RestorationBootstrapCoordinator()

    return { store, action, next in
        let restorationGraceNanoseconds = UInt64(restorationGracePeriod * 1_000_000_000)

        func canStartScanning(for state: AppState) -> Bool {
            switch state.connection {
            case .idle, .disconnected, .scanning:
                return state.lifecycle != .restoring
            case .connecting, .handshaking, .connected, .restored, .restoredValidating, .restoredConnected, .disconnecting:
                return false
            }
        }

        func dispatchStartupScanIfNeeded() async {
            await MainActor.run {
                guard canStartScanning(for: store.state) else { return }
                store.dispatch(.startScanning)
            }
        }

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
            Task {
                for await peripheralIDs in deviceRepo.restoredPeripheralIDsStream {
                    guard !peripheralIDs.isEmpty else { continue }
                    guard restorationContextStore.load() != nil else {
                        HRSenseLogging.info(.state, "Ignoring BLE restoration without persisted eligibility context")
                        await bootstrapCoordinator.cancelStartupFallback()
                        await dispatchStartupScanIfNeeded()
                        continue
                    }
                    await bootstrapCoordinator.beginRestoreAttempt()
                    await MainActor.run {
                        store.dispatch(.restoreInitiated(peripheralIDs: peripheralIDs))
                    }
                }
            }
            Task {
                for await device in deviceRepo.discoveredDevicesStream {
                    await MainActor.run {
                        store.dispatch(.deviceDiscovered(device))
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
        case .appLaunched:
            next(action)
            if restorationContextStore.load() == nil {
                Task {
                    await bootstrapCoordinator.cancelStartupFallback()
                    await dispatchStartupScanIfNeeded()
                }
            } else {
                Task {
                    let fallbackTask = Task {
                        try? await Task.sleep(nanoseconds: restorationGraceNanoseconds)
                        guard !Task.isCancelled else { return }
                        let shouldFallback = await bootstrapCoordinator.resolvePendingFallback()
                        guard shouldFallback else { return }
                        await dispatchStartupScanIfNeeded()
                    }
                    await bootstrapCoordinator.installStartupFallbackTask(fallbackTask)
                }
            }

        case .restoreInitiated(let peripheralIDs):
            next(action)
            let context = restorationContextStore.load()
            Task {
                defer { Task { await bootstrapCoordinator.finishRestoreAttempt() } }
                do {
                    _ = try await deviceRepo.restoreConnection(context: context)
                    await MainActor.run {
                        store.dispatch(.restoreConnectionRestored(peripheralIDs: peripheralIDs))
                    }
                } catch {
                    HRSenseLogging.error(.state, "BLE restore failed: \(error.localizedDescription)")
                    let message: String
                    if let appError = error as? AppError,
                       case .handshakeFailed(let reason) = appError {
                        message = reason
                    } else {
                        message = (error as? AppError)?.localizedDescription ?? error.localizedDescription
                    }
                    await MainActor.run {
                        store.dispatch(.restoreFailed(reason: message))
                        store.dispatch(.startScanning)
                    }
                }
            }

        case .startScanning:
            guard canStartScanning(for: store.state) else { return }
            next(action)
            Task {
                await bootstrapCoordinator.cancelStartupFallback()
                await deviceRepo.startScanning()
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
                    HRSenseLogging.error(.state, "BLE connect/handshake failed: \(error.localizedDescription)")
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

        case .restoreConnectionRestored:
            next(action)
            Task {
                await bootstrapCoordinator.finishRestoreAttempt()
            }

        case .restoreFailed:
            next(action)
            Task {
                await bootstrapCoordinator.finishRestoreAttempt()
            }

        default:
            next(action)
        }
    }
}
