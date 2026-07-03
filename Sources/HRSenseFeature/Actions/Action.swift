import Foundation
import HRSenseCore

/// Single global action enum for the root reducer.
/// All state mutations flow through this enum — no side channels.
/// Extended incrementally in M8 (compute/inference) and M10 (lifecycle/restore).
public enum Action: Equatable, Sendable {
    // MARK: Scanning
    case startScanning
    case stopScanning

    // MARK: Devices
    case deviceDiscovered(DeviceInfo)
    case connect(deviceID: UUID)
    case disconnect

    // MARK: Connection
    case connectionStateChanged(ConnectionState)
    case deviceInfoUpdated(DeviceInfo)  // M3: device info after handshake

    // MARK: Data
    case heartRateReceived([HeartRateSample])
    case deviceEvent(DeviceEvent)

    // MARK: Compute (M8 full impl)
    case hrvComputed(HRVMetrics)

    // MARK: Inference (M8 full impl)
    case inferenceCompleted(InferenceResult)

    // MARK: OTA (M6 full impl)
    case otaStateChanged(OTAState)

    // MARK: Error
    case errorOccurred(AppError)
    case dismissError

    // MARK: Misc
    case clearSamples
}

// MARK: - CustomStringConvertible (for LoggingMiddleware)

extension Action: CustomStringConvertible {
    public var description: String {
        switch self {
        case .startScanning: return "startScanning"
        case .stopScanning: return "stopScanning"
        case .deviceDiscovered(let d): return "deviceDiscovered(\(d.name))"
        case .connect(let id): return "connect(\(id))"
        case .disconnect: return "disconnect"
        case .connectionStateChanged(let s): return "connectionStateChanged(\(s))"
        case .deviceInfoUpdated(let i): return "deviceInfoUpdated(\(i.name) fw=\(i.firmwareVersion))"
        case .heartRateReceived(let s): return "heartRateReceived(\(s.count) samples)"
        case .deviceEvent: return "deviceEvent"
        case .hrvComputed: return "hrvComputed"
        case .inferenceCompleted: return "inferenceCompleted"
        case .otaStateChanged(let o): return "otaStateChanged(\(o.phase))"
        case .errorOccurred(let e): return "errorOccurred(\(e))"
        case .dismissError: return "dismissError"
        case .clearSamples: return "clearSamples"
        }
    }
}
