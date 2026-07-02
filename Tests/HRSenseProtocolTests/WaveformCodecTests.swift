import XCTest
@testable import HRSenseProtocol

final class WaveformCodecTests: XCTestCase {

    func test_roundTrip() {
        let original = WaveformBlock(
            waveformType: 1, sampleRateHz: 128, blockSeq: 7,
            startTimestampMs: 5000, sampleBits: 16,
            samples: [100, -50, 200, -100, 75]
        )
        let encoded = WaveformCodec.encode(original)
        let decoded = WaveformCodec.decode(body: encoded)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.waveformType, 1)
        XCTAssertEqual(decoded?.sampleRateHz, 128)
        XCTAssertEqual(decoded?.blockSeq, 7)
        XCTAssertEqual(decoded?.samples, [100, -50, 200, -100, 75])
    }

    func test_roundTrip_12bitSamples() {
        let original = WaveformBlock(
            waveformType: 2, sampleRateHz: 250, blockSeq: 0,
            startTimestampMs: 0, sampleBits: 12,
            samples: [0, 1, -1, 500, -500, 2047, -2048]
        )
        let encoded = WaveformCodec.encode(original)
        let decoded = WaveformCodec.decode(body: encoded)
        XCTAssertEqual(decoded?.sampleBits, 12)
        XCTAssertEqual(decoded?.samples.count, 7)
    }

    func test_emptySamples() {
        let original = WaveformBlock(
            waveformType: 1, sampleRateHz: 100, blockSeq: 1,
            startTimestampMs: 100, sampleBits: 16, samples: []
        )
        let encoded = WaveformCodec.encode(original)
        let decoded = WaveformCodec.decode(body: encoded)
        XCTAssertEqual(decoded?.samples, [])
    }

    func test_detectBlockLoss() {
        XCTAssertEqual(WaveformCodec.detectBlockLoss(prevSeq: 5, currentSeq: 6), 0)
        XCTAssertEqual(WaveformCodec.detectBlockLoss(prevSeq: 5, currentSeq: 7), 1)
        XCTAssertEqual(WaveformCodec.detectBlockLoss(prevSeq: 5, currentSeq: 10), 4)
        // u32 wrap-around: 0xFFFFFFFE → 2 = gap of 3
        // diff = Int(Int64(2) - Int64(0xFFFFFFFE)) = Int(2 - (-2)) = 4
        // gap = max(0, 4 - 1) = 3
        XCTAssertEqual(WaveformCodec.detectBlockLoss(prevSeq: 0xFFFF_FFFE, currentSeq: 2), 3)
        // No loss on wrap to 0: (0 - 0xFFFFFFFF = 1) diff=1, gap=0
        XCTAssertEqual(WaveformCodec.detectBlockLoss(prevSeq: 0xFFFF_FFFF, currentSeq: 0), 0)
    }

    func test_encoderMtuSizing() {
        // MTU=185 default: max samples should be >0
        let max = WaveformEncoder.maxSamplesPerBlock(mtu: 185, sampleBits: 16)
        XCTAssertGreaterThan(max, 0)

        let max250 = WaveformEncoder.maxSamplesPerBlock(mtu: 250, sampleBits: 16)
        XCTAssertGreaterThan(max250, max, "Larger MTU should allow more samples")
    }

    func test_encoderProducesFragments() {
        let block = WaveformBlock(
            waveformType: 1, sampleRateHz: 128, blockSeq: 0,
            startTimestampMs: 0, sampleBits: 16,
            samples: Array(repeating: 100, count: 10)
        )
        let fragments = WaveformEncoder.encode(block: block, seq: 3, mtu: 185)
        XCTAssertFalse(fragments.isEmpty)

        // Round-trip through FrameAssembler
        let assembler = FrameAssembler()
        var decodedBlock: WaveformBlock?
        for frag in fragments {
            for frame in assembler.feed(frag) {
                if case let .waveform(wb) = frame {
                    decodedBlock = wb
                }
            }
        }
        XCTAssertNotNil(decodedBlock)
        XCTAssertEqual(decodedBlock?.samples.count, 10)
    }
}
