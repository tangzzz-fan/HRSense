import XCTest
@testable import HRSenseProtocol

final class DataCodecTests: XCTestCase {

    func test_fullSampleRoundTrip() {
        let original = DeviceSample(
            timestamp: 42_000,
            heartRate: 72,
            rrIntervals: [800, 820, 790],
            battery: 85,
            sensorStatus: 0x01,
            sampleSeq: 100
        )
        let encoded = DataCodec.encode(original)
        let decoded = DataCodec.decode(body: encoded)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.timestamp, 42_000)
        XCTAssertEqual(decoded?.heartRate, 72)
        XCTAssertEqual(decoded?.rrIntervals, [800, 820, 790])
        XCTAssertEqual(decoded?.battery, 85)
        XCTAssertEqual(decoded?.sensorStatus, 0x01)
        XCTAssertEqual(decoded?.sampleSeq, 100)
    }

    func test_minimalSampleRoundTrip() {
        let original = DeviceSample(timestamp: 500)
        let encoded = DataCodec.encode(original)
        let decoded = DataCodec.decode(body: encoded)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.timestamp, 500)
        XCTAssertNil(decoded?.heartRate)
        XCTAssertEqual(decoded?.rrIntervals, [])
        XCTAssertNil(decoded?.battery)
    }

    func test_heartRateOnlyRoundTrip() {
        let original = DeviceSample(timestamp: 1000, heartRate: 65)
        let encoded = DataCodec.encode(original)
        let decoded = DataCodec.decode(body: encoded)

        XCTAssertEqual(decoded?.heartRate, 65)
    }

    func test_rrIntervalsOnlyRoundTrip() {
        let original = DeviceSample(timestamp: 2000, rrIntervals: [750, 760, 755, 770])
        let encoded = DataCodec.encode(original)
        let decoded = DataCodec.decode(body: encoded)

        XCTAssertEqual(decoded?.rrIntervals.count, 4)
        XCTAssertEqual(decoded?.rrIntervals, [750, 760, 755, 770])
    }

    func test_decodeMalformed() {
        // Empty body
        XCTAssertNil(DataCodec.decode(body: []))
        // Unknown DataKind
        XCTAssertNil(DataCodec.decode(body: [0xFF]))
        // DataKind present but truncated TLV
        XCTAssertNil(DataCodec.decode(body: [0x01, 0x02]))  // kind + bogus TLV
    }
}
