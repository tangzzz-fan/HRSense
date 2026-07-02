import SwiftUI
import HRSenseCore

/// Displays waveform throughput and performance metrics.
public struct ThroughputPanelView: View {
    public let metrics: WaveformMetrics
    public let sampleCount: Int

    public init(metrics: WaveformMetrics, sampleCount: Int) {
        self.metrics = metrics
        self.sampleCount = sampleCount
    }

    public var body: some View {
        HStack(spacing: 16) {
            MetricBadge(label: "Throughput", value: String(format: "%.1f KB/s", metrics.effectiveThroughputBytesPerSec / 1024))
            MetricBadge(label: "Samples/s", value: String(format: "%.0f", metrics.samplesPerSec))
            MetricBadge(label: "Loss", value: String(format: "%.1f%%", metrics.blockLossRate * 100))
            MetricBadge(label: "MTU", value: "\(metrics.mtu)")
            MetricBadge(label: "Total", value: "\(sampleCount)")
        }
        .font(.caption2)
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

private struct MetricBadge: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).fontWeight(.semibold)
            Text(label).foregroundColor(.secondary)
        }
    }
}
