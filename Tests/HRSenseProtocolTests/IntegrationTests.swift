import XCTest
@testable import HRSenseProtocol

/// End-to-end integration: Command → encode → fragment → feed → DecodedFrame
final class IntegrationTests: XCTestCase {

    func test_commandE2E() {
        let caps = Capabilities(rawValue: 0x01)  // HEART_RATE only
        let cmd = Command.hello(capabilities: caps)
        let fragments = encodeCommand(cmd, seq: 1, mtu: 185)

        let assembler = FrameAssembler()
        let results = assembler.feed(fragments[0])

        XCTAssertEqual(results.count, 1)
        guard case let .command(decoded) = results[0] else {
            XCTFail("Expected .command, got \(results[0])")
            return
        }
        XCTAssertEqual(decoded.opCode, .hello)
        XCTAssertEqual(decoded.flags.isResponse, false)
        XCTAssertEqual(decoded.params.first(where: { $0.tag == .capabilities })?.value, [0x01, 0x00, 0x00, 0x00])
    }

    func test_dataE2E() {
        let sample = DeviceSample(
            timestamp: 5000,
            heartRate: 80,
            rrIntervals: [780, 790, 770],
            battery: 90,
            sensorStatus: 0x03,
            sampleSeq: 42
        )
        let fragments = encodeData(sample, seq: 3, mtu: 185)

        let assembler = FrameAssembler()
        let results = assembler.feed(fragments[0])

        XCTAssertEqual(results.count, 1)
        guard case let .data(decoded) = results[0] else {
            XCTFail("Expected .data")
            return
        }
        XCTAssertEqual(decoded.timestamp, 5000)
        XCTAssertEqual(decoded.heartRate, 80)
        XCTAssertEqual(decoded.rrIntervals, [780, 790, 770])
        XCTAssertEqual(decoded.battery, 90)
        XCTAssertEqual(decoded.sensorStatus, 0x03)
        XCTAssertEqual(decoded.sampleSeq, 42)
    }

    func test_dataE2E_multiFragment() {
        let rr = Array(repeating: UInt16(800), count: 80)
        let sample = DeviceSample(timestamp: 1000, heartRate: 72, rrIntervals: rr, sampleSeq: 5)
        let fragments = encodeData(sample, seq: 7, mtu: 30)

        XCTAssertGreaterThan(fragments.count, 1)

        let assembler = FrameAssembler()
        var final: DecodedFrame?
        for frag in fragments {
            let results = assembler.feed(frag)
            if !results.isEmpty { final = results[0] }
        }

        guard case let .data(decoded) = final else {
            XCTFail("Expected .data at end")
            return
        }
        XCTAssertEqual(decoded.rrIntervals.count, 80)
        XCTAssertEqual(decoded.sampleSeq, 5)
    }
}
