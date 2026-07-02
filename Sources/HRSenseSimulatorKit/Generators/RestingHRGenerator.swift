import Foundation
import HRSenseProtocol

/// Resting heart-rate generator: 60–75 bpm with sinusoidal variation.
public final class RestingHRGenerator: DataGeneratorProtocol, @unchecked Sendable {
    public private(set) var mode: GeneratorMode = .resting
    private var sampleSeq: UInt32 = 0
    private let baseBPM: Double
    private let amplitude: Double
    private let periodSeconds: Double
    private var startTime: DispatchTime = .now()

    public init(baseBPM: Double = 65, amplitude: Double = 5, periodSeconds: Double = 10) {
        self.baseBPM = baseBPM
        self.amplitude = amplitude
        self.periodSeconds = periodSeconds
    }

    public func start() {
        startTime = .now()
        sampleSeq = 0
    }

    public func stop() {}

    public func nextSample(timestampMs: UInt32) -> DeviceSample {
        let t = Double(timestampMs) / 1000.0
        let hr = Int(baseBPM + amplitude * sin(2 * Double.pi * t / periodSeconds))
        let rr: [UInt16] = [UInt16(60_000 / max(hr, 30))]
        let seq = sampleSeq
        sampleSeq += 1

        return DeviceSample(
            timestamp: timestampMs,
            heartRate: UInt16(hr),
            rrIntervals: rr,
            battery: 90,
            sensorStatus: 0x01,
            sampleSeq: seq
        )
    }
}
