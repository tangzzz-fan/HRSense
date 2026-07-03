import Foundation
import HRSenseProtocol

/// Exercise heart-rate generator: ramps up, sustains, recovers.
///
/// Produces 2 RR intervals per sample with reduced variability during
/// peak exercise (lower HRV → "Stress" classification), recovering
/// towards baseline variability during cool-down.
public final class ExerciseHRGenerator: DataGeneratorProtocol, @unchecked Sendable {
    public private(set) var mode: GeneratorMode = .exercise
    private var sampleSeq: UInt32 = 0

    /// Intensity phases (seconds from start).
    private let warmupSeconds: Double
    private let peakSeconds: Double
    private let recoverySeconds: Double
    private let restBPM: Double
    private let peakBPM: Double

    public init(
        warmupSeconds: Double = 60,
        peakSeconds: Double = 120,
        recoverySeconds: Double = 90,
        restBPM: Double = 65,
        peakBPM: Double = 150
    ) {
        self.warmupSeconds = warmupSeconds
        self.peakSeconds = peakSeconds
        self.recoverySeconds = recoverySeconds
        self.restBPM = restBPM
        self.peakBPM = peakBPM
    }

    public func start() { sampleSeq = 0 }
    public func stop() {}

    public func nextSample(timestampMs: UInt32) -> DeviceSample {
        let t = Double(timestampMs) / 1000.0
        let hr = Double(currentHR(at: t))
        let seq = sampleSeq
        sampleSeq += 1

        // During exercise: reduced RSA amplitude and noise (sympathetic dominance)
        // During rest/recovery: normal RSA amplitude (parasympathetic return)
        let rsaAmp = hr > 100 ? 5.0 : 18.0
        let noiseSd = hr > 100 ? 3.0 : 8.0
        let rr = RRSynthesizer.generate(
            heartRate: hr,
            elapsedSeconds: t,
            rsaAmplitude: rsaAmp,
            noiseStd: noiseSd,
            intervalCount: 2
        )

        return DeviceSample(
            timestamp: timestampMs,
            heartRate: UInt16(hr),
            rrIntervals: rr,
            sampleSeq: seq
        )
    }

    private func currentHR(at t: Double) -> Int {
        let warmupEnd = warmupSeconds
        let peakEnd = warmupSeconds + peakSeconds
        let recoveryEnd = warmupSeconds + peakSeconds + recoverySeconds

        if t < warmupEnd {
            let p = t / warmupEnd
            return Int(restBPM + (peakBPM - restBPM) * p)
        } else if t < peakEnd {
            return Int(peakBPM)
        } else if t < recoveryEnd {
            let p = (t - peakEnd) / recoverySeconds
            return Int(peakBPM - (peakBPM - restBPM) * p)
        } else {
            return Int(restBPM)
        }
    }
}
