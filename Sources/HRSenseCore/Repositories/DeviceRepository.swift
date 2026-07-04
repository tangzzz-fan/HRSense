import Foundation

/// Repository protocol for BLE device communication.
/// Upper layers (Feature) depend on this protocol, not on CoreBluetooth directly.
public protocol DeviceRepository: AnyObject, Sendable {
    /// Current connection state.
    var connectionState: ConnectionState { get }

    /// Async stream of connection state changes.
    var connectionStateStream: AsyncStream<ConnectionState> { get }

    /// Async stream of discovered devices during scanning.
    var discoveredDevicesStream: AsyncStream<DeviceInfo> { get }

    /// Async stream of heart rate samples received from the device.
    var heartRateStream: AsyncStream<HeartRateSample> { get }

    /// Async stream of device info updates (emitted after successful handshake).
    var deviceInfoStream: AsyncStream<DeviceInfo> { get }

    /// Async stream of restored peripheral identifiers reported by CoreBluetooth
    /// state preservation/restoration.
    var restoredPeripheralIDsStream: AsyncStream<[UUID]> { get }

    /// Start scanning for HRSense peripherals.
    func startScanning() async

    /// Stop scanning.
    func stopScanning()

    /// Connect to a discovered device by its peripheral identifier.
    /// This triggers the full connection+handshake flow:
    ///   BLE connect → discover services → subscribe notify → HELLO → HELLO_ACK → START_STREAM
    /// After successful handshake, a DeviceInfo is yielded to `deviceInfoStream` and
    /// connection state transitions to `.connected`.
    func connect(to deviceID: UUID) async throws

    /// Disconnect from the currently connected device.
    func disconnect()

    /// Send a raw command and await the response.
    /// - Returns: response data fragments.
    func sendCommand(_ opcode: UInt8, payload: Data) async throws -> Data

    /// Perform the handshake sequence after BLE connection is established.
    /// Sends HELLO → awaits HELLO_ACK → sends START_STREAM.
    /// - Returns: the parsed DeviceInfo from the HELLO_ACK response.
    func performHandshake() async throws -> DeviceInfo

    /// Resume a CoreBluetooth-restored BLE session by rediscovering services,
    /// validating the restored peripheral identity, and re-running handshake
    /// if needed.
    func restoreConnection(context: RestorationContext?) async throws -> DeviceInfo
}
