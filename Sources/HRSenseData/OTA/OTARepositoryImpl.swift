import Foundation
import HRSenseCore
import HRSenseProtocol

/// Implements OTARepository by orchestrating the App-side OTA BLE flow.
public final class OTARepositoryImpl: OTARepository, @unchecked Sendable {
    private let sendCommand: (UInt8, Data) async throws -> Data
    private let imageData: () -> Data

    private var progressContinuation: AsyncStream<OTAProgress>.Continuation?
    private var shouldAbort = false
    private var windowSize: Int = 256

    public let progressStream: AsyncStream<OTAProgress>

    public init(
        sendCommand: @escaping (UInt8, Data) async throws -> Data,
        imageData: @escaping () -> Data
    ) {
        self.sendCommand = sendCommand
        self.imageData = imageData
        var cont: AsyncStream<OTAProgress>.Continuation!
        self.progressStream = AsyncStream { cont = $0 }
        self.progressContinuation = cont
    }

    public func startOTA(image: OTAFirmwareImage) async throws {
        shouldAbort = false
        let progress = OTAProgress(phase: .preparing, totalBytes: Int(image.imageSize))
        progressContinuation?.yield(progress)

        let fullImage = imageData()
        let computedCRC = CRC32.compute(fullImage)

        // Step 1: OTA_START
        let startCmd = OTACommand.otaStart(imageSize: UInt32(fullImage.count), imageCRC32: computedCRC, newVersion: image.newVersion)
        let startPayload = Data(OTACodec.encode(startCmd))
        let startResponseData = try await sendCommand(startCmd.opCode.rawValue, startPayload)

        guard let startResp = OTACodec.decode(body: [UInt8](startResponseData)),
              startResp.opCode == .otaStartAck,
              let statusByte = startResp.payload.first,
              statusByte == OTAStatusCode.success.rawValue
        else {
            progressContinuation?.yield(OTAProgress(phase: .failed(error: "OTA_START rejected")))
            throw AppError.otaFailed(phase: "start")
        }

        progressContinuation?.yield(OTAProgress(phase: .transferring(progress: 0.0), totalBytes: fullImage.count))

        // Step 2: Transfer windows
        let totalSize = fullImage.count
        var offset = 0
        let maxRetries = 3

        while offset < totalSize, !shouldAbort {
            let windowEnd = min(offset + windowSize, totalSize)
            let chunk = fullImage[offset..<windowEnd]

            let windowCmd = OTACommand.otaWindowBegin(offset: UInt32(offset), size: UInt16(chunk.count))
            var windowPayload = Data(OTACodec.encode(windowCmd))
            windowPayload.append(contentsOf: chunk)

            var retries = 0
            var windowOK = false
            while retries < maxRetries, !windowOK, !shouldAbort {
                do {
                    let respData = try await sendCommand(windowCmd.opCode.rawValue, windowPayload)
                    if let resp = OTACodec.decode(body: [UInt8](respData)),
                       resp.opCode == .otaWindowAck,
                       let status = resp.payload.first,
                       status == OTAStatusCode.success.rawValue {
                        windowOK = true
                    }
                } catch {}
                retries += 1
            }

            if !windowOK {
                progressContinuation?.yield(OTAProgress(phase: .failed(error: "Window transfer failed")))
                throw AppError.otaFailed(phase: "transfer")
            }

            offset = windowEnd
            let prog = Double(offset) / Double(totalSize)
            progressContinuation?.yield(OTAProgress(phase: .transferring(progress: prog), transferProgress: prog, bytesWritten: offset, totalBytes: totalSize))
        }

        guard !shouldAbort else {
            progressContinuation?.yield(OTAProgress(phase: .failed(error: "Aborted")))
            return
        }

        // Step 3: Validate
        progressContinuation?.yield(OTAProgress(phase: .validating))
        let validateCmd = OTACommand.otaValidate(expectedCRC32: computedCRC)
        let validatePayload = Data(OTACodec.encode(validateCmd))
        let validateResp = try await sendCommand(validateCmd.opCode.rawValue, validatePayload)

        guard let vr = OTACodec.decode(body: [UInt8](validateResp)),
              vr.opCode == .otaValidateResult,
              let vStatus = vr.payload.first,
              vStatus == OTAStatusCode.success.rawValue
        else {
            progressContinuation?.yield(OTAProgress(phase: .failed(error: "Validation failed")))
            throw AppError.otaFailed(phase: "validate")
        }

        // Step 4: Apply
        progressContinuation?.yield(OTAProgress(phase: .applying))
        let applyCmd = OTACommand.otaApply()
        let applyPayload = Data(OTACodec.encode(applyCmd))
        _ = try await sendCommand(applyCmd.opCode.rawValue, applyPayload)

        progressContinuation?.yield(OTAProgress(phase: .completed(newVersion: image.newVersion)))
    }

    public func abortOTA() {
        shouldAbort = true
        progressContinuation?.yield(OTAProgress(phase: .failed(error: "User cancelled")))
    }

    public func cancelOTA() {
        abortOTA()
    }
}
