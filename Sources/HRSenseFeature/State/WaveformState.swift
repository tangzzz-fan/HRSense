import Foundation
import HRSenseCore

/// Waveform Redux state fragment — added to LiveState.
public struct WaveformState: Equatable, Sendable {
    /// Latest ECG samples (ring buffer window).
    public var ecgSamples: [WaveformSample] = []
    /// Latest PPG samples (ring buffer window).
    public var ppgSamples: [WaveformSample] = []
    /// Currently selected waveform type.
    public var selectedType: WaveformType = .ecg
    /// Throughput metrics.
    public var metrics: WaveformMetrics = WaveformMetrics()
    /// Whether waveform streaming is active.
    public var isStreaming: Bool = false

    public init(
        ecgSamples: [WaveformSample] = [],
        ppgSamples: [WaveformSample] = [],
        selectedType: WaveformType = .ecg,
        metrics: WaveformMetrics = WaveformMetrics(),
        isStreaming: Bool = false
    ) {
        self.ecgSamples = ecgSamples
        self.ppgSamples = ppgSamples
        self.selectedType = selectedType
        self.metrics = metrics
        self.isStreaming = isStreaming
    }
}
