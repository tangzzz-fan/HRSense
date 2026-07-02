import Foundation

/// Use case: connect to a discovered device.
public struct ConnectDeviceUseCase: Sendable {
    public let repository: any DeviceRepository

    public init(repository: any DeviceRepository) {
        self.repository = repository
    }

    /// Connect to the device with the given identifier.
    public func execute(deviceID: UUID) async throws {
        try await repository.connect(to: deviceID)
    }
}
