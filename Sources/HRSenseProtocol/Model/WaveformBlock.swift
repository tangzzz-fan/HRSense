import Foundation

/// Waveform block (DataKind=0x02).
/// v1 protocol — full model for M5 high-throughput waveform.
public struct WaveformBlock: Equatable, Sendable {
    /// 1=ECG, 2=PPG.
    public let waveformType: UInt8
    /// Sampling rate in Hz.
    public let sampleRateHz: UInt16
    /// Continuous block sequence number (u32, wraps for loss detection).
    public let blockSeq: UInt32
    /// Start timestamp (device-relative ms from t0).
    public let startTimestampMs: UInt32
    /// Bits per sample (12 or 16).
    public let sampleBits: UInt8
    /// Raw sample values.
    public let samples: [Int16]

    public init(
        waveformType: UInt8,
        sampleRateHz: UInt16,
        blockSeq: UInt32,
        startTimestampMs: UInt32,
        sampleBits: UInt8,
        samples: [Int16]
    ) {
        self.waveformType = waveformType
        self.sampleRateHz = sampleRateHz
        self.blockSeq = blockSeq
        self.startTimestampMs = startTimestampMs
        self.sampleBits = sampleBits
        self.samples = samples
    }

    /// Number of samples in this block.
    public var sampleCount: Int { samples.count }

    /// Duration of this block in milliseconds.
    public var durationMs: Double {
        guard sampleRateHz > 0 else { return 0 }
        return Double(samples.count) / Double(sampleRateHz) * 1000.0
    }

    /// Waveform type label.
    public var typeLabel: String {
        switch waveformType {
        case 1: return "ECG"
        case 2: return "PPG"
        default: return "Waveform(\(waveformType))"
        }
    }
}
