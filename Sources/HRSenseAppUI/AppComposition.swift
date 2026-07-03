import Foundation
import HRSenseData
import HRSenseFeature
import HRSenseProtocol
import TGReduxKit

/// Composition root for the iOS app shell.
///
/// Owns dependency wiring between Data and Feature layers so that Views stay
/// focused on presentation instead of constructing repositories and middleware.
public enum AppComposition {
    @MainActor
    public static func makeStore() -> Store<AppState, Action> {
        HRSenseLogging.activateOSLog()

        let waveformBuffer = WaveformRingBuffer()
        let bleDataSource = BLECentralDataSource(waveformRingBuffer: waveformBuffer)
        let deviceRepo = DeviceRepositoryImpl(bleDataSource: bleDataSource)
        let computeRepo = ComputeRepositoryImpl()
        let inferenceRepo = InferenceRepositoryImpl()

        // Start MetricKit subscription early so crash/hang diagnostics are captured.
        _ = MetricKitManager.shared

        let otaRepo = OTARepositoryImpl(
            sendOTAControl: { [bleDataSource] command in
                try await bleDataSource.sendOTAControl(command)
            },
            sendOTAControlAndWait: { [bleDataSource] command, timeout in
                try await bleDataSource.sendOTAControlAndWait(command, timeout: timeout)
            },
            waitForOTAWindowAck: { [bleDataSource] timeout in
                try await bleDataSource.waitForOTAWindowAck(timeout: timeout)
            },
            sendOTAChunk: { [bleDataSource] chunk in
                bleDataSource.sendOTAChunk(chunk)
            },
            imageData: { Data() }  // Firmware bytes are injected later during real OTA integration.
        )

        let middleware: [Middleware<AppState, Action>] = [
            makeConnectionMiddleware(
                deviceRepo: deviceRepo,
                backoffProvider: { [bleDataSource] in
                    bleDataSource.connectionStateMachine.nextBackoff()
                }
            ),
            makeBLEStreamMiddleware(deviceRepo: deviceRepo),
            makeComputeMiddleware(computeRepo: computeRepo),
            makeInferenceMiddleware(inferenceRepo: inferenceRepo),
            makeLoggingMiddleware(),
            makeWaveformMiddleware(waveformRingBuffer: waveformBuffer),
            makeOTAMiddleware(otaRepo: otaRepo),
        ]

        return Store(
            initialState: AppState(),
            reducer: AppReducer.reduce,
            middlewares: middleware
        )
    }
}
