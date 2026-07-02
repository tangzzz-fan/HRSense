import XCTest
@testable import HRSenseSimulatorKit
import HRSenseProtocol

final class DataGeneratorTests: XCTestCase {

    func test_restingHRGenerator() {
        let gen = RestingHRGenerator()
        gen.start()

        let sample = gen.nextSample(timestampMs: 0)
        XCTAssertNotNil(sample.heartRate)
        if let hr = sample.heartRate {
            XCTAssertGreaterThanOrEqual(hr, 55)
            XCTAssertLessThanOrEqual(hr, 80)
        }
        XCTAssertNotNil(sample.rrIntervals.first)
        XCTAssertEqual(sample.sampleSeq, 0)

        let sample2 = gen.nextSample(timestampMs: 1000)
        XCTAssertEqual(sample2.sampleSeq, 1)
    }

    func test_exerciseHRGenerator_rampsUp() {
        let gen = ExerciseHRGenerator(warmupSeconds: 30, peakSeconds: 60, recoverySeconds: 30)
        gen.start()

        // Start of warmup
        let s0 = gen.nextSample(timestampMs: 0)
        if let hr = s0.heartRate {
            XCTAssertLessThan(hr, 80)
        }

        // After 15 seconds of warmup (halfway)
        let s15 = gen.nextSample(timestampMs: 15_000)
        if let hr = s15.heartRate {
            XCTAssertGreaterThan(hr, 80)
            XCTAssertLessThan(hr, 120)
        }

        // During peak
        let sPeak = gen.nextSample(timestampMs: 60_000)  // 30 warmup + 30 peak
        if let hr = sPeak.heartRate {
            XCTAssertEqual(hr, 150)  // peakBPM
        }
    }

    func test_manualHRGenerator() {
        let gen = ManualHRGenerator(heartRate: 80)

        let sample = gen.nextSample(timestampMs: 0)
        XCTAssertEqual(sample.heartRate, 80)

        gen.currentHeartRate = 120
        let sample2 = gen.nextSample(timestampMs: 1000)
        XCTAssertEqual(sample2.heartRate, 120)
    }

    func test_anomalyHRGenerator() {
        let gen = AnomalyHRGenerator(baseBPM: 70)
        gen.start()

        // Collect several samples — some should deviate from base
        var values: [UInt16] = []
        for i in 0..<30 {
            let s = gen.nextSample(timestampMs: UInt32(i * 1000))
            if let hr = s.heartRate { values.append(hr) }
        }
        let maxVal = values.max() ?? 0
        let minVal = values.min() ?? 0

        // Anomalies should produce a wider range
        XCTAssertGreaterThan(maxVal - minVal, 5, "Should have anomalies producing spread")
    }

    func test_replayHRGenerator_fromCSVString() throws {
        let gen = ReplayHRGenerator()
        let csv = """
        0,72,800,810
        1000,75,780,775
        2000,80,750,740
        """
        try gen.loadCSVString(csv)
        gen.start()

        let s1 = gen.nextSample(timestampMs: 0)
        XCTAssertEqual(s1.heartRate, 72)
        XCTAssertEqual(s1.rrIntervals, [800, 810])

        let s2 = gen.nextSample(timestampMs: 1000)
        XCTAssertEqual(s2.heartRate, 75)

        // Should wrap around after consuming all 3 rows
        // s3 → row 2 (heartRate 80)
        // s4 → row 0 (heartRate 72) — wraps
        _ = gen.nextSample(timestampMs: 2000)  // s3: 80
        let s4 = gen.nextSample(timestampMs: 3000)  // s4: wraps back to row 0
        XCTAssertEqual(s4.heartRate, 72, "After consuming all rows, should wrap to start")
    }

    func test_csvParser() throws {
        let parser = CSVParser()
        let result = try parser.parse("1000,72,800\n2000,75,780")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], ["1000", "72", "800"])
        XCTAssertEqual(result[1], ["2000", "75", "780"])
    }
}
