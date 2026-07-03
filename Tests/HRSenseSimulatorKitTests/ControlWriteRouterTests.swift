import XCTest
@testable import HRSenseSimulatorKit
import HRSenseProtocol

final class ControlWriteRouterTests: XCTestCase {
    func test_routerEchoesIncomingSequenceIntoAckPayload() {
        var router = SimulatedPeripheral.ControlWriteRouter()
        let processor = CommandProcessor(config: SimulatorConfig())
        processor.didConnect()
        _ = processor.process(command: Command.hello(capabilities: Capabilities(rawValue: 0x01)), seq: 0)

        let incomingFragments = encodeCommand(Command.startStream(), seq: 0x2A, mtu: 185)
        XCTAssertEqual(incomingFragments.count, 1)

        let routed = router.process(incomingFragments[0], commandProcessor: processor)
        XCTAssertEqual(routed.count, 1)

        let responses = routed[0].1
        let assembler = FrameAssembler()
        let decoded = responses.compactMap { assembler.feed($0).first }

        guard case let .ack(ack)? = decoded.first else {
            return XCTFail("Expected START_STREAM to generate an ACK response")
        }

        XCTAssertEqual(ack.seq, 0x2A)
        XCTAssertEqual(ack.opcode, CommandOpCode.startStream.rawValue)
        XCTAssertEqual(ack.status, 0x00)
    }

    func test_routerResetClearsAssemblerState() {
        var router = SimulatedPeripheral.ControlWriteRouter()
        router.reset()

        let processor = CommandProcessor(config: SimulatorConfig())
        let fragments = router.process(Data(), commandProcessor: processor)

        XCTAssertTrue(fragments.isEmpty)
    }
}
