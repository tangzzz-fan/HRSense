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
