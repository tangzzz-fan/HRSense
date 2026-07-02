import Foundation
import CoreBluetooth

/// Utility for checking Bluetooth permissions on macOS.
public enum BluetoothPermission: Sendable {
    /// Current authorization status.
    public static var status: CBManagerAuthorization {
        CBPeripheralManager.authorization
    }

    /// Whether Bluetooth is authorized.
    public static var isAuthorized: Bool {
        switch CBPeripheralManager.authorization {
        case .allowedAlways, .restricted:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    /// Whether Bluetooth is powered on.
    public static var isPoweredOn: Bool {
        // Best-effort: a CBPeripheralManager instance would report state.
        // At this static level we can only check authorization.
        return isAuthorized
    }
}
