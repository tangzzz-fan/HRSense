import SwiftUI
import HRSenseFeature
import HRSenseData
import HRSenseProtocol
import TGReduxKit

public struct HRSenseAppContainerView: View {
    @State private var store: Store<AppState, Action>

    public init() {
        // Activate OSLog-backed logging
        HRSenseLogging.activateOSLog()

        let bleDataSource = BLECentralDataSource()
        let deviceRepo = DeviceRepositoryImpl(bleDataSource: bleDataSource)
        let computeRepo = ComputeRepositoryImpl()
        let inferenceRepo = InferenceRepositoryImpl()
        let waveformBuffer = WaveformRingBuffer()

        // Kick-start the MetricKit manager (crash/hang diagnostics)
        _ = MetricKitManager.shared

        // OTA repository — needs sendCommand/sendOTAChunk closures from BLE data source
        let otaRepo = OTARepositoryImpl(
            sendCommand: { [bleDataSource] opcode, payload in
                try await bleDataSource.sendCommand(opcode, payload: payload)
            },
            sendOTAChunk: { [bleDataSource] chunk in
                bleDataSource.sendOTAChunk(chunk)
            },
            imageData: { Data() }  // placeholder — real firmware loaded at OTA start time
        )

        let middleware: [Middleware<AppState, Action>] = [
            makeConnectionMiddleware(
                deviceRepo: deviceRepo,
                backoffProvider: { [bleDataSource] in bleDataSource.connectionStateMachine.nextBackoff() }
            ),
            makeBLEStreamMiddleware(deviceRepo: deviceRepo),
            makeComputeMiddleware(computeRepo: computeRepo),
            makeInferenceMiddleware(inferenceRepo: inferenceRepo),
            makeLoggingMiddleware(),
            makeWaveformMiddleware(waveformRingBuffer: waveformBuffer),
            makeOTAMiddleware(otaRepo: otaRepo),
        ]

        let store = Store(
            initialState: AppState(),
            reducer: AppReducer.reduce,
            middlewares: middleware
        )

        self.store = store
    }

    public var body: some View {
        RootView()
            .provideStore(store)
    }
}
