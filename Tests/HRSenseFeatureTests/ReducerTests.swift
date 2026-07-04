import XCTest
@testable import HRSenseFeature
@testable import HRSenseCore

final class ReducerTests: XCTestCase {

    // MARK: - Lifecycle / restore (M10)

    func test_didEnterBackground_setsLifecycleBackground() {
        var state = AppState()
        AppReducer.reduce(state: &state, action: .didEnterBackground)
        XCTAssertEqual(state.lifecycle, .background)
    }

    func test_willEnterForeground_setsLifecycleActive() {
        var state = AppState(lifecycle: .background)
        AppReducer.reduce(state: &state, action: .willEnterForeground)
        XCTAssertEqual(state.lifecycle, .active)
    }

    func test_willEnterForeground_doesNotOverrideRestoring() {
        var state = AppState(lifecycle: .restoring)
        AppReducer.reduce(state: &state, action: .willEnterForeground)
        XCTAssertEqual(state.lifecycle, .restoring)
    }

    func test_restoreInitiated_setsRestoringAndRestoredConnection() {
        var state = AppState(connection: .connected, error: .connectionLost)
        AppReducer.reduce(state: &state, action: .restoreInitiated(peripheralIDs: [UUID()]))
        XCTAssertEqual(state.lifecycle, .restoring)
        XCTAssertEqual(state.connection, .restored)
        XCTAssertNil(state.error)
    }

    func test_restoreConnectionRestored_setsRestoredConnected() {
        var state = AppState(lifecycle: .restoring, connection: .restored)
        AppReducer.reduce(state: &state, action: .restoreConnectionRestored(peripheralIDs: [UUID()]))
        XCTAssertEqual(state.lifecycle, .active)
        XCTAssertEqual(state.connection, .restoredConnected)
    }

    func test_restoreFailed_setsDisconnectedAndError() {
        var state = AppState(lifecycle: .restoring, connection: .restored)
        AppReducer.reduce(state: &state, action: .restoreFailed(reason: "device identity mismatch"))
        XCTAssertEqual(state.lifecycle, .active)
        XCTAssertEqual(state.connection, .disconnected)
        XCTAssertEqual(state.error, .handshakeFailed(reason: "device identity mismatch"))
    }

    // MARK: - Scanning

    func test_startScanning_setsState() {
        var state = AppState()
        AppReducer.reduce(state: &state, action: .startScanning)
        XCTAssertEqual(state.connection, .scanning)
    }

    func test_stopScanning_setsIdle() {
        var state = AppState(connection: .scanning)
        AppReducer.reduce(state: &state, action: .stopScanning)
        XCTAssertEqual(state.connection, .idle)
    }

    // MARK: - Connection

    func test_connect_setsConnecting() {
        var state = AppState()
        AppReducer.reduce(state: &state, action: .connect(deviceID: UUID()))
        XCTAssertEqual(state.connection, .connecting)
    }

    func test_disconnect_setsDisconnecting() {
        var state = AppState(connection: .connected)
        AppReducer.reduce(state: &state, action: .disconnect)
        XCTAssertEqual(state.connection, .disconnecting)
    }

    func test_connectionStateChanged_connected_clearsError() {
        var state = AppState(error: .connectionTimeout)
        AppReducer.reduce(state: &state, action: .connectionStateChanged(.connected))
        XCTAssertNil(state.error)
        XCTAssertEqual(state.connection, .connected)
    }

    func test_connectionStateChanged_restoredConnected_clearsError() {
        var state = AppState(error: .connectionTimeout)
        AppReducer.reduce(state: &state, action: .connectionStateChanged(.restoredConnected))
        XCTAssertNil(state.error)
        XCTAssertEqual(state.connection, .restoredConnected)
    }

    func test_connectionStateChanged_disconnected_clearsDevice() {
        let device = DeviceInfo(peripheralIdentifier: UUID(), name: "X", model: "M1",
                                firmwareVersion: "1", protocolVersion: 1, capabilities: 0)
        var state = AppState(device: device)
        AppReducer.reduce(state: &state, action: .connectionStateChanged(.disconnected))
        XCTAssertNil(state.device)
    }

    func test_deviceDiscovered_appendsDevice() {
        let device = DeviceInfo(peripheralIdentifier: UUID(), name: "Sim", model: "", firmwareVersion: "", protocolVersion: 0, capabilities: 0)
        var state = AppState()
        AppReducer.reduce(state: &state, action: .deviceDiscovered(device))
        XCTAssertEqual(state.discoveredDevices, [device])
    }

    func test_deviceDiscovered_deduplicatesByPeripheralIdentifier() {
        let id = UUID()
        let first = DeviceInfo(peripheralIdentifier: id, name: "Unknown", model: "", firmwareVersion: "", protocolVersion: 0, capabilities: 0)
        let updated = DeviceInfo(peripheralIdentifier: id, name: "HRSense Simulator", model: "", firmwareVersion: "", protocolVersion: 0, capabilities: 0)
        var state = AppState(discoveredDevices: [first])
        AppReducer.reduce(state: &state, action: .deviceDiscovered(updated))
        XCTAssertEqual(state.discoveredDevices, [updated])
    }

    // MARK: - Heart rate data

    func test_heartRateReceived_updatesLiveState() {
        let now = Date()
        let sample = HeartRateSample(timestamp: now, heartRate: 72, rrIntervals: [800])
        var state = AppState()

        AppReducer.reduce(state: &state, action: .heartRateReceived([sample]))

        XCTAssertEqual(state.live.currentHeartRate, 72)
        XCTAssertEqual(state.live.recentSamples.count, 1)
        XCTAssertEqual(state.live.recentSamples.first?.heartRate, 72)
    }

    func test_heartRateReceived_truncatesAt600() {
        let sample = HeartRateSample(timestamp: Date(), heartRate: 70)
        var state = AppState()
        // Add 650 samples — should truncate to last 600
        for _ in 0..<650 {
            AppReducer.reduce(state: &state, action: .heartRateReceived([sample]))
        }
        XCTAssertEqual(state.live.recentSamples.count, 600)
    }

    func test_clearSamples_resetsLive() {
        let sample = HeartRateSample(timestamp: Date(), heartRate: 80)
        var state = AppState()
        AppReducer.reduce(state: &state, action: .heartRateReceived([sample]))
        AppReducer.reduce(state: &state, action: .clearSamples)
        XCTAssertEqual(state.live.recentSamples.count, 0)
        XCTAssertNil(state.live.currentHeartRate)
    }

    // MARK: - Compute / Inference

    func test_computeStarted_setsMetricsRunning() {
        var state = AppState()
        AppReducer.reduce(state: &state, action: .computeStarted)
        XCTAssertEqual(state.metrics.computationStatus, .computing)
    }

    func test_hrvComputed_updatesMetrics() {
        var state = AppState()
        let metrics = HRVMetrics(sdnn: 50, rmssd: 30)
        AppReducer.reduce(state: &state, action: .hrvComputed(metrics))
        XCTAssertEqual(state.metrics.latestHRV, metrics)
        XCTAssertEqual(state.metrics.computationStatus, .ready)
    }

    func test_inferenceStarted_setsRunning() {
        var state = AppState()
        AppReducer.reduce(state: &state, action: .inferenceStarted)
        XCTAssertEqual(state.inference.status, .running)
    }

    func test_inferenceCompleted_updatesState() {
        var state = AppState()
        let result = InferenceResult(label: "Stress", probabilities: ["Stress": 0.85], modelVersion: "1.0")
        AppReducer.reduce(state: &state, action: .inferenceCompleted(result))
        XCTAssertEqual(state.inference.latestResult, result)
        XCTAssertEqual(state.inference.status, .completed)
    }

    func test_featuresExtracted_updatesLatestFeatures() {
        var state = AppState()
        let fv = FeatureVector(values: Array(repeating: 1, count: FeatureVector.dim))
        AppReducer.reduce(state: &state, action: .featuresExtracted(fv))
        XCTAssertEqual(state.inference.latestFeatures, fv)
    }

    // MARK: - Error

    func test_errorOccurred_setsError() {
        var state = AppState()
        AppReducer.reduce(state: &state, action: .errorOccurred(.decodeError))
        XCTAssertEqual(state.error, .decodeError)
    }

    func test_errorOccurred_connectionClass_forcesDisconnected() {
        var state = AppState(connection: .connected)
        AppReducer.reduce(state: &state, action: .errorOccurred(.connectionLost))
        XCTAssertEqual(state.connection, .disconnected)
    }

    func test_errorOccurred_nonConnectionClass_keepsConnected() {
        var state = AppState(connection: .connected)
        AppReducer.reduce(state: &state, action: .errorOccurred(.decodeError))
        XCTAssertEqual(state.connection, .connected)
    }

    func test_errorOccurred_computeFailed_resetsMetricsStatus() {
        var state = AppState(metrics: MetricsState(computationStatus: .computing))
        AppReducer.reduce(state: &state, action: .errorOccurred(.computeFailed))
        XCTAssertEqual(state.metrics.computationStatus, .idle)
    }

    func test_errorOccurred_inferenceFailed_resetsInferenceStatus() {
        var state = AppState(inference: InferenceState(status: .running))
        AppReducer.reduce(state: &state, action: .errorOccurred(.inferenceFailed))
        XCTAssertEqual(state.inference.status, .idle)
    }

    func test_dismissError_nilsError() {
        var state = AppState(error: .connectionTimeout)
        AppReducer.reduce(state: &state, action: .dismissError)
        XCTAssertNil(state.error)
    }

    // MARK: - OTA

    func test_otaStateChanged() {
        var state = AppState()
        let ota = OTAState(phase: .transferring(progress: 0.5), progress: 0.5)
        AppReducer.reduce(state: &state, action: .otaStateChanged(ota))
        XCTAssertEqual(state.ota.progress, 0.5)
    }

    // MARK: - Device info

    func test_deviceInfoUpdated_setsDevice() {
        let device = DeviceInfo(peripheralIdentifier: UUID(), name: "HRSense", model: "M2",
                                firmwareVersion: "2.0", protocolVersion: 1, capabilities: 0)
        var state = AppState()
        AppReducer.reduce(state: &state, action: .deviceInfoUpdated(device))
        XCTAssertEqual(state.device, device)
    }

    func test_deviceInfoUpdated_updatesDiscoveredDeviceEntry() {
        let id = UUID()
        let discovered = DeviceInfo(peripheralIdentifier: id, name: "HRSense Peripheral", model: "", firmwareVersion: "", protocolVersion: 0, capabilities: 0)
        let connected = DeviceInfo(peripheralIdentifier: id, name: "HRSense Peripheral", model: "M2", firmwareVersion: "2.0", protocolVersion: 1, capabilities: 0x3)
        var state = AppState(discoveredDevices: [discovered])
        AppReducer.reduce(state: &state, action: .deviceInfoUpdated(connected))
        XCTAssertEqual(state.discoveredDevices, [connected])
    }

    // MARK: - Waveform

    func test_waveformSamplesReceived_appendsSamples() {
        var state = AppState()
        let sample = WaveformSample(type: .ecg, sampleRateHz: 128, timestamp: Date(), value: 0.5)
        AppReducer.reduce(state: &state, action: .waveformSamplesReceived([sample]))
        XCTAssertEqual(state.waveform.ecgSamples.count, 1)
        XCTAssertTrue(state.waveform.isStreaming)
    }

    func test_waveformSamplesReceived_routesSamplesByType() {
        var state = AppState()
        let ecgSample = WaveformSample(type: .ecg, sampleRateHz: 128, timestamp: Date(), value: 0.5)
        let ppgSample = WaveformSample(type: .ppg, sampleRateHz: 64, timestamp: Date(), value: 0.25)

        AppReducer.reduce(state: &state, action: .waveformSamplesReceived([ecgSample, ppgSample]))

        XCTAssertEqual(state.waveform.ecgSamples, [ecgSample])
        XCTAssertEqual(state.waveform.ppgSamples, [ppgSample])
        XCTAssertTrue(state.waveform.isStreaming)
    }

    func test_waveformMetricsUpdated_updatesMetrics() {
        var state = AppState()
        var metrics = WaveformMetrics()
        metrics.mtu = 247
        AppReducer.reduce(state: &state, action: .waveformMetricsUpdated(metrics))
        XCTAssertEqual(state.waveform.metrics.mtu, 247)
    }

    func test_waveformTypeSelected_updatesType() {
        var state = AppState()
        AppReducer.reduce(state: &state, action: .waveformTypeSelected(.ppg))
        XCTAssertEqual(state.waveform.selectedType, .ppg)
    }

    // MARK: - Feature vector

    func test_featuresExtracted_keepsConnectionStateUnchanged() {
        var state = AppState()
        let fv = FeatureVector(values: Array(repeating: 0, count: 14))
        AppReducer.reduce(state: &state, action: .featuresExtracted(fv))
        XCTAssertEqual(state.connection, .idle)
        XCTAssertEqual(state.inference.latestFeatures, fv)
    }
}
