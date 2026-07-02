import Foundation

/// Domain entity: a single ECG/PPG waveform sample.
public struct WaveformSample: Equatable, Sendable {
    /// Waveform type (1=ECG, 2=PPG).
    public let type: WaveformType
    /// Sampling rate in Hz.
    public let sampleRateHz: Int
    /// Absolute wall-clock timestamp.
    public let timestamp: Date
    /// Sample value (normalised to Float).
    public let value: Float

    public init(type: WaveformType, sampleRateHz: Int, timestamp: Date, value: Float) {
        self.type = type
        self.sampleRateHz = sampleRateHz
        self.timestamp = timestamp
        self.value = value
    }
}

/// Waveform type enum.
public enum WaveformType: UInt8, Equatable, Sendable, CaseIterable {
    case ecg = 1
    case ppg = 2
}
