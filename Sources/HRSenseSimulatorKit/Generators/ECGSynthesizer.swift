import Foundation
import HRSenseProtocol

/// Synthesises realistic ECG waveforms using a PQRST template model.
public final class ECGSynthesizer: @unchecked Sendable {
    public let sampleRateHz: Int
    public let heartRate: Double
    public let noiseAmplitude: Double
    public let baselineWanderAmplitude: Double
    private let beatDuration: Double

    public init(
        sampleRateHz: Int = 128, heartRate: Double = 70,
        noiseAmplitude: Double = 0.01, baselineWanderAmplitude: Double = 0.02
    ) {
        self.sampleRateHz = sampleRateHz
        self.heartRate = heartRate
        self.noiseAmplitude = noiseAmplitude
        self.baselineWanderAmplitude = baselineWanderAmplitude
        self.beatDuration = 60.0 / heartRate
    }

    public func generate(count: Int, startTimestampMs: UInt32, blockSeq: UInt32) -> WaveformBlock {
        var samples: [Int16] = []
        samples.reserveCapacity(count)

        for i in 0..<count {
            let t = Double(i) / Double(sampleRateHz)
            let globalT = Double(startTimestampMs) / 1000.0 + t
            let beatPhase = fmod(globalT, beatDuration) / beatDuration

            let ecg = pqrstWaveform(beatPhase)
            let noise = gaussianNoise()
            let wander = baselineWanderAmplitude * sin(2 * Double.pi * globalT / 10.0)
            let value = ecg + noise + wander
            let scaled = value * 1000.0
            let clamped = max(-32768, min(32767, scaled))
            samples.append(Int16(clamped))
        }

        return WaveformBlock(
            waveformType: 1, sampleRateHz: UInt16(sampleRateHz), blockSeq: blockSeq,
            startTimestampMs: startTimestampMs, sampleBits: 16, samples: samples
        )
    }

    private func pqrstWaveform(_ phase: Double) -> Double {
        if phase < 0.15 {
            return 0.1 * sin(Double.pi * phase / 0.15)
        } else if phase < 0.20 {
            let p = (phase - 0.15) / 0.05
            return -0.1 * p - 0.1
        } else if phase < 0.25 {
            let p = (phase - 0.20) / 0.05
            return 1.0 * exp(-10 * (p - 0.5) * (p - 0.5))
        } else if phase < 0.35 {
            let p = (phase - 0.25) / 0.10
            return -0.3 * exp(-8 * p * p)
        } else if phase < 0.55 {
            let p = (phase - 0.35) / 0.20
            return 0.3 * sin(Double.pi * p)
        } else {
            return 0
        }
    }

    private func gaussianNoise() -> Double {
        let u1 = Double.random(in: 0..<1)
        let u2 = Double.random(in: 0..<1)
        return noiseAmplitude * sqrt(-2 * log(max(u1, 1e-10))) * cos(2 * Double.pi * u2)
    }
}
