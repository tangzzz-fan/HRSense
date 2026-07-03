import Foundation
import HRSenseCore

/// Pure-function reducer: (inout AppState, Action) -> Void.
///
/// All state mutations are deterministic. No side effects — those live in Middleware.
///
/// Key rules:
///   - heartRateReceived: append to recentSamples, suffix(600) truncation
///   - connectionStateChanged: update connection; .connected clears error
///   - computeStarted/hrvComputed: drive metrics.computationStatus
///   - featuresExtracted/inferenceStarted/inferenceCompleted: drive explicit inference pipeline state
///   - errorOccurred: set error; connection-class errors set connection = .disconnected
///   - dismissError: nil out error
public enum AppReducer {
    public static func reduce(state: inout AppState, action: Action) {
        switch action {
        case .startScanning:
            state.connection = .scanning
            state.discoveredDevices = []

        case .stopScanning:
            state.connection = .idle

        case .deviceDiscovered(let device):
            if let index = state.discoveredDevices.firstIndex(where: { $0.peripheralIdentifier == device.peripheralIdentifier }) {
                state.discoveredDevices[index] = device
            } else {
                state.discoveredDevices.append(device)
            }

        case .connect:
            state.connection = .connecting
            state.error = nil

        case .disconnect:
            state.connection = .disconnecting

        case .connectionStateChanged(let newState):
            state.connection = newState
            if newState == .connected {
                state.error = nil
            }
            if newState == .disconnected {
                state.device = nil
            }

        case .deviceInfoUpdated(let info):
            state.device = info
            if let index = state.discoveredDevices.firstIndex(where: { $0.peripheralIdentifier == info.peripheralIdentifier }) {
                state.discoveredDevices[index] = info
            } else {
                state.discoveredDevices.append(info)
            }

        case .heartRateReceived(let samples):
            state.live.recentSamples.append(contentsOf: samples)
            // Keep bounded to 600 entries (~10 min @ 1 Hz)
            if state.live.recentSamples.count > 600 {
                state.live.recentSamples = Array(state.live.recentSamples.suffix(600))
            }
            if let latest = samples.last {
                state.live.currentHeartRate = latest.heartRate
                state.live.lastUpdated = Date()
            }

        case .deviceEvent:
            break // Handled by middleware for logging; state unchanged

        case .computeStarted:
            state.metrics.computationStatus = .computing

        case .hrvComputed(let metrics):
            state.metrics.latestHRV = metrics
            state.metrics.computationStatus = .ready

        case .inferenceStarted:
            state.inference.status = .running

        case .inferenceCompleted(let result):
            state.inference.latestResult = result
            state.inference.status = .completed

        case .featuresExtracted(let features):
            state.inference.latestFeatures = features

        case .sleep(let sleepAction):
            reduceSleep(state: &state, action: sleepAction)

        case .otaStateChanged(let ota):
            state.ota = ota

        case .waveformSamplesReceived(let samples):
            state.waveform.ecgSamples.append(contentsOf: samples)
            // Keep bounded to last 7680 samples (~60s @ 128 Hz)
            let maxSamples = 7680
            if state.waveform.ecgSamples.count > maxSamples {
                state.waveform.ecgSamples = Array(state.waveform.ecgSamples.suffix(maxSamples))
            }
            state.waveform.isStreaming = true

        case .waveformMetricsUpdated(let metrics):
            state.waveform.metrics = metrics

        case .waveformTypeSelected(let type):
            state.waveform.selectedType = type

        case .errorOccurred(let error):
            state.error = error
            switch error {
            case .computeFailed:
                state.metrics.computationStatus = .idle
            case .inferenceFailed:
                state.inference.status = .idle
            case .sleepInferenceFailed:
                state.sleep.status = .idle
            default:
                break
            }
            // Connection-class errors force disconnection
            switch error {
            case .connectionTimeout, .connectionLost, .bluetoothPoweredOff:
                state.connection = .disconnected
            default:
                break
            }

        case .dismissError:
            state.error = nil

        case .clearSamples:
            state.live = LiveState()
        }
    }
}

private extension AppReducer {
    static func reduceSleep(state: inout AppState, action: SleepAction) {
        switch action {
        case .monitoringStarted(let startAt):
            state.sleep.isMonitoring = true
            state.sleep.monitoringStartedAt = startAt
            state.sleep.status = .monitoring
            if state.sleep.currentSession == nil {
                state.sleep.stageHistory = []
            }

        case .monitoringStopped:
            state.sleep.isMonitoring = false
            state.sleep.status = .idle

        case .historyLoadRequested:
            break

        case .historyLoaded(let sessions):
            state.sleep.recentSessions = sessions

        case .windowPrepared(let input):
            state.sleep.latestWindowInput = input
            state.sleep.status = .monitoring

        case .inferenceStarted:
            state.sleep.status = .inferring

        case .inferenceCompleted(let prediction):
            state.sleep.lastInference = prediction
            state.sleep.status = .ready

        case .sessionUpdated(let session):
            state.sleep.currentSession = session
            state.sleep.stageHistory = session.stages

        case .sessionPersisted(let sessionID):
            state.sleep.lastPersistedSessionID = sessionID

        case .reset:
            state.sleep = SleepState()
        }
    }
}
