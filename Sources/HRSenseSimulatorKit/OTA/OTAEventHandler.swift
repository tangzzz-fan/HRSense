import Foundation
import HRSenseProtocol

/// Handles incoming OTA command writes from the App.
///
/// Commands (0003) route here; image data (0005) flows to OTAImageBuffer directly.
/// The device responds via the notify (0002) channel with ACK frames.
public final class OTAEventHandler: @unchecked Sendable {

    private let stateMachine: OTAStateMachine
    private var imageBuffer: OTAImageBuffer?
    private let mtu: Int
    private var lastTransferredCRC32: UInt32?

    public var onRebootNeeded: (() -> Void)?

    public init(stateMachine: OTAStateMachine, mtu: Int = 185) {
        self.stateMachine = stateMachine
        self.mtu = mtu
    }

    /// Handle an OTA command received via Control/Write (0003).
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

    /// Receive raw OTA image data via OTA Data (0005).
    /// Data is accumulated into the image buffer.
    /// - Returns: true if data was accepted.
    @discardableResult
    public func receiveOTAChunk(offset: Int, data: [UInt8]) -> Bool {
        guard stateMachine.state == .transferring,
              let buf = imageBuffer,
              buf.write(offset: offset, data: data) else {
            HRSenseLogging.error(.ota, "OTA chunk rejected: offset=\(offset) state=\(stateMachine.state)")
            return false
        }
        HRSenseLogging.debug(.ota, "OTA chunk accepted: offset=\(offset) size=\(data.count) progress=\(String(format: "%.1f%%", buf.progress * 100))")
        return true
    }

    // MARK: - Private handlers

    private func handleStart(_ cmd: OTACommand) -> [OTACommand] {
        guard let (imageSize, imageCRC32, newVersion) = OTACodec.parseStartPayload(cmd.payload) else {
            HRSenseLogging.error(.ota, "OTA_START: invalid payload")
            return [OTACommand.otaStartAck(status: .invalidImage)]
        }

        HRSenseLogging.info(.ota, "OTA_START received: size=\(imageSize) crc=0x\(String(imageCRC32, radix: 16)) ver=\(newVersion)")

        // Precondition checks
        if let failure = OTAPreconditionChecker.check(
            batteryPercent: 85,
            currentVersion: stateMachine.currentVersion,
            targetVersion: newVersion
        ) {
            HRSenseLogging.error(.ota, "OTA_START precondition failed: \(failure)")
            return [OTACommand.otaStartAck(status: failure)]
        }

        // Check CRC match for resume
        let resumeOff: UInt32?
        if let lastCRC = lastTransferredCRC32, lastCRC == imageCRC32,
           let buf = imageBuffer, buf.finalCRC32 == imageCRC32 {
            let off = UInt32(buf.resumeOffset)
            resumeOff = off > 0 ? off : nil
            HRSenseLogging.info(.ota, "Resuming from offset=\(off) (CRC match)")
        } else {
            // New image or different CRC — fresh transfer
            imageBuffer = OTAImageBuffer(totalSize: Int(imageSize))
            resumeOff = nil
            HRSenseLogging.info(.ota, "Fresh transfer started")
        }

        lastTransferredCRC32 = imageCRC32
        stateMachine.handle(.startReceived(imageSize: imageSize, imageCRC32: imageCRC32, newVersion: newVersion))
        stateMachine.handle(.windowTransferComplete)

        return [OTACommand.otaStartAck(status: .success, resumeOffset: resumeOff)]
    }

    private func handleWindow(_ cmd: OTACommand) -> [OTACommand] {
        guard let buf = imageBuffer else {
            return [OTACommand.otaWindowAck(status: .invalidImage, offset: 0)]
        }

        guard cmd.payload.count >= 6 else {
            return [OTACommand.otaWindowAck(status: .invalidImage, offset: 0)]
        }
        let offset = Int(UInt32(cmd.payload[0]) | (UInt32(cmd.payload[1]) << 8) |
                         (UInt32(cmd.payload[2]) << 16) | (UInt32(cmd.payload[3]) << 24))
        let size = Int(UInt16(cmd.payload[4]) | (UInt16(cmd.payload[5]) << 8))
        let data = Array(cmd.payload.dropFirst(6).prefix(size))

        guard buf.write(offset: offset, data: data) else {
            HRSenseLogging.error(.ota, "OTA_WINDOW write failed: offset=\(offset)")
            return [OTACommand.otaWindowAck(status: .windowOutOfOrder, offset: 0)]
        }

        HRSenseLogging.debug(.ota, "OTA_WINDOW written: offset=\(offset) bytes=\(data.count) progress=\(String(format: "%.1f%%", buf.progress * 100))")
        return [OTACommand.otaWindowAck(status: .success, offset: UInt32(buf.resumeOffset))]
    }

    private func handleValidate(_ cmd: OTACommand) -> [OTACommand] {
        guard let buf = imageBuffer else {
            return [OTACommand(opCode: .otaValidateResult, payload: [OTAStatusCode.invalidImage.rawValue])]
        }

        stateMachine.handle(.validateRequested)

        let expectedCRC: UInt32
        if cmd.payload.count >= 4 {
            expectedCRC = UInt32(cmd.payload[0]) | (UInt32(cmd.payload[1]) << 8) |
                          (UInt32(cmd.payload[2]) << 16) | (UInt32(cmd.payload[3]) << 24)
        } else {
            expectedCRC = 0
        }

        let actualCRC = buf.finalCRC32
        HRSenseLogging.info(.ota, "OTA_VALIDATE: expected=0x\(String(expectedCRC, radix: 16)) actual=0x\(String(actualCRC, radix: 16))")

        if actualCRC == expectedCRC {
            stateMachine.handle(.validationPassed)
            HRSenseLogging.info(.ota, "OTA_VALIDATE: passed")
            return [OTACommand(opCode: .otaValidateResult, payload: [OTAStatusCode.success.rawValue])]
        } else {
            stateMachine.handle(.validationFailed)
            HRSenseLogging.error(.ota, "OTA_VALIDATE: failed — CRC mismatch")
            return [OTACommand(opCode: .otaValidateResult, payload: [OTAStatusCode.crcMismatch.rawValue])]
        }
    }

    private func handleApply(_ cmd: OTACommand) -> [OTACommand] {
        HRSenseLogging.info(.ota, "OTA_APPLY: committing firmware")
        stateMachine.handle(.applyRequested)
        stateMachine.handle(.applyComplete)

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.stateMachine.handle(.rebootComplete)
            HRSenseLogging.info(.ota, "OTA reboot complete — new version=\(self?.stateMachine.currentVersion ?? "?")")
            self?.onRebootNeeded?()
        }

        return [OTACommand(opCode: .otaApply, payload: [OTAStatusCode.success.rawValue])]
    }

    private func handleAbort(_ cmd: OTACommand) -> [OTACommand] {
        HRSenseLogging.info(.ota, "OTA_ABORT received")
        stateMachine.handle(.abortReceived)
        imageBuffer = nil
        return [OTACommand(opCode: .otaAbort, payload: [OTAStatusCode.success.rawValue])]
    }
}
