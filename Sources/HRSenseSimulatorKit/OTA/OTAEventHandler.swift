import Foundation
import HRSenseProtocol

/// Handles incoming OTA command writes from the App.
///
/// Routes via OTAStateMachine + OTAImageBuffer and produces response frames.
public final class OTAEventHandler: @unchecked Sendable {

    private let stateMachine: OTAStateMachine
    private var imageBuffer: OTAImageBuffer?
    private let mtu: Int

    public var onRebootNeeded: (() -> Void)?

    public init(stateMachine: OTAStateMachine, mtu: Int = 185) {
        self.stateMachine = stateMachine
        self.mtu = mtu
    }

    /// Handle an OTA command from the App. Returns response OTACommands.
    public func handle(command: OTACommand) -> [OTACommand] {
        switch command.opCode {
        case .otaStart:
            return handleStart(command)
        case .otaWindowBegin:
            return handleWindow(command)
        case .otaValidate:
            return handleValidate(command)
        case .otaApply:
            return handleApply(command)
        case .otaAbort:
            return handleAbort(command)
        default:
            return []
        }
    }

    private func handleStart(_ cmd: OTACommand) -> [OTACommand] {
        guard let (imageSize, imageCRC32, newVersion) = OTACodec.parseStartPayload(cmd.payload) else {
            return [OTACommand.otaStartAck(status: .invalidImage)]
        }

        // Precondition checks
        if let failure = OTAPreconditionChecker.check(
            batteryPercent: 85,  // Simulated
            currentVersion: stateMachine.currentVersion,
            targetVersion: newVersion
        ) {
            return [OTACommand.otaStartAck(status: failure)]
        }

        // Check resume offset
        let off = imageBuffer?.resumeOffset ?? 0
        let resumeOff: UInt32? = off > 0 ? UInt32(off) : nil

        // Create new image buffer
        imageBuffer = OTAImageBuffer(totalSize: Int(imageSize))

        stateMachine.handle(.startReceived(imageSize: imageSize, imageCRC32: imageCRC32, newVersion: newVersion))
        stateMachine.handle(.windowTransferComplete)  // Move to transferring

        return [OTACommand.otaStartAck(status: .success, resumeOffset: resumeOff)]
    }

    private func handleWindow(_ cmd: OTACommand) -> [OTACommand] {
        guard let buf = imageBuffer else {
            return [OTACommand.otaWindowAck(status: .invalidImage, offset: 0)]
        }

        // Payload: windowOffset(u32) + windowSize(u16) + data
        guard cmd.payload.count >= 6 else {
            return [OTACommand.otaWindowAck(status: .invalidImage, offset: 0)]
        }
        let offset = Int(UInt32(cmd.payload[0]) | (UInt32(cmd.payload[1]) << 8) |
                         (UInt32(cmd.payload[2]) << 16) | (UInt32(cmd.payload[3]) << 24))
        let size = Int(UInt16(cmd.payload[4]) | (UInt16(cmd.payload[5]) << 8))
        let data = Array(cmd.payload.dropFirst(6).prefix(size))

        guard buf.write(offset: offset, data: data) else {
            return [OTACommand.otaWindowAck(status: .windowOutOfOrder, offset: 0)]
        }

        return [OTACommand.otaWindowAck(status: .success, offset: UInt32(buf.resumeOffset))]
    }

    private func handleValidate(_ cmd: OTACommand) -> [OTACommand] {
        guard let buf = imageBuffer else {
            return [OTACommand(opCode: .otaValidateResult, payload: [OTAStatusCode.invalidImage.rawValue])]
        }

        stateMachine.handle(.validateRequested)

        // Check expected CRC
        let expectedCRC: UInt32
        if cmd.payload.count >= 4 {
            expectedCRC = UInt32(cmd.payload[0]) | (UInt32(cmd.payload[1]) << 8) |
                          (UInt32(cmd.payload[2]) << 16) | (UInt32(cmd.payload[3]) << 24)
        } else {
            expectedCRC = 0
        }

        if buf.finalCRC32 == expectedCRC {
            stateMachine.handle(.validationPassed)
            return [OTACommand(opCode: .otaValidateResult, payload: [OTAStatusCode.success.rawValue])]
        } else {
            stateMachine.handle(.validationFailed)
            return [OTACommand(opCode: .otaValidateResult, payload: [OTAStatusCode.crcMismatch.rawValue])]
        }
    }

    private func handleApply(_ cmd: OTACommand) -> [OTACommand] {
        stateMachine.handle(.applyRequested)
        stateMachine.handle(.applyComplete)

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.stateMachine.handle(.rebootComplete)
            self?.onRebootNeeded?()
        }

        return [OTACommand(opCode: .otaApply, payload: [OTAStatusCode.success.rawValue])]
    }

    private func handleAbort(_ cmd: OTACommand) -> [OTACommand] {
        stateMachine.handle(.abortReceived)
        imageBuffer = nil
        return [OTACommand(opCode: .otaAbort, payload: [OTAStatusCode.success.rawValue])]
    }
}
