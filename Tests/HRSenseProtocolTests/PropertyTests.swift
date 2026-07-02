import XCTest
@testable import HRSenseProtocol

/// Property-based round-trip tests: decode(encode(x)) == x for random inputs.
final class PropertyTests: XCTestCase {

    // MARK: - DeviceSample round-trip

    func test_deviceSampleRoundTrip() {
        for _ in 0..<100 {
            let sample = makeRandomSample()
            let encoded = DataCodec.encode(sample)
            guard let decoded = DataCodec.decode(body: encoded) else {
                XCTFail("Failed to decode a valid sample")
                return
            }
            XCTAssertEqual(decoded.timestamp, sample.timestamp)
            XCTAssertEqual(decoded.heartRate, sample.heartRate)
            XCTAssertEqual(decoded.rrIntervals, sample.rrIntervals)
            XCTAssertEqual(decoded.battery, sample.battery)
            XCTAssertEqual(decoded.sensorStatus, sample.sensorStatus)
            XCTAssertEqual(decoded.sampleSeq, sample.sampleSeq)
        }
    }

    func test_commandRoundTrip() {
        let ops: [CommandOpCode] = [.hello, .helloAck, .startStream, .stopStream, .setConfig]
        for op in ops {
            let cmd = makeCommand(op: op)
            let encoded = CommandCodec.encode(cmd)
            guard let decoded = CommandCodec.decode(body: encoded) else {
                XCTFail("Failed to decode command \(op)")
                return
            }
            XCTAssertEqual(decoded.opCode, cmd.opCode)
            XCTAssertEqual(decoded.flags.isResponse, cmd.flags.isResponse)
        }
    }

    func test_waveformBlockRoundTrip() {
        for _ in 0..<50 {
            let block = makeRandomBlock()
            let encoded = WaveformCodec.encode(block)
            guard let decoded = WaveformCodec.decode(body: encoded) else {
                XCTFail("Failed to decode waveform block")
                return
            }
            XCTAssertEqual(decoded.waveformType, block.waveformType)
            XCTAssertEqual(decoded.sampleRateHz, block.sampleRateHz)
            XCTAssertEqual(decoded.blockSeq, block.blockSeq)
            XCTAssertEqual(decoded.samples, block.samples)
        }
    }

    // MARK: - Helpers

    private func makeRandomSample() -> DeviceSample {
        DeviceSample(
            timestamp: UInt32.random(in: 0..<1_000_000),
            heartRate: Bool.random() ? UInt16.random(in: 40...200) : nil,
            rrIntervals: (0..<Int.random(in: 0...10)).map { _ in UInt16.random(in: 400...1500) },
            battery: Bool.random() ? UInt8.random(in: 0...100) : nil,
            sensorStatus: Bool.random() ? UInt8.random(in: 0...7) : nil,
            sampleSeq: Bool.random() ? UInt32.random(in: 0...1_000_000) : nil
        )
    }

    private func makeCommand(op: CommandOpCode) -> Command {
        switch op {
        case .hello:
            return .hello(capabilities: Capabilities(rawValue: UInt32.random(in: 0...0x7FF)))
        case .helloAck:
            return .helloAck(capabilities: Capabilities(rawValue: UInt32.random(in: 0...0x7FF)),
                             model: "Sim", firmwareVersion: "1.0.0")
        case .startStream:
            return .startStream()
        case .stopStream:
            return .stopStream()
        default:
            return Command(opCode: op, flags: CommandFlags(isResponse: false), params: [])
        }
    }

    private func makeRandomBlock() -> WaveformBlock {
        let count = Int.random(in: 1...20)
        return WaveformBlock(
            waveformType: Bool.random() ? 1 : 2,
            sampleRateHz: UInt16.random(in: 64...512),
            blockSeq: UInt32.random(in: 0...1000),
            startTimestampMs: UInt32.random(in: 0...100_000),
            sampleBits: Bool.random() ? 12 : 16,
            samples: (0..<count).map { _ in Int16.random(in: -2048...2047) }
        )
    }
}
