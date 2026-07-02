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
