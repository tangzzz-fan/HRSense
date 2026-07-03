import Foundation

/// Canonical error enum for the HRSense app.
/// Every error that reaches the UI must be expressed as an AppError case.
/// Defined in doc 04-app-clean-redux §8.5.
public enum AppError: Error, Equatable, Sendable {
    case bluetoothUnauthorized
    case bluetoothPoweredOff
    case deviceNotFound
    case connectionTimeout
    case connectionLost
    case handshakeFailed(reason: String)
    case commandTimeout(opcode: UInt8)
    case protocolError(detail: String)
    case decodeError
    case computeFailed
    case inferenceFailed
    case modelLoadFailed
    case otaFailed(phase: String)
}

extension AppError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .bluetoothUnauthorized:
            return "Bluetooth access is not authorized."
        case .bluetoothPoweredOff:
            return "Bluetooth is powered off."
        case .deviceNotFound:
            return "The selected peripheral is no longer available."
        case .connectionTimeout:
            return "The BLE connection attempt timed out."
        case .connectionLost:
            return "The BLE connection was lost."
        case .handshakeFailed(let reason):
            return "Handshake failed: \(reason)"
        case .commandTimeout(let opcode):
            return "Command 0x\(String(opcode, radix: 16)) timed out while waiting for a response."
        case .protocolError(let detail):
            return "Protocol error: \(detail)"
        case .decodeError:
            return "Failed to decode BLE payload."
        case .computeFailed:
            return "Feature computation failed."
        case .inferenceFailed:
            return "CoreML inference failed."
        case .modelLoadFailed:
            return "The CoreML model could not be loaded."
        case .otaFailed(let phase):
            return "OTA failed during \(phase)."
        }
    }
}
