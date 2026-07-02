import XCTest
@testable import HRSenseProtocol

final class CodecRoundTripTests: XCTestCase {

    func test_ackRoundTrip() {
        let original = ACKPayload(seq: 42, opcode: 0x01, status: 0x00)
        let encoded = ACKCodec.encode(original)
        let decoded = ACKCodec.decode(body: encoded)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.seq, 42)
        XCTAssertEqual(decoded?.opcode, 0x01)
        XCTAssertEqual(decoded?.status, 0x00)
        XCTAssertTrue(decoded?.isSuccess == true)
    }

    func test_eventRoundTrip() {
        let original = DeviceEvent(kind: .batteryLevelChanged, payload: [85], timestamp: 10_000)
        let encoded = EventCodec.encode(original)
        let decoded = EventCodec.decode(body: encoded)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.kind, .batteryLevelChanged)
        XCTAssertEqual(decoded?.payload, [85])
        XCTAssertEqual(decoded?.timestamp, 10_000)
    }

    func test_waveformRoundTrip() {
        let original = WaveformBlock(
            waveformType: 1,       // ECG
            sampleRateHz: 128,
            blockSeq: 7,
            startTimestampMs: 5000,
            sampleBits: 16,
            samples: [100, -50, 200, -100, 75]
        )
        let encoded = WaveformCodec.encode(original)
        let decoded = WaveformCodec.decode(body: encoded)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.waveformType, 1)
        XCTAssertEqual(decoded?.sampleRateHz, 128)
        XCTAssertEqual(decoded?.blockSeq, 7)
        XCTAssertEqual(decoded?.startTimestampMs, 5000)
        XCTAssertEqual(decoded?.sampleBits, 16)
        XCTAssertEqual(decoded?.samples, [100, -50, 200, -100, 75])
    }

    func test_otaRoundTrip() {
        let original = OTACommand(opCode: .otaStart, payload: [0x01, 0x00, 0x00, 0x00])
        let encoded = OTACodec.encode(original)
        let decoded = OTACodec.decode(body: encoded)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.opCode, .otaStart)
        XCTAssertEqual(decoded?.payload, [0x01, 0x00, 0x00, 0x00])
    }
}
