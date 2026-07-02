import Foundation

/// Waveform block (DataKind=0x02).
/// M1 placeholder — full model and codec implemented in M5.
public struct WaveformBlock: Equatable, Sendable {
    /// 1=ECG, 2=PPG.
    public let waveformType: UInt8
    /// Sampling rate in Hz.
    public let sampleRateHz: UInt16
    /// Continuous block sequence number (u32, wraps).
    public let blockSeq: UInt32
    /// Start timestamp (device-relative ms).
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
}
