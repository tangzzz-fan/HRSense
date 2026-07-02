import Foundation
import HRSenseCore

/// Pure-function reducer: (inout AppState, Action) -> Void.
///
/// All state mutations are deterministic. No side effects — those live in Middleware.
///
/// Key rules:
///   - heartRateReceived: append to recentSamples, suffix(600) truncation
///   - connectionStateChanged: update connection; .connected clears error
///   - hrvComputed: set metrics.latestHRV
///   - inferenceCompleted: set inference.latestResult
///   - errorOccurred: set error; connection-class errors set connection = .disconnected
///   - dismissError: nil out error
public enum AppReducer {
    public static func reduce(state: inout AppState, action: Action) {
        switch action {
        case .startScanning:
            state.connection = .scanning

        case .stopScanning:
            state.connection = .idle

        case .deviceDiscovered:
            break // Handled by middleware — no state change needed at reducer level

        case .connect:
            state.connection = .connecting
            state.error = nil

        case .disconnect:
            state.connection = .disconnecting

        case .connectionStateChanged(let newState):
            state.connection = newState
            if newState == .connected {
                state.error = nil
            }
            if newState == .disconnected {
                state.device = nil
            }

        case .heartRateReceived(let samples):
            state.live.recentSamples.append(contentsOf: samples)
            // Keep bounded to 600 entries (~10 min @ 1 Hz)
            if state.live.recentSamples.count > 600 {
                state.live.recentSamples = Array(state.live.recentSamples.suffix(600))
            }
            if let latest = samples.last {
                state.live.currentHeartRate = latest.heartRate
                state.live.lastUpdated = Date()
            }

        case .deviceEvent:
            break // Handled by middleware for logging; state unchanged

        case .hrvComputed(let metrics):
            state.metrics.latestHRV = metrics
            state.metrics.computationStatus = .ready

        case .inferenceCompleted(let result):
            state.inference.latestResult = result
            state.inference.status = .completed

        case .otaStateChanged(let ota):
            state.ota = ota

        case .errorOccurred(let error):
            state.error = error
            // Connection-class errors force disconnection
            switch error {
            case .connectionTimeout, .connectionLost, .bluetoothPoweredOff:
                state.connection = .disconnected
            default:
                break
            }

        case .dismissError:
            state.error = nil

        case .clearSamples:
            state.live = LiveState()
        }
    }
}
