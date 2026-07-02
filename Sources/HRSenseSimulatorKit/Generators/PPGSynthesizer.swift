import Foundation
import HRSenseProtocol

/// Synthesises PPG (photoplethysmogram) waveforms.
///
/// PPG morphology: systolic peak → dicrotic notch → diastolic decay.
/// Driven by heart rate for inter-beat timing.
public final class PPGSynthesizer: Sendable {
    public let sampleRateHz: Int
    public let heartRate: Double
    public let noiseAmplitude: Double

    private let beatDuration: Double

    public init(
        sampleRateHz: Int = 128,
        heartRate: Double = 70,
        noiseAmplitude: Double = 0.005
    ) {
        self.sampleRateHz = sampleRateHz
        self.heartRate = heartRate
        self.noiseAmplitude = noiseAmplitude
        self.beatDuration = 60.0 / heartRate
    }

    /// Generate `count` PPG samples.
    public func generate(count: Int, startTimestampMs: UInt32, blockSeq: UInt32) -> WaveformBlock {
        var samples: [Int16] = []
        samples.reserveCapacity(count)

        for i in 0..<count {
            let t = Double(i) / Double(sampleRateHz)
            let globalT = Double(startTimestampMs) / 1000.0 + t
            let beatPhase = fmod(globalT, beatDuration) / beatDuration

            let ppg = ppgWaveform(beatPhase)
            let noise = Double.random(in: -noiseAmplitude...noiseAmplitude)
            let value = ppg + noise

            // PPG is unipolar (~0–1.0 normalised), map to i16: 0 → 0, 1.0 → 30000
            let scaled = value * 30000.0
            let clamped = max(0, min(32767, scaled))
            samples.append(Int16(clamped))
        }

        return WaveformBlock(
            waveformType: 2, sampleRateHz: UInt16(sampleRateHz), blockSeq: blockSeq,
            startTimestampMs: startTimestampMs, sampleBits: 16, samples: samples
        )
    }

    /// Simplified PPG waveform: systolic peak → dicrotic notch → decay.
    private func ppgWaveform(_ phase: Double) -> Double {
        if phase < 0.2 {
            return sin(Double.pi * phase / 0.2)  // systolic upstroke
        } else if phase < 0.35 {
            let p = (phase - 0.2) / 0.15
            return exp(-5 * p) + 0.15 * sin(Double.pi * p * 3)  // dicrotic notch
        } else {
            let p = (phase - 0.35) / 0.65
            return 0.1 * exp(-3 * p)  // diastolic decay
        }
    }
}
