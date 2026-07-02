import Foundation
import HRSenseCore
import TGReduxKit

/// Middleware that subscribes to the waveform data stream and dispatches
/// waveform-related actions.
public func makeWaveformMiddleware(
    waveformRingBuffer: any WaveformRingBufferProtocol
) -> Middleware<AppState, Action> {
    { store, action, next in
        next(action)
        // M5 baseline: waveform data routed through heartRateReceived path
        // Full waveform pipeline with dedicated ring buffer observation in M5+ extensions
    }
}
