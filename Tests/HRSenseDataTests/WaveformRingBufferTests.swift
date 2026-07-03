import XCTest
@testable import HRSenseData
import HRSenseCore

final class WaveformRingBufferTests: XCTestCase {
    func test_pushEvictsOldestSamplesWhenCapacityExceeded() {
        let buffer = WaveformRingBuffer(capacity: 3)
        let now = Date()

        buffer.push([
            WaveformSample(type: .ecg, sampleRateHz: 128, timestamp: now, value: 0.1),
            WaveformSample(type: .ecg, sampleRateHz: 128, timestamp: now.addingTimeInterval(0.01), value: 0.2)
        ])
        buffer.push([
            WaveformSample(type: .ecg, sampleRateHz: 128, timestamp: now.addingTimeInterval(0.02), value: 0.3),
            WaveformSample(type: .ecg, sampleRateHz: 128, timestamp: now.addingTimeInterval(0.03), value: 0.4)
        ])

        let recent = buffer.readRecent(durationMs: 1_000)

        XCTAssertEqual(buffer.totalPushed, 4)
        XCTAssertEqual(recent.count, 3)
        XCTAssertEqual(Double(recent.first?.value ?? 0), 0.2, accuracy: 0.0001)
        XCTAssertEqual(Double(recent.last?.value ?? 0), 0.4, accuracy: 0.0001)
    }

    func test_recordBlockUpdatesMetricsAndDetectsLoss() {
        let buffer = WaveformRingBuffer()

        buffer.recordBlock(bytes: 120, blockSeq: 10, sampleCount: 20)
        buffer.recordBlock(bytes: 120, blockSeq: 12, sampleCount: 20)
        let metrics = buffer.metricsSnapshot

        XCTAssertGreaterThan(metrics.blockLossRate, 0)
        XCTAssertEqual(buffer.totalPushed, 0)
    }
}
