import XCTest
@testable import HRSenseProtocol

final class ProtobufCommandCodecTests: XCTestCase {
    func test_helloRoundTripThroughProtobufCodec() throws {
        let original = Command.hello(
            versions: [ProtocolVersion.v1],
            capabilities: [.heartRate, .protobufPayload]
        )

        let encoded = try ProtobufCommandCodec.encode(original)
        let decoded = ProtobufCommandCodec.decode(body: encoded)

        XCTAssertEqual(decoded?.opCode, .hello)
        XCTAssertEqual(decoded?.flags.isResponse, false)
        XCTAssertEqual(
            decoded?.params.first(where: { $0.tag == .capabilities })?.value,
            Capabilities([.heartRate, .protobufPayload]).bytesLE
        )
    }

    func test_helloAckRoundTripThroughProtobufCodec() throws {
        let original = Command.helloAck(
            version: ProtocolVersion.v1,
            capabilities: [.heartRate, .rrIntervals, .protobufPayload],
            model: "HRSense-Sim",
            firmwareVersion: "1.0.0-sim"
        )

        let encoded = try ProtobufCommandCodec.encode(original)
        let decoded = ProtobufCommandCodec.decode(body: encoded)

        XCTAssertEqual(decoded?.opCode, .helloAck)
        XCTAssertEqual(decoded?.flags.isResponse, true)
        XCTAssertEqual(
            String(bytes: decoded?.params.first(where: { $0.tag == .battery })?.value ?? [], encoding: .utf8),
            "HRSense-Sim"
        )
        XCTAssertEqual(
            String(bytes: decoded?.params.first(where: { $0.tag == .sensorStatus })?.value ?? [], encoding: .utf8),
            "1.0.0-sim"
        )
    }
}
