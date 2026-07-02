import Foundation
import HRSenseProtocol

/// Generator with a manually-set heart rate (e.g., driven by a UI slider).
public final class ManualHRGenerator: DataGeneratorProtocol, @unchecked Sendable {
    public private(set) var mode: GeneratorMode = .manual(heartRate: 70)
    private var sampleSeq: UInt32 = 0

    public var currentHeartRate: Int = 70 {
        didSet { mode = .manual(heartRate: currentHeartRate) }
    }

    public init(heartRate: Int = 70) {
        self.currentHeartRate = heartRate
    }

    public func start() { sampleSeq = 0 }
    public func stop() {}

    public func nextSample(timestampMs: UInt32) -> DeviceSample {
        let hr = max(currentHeartRate, 30)
        let seq = sampleSeq
        sampleSeq += 1

        return DeviceSample(
            timestamp: timestampMs,
            heartRate: UInt16(hr),
            rrIntervals: [UInt16(60_000 / hr)],
            sampleSeq: seq
        )
    }
}
