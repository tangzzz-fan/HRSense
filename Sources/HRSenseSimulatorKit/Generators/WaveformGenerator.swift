import Foundation
import HRSenseProtocol

/// Coordinates waveform generation with phase continuity across blocks.
public final class WaveformGenerator: @unchecked Sendable {
    public let type: UInt8
    public let sampleRateHz: Int
    public let heartRate: Double
    private let lock = NSLock()
    private var _blockSeq: UInt32 = 0
    private var _elapsedMs: UInt32 = 0
    private let ecgSynth: ECGSynthesizer?
    private let ppgSynth: PPGSynthesizer?

    public static func ecg(sampleRateHz: Int = 128, heartRate: Double = 70,
                           noiseAmplitude: Double = 0.01) -> WaveformGenerator {
        WaveformGenerator(type: 1, sampleRateHz: sampleRateHz, heartRate: heartRate,
                          ecgSynth: ECGSynthesizer(sampleRateHz: sampleRateHz, heartRate: heartRate,
                                                    noiseAmplitude: noiseAmplitude), ppgSynth: nil)
    }

    public static func ppg(sampleRateHz: Int = 128, heartRate: Double = 70) -> WaveformGenerator {
        WaveformGenerator(type: 2, sampleRateHz: sampleRateHz, heartRate: heartRate,
                          ecgSynth: nil,
                          ppgSynth: PPGSynthesizer(sampleRateHz: sampleRateHz, heartRate: heartRate))
    }

    private init(type: UInt8, sampleRateHz: Int, heartRate: Double,
                 ecgSynth: ECGSynthesizer?, ppgSynth: PPGSynthesizer?) {
        self.type = type; self.sampleRateHz = sampleRateHz; self.heartRate = heartRate
        self.ecgSynth = ecgSynth; self.ppgSynth = ppgSynth
    }

    public func nextBlock(count: Int) -> WaveformBlock {
        lock.lock(); defer { lock.unlock() }
        let seq = _blockSeq; let startMs = _elapsedMs
        _blockSeq = _blockSeq &+ 1
        _elapsedMs = _elapsedMs &+ UInt32(Double(count) / Double(sampleRateHz) * 1000.0)

        if let ecg = ecgSynth { return ecg.generate(count: count, startTimestampMs: startMs, blockSeq: seq) }
        else if let ppg = ppgSynth { return ppg.generate(count: count, startTimestampMs: startMs, blockSeq: seq) }
        return WaveformBlock(waveformType: type, sampleRateHz: UInt16(sampleRateHz), blockSeq: seq,
                              startTimestampMs: startMs, sampleBits: 16,
                              samples: Array(repeating: 0, count: count))
    }

    public func reset() { lock.withLock { _blockSeq = 0; _elapsedMs = 0 } }
}
