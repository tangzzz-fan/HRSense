import Foundation

/// Repository protocol for BLE device communication.
/// Upper layers (Feature) depend on this protocol, not on CoreBluetooth directly.
public protocol DeviceRepository: AnyObject, Sendable {
    /// Current connection state stream.
    var connectionState: ConnectionState { get }

    /// Async stream of connection state changes.
    var connectionStateStream: AsyncStream<ConnectionState> { get }

    /// Async stream of discovered devices during scanning.
    var discoveredDevicesStream: AsyncStream<DeviceInfo> { get }

    /// Async stream of heart rate samples received from the device.
    var heartRateStream: AsyncStream<HeartRateSample> { get }

    /// Start scanning for HRSense peripherals.
    func startScanning() async

    /// Stop scanning.
    func stopScanning()

    /// Connect to a discovered device by its peripheral identifier.
    func connect(to deviceID: UUID) async throws

    /// Disconnect from the currently connected device.
    func disconnect()

    /// Send a raw command and await the response.
    /// - Returns: response data fragments.
    func sendCommand(_ opcode: UInt8, payload: Data) async throws -> Data
}
