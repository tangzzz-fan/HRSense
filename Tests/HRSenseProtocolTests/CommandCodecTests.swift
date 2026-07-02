import XCTest
@testable import HRSenseProtocol

final class CommandCodecTests: XCTestCase {

    func test_helloRoundTrip() {
        let caps = Capabilities(rawValue: 0x0000002F)  // HR + RR + battery + contact + configurable
        let original = Command.hello(capabilities: caps)

        let encoded = CommandCodec.encode(original)
        let decoded = CommandCodec.decode(body: encoded)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.opCode, .hello)
        XCTAssertEqual(decoded?.flags.isResponse, false)
    }

    func test_helloAckRoundTrip() {
        let original = Command.helloAck(
            capabilities: Capabilities(rawValue: 0x2F),
            model: "HRSense-Sim",
            firmwareVersion: "1.0.0"
        )

        let encoded = CommandCodec.encode(original)
        let decoded = CommandCodec.decode(body: encoded)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.opCode, .helloAck)
        XCTAssertEqual(decoded?.flags.isResponse, true)
    }

    func test_startStreamRoundTrip() {
        let original = Command.startStream()

        let encoded = CommandCodec.encode(original)
        let decoded = CommandCodec.decode(body: encoded)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.opCode, .startStream)
    }

    func test_stopStreamRoundTrip() {
        let original = Command.stopStream()

        let encoded = CommandCodec.encode(original)
        let decoded = CommandCodec.decode(body: encoded)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.opCode, .stopStream)
        XCTAssertEqual(decoded?.params.count, 0)
    }

    func test_truncatedBody() {
        XCTAssertNil(CommandCodec.decode(body: [0x01]))  // opcode only, no flags
        XCTAssertNil(CommandCodec.decode(body: []))
    }

    func test_unknownOpcode() {
        XCTAssertNil(CommandCodec.decode(body: [0xFE, 0x00]))
    }
}
