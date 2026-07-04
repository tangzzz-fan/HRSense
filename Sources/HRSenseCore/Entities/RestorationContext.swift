import Foundation

/// Persisted context used to decide whether a BLE restoration attempt is eligible.
///
/// The app only enters the user-visible restore flow when it has both:
/// 1. A CoreBluetooth-restored peripheral from the system.
/// 2. A previously persisted restoration context from a successful handshake.
///
/// This prevents first launch from showing a misleading "restoring" state.
public struct RestorationContext: Equatable, Codable, Sendable {
    /// The BLE peripheral identity that completed a successful handshake.
    public let peripheralIdentifier: UUID

    /// Last known device model from the application handshake.
    public let model: String

    /// Last negotiated protocol version.
    public let protocolVersion: UInt8

    /// Last negotiated capability bitmap.
    public let capabilities: UInt32

    /// Timestamp of the last successful session confirmation.
    public let lastSuccessfulHandshakeAt: Date

    public init(
        peripheralIdentifier: UUID,
        model: String,
        protocolVersion: UInt8,
        capabilities: UInt32,
        lastSuccessfulHandshakeAt: Date
    ) {
        self.peripheralIdentifier = peripheralIdentifier
        self.model = model
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.lastSuccessfulHandshakeAt = lastSuccessfulHandshakeAt
    }
}
