import XCTest
@testable import HRSenseData
import HRSenseCore
import HRSenseProtocol

final class OTARepositoryImplTests: XCTestCase {
    func test_startOTAWaitsForWindowAckAndSendsOffsetPrefixedChunk() async throws {
        let image = Data([0x10, 0x11, 0x12, 0x13])
        let expectedCRC = CRC32.compute(image)

        var controlCommands: [OTAOpCode] = []
        var writtenChunks: [Data] = []

        let repository = OTARepositoryImpl(
            sendOTAControl: { command in
                controlCommands.append(command.opCode)
            },
            sendOTAControlAndWait: { command, _ in
                controlCommands.append(command.opCode)
                switch command.opCode {
                case .otaStart:
                    return .otaStartAck(status: .success)
                case .otaValidate:
                    return OTACommand(opCode: .otaValidateResult, payload: [OTAStatusCode.success.rawValue])
                case .otaApply:
                    return OTACommand(opCode: .otaApply, payload: [OTAStatusCode.success.rawValue])
                default:
                    XCTFail("Unexpected OTA control wait command: \(command.opCode)")
                    return OTACommand(opCode: .otaAbort, payload: [OTAStatusCode.invalidImage.rawValue])
                }
            },
            waitForOTAWindowAck: { _ in
                OTACommand.otaWindowAck(status: .success, offset: UInt32(image.count))
            },
            sendOTAChunk: { data in
                writtenChunks.append(data)
            },
            imageData: { image }
        )

        try await repository.startOTA(
            image: OTAFirmwareImage(
                imageSize: UInt32(image.count),
                imageCRC32: expectedCRC,
                newVersion: "1.0.1"
            )
        )

        XCTAssertEqual(controlCommands, [.otaStart, .otaWindowBegin, .otaValidate, .otaApply])
        XCTAssertEqual(writtenChunks.count, 1)
        XCTAssertEqual(writtenChunks[0].prefix(4), Data([0x00, 0x00, 0x00, 0x00]))
        XCTAssertEqual(writtenChunks[0].dropFirst(4), image)
    }
}
