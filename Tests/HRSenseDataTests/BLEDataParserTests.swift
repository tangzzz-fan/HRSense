import XCTest
@testable import HRSenseData
import HRSenseCore
import HRSenseProtocol

final class BLEDataParserTests: XCTestCase {
    func test_parseWaveformBlockMapsTypeTimestampsAndNormalizedValues() {
        let parser = BLEDataParser()
        parser.markT0()
        let block = WaveformBlock(
            waveformType: WaveformType.ecg.rawValue,
            sampleRateHz: 100,
            blockSeq: 7,
            startTimestampMs: 200,
            sampleBits: 16,
            samples: [3276, -16384, 8192]
        )

        let samples = parser.parseWaveformBlock(block)

        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples[0].type, .ecg)
        XCTAssertEqual(samples[0].sampleRateHz, 100)
        XCTAssertEqual(samples[0].value, Float(3276) / 32768.0, accuracy: 0.0001)
        XCTAssertEqual(
            samples[1].timestamp.timeIntervalSince(samples[0].timestamp),
            0.01,
            accuracy: 0.002
        )
    }

    func test_parseWaveformBlockRejectsUnknownType() {
        let parser = BLEDataParser()
        let block = WaveformBlock(
            waveformType: 9,
            sampleRateHz: 128,
            blockSeq: 1,
            startTimestampMs: 0,
            sampleBits: 12,
            samples: [1, 2, 3]
        )

        XCTAssertTrue(parser.parseWaveformBlock(block).isEmpty)
    }
}
