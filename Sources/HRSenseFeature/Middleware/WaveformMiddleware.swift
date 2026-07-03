import Foundation
import HRSenseCore
import HRSenseProtocol
import TGReduxKit

/// Middleware that manages the waveform data pipeline.
///
/// Subscribes to the waveform ring buffer on a polling cadence and
/// periodically dispatches waveform samples + throughput metrics to Redux.
///
/// M5 baseline: polls the WaveformRingBuffer at ~10 Hz and dispatches
/// the most recent 5-second window of samples for rendering.
public func makeWaveformMiddleware(
    waveformRingBuffer: any WaveformRingBufferProtocol,
    pollInterval: TimeInterval = 0.1,  // 10 Hz polling
    backgroundPollInterval: TimeInterval = 0.5
) -> Middleware<AppState, Action> {
    var pollTaskStarted = false

    return { store, action, next in
        next(action)

        // Start poll task on first connection to prevent duplicate subscriptions
        if (action == .connectionStateChanged(.connected) || action == .connectionStateChanged(.restoredConnected)),
           !pollTaskStarted {
            pollTaskStarted = true
            Task {
                while !Task.isCancelled {
                    let lifecycle = await MainActor.run { store.state.lifecycle }
                    if lifecycle == .background {
                        try? await Task.sleep(nanoseconds: UInt64(backgroundPollInterval * 1_000_000_000))
                        continue
                    }

                    let samples = waveformRingBuffer.readRecent(durationMs: 5000)
                    let metrics = waveformRingBuffer.metricsSnapshot

                    if !samples.isEmpty {
                        await MainActor.run {
                            store.dispatch(.waveformSamplesReceived(samples))
                        }
                    }
                    await MainActor.run {
                        store.dispatch(.waveformMetricsUpdated(metrics))
                    }

                    try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                }
            }
        }

        // Handle waveform type selection
        if case .waveformTypeSelected = action {
            // No side effects needed — reducer updates the state directly
        }

        // Reset poll on disconnect
        if case .connectionStateChanged(.disconnected) = action {
            pollTaskStarted = false
        }
    }
}
