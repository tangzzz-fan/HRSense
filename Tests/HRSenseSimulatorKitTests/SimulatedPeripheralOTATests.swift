import XCTest
@testable import HRSenseSimulatorKit
import HRSenseProtocol

final class SimulatedPeripheralOTATests: XCTestCase {
    func test_otaApplyRebootUpdatesFirmwareVersionVisibleToNextHandshake() async throws {
        let peripheral = SimulatedPeripheral(
            config: SimulatorConfig(firmwareVersion: "1.0.0-sim")
        )
        let image = Data([0x10, 0x11, 0x12, 0x13])
        let imageCRC = CRC32.compute(image)

        let startResponses = peripheral.otaEventHandler?.handle(
            command: .otaStart(imageSize: UInt32(image.count), imageCRC32: imageCRC, newVersion: "1.0.1-sim")
        )
        XCTAssertEqual(OTACommand.parseStartAckPayload(startResponses?.first?.payload ?? [])?.status, .success)

        _ = peripheral.otaEventHandler?.handle(command: .otaWindowBegin(offset: 0, size: UInt16(image.count)))
        let packet = Data([0x00, 0x00, 0x00, 0x00]) + image
        let chunkResponses = peripheral.otaEventHandler?.receiveOTAChunk(packet: [UInt8](packet))
        XCTAssertEqual(OTACommand.parseWindowAckPayload(chunkResponses?.first?.payload ?? [])?.status, .success)

        let validateResponses = peripheral.otaEventHandler?.handle(command: .otaValidate(expectedCRC32: imageCRC))
        XCTAssertEqual(validateResponses?.first?.opCode, .otaValidateResult)
        XCTAssertEqual(validateResponses?.first?.payload.first, OTAStatusCode.success.rawValue)

        let applyResponses = peripheral.otaEventHandler?.handle(command: .otaApply())
        XCTAssertEqual(applyResponses?.first?.opCode, .otaApply)
        XCTAssertEqual(applyResponses?.first?.payload.first, OTAStatusCode.success.rawValue)

        await assertEventually(timeout: 2) {
            peripheral.currentFirmwareVersion == "1.0.1-sim"
        }

        XCTAssertEqual(peripheral.currentFirmwareVersion, "1.0.1-sim")

        let processor = peripheral.commandProcessor
        processor.didConnect()
        let responses = processor.process(
            command: Command.hello(capabilities: Capabilities(rawValue: 0x01)),
            seq: 0
        )

        let assembler = FrameAssembler()
        let helloAck = responses
            .flatMap { assembler.feed($0) }
            .compactMap { frame -> Command? in
                if case let .command(command) = frame { return command }
                return nil
            }
            .first

        XCTAssertEqual(helloAck?.opCode, .helloAck)
        let firmwareParam = helloAck?.params.first(where: { $0.tag == .sensorStatus })
        XCTAssertEqual(String(bytes: firmwareParam?.value ?? [], encoding: .utf8), "1.0.1-sim")
    }
}

private extension XCTestCase {
    /// Polls a synchronous condition until it succeeds or the timeout elapses.
    func assertEventually(
        timeout: TimeInterval = 2,
        pollInterval: TimeInterval = 0.02,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        XCTFail("Condition was not satisfied within \(timeout) seconds.", file: file, line: line)
    }
}
