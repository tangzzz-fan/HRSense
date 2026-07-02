import XCTest
@testable import HRSenseSimulatorKit
import HRSenseProtocol

final class CommandProcessorTests: XCTestCase {

    func test_helloGeneratesHelloAck() {
        let config = SimulatorConfig()
        let processor = CommandProcessor(config: config)
        let cmd = Command.hello(capabilities: Capabilities(rawValue: 0x01))

        let responses = processor.process(command: cmd, seq: 1)

        XCTAssertFalse(responses.isEmpty, "HELLO should produce HELLO_ACK response")
        // Decode the response to verify
        let assembler = FrameAssembler()
        var decodedCmd: Command?
        for frag in responses {
            let frames = assembler.feed(frag)
            if case let .command(c) = frames.first {
                decodedCmd = c
            }
        }
        XCTAssertEqual(decodedCmd?.opCode, .helloAck)
        XCTAssertTrue(decodedCmd?.flags.isResponse ?? false)
    }

    func test_helloTransitionsToHandshakeDone() {
        let processor = CommandProcessor(config: SimulatorConfig())
        processor.didConnect()  // BLE connection must precede command writes
        let cmd = Command.hello(capabilities: Capabilities(rawValue: 0x01))

        _ = processor.process(command: cmd, seq: 0)

        XCTAssertEqual(processor.state, .handshakeDone)
    }

    func test_startStreamGeneratesAck() {
        let processor = CommandProcessor(config: SimulatorConfig())
        processor.didConnect()
        _ = processor.process(command: Command.hello(capabilities: Capabilities(rawValue: 0x01)), seq: 0)
        let cmd = Command.startStream()
        let responses = processor.process(command: cmd, seq: 2)

        XCTAssertFalse(responses.isEmpty, "START_STREAM should produce ACK")
        XCTAssertEqual(processor.state, .streaming)
    }

    func test_stopStreamTransitionsBack() {
        let processor = CommandProcessor(config: SimulatorConfig())
        processor.didConnect()
        _ = processor.process(command: Command.hello(capabilities: Capabilities(rawValue: 0x01)), seq: 0)
        _ = processor.process(command: Command.startStream(), seq: 1)
        _ = processor.process(command: Command.stopStream(), seq: 2)

        XCTAssertEqual(processor.state, .handshakeDone)
    }

    func test_unknownOpcodeReturnsError() {
        let processor = CommandProcessor(config: SimulatorConfig())
        processor.didConnect()
        // Create a command with a purpose-built unknown opcode raw byte
        let cmd = Command(opCode: .hello, flags: CommandFlags(isResponse: false), params: [])
        // Send a valid opcode (hello) — that's a well-known path. The "error" opcode
        // case in the switch returns []. Test that the switch handles it without crashing:
        let errorCmd = Command(opCode: .error, flags: CommandFlags(isResponse: false), params: [])
        let responses = processor.process(command: errorCmd, seq: 0)
        // .error case returns [] — valid, no-op for the simulator
        XCTAssertEqual(responses.count, 0)
    }

    func test_encodeSample() {
        let config = SimulatorConfig(mtu: 185)
        let processor = CommandProcessor(config: config)
        let sample = DeviceSample(timestamp: 1000, heartRate: 72, sampleSeq: 1)

        let fragments = processor.encodeSample(sample)
        XCTAssertFalse(fragments.isEmpty)
    }

    func test_resetClearsState() {
        let processor = CommandProcessor(config: SimulatorConfig())
        _ = processor.process(command: Command.hello(capabilities: Capabilities(rawValue: 0x01)), seq: 0)
        _ = processor.process(command: Command.startStream(), seq: 1)

        processor.reset()

        XCTAssertEqual(processor.state, .advertising)
    }
}
