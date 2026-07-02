/// Waveform throughput metrics — measured at the App receive side.
public struct WaveformMetrics: Equatable, Sendable {
    /// Effective data throughput in bytes/second.
    public var effectiveThroughputBytesPerSec: Double = 0
    /// End-to-end latency from device t0 to App receive in ms.
    public var endToEndLatencyMs: Double = 0
    /// Fraction of blocks lost (0.0–1.0).
    public var blockLossRate: Double = 0
    /// UI rendering frame rate.
    public var uiFrameRate: Double = 0
    /// Current MTU in use.
    public var mtu: Int = 185
    /// Samples received per second.
    public var samplesPerSec: Double = 0

    public init() {}
}
