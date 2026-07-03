import Foundation
import HRSenseCore
import TGReduxKit

/// Minimal background execution policy for M10.
///
/// Goal: keep BLE connectivity/restoration alive while suppressing non-essential
/// UI and ML work when the app is backgrounded.
public struct BackgroundExecutionPolicy: Equatable, Sendable {
    public let pauseWaveformRenderingInBackground: Bool
    public let pauseStressInferenceInBackground: Bool
    public let pauseComputeInBackgroundUnlessSleepMonitoring: Bool
    public let stopUserScanningOnBackground: Bool

    public init(
        pauseWaveformRenderingInBackground: Bool = true,
        pauseStressInferenceInBackground: Bool = true,
        pauseComputeInBackgroundUnlessSleepMonitoring: Bool = true,
        stopUserScanningOnBackground: Bool = true
    ) {
        self.pauseWaveformRenderingInBackground = pauseWaveformRenderingInBackground
        self.pauseStressInferenceInBackground = pauseStressInferenceInBackground
        self.pauseComputeInBackgroundUnlessSleepMonitoring = pauseComputeInBackgroundUnlessSleepMonitoring
        self.stopUserScanningOnBackground = stopUserScanningOnBackground
    }

    public static let minimal = BackgroundExecutionPolicy()
}

/// M10 minimal background policy middleware.
///
/// This middleware intentionally focuses on a narrow set of actions:
/// - stop user-initiated scanning after entering background
/// - suppress waveform rendering actions in background
/// - suppress generic stress inference in background
/// - suppress compute when no active sleep monitoring session exists
public func makeBackgroundMiddleware(
    policy: BackgroundExecutionPolicy = .minimal
) -> Middleware<AppState, Action> {
    { store, action, next in
        if shouldDrop(action: action, state: store.state, policy: policy) {
            return
        }

        next(action)

        if case .didEnterBackground = action,
           policy.stopUserScanningOnBackground,
           store.state.connection == .scanning {
            store.dispatch(.stopScanning)
        }
    }
}

private func shouldDrop(
    action: Action,
    state: AppState,
    policy: BackgroundExecutionPolicy
) -> Bool {
    guard state.lifecycle == .background else { return false }

    switch action {
    case .waveformSamplesReceived, .waveformMetricsUpdated:
        return policy.pauseWaveformRenderingInBackground

    case .featuresExtracted, .inferenceStarted, .inferenceCompleted:
        return policy.pauseStressInferenceInBackground

    case .computeStarted, .hrvComputed:
        return policy.pauseComputeInBackgroundUnlessSleepMonitoring && !state.sleep.isMonitoring

    default:
        return false
    }
}
