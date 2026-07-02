import Foundation

/// Repository protocol for OTA firmware update operations.
public protocol OTARepository: AnyObject, Sendable {
    /// Current OTA progress stream.
    var progressStream: AsyncStream<OTAProgress> { get }

    /// Start an OTA update with the given firmware image.
    func startOTA(image: OTAFirmwareImage) async throws

    /// Abort the current OTA operation.
    func abortOTA()

    /// Cancel and reset OTA state.
    func cancelOTA()
}
