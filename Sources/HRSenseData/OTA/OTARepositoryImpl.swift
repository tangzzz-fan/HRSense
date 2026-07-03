import Foundation
import HRSenseCore
import HRSenseProtocol

/// Implements OTARepository by orchestrating the App-side OTA BLE flow.
///
/// Two channels (doc 07 + doc 03 §3.1):
///   Control (0003) — OTA commands (START, VALIDATE, APPLY) via Write With Response
///   OTA Data (0005) — firmware image chunks via Write Without Response
///
/// Flow control: App sends window data on 0005, then waits for OTA_WINDOW_ACK
/// on the notify (0002) before sending the next window.
///
/// Resume: if the previous transfer was interrupted, App can resume from
/// `resumeOffset` if the imageCRC32 matches the previously transferred image.
public final class OTARepositoryImpl: OTARepository, @unchecked Sendable {
    private let sendOTAControl: (OTACommand) async throws -> Void
    private let sendOTAControlAndWait: (OTACommand, TimeInterval) async throws -> OTACommand
    private let waitForOTAWindowAck: (TimeInterval) async throws -> OTACommand
    private let sendOTAChunk: (Data) -> Void
    private let imageData: () -> Data
    private let metricsCollector: MetricsCollector?

    private var progressContinuation: AsyncStream<OTAProgress>.Continuation?
    private var shouldAbort = false
    private var windowSize: Int = 256
    private var maxWindow: Int = 1

    /// Last known image CRC32 from a previous (possibly interrupted) transfer.
    private var lastTransferredCRC32: UInt32?
    /// Last known resumeOffset reported by device.
    private var lastResumeOffset: Int = 0

    public let progressStream: AsyncStream<OTAProgress>

    public init(
        sendOTAControl: @escaping (OTACommand) async throws -> Void,
        sendOTAControlAndWait: @escaping (OTACommand, TimeInterval) async throws -> OTACommand,
        waitForOTAWindowAck: @escaping (TimeInterval) async throws -> OTACommand,
        sendOTAChunk: @escaping (Data) -> Void,
        imageData: @escaping () -> Data,
        metricsCollector: MetricsCollector? = nil
    ) {
        self.sendOTAControl = sendOTAControl
        self.sendOTAControlAndWait = sendOTAControlAndWait
        self.waitForOTAWindowAck = waitForOTAWindowAck
        self.sendOTAChunk = sendOTAChunk
        self.imageData = imageData
        self.metricsCollector = metricsCollector
        var cont: AsyncStream<OTAProgress>.Continuation!
        self.progressStream = AsyncStream { cont = $0 }
        self.progressContinuation = cont
    }

    /// Start an OTA firmware update.
    public func startOTA(image: OTAFirmwareImage) async throws {
        shouldAbort = false
        metricsCollector?.recordOTAAttempt()
        emit(.preparing, progress: 0)

        let fullImage = imageData()
        let computedCRC = CRC32.compute(fullImage)

        HRSenseLogging.info(.ota, "OTA_START imageSize=\(image.imageSize) crc32=0x\(String(computedCRC, radix: 16)) version=\(image.newVersion)")

        // Step 1: OTA_START (via Control 0003)
        let startCmd = OTACommand.otaStart(imageSize: UInt32(fullImage.count), imageCRC32: computedCRC, newVersion: image.newVersion)
        let startResp = try await sendOTAControlAndWait(startCmd, 5.0)

        guard startResp.opCode == .otaStartAck,
              let startAck = OTACommand.parseStartAckPayload(startResp.payload) else {
            HRSenseLogging.error(.ota, "OTA_START rejected: invalid response")
            emit(.failed(error: "OTA_START rejected"))
            throw AppError.otaFailed(phase: "start")
        }

        guard startAck.status == .success else {
            HRSenseLogging.error(.ota, "OTA_START rejected: status=\(startAck.status)")
            emit(.failed(error: "OTA_START status=\(startAck.status.rawValue)"))
            throw AppError.otaFailed(phase: "start")
        }

        if let resumeOffset = startAck.resumeOffset {
            let resumeOff = Int(resumeOffset)
            lastResumeOffset = resumeOff
            HRSenseLogging.info(.ota, "Device resumeOffset=\(resumeOff)")
        }
        if let maxChunkSize = startAck.maxChunkSize {
            windowSize = max(1, Int(maxChunkSize))
        }
        if let maxWindow = startAck.maxWindow {
            self.maxWindow = max(1, Int(maxWindow))
        }
        HRSenseLogging.info(.ota, "Negotiated OTA limits: maxChunkSize=\(windowSize) maxWindow=\(maxWindow)")

        // Device already validated the image identity by returning resumeOffset in OTA_START_ACK.
        if lastResumeOffset > 0, lastResumeOffset < fullImage.count {
            HRSenseLogging.info(.ota, "Resuming transfer from offset=\(lastResumeOffset)")
        } else {
            lastResumeOffset = 0
            HRSenseLogging.info(.ota, "Starting fresh transfer")
        }

        // Store CRC for potential future resume
        lastTransferredCRC32 = computedCRC

        emit(.transferring(progress: Double(lastResumeOffset) / Double(fullImage.count)),
              transferProgress: Double(lastResumeOffset) / Double(fullImage.count),
              bytesWritten: lastResumeOffset)

        // Step 2: Transfer windows (via OTA Data 0005)
        let totalSize = fullImage.count
        var offset = lastResumeOffset
        let maxRetries = 3

        while offset < totalSize, !shouldAbort {
            let windowEnd = min(offset + windowSize, totalSize)
            let chunk = Data(fullImage[offset..<windowEnd])

            // Send window begin command on Control (0003)
            let windowCmd = OTACommand.otaWindowBegin(offset: UInt32(offset), size: UInt16(chunk.count))
            try await sendOTAControl(windowCmd)

            HRSenseLogging.debug(.ota, "OTA_WINDOW_BEGIN offset=\(offset) size=\(chunk.count)")

            var windowOK = false
            for attempt in 1...maxRetries where !windowOK && !shouldAbort {
                // Send chunk via dedicated OTA Data channel (0005, Write Without Response)
                sendOTAChunk(encodeChunkPacket(offset: offset, chunk: chunk))

                HRSenseLogging.debug(.ota, "OTA chunk sent offset=\(offset) attempt=\(attempt)/\(maxRetries)")

                do {
                    let ack = try await waitForOTAWindowAck(2.0)
                    windowOK = isAcceptedWindowAck(
                        ack,
                        expectedOffset: windowEnd,
                        expectedWindowCRC32: CRC32.compute(chunk)
                    )
                    if !windowOK {
                        HRSenseLogging.error(.ota, "OTA_WINDOW_ACK rejected offset=\(offset) attempt=\(attempt)")
                    }
                } catch {
                    HRSenseLogging.error(.ota, "OTA_WINDOW_ACK timeout/error offset=\(offset) attempt=\(attempt): \(error.localizedDescription)")
                }
            }

            if !windowOK {
                HRSenseLogging.error(.ota, "Window transfer failed at offset=\(offset) after \(maxRetries) retries")
                emit(.failed(error: "Window transfer failed"))
                throw AppError.otaFailed(phase: "transfer")
            }

            offset = windowEnd
            let progress = Double(offset) / Double(totalSize)
            emit(.transferring(progress: progress),
                  transferProgress: progress,
                  bytesWritten: offset)
        }

        guard !shouldAbort else {
            HRSenseLogging.info(.ota, "OTA aborted by user")
            emit(.failed(error: "Aborted"))
            return
        }

        // Step 3: OTA_VALIDATE (via Control 0003)
        HRSenseLogging.info(.ota, "OTA_VALIDATE expectedCRC32=0x\(String(computedCRC, radix: 16))")
        emit(.validating)

        let validateCmd = OTACommand.otaValidate(expectedCRC32: computedCRC)
        let validateResp = try await sendOTAControlAndWait(validateCmd, 5.0)

        guard validateResp.opCode == .otaValidateResult,
              let vStatus = validateResp.payload.first,
              vStatus == OTAStatusCode.success.rawValue
        else {
            HRSenseLogging.error(.ota, "Validation failed — CRC mismatch or image corrupt")
            emit(.failed(error: "Validation failed"))
            throw AppError.otaFailed(phase: "validate")
        }

        // Step 4: OTA_APPLY (via Control 0003)
        HRSenseLogging.info(.ota, "OTA_APPLY — committing new firmware")
        emit(.applying)

        let applyCmd = OTACommand.otaApply()
        _ = try await sendOTAControlAndWait(applyCmd, 5.0)

        HRSenseLogging.info(.ota, "OTA complete — new version=\(image.newVersion)")
        metricsCollector?.recordOTASuccess()
        emit(.completed(newVersion: image.newVersion))
    }

    public func abortOTA() {
        shouldAbort = true
        HRSenseLogging.info(.ota, "OTA aborted")
        emit(.failed(error: "User cancelled"))
    }

    public func cancelOTA() {
        abortOTA()
    }

    // MARK: - Private helpers

    private func emit(_ phase: OTAPhase,
                      transferProgress: Double = 0,
                      bytesWritten: Int = 0,
                      progress: Double = 0) {
        let p = OTAProgress(
            phase: phase,
            transferProgress: transferProgress,
            bytesWritten: bytesWritten,
            totalBytes: 0
        )
        progressContinuation?.yield(p)
    }

    private func encodeChunkPacket(offset: Int, chunk: Data) -> Data {
        var packet = Data()
        var littleEndianOffset = UInt32(offset).littleEndian
        withUnsafeBytes(of: &littleEndianOffset) { packet.append(contentsOf: $0) }
        packet.append(chunk)
        return packet
    }

    private func isAcceptedWindowAck(_ ack: OTACommand, expectedOffset: Int, expectedWindowCRC32: UInt32) -> Bool {
        guard ack.opCode == .otaWindowAck,
              let parsed = OTACommand.parseWindowAckPayload(ack.payload) else {
            return false
        }
        let acknowledgedOffset = Int(parsed.recvOffset)
        HRSenseLogging.debug(
            .ota,
            "OTA_WINDOW_ACK status=\(parsed.status) recvOffset=\(acknowledgedOffset) windowCRC32=0x\(String(parsed.windowCRC32, radix: 16))"
        )
        return parsed.status == .success &&
            acknowledgedOffset == expectedOffset &&
            parsed.windowCRC32 == expectedWindowCRC32
    }
}
