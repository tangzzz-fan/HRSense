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
                OTACommand.otaWindowAck(
                    status: .success,
                    offset: UInt32(image.count),
                    windowCRC32: CRC32.compute(image)
                )
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

    func test_startOTAHonorsNegotiatedMaxChunkSize() async throws {
        let image = Data([0x10, 0x11, 0x12, 0x13])
        var controlCommands: [OTACommand] = []
        var writtenChunks: [Data] = []
        var ackIndex = 0

        let repository = OTARepositoryImpl(
            sendOTAControl: { command in
                controlCommands.append(command)
            },
            sendOTAControlAndWait: { command, _ in
                controlCommands.append(command)
                switch command.opCode {
                case .otaStart:
                    return .otaStartAck(status: .success, maxChunkSize: 2, maxWindow: 1)
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
                defer { ackIndex += 1 }
                let endOffset: UInt32 = ackIndex == 0 ? 2 : 4
                let chunk = ackIndex == 0 ? Data(image.prefix(2)) : Data(image.suffix(2))
                return OTACommand.otaWindowAck(
                    status: .success,
                    offset: endOffset,
                    windowCRC32: CRC32.compute(chunk)
                )
            },
            sendOTAChunk: { data in
                writtenChunks.append(data)
            },
            imageData: { image }
        )

        try await repository.startOTA(
            image: OTAFirmwareImage(
                imageSize: UInt32(image.count),
                imageCRC32: CRC32.compute(image),
                newVersion: "1.0.1"
            )
        )

        XCTAssertEqual(controlCommands.map(\.opCode), [.otaStart, .otaWindowBegin, .otaWindowBegin, .otaValidate, .otaApply])
        XCTAssertEqual(writtenChunks.count, 2)
        XCTAssertEqual(writtenChunks[0].prefix(4), Data([0x00, 0x00, 0x00, 0x00]))
        XCTAssertEqual(writtenChunks[0].dropFirst(4), Data([0x10, 0x11]))
        XCTAssertEqual(writtenChunks[1].prefix(4), Data([0x02, 0x00, 0x00, 0x00]))
        XCTAssertEqual(writtenChunks[1].dropFirst(4), Data([0x12, 0x13]))
    }

    func test_startOTAThrowsAfterWindowAckTimeoutRetriesExhausted() async {
        let image = Data([0x10, 0x11, 0x12, 0x13])
        var chunkSendCount = 0
        var waitCount = 0

        let repository = OTARepositoryImpl(
            sendOTAControl: { _ in },
            sendOTAControlAndWait: { command, _ in
                switch command.opCode {
                case .otaStart:
                    return .otaStartAck(status: .success)
                case .otaValidate:
                    return OTACommand(opCode: .otaValidateResult, payload: [OTAStatusCode.success.rawValue])
                case .otaApply:
                    return OTACommand(opCode: .otaApply, payload: [OTAStatusCode.success.rawValue])
                default:
                    return OTACommand(opCode: .otaAbort, payload: [OTAStatusCode.invalidImage.rawValue])
                }
            },
            waitForOTAWindowAck: { _ in
                waitCount += 1
                throw AppError.commandTimeout(opcode: OTAOpCode.otaWindowAck.rawValue)
            },
            sendOTAChunk: { _ in
                chunkSendCount += 1
            },
            imageData: { image }
        )

        do {
            try await repository.startOTA(
                image: OTAFirmwareImage(
                    imageSize: UInt32(image.count),
                    imageCRC32: CRC32.compute(image),
                    newVersion: "1.0.1"
                )
            )
            XCTFail("Expected OTA transfer to fail after ACK timeouts")
        } catch let error as AppError {
            XCTAssertEqual(error, .otaFailed(phase: "transfer"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(waitCount, 3)
        XCTAssertEqual(chunkSendCount, 3)
    }

    func test_startOTAThrowsWhenDeviceRejectsOnLowBattery() async {
        let image = Data([0x10, 0x11, 0x12, 0x13])

        let repository = OTARepositoryImpl(
            sendOTAControl: { _ in },
            sendOTAControlAndWait: { command, _ in
                switch command.opCode {
                case .otaStart:
                    return .otaStartAck(status: .lowBattery)
                default:
                    return OTACommand(opCode: .otaAbort, payload: [OTAStatusCode.invalidImage.rawValue])
                }
            },
            waitForOTAWindowAck: { _ in
                XCTFail("Should not wait for window ACK when OTA_START is rejected")
                return OTACommand.otaWindowAck(status: .success, offset: 0, windowCRC32: 0)
            },
            sendOTAChunk: { _ in
                XCTFail("Should not send chunks when OTA_START is rejected")
            },
            imageData: { image }
        )

        do {
            try await repository.startOTA(
                image: OTAFirmwareImage(
                    imageSize: UInt32(image.count),
                    imageCRC32: CRC32.compute(image),
                    newVersion: "1.0.1"
                )
            )
            XCTFail("Expected OTA start failure on low battery")
        } catch let error as AppError {
            XCTAssertEqual(error, .otaFailed(phase: "start"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_startOTARejectsWindowAckWhenCRCDoesNotMatch() async {
        let image = Data([0x10, 0x11, 0x12, 0x13])
        let expectedCRC = CRC32.compute(image)
        var waitCount = 0

        let repository = OTARepositoryImpl(
            sendOTAControl: { _ in },
            sendOTAControlAndWait: { command, _ in
                switch command.opCode {
                case .otaStart:
                    return .otaStartAck(status: .success)
                case .otaValidate:
                    return OTACommand(opCode: .otaValidateResult, payload: [OTAStatusCode.success.rawValue])
                case .otaApply:
                    return OTACommand(opCode: .otaApply, payload: [OTAStatusCode.success.rawValue])
                default:
                    return OTACommand(opCode: .otaAbort, payload: [OTAStatusCode.invalidImage.rawValue])
                }
            },
            waitForOTAWindowAck: { _ in
                waitCount += 1
                return OTACommand.otaWindowAck(
                    status: .success,
                    offset: UInt32(image.count),
                    windowCRC32: 0xDEADBEEF
                )
            },
            sendOTAChunk: { _ in },
            imageData: { image }
        )

        do {
            try await repository.startOTA(
                image: OTAFirmwareImage(
                    imageSize: UInt32(image.count),
                    imageCRC32: expectedCRC,
                    newVersion: "1.0.1"
                )
            )
            XCTFail("Expected OTA transfer to fail on CRC mismatch")
        } catch let error as AppError {
            XCTAssertEqual(error, .otaFailed(phase: "transfer"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(waitCount, 3)
    }

    func test_startOTAThrowsWhenValidateFails() async {
        let image = Data([0x10, 0x11, 0x12, 0x13])

        let repository = OTARepositoryImpl(
            sendOTAControl: { _ in },
            sendOTAControlAndWait: { command, _ in
                switch command.opCode {
                case .otaStart:
                    return .otaStartAck(status: .success)
                case .otaValidate:
                    return OTACommand(opCode: .otaValidateResult, payload: [OTAStatusCode.crcMismatch.rawValue])
                case .otaApply:
                    return OTACommand(opCode: .otaApply, payload: [OTAStatusCode.success.rawValue])
                default:
                    return OTACommand(opCode: .otaAbort, payload: [OTAStatusCode.invalidImage.rawValue])
                }
            },
            waitForOTAWindowAck: { _ in
                OTACommand.otaWindowAck(
                    status: .success,
                    offset: UInt32(image.count),
                    windowCRC32: CRC32.compute(image)
                )
            },
            sendOTAChunk: { _ in },
            imageData: { image }
        )

        do {
            try await repository.startOTA(
                image: OTAFirmwareImage(
                    imageSize: UInt32(image.count),
                    imageCRC32: CRC32.compute(image),
                    newVersion: "1.0.1"
                )
            )
            XCTFail("Expected OTA validate failure")
        } catch let error as AppError {
            XCTAssertEqual(error, .otaFailed(phase: "validate"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_startOTAResumesFromResumeOffsetAndOnlySendsRemainingBytes() async throws {
        let image = Data([0x10, 0x11, 0x12, 0x13])
        var writtenChunks: [Data] = []

        let repository = OTARepositoryImpl(
            sendOTAControl: { _ in },
            sendOTAControlAndWait: { command, _ in
                switch command.opCode {
                case .otaStart:
                    return .otaStartAck(status: .success, resumeOffset: 2)
                case .otaValidate:
                    return OTACommand(opCode: .otaValidateResult, payload: [OTAStatusCode.success.rawValue])
                case .otaApply:
                    return OTACommand(opCode: .otaApply, payload: [OTAStatusCode.success.rawValue])
                default:
                    return OTACommand(opCode: .otaAbort, payload: [OTAStatusCode.invalidImage.rawValue])
                }
            },
            waitForOTAWindowAck: { _ in
                OTACommand.otaWindowAck(
                    status: .success,
                    offset: UInt32(image.count),
                    windowCRC32: CRC32.compute(Data(image.dropFirst(2)))
                )
            },
            sendOTAChunk: { data in
                writtenChunks.append(data)
            },
            imageData: { image }
        )

        try await repository.startOTA(
            image: OTAFirmwareImage(
                imageSize: UInt32(image.count),
                imageCRC32: CRC32.compute(image),
                newVersion: "1.0.1"
            )
        )

        XCTAssertEqual(writtenChunks.count, 1)
        XCTAssertEqual(writtenChunks[0].prefix(4), Data([0x02, 0x00, 0x00, 0x00]))
        XCTAssertEqual(writtenChunks[0].dropFirst(4), Data([0x12, 0x13]))
    }
}
