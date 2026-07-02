import Foundation
import HRSenseProtocol

/// Exercise heart-rate generator: ramps up, sustains, recovers.
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
        let hr = currentHR(at: t)
        let seq = sampleSeq
        sampleSeq += 1

        return DeviceSample(
            timestamp: timestampMs,
            heartRate: UInt16(hr),
            rrIntervals: [UInt16(60_000 / max(hr, 30))],
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
