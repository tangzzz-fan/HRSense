import XCTest
@testable import HRSenseData

final class MetricsCollectorTests: XCTestCase {

    func test_initial() {
        let m = MetricsCollector()
        XCTAssertEqual(m.totalSamplesReceived, 0)
        XCTAssertEqual(m.samplesLost, 0)
        XCTAssertEqual(m.reconnectCount, 0)
    }

    func test_recordSample() {
        let m = MetricsCollector()
        m.recordSampleReceived()
        m.recordSampleReceived()
        XCTAssertEqual(m.totalSamplesReceived, 2)
    }

    func test_recordLost() {
        let m = MetricsCollector()
        m.recordSamplesLost(5)
        XCTAssertEqual(m.samplesLost, 5)
    }

    func test_snapshot() {
        let m = MetricsCollector()
        m.recordSampleReceived()
        m.recordSamplesLost(2)
        m.recordReconnect()
        let snap = m.snapshot()
        XCTAssertEqual(snap.totalSamplesReceived, 1)
        XCTAssertEqual(snap.samplesLost, 2)
        XCTAssertEqual(snap.reconnectCount, 1)
    }
}
