import Foundation

/// Use case: orchestrate the full OTA firmware update flow.
public struct OTAUpdateUseCase: Sendable {
    public let repository: any OTARepository

    public init(repository: any OTARepository) {
        self.repository = repository
    }

    /// Begin OTA update with the given firmware image.
    public func execute(image: OTAFirmwareImage) async throws {
        try await repository.startOTA(image: image)
    }

    /// Abort the update.
    public func abort() {
        repository.abortOTA()
    }
}
