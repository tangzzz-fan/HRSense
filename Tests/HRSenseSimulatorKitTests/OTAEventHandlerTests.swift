import XCTest
@testable import HRSenseSimulatorKit
import HRSenseProtocol

final class OTAEventHandlerTests: XCTestCase {
    func test_startAckCarriesResumeOffsetAndNegotiatedLimits() {
        let handler = OTAEventHandler(
            stateMachine: OTAStateMachine(currentVersion: "1.0.0"),
            mtu: 185,
            maxChunkSize: 96,
            maxWindow: 2
        )
        let imageBytes: [UInt8] = [1, 2, 3, 4]
        let fullCRC = CRC32.compute(Data(imageBytes))

        _ = handler.handle(
            command: .otaStart(imageSize: UInt32(imageBytes.count), imageCRC32: fullCRC, newVersion: "1.0.1")
        )
        _ = handler.handle(command: .otaWindowBegin(offset: 0, size: 2))

        var packet = Data()
        var offset: UInt32 = 0
        withUnsafeBytes(of: &offset) { packet.append(contentsOf: $0) }
        packet.append(contentsOf: imageBytes.prefix(2))
        _ = handler.receiveOTAChunk(packet: [UInt8](packet))

        let restartResponses = handler.handle(
            command: .otaStart(imageSize: UInt32(imageBytes.count), imageCRC32: fullCRC, newVersion: "1.0.1")
        )

        let parsed = OTACommand.parseStartAckPayload(restartResponses[0].payload)
        XCTAssertEqual(parsed?.status, .success)
        XCTAssertEqual(parsed?.resumeOffset, 2)
        XCTAssertEqual(parsed?.maxChunkSize, 96)
        XCTAssertEqual(parsed?.maxWindow, 2)
    }

    func test_windowBeginThenChunkProducesWindowAckWithCRC32() {
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
        let parsed = OTACommand.parseWindowAckPayload(chunkResponses[0].payload)
        XCTAssertEqual(parsed?.status, .success)
        XCTAssertEqual(parsed?.recvOffset, UInt32(imageBytes.count))
        XCTAssertEqual(parsed?.windowCRC32, crc)
    }

    func test_chunkWithoutPendingWindowReturnsOutOfOrderAck() {
        let handler = OTAEventHandler(stateMachine: OTAStateMachine(currentVersion: "1.0.0"))
        let packet = Data([0, 0, 0, 0, 1, 2, 3, 4])

        let responses = handler.receiveOTAChunk(packet: [UInt8](packet))

        XCTAssertEqual(responses.count, 1)
        XCTAssertEqual(responses.first?.opCode, .otaWindowAck)
        XCTAssertEqual(OTACommand.parseWindowAckPayload(responses[0].payload)?.status, .windowOutOfOrder)
    }

    func test_outOfOrderWindowBeginReturnsWindowOutOfOrderAck() {
        let handler = OTAEventHandler(stateMachine: OTAStateMachine(currentVersion: "1.0.0"))
        let imageBytes: [UInt8] = [1, 2, 3, 4]
        let crc = CRC32.compute(Data(imageBytes))

        _ = handler.handle(
            command: .otaStart(imageSize: UInt32(imageBytes.count), imageCRC32: crc, newVersion: "1.0.1")
        )

        let responses = handler.handle(command: .otaWindowBegin(offset: 2, size: 2))

        XCTAssertEqual(responses.count, 1)
        XCTAssertEqual(OTACommand.parseWindowAckPayload(responses[0].payload)?.status, .windowOutOfOrder)
        XCTAssertEqual(OTACommand.parseWindowAckPayload(responses[0].payload)?.recvOffset, 0)
    }

    func test_restartWithSameImageReturnsResumeOffset() {
        let handler = OTAEventHandler(stateMachine: OTAStateMachine(currentVersion: "1.0.0"))
        let imageBytes: [UInt8] = [1, 2, 3, 4]
        let fullCRC = CRC32.compute(Data(imageBytes))

        _ = handler.handle(
            command: .otaStart(imageSize: UInt32(imageBytes.count), imageCRC32: fullCRC, newVersion: "1.0.1")
        )
        _ = handler.handle(command: .otaWindowBegin(offset: 0, size: 2))

        var packet = Data()
        var offset: UInt32 = 0
        withUnsafeBytes(of: &offset) { packet.append(contentsOf: $0) }
        packet.append(contentsOf: imageBytes.prefix(2))
        _ = handler.receiveOTAChunk(packet: [UInt8](packet))

        let restartResponses = handler.handle(
            command: .otaStart(imageSize: UInt32(imageBytes.count), imageCRC32: fullCRC, newVersion: "1.0.1")
        )

        XCTAssertEqual(restartResponses.count, 1)
        XCTAssertEqual(restartResponses[0].opCode, .otaStartAck)
        XCTAssertEqual(OTACommand.parseStartAckPayload(restartResponses[0].payload)?.status, .success)
        XCTAssertEqual(OTACommand.parseStartAckPayload(restartResponses[0].payload)?.resumeOffset, 2)
    }

    func test_startRejectsWhenBatteryTooLow() {
        let handler = OTAEventHandler(
            stateMachine: OTAStateMachine(currentVersion: "1.0.0"),
            batteryPercent: 20
        )
        let imageBytes: [UInt8] = [1, 2, 3, 4]
        let crc = CRC32.compute(Data(imageBytes))

        let responses = handler.handle(
            command: .otaStart(imageSize: UInt32(imageBytes.count), imageCRC32: crc, newVersion: "1.0.1")
        )

        XCTAssertEqual(OTACommand.parseStartAckPayload(responses[0].payload)?.status, .lowBattery)
    }

    func test_startRejectsDowngrade() {
        let handler = OTAEventHandler(stateMachine: OTAStateMachine(currentVersion: "2.0.0"))
        let imageBytes: [UInt8] = [1, 2, 3, 4]
        let crc = CRC32.compute(Data(imageBytes))

        let responses = handler.handle(
            command: .otaStart(imageSize: UInt32(imageBytes.count), imageCRC32: crc, newVersion: "1.9.9")
        )

        XCTAssertEqual(OTACommand.parseStartAckPayload(responses[0].payload)?.status, .downgradeDenied)
    }

    func test_abortClearsTransferStateAndFutureChunkIsRejected() {
        let handler = OTAEventHandler(stateMachine: OTAStateMachine(currentVersion: "1.0.0"))
        let imageBytes: [UInt8] = [1, 2, 3, 4]
        let crc = CRC32.compute(Data(imageBytes))

        _ = handler.handle(
            command: .otaStart(imageSize: UInt32(imageBytes.count), imageCRC32: crc, newVersion: "1.0.1")
        )
        _ = handler.handle(command: .otaWindowBegin(offset: 0, size: UInt16(imageBytes.count)))

        let abortResponses = handler.handle(command: .otaAbort())
        XCTAssertEqual(abortResponses[0].opCode, .otaAbort)
        XCTAssertEqual(abortResponses[0].payload.first, OTAStatusCode.success.rawValue)

        var packet = Data()
        var offset: UInt32 = 0
        withUnsafeBytes(of: &offset) { packet.append(contentsOf: $0) }
        packet.append(contentsOf: imageBytes)

        let chunkResponses = handler.receiveOTAChunk(packet: [UInt8](packet))
        XCTAssertEqual(OTACommand.parseWindowAckPayload(chunkResponses[0].payload)?.status, .windowOutOfOrder)
    }
}
