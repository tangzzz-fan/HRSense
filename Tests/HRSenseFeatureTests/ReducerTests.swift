import XCTest
@testable import HRSenseFeature
@testable import HRSenseCore

final class ReducerTests: XCTestCase {

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

    func test_connectionStateChanged_disconnected_clearsDevice() {
        let device = DeviceInfo(peripheralIdentifier: UUID(), name: "X", model: "M1",
                                firmwareVersion: "1", protocolVersion: 1, capabilities: 0)
        var state = AppState(device: device)
        AppReducer.reduce(state: &state, action: .connectionStateChanged(.disconnected))
        XCTAssertNil(state.device)
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

    func test_hrvComputed_updatesMetrics() {
        var state = AppState()
        let metrics = HRVMetrics(sdnn: 50, rmssd: 30)
        AppReducer.reduce(state: &state, action: .hrvComputed(metrics))
        XCTAssertEqual(state.metrics.latestHRV, metrics)
        XCTAssertEqual(state.metrics.computationStatus, .ready)
    }

    func test_inferenceCompleted_updatesState() {
        var state = AppState()
        let result = InferenceResult(label: "Stress", probabilities: ["Stress": 0.85], modelVersion: "1.0")
        AppReducer.reduce(state: &state, action: .inferenceCompleted(result))
        XCTAssertEqual(state.inference.latestResult, result)
        XCTAssertEqual(state.inference.status, .completed)
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
}
