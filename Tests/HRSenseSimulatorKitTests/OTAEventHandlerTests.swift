import XCTest
@testable import HRSenseSimulatorKit
import HRSenseProtocol

final class OTAEventHandlerTests: XCTestCase {
    func test_windowBeginThenChunkProducesWindowAck() {
        let handler = OTAEventHandler(stateMachine: OTAStateMachine(currentVersion: "1.0.0"))
        let imageBytes: [UInt8] = [1, 2, 3, 4]
        let crc = CRC32.compute(Data(imageBytes))

        let startResponses = handler.handle(
            command: .otaStart(imageSize: UInt32(imageBytes.count), imageCRC32: crc, newVersion: "1.0.1")
        )
        XCTAssertEqual(startResponses.first?.opCode, .otaStartAck)

        let beginResponses = handler.handle(command: .otaWindowBegin(offset: 0, size: UInt16(imageBytes.count)))
        XCTAssertTrue(beginResponses.isEmpty)

        var packet = Data()
        var offset: UInt32 = 0
        withUnsafeBytes(of: &offset) { packet.append(contentsOf: $0) }
        packet.append(contentsOf: imageBytes)

        let chunkResponses = handler.receiveOTAChunk(packet: [UInt8](packet))
        XCTAssertEqual(chunkResponses.count, 1)
        XCTAssertEqual(chunkResponses.first?.opCode, .otaWindowAck)
        XCTAssertEqual(chunkResponses.first?.payload.first, OTAStatusCode.success.rawValue)
    }

    func test_chunkWithoutPendingWindowReturnsOutOfOrderAck() {
        let handler = OTAEventHandler(stateMachine: OTAStateMachine(currentVersion: "1.0.0"))
        let packet = Data([0, 0, 0, 0, 1, 2, 3, 4])

        let responses = handler.receiveOTAChunk(packet: [UInt8](packet))

        XCTAssertEqual(responses.count, 1)
        XCTAssertEqual(responses.first?.opCode, .otaWindowAck)
        XCTAssertEqual(responses.first?.payload.first, OTAStatusCode.windowOutOfOrder.rawValue)
    }
}
