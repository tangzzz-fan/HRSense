import Foundation
import HRSenseCore

/// Root application state — all state is Equatable for deterministic testing.
public struct AppState: Equatable, Sendable {
    /// BLE connection status.
    public var connection: ConnectionState
    /// Info about the currently connected device.
    public var device: DeviceInfo?
    /// Live sensor data.
    public var live: LiveState
    /// Performance metrics.
    public var metrics: MetricsState
    /// ML inference state.
    public var inference: InferenceState
    /// OTA firmware update state.
    public var ota: OTAState
    /// Current error (shown in UI banner).
    public var error: AppError?

    public init(
        connection: ConnectionState = .idle,
        device: DeviceInfo? = nil,
        live: LiveState = LiveState(),
        metrics: MetricsState = MetricsState(),
        inference: InferenceState = InferenceState(),
        ota: OTAState = OTAState(),
        error: AppError? = nil
    ) {
        self.connection = connection
        self.device = device
        self.live = live
        self.metrics = metrics
        self.inference = inference
        self.ota = ota
        self.error = error
    }
}
