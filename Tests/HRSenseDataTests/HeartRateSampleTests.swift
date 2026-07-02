import XCTest
@testable import HRSenseCore

final class HeartRateSampleTests: XCTestCase {
    func test_init() {
        let now = Date()
        let sample = HeartRateSample(timestamp: now, heartRate: 72, rrIntervals: [800, 820])
        XCTAssertEqual(sample.heartRate, 72)
        XCTAssertEqual(sample.rrIntervals, [800, 820])
        XCTAssertEqual(sample.timestamp, now)
    }

    func test_optionalFields() {
        let sample = HeartRateSample(timestamp: Date(), heartRate: 65)
        XCTAssertNil(sample.sampleSeq)
        XCTAssertNil(sample.sensorContact)
        XCTAssertEqual(sample.rrIntervals, [])
    }
}
