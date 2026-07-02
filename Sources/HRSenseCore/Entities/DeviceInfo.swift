import Foundation

/// Domain entity: device information obtained during handshake.
public struct DeviceInfo: Equatable, Sendable {
    /// UUID identifier of the BLE peripheral.
    public let peripheralIdentifier: UUID
    /// Local name from advertisement or GATT.
    public let name: String
    /// Device model string.
    public let model: String
    /// Firmware version string.
    public let firmwareVersion: String
    /// Negotiated protocol version.
    public let protocolVersion: UInt8
    /// Device capability bitmap.
    public let capabilities: UInt32

    public init(
        peripheralIdentifier: UUID,
        name: String,
        model: String,
        firmwareVersion: String,
        protocolVersion: UInt8,
        capabilities: UInt32
    ) {
        self.peripheralIdentifier = peripheralIdentifier
        self.name = name
        self.model = model
        self.firmwareVersion = firmwareVersion
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
    }
}
