import Foundation

/// Protocol for a fixed-capacity thread-safe ring buffer for waveform data.
///
/// Used by HRSenseData (implementation) and referenced by HRSenseFeature
/// (via Repository). Push new blocks; read recent samples for rendering.
public protocol WaveformRingBufferProtocol: AnyObject, Sendable {
    /// Push a batch of waveform samples (appends, evicts oldest if at capacity).
    func push(_ samples: [WaveformSample])

    /// Record block-level receive metrics before sample conversion.
    func recordBlock(bytes: Int, blockSeq: UInt32, sampleCount: Int)

    /// Read samples within the given trailing window (ms).
    /// - Parameter durationMs: lookback window in milliseconds.
    /// - Returns: samples within that window, oldest-to-newest.
    func readRecent(durationMs: Double) -> [WaveformSample]

    /// Current metrics snapshot.
    var metricsSnapshot: WaveformMetrics { get }

    /// Total sample count pushed since creation.
    var totalPushed: Int { get }
}
