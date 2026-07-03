import Foundation
import HRSenseProtocol

/// Anomaly heart-rate generator: produces spikes, drops, and erratic values.
///
/// Generates 2 RR intervals per sample. Normal beats have moderate variability;
/// every ~15th sample injects a large anomaly spike.
public final class AnomalyHRGenerator: DataGeneratorProtocol, @unchecked Sendable {
    public private(set) var mode: GeneratorMode = .anomaly
    private var sampleSeq: UInt32 = 0
    private let baseBPM: Int

    public init(baseBPM: Int = 70) {
        self.baseBPM = baseBPM
    }

    public func start() { sampleSeq = 0 }
    public func stop() {}

    public func nextSample(timestampMs: UInt32) -> DeviceSample {
        let seq = sampleSeq
        sampleSeq += 1
        let t = Double(timestampMs) / 1000.0

        // Every ~15th sample injects an anomaly
        let hr: Int
        let rsaAmp: Double
        let noiseSd: Double
        if seq % 15 == 0 {
            hr = Int.random(in: 30...200)
            rsaAmp = 40  // exaggerated variability during anomaly
            noiseSd = 30
        } else {
            hr = baseBPM + Int.random(in: -3...3)
            rsaAmp = 15
            noiseSd = 8
        }

        let rr = RRSynthesizer.generate(
            heartRate: Double(hr),
            elapsedSeconds: t,
            rsaAmplitude: rsaAmp,
            noiseStd: noiseSd,
            intervalCount: 2
        )

        return DeviceSample(
            timestamp: timestampMs,
            heartRate: UInt16(max(hr, 20)),
            rrIntervals: rr,
            sampleSeq: seq
        )
    }
}
