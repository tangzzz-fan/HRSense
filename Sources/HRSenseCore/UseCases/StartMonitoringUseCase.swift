import Foundation

/// Use case: start monitoring by scanning for HRSense peripherals.
public struct StartMonitoringUseCase: Sendable {
    public let repository: any DeviceRepository

    public init(repository: any DeviceRepository) {
        self.repository = repository
    }

    /// Begin scanning for nearby HRSense devices.
    public func execute() async {
        await repository.startScanning()
    }
}
