import SwiftUI
import HRSenseCore

/// Composes waveform canvas + throughput metrics + type selector.
public struct WaveformDisplayView: View {
    public let samples: [WaveformSample]
    public let metrics: WaveformMetrics
    @Binding public var selectedType: WaveformType

    public init(samples: [WaveformSample], metrics: WaveformMetrics, selectedType: Binding<WaveformType>) {
        self.samples = samples
        self.metrics = metrics
        self._selectedType = selectedType
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Canvas
            WaveformCanvasView(samples: samples, waveformType: selectedType, windowSeconds: 5)
                .frame(height: 120)
                .background(Color.black.opacity(0.05))
                .cornerRadius(8)

            // Metrics
            ThroughputPanelView(metrics: metrics, sampleCount: samples.count)

            // Type selector
            Picker("Type", selection: $selectedType) {
                Text("ECG").tag(WaveformType.ecg)
                Text("PPG").tag(WaveformType.ppg)
            }
            .pickerStyle(.segmented)
        }
    }
}
