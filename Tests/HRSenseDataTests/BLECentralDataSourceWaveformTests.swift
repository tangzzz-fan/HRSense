import XCTest
@testable import HRSenseData
import HRSenseCore
import HRSenseProtocol

private final class RecordingWaveformRingBuffer: WaveformRingBufferProtocol, @unchecked Sendable {
    var pushedSamples: [WaveformSample] = []
    var recordedBlocks: [(bytes: Int, blockSeq: UInt32, sampleCount: Int)] = []
    var metricsSnapshot = WaveformMetrics()
    var totalPushed: Int { pushedSamples.count }

    func push(_ samples: [WaveformSample]) {
        pushedSamples.append(contentsOf: samples)
    }

    func recordBlock(bytes: Int, blockSeq: UInt32, sampleCount: Int) {
        recordedBlocks.append((bytes, blockSeq, sampleCount))
    }

    func readRecent(durationMs: Double) -> [WaveformSample] {
        pushedSamples
    }
}

final class BLECentralDataSourceWaveformTests: XCTestCase {
    func test_waveformFrameIsRecordedAndPushedToRingBuffer() {
        let buffer = RecordingWaveformRingBuffer()
        let dataSource = BLECentralDataSource(
            waveformRingBuffer: buffer,
            bootstrapCentralManager: false
        )
        dataSource.dataParser.markT0()
        let block = WaveformBlock(
            waveformType: WaveformType.ppg.rawValue,
            sampleRateHz: 128,
            blockSeq: 42,
            startTimestampMs: 500,
            sampleBits: 12,
            samples: [100, -200, 300]
        )

        dataSource.consume(frame: .waveform(block), receivedBytes: 96)

        XCTAssertEqual(buffer.recordedBlocks.count, 1)
        XCTAssertEqual(buffer.recordedBlocks.first?.bytes, 96)
        XCTAssertEqual(buffer.recordedBlocks.first?.blockSeq, 42)
        XCTAssertEqual(buffer.recordedBlocks.first?.sampleCount, 3)
        XCTAssertEqual(buffer.pushedSamples.count, 3)
        XCTAssertEqual(buffer.pushedSamples.first?.type, .ppg)
    }
}
