import Foundation
import HRSenseProtocol

/// Anomaly heart-rate generator: produces spikes, drops, and erratic values.
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

        // Every ~15th sample injects an anomaly
        let hr: Int
        if seq % 15 == 0 {
            hr = Int.random(in: 30...200)
        } else {
            hr = baseBPM + Int.random(in: -3...3)
        }

        return DeviceSample(
            timestamp: timestampMs,
            heartRate: UInt16(max(hr, 20)),
            rrIntervals: [UInt16(60_000 / max(hr, 20))],
            sampleSeq: seq
        )
    }
}
