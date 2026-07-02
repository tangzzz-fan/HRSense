import Foundation

/// Configuration for the simulated device.
public struct SimulatorConfig: Equatable, Sendable {
    /// Device model string (reported in HELLO_ACK).
    public var model: String
    /// Firmware version string.
    public var firmwareVersion: String
    /// Protocol version (v1 = 0x01).
    public var protocolVersion: UInt8
    /// Capability bitmap.
    public var capabilities: UInt32
    /// Local name advertised via BLE.
    public var advertisingLocalName: String
    /// Maximum Transmission Unit (default 185, typical iOS BLE).
    public var mtu: Int

    public init(
        model: String = "HRSense-Sim",
        firmwareVersion: String = "1.0.0-sim",
        protocolVersion: UInt8 = 0x01,
        capabilities: UInt32 = 0x0000_002F,  // HR + RR + battery + contact + configurable
        advertisingLocalName: String = "HRSense-Sim",
        mtu: Int = 185
    ) {
        self.model = model
        self.firmwareVersion = firmwareVersion
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.advertisingLocalName = advertisingLocalName
        self.mtu = mtu
    }
}
