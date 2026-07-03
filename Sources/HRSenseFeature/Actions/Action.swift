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
    case computeStarted
    case hrvComputed(HRVMetrics)

    // MARK: Inference (M8 full impl)
    case inferenceStarted
    case inferenceCompleted(InferenceResult)
    case featuresExtracted(FeatureVector)  // M8: intermediate step — 14 features extracted

    // MARK: Sleep (M9 phase 5)
    case sleep(SleepAction)

    // MARK: OTA (M6 full impl)
    case otaStateChanged(OTAState)

    // MARK: Waveform (M5)
    case waveformSamplesReceived([WaveformSample])  // M5: new waveform samples pushed to ring buffer
    case waveformMetricsUpdated(WaveformMetrics)    // M5: throughput metrics snapshot
    case waveformTypeSelected(WaveformType)         // M5: user switches ECG/PPG

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
        case .computeStarted: return "computeStarted"
        case .hrvComputed: return "hrvComputed"
        case .inferenceStarted: return "inferenceStarted"
        case .inferenceCompleted: return "inferenceCompleted"
        case .featuresExtracted: return "featuresExtracted"
        case .sleep(let action): return "sleep(\(action))"
        case .otaStateChanged(let o): return "otaStateChanged(\(o.phase))"
        case .waveformSamplesReceived(let s): return "waveformSamplesReceived(\(s.count) samples)"
        case .waveformMetricsUpdated: return "waveformMetricsUpdated"
        case .waveformTypeSelected(let t): return "waveformTypeSelected(\(t))"
        case .errorOccurred(let e): return "errorOccurred(\(e))"
        case .dismissError: return "dismissError"
        case .clearSamples: return "clearSamples"
        }
    }
}

extension SleepAction: CustomStringConvertible {
    public var description: String {
        switch self {
        case .monitoringStarted:
            return "monitoringStarted"
        case .monitoringStopped:
            return "monitoringStopped"
        case .historyLoadRequested:
            return "historyLoadRequested"
        case .historyLoaded:
            return "historyLoaded"
        case .windowPrepared:
            return "windowPrepared"
        case .inferenceStarted:
            return "inferenceStarted"
        case .inferenceCompleted:
            return "inferenceCompleted"
        case .sessionUpdated:
            return "sessionUpdated"
        case .sessionPersisted:
            return "sessionPersisted"
        case .reset:
            return "reset"
        }
    }
}
