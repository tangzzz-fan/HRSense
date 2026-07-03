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
    public final class RuntimeServices {
        let retentionScheduler: BackgroundTaskScheduler

        init(retentionScheduler: BackgroundTaskScheduler) {
            self.retentionScheduler = retentionScheduler
        }
    }

    public struct AppShell {
        public let store: Store<AppState, Action>
        public let diagnosticPanelModel: DiagnosticPanelModel
        public let runtimeServices: RuntimeServices?
    }

    @MainActor
    public static func makeAppShell() -> AppShell {
        HRSenseLogging.activateOSLog()

        let waveformBuffer = WaveformRingBuffer()
        let bleDataSource = BLECentralDataSource(waveformRingBuffer: waveformBuffer)
        let deviceRepo = DeviceRepositoryImpl(bleDataSource: bleDataSource)
        let computeRepo = ComputeRepositoryImpl()
        let inferenceRepo = InferenceRepositoryImpl()
        let sleepInferenceRepo = SleepInferenceRepositoryImpl()
        let persistenceStore = makePersistenceStore()

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
            imageData: { Data() },  // Firmware bytes are injected later during real OTA integration.
            metricsCollector: deviceRepo.metricsCollector
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
            makeSleepMiddleware(
                sleepInferenceRepository: sleepInferenceRepo,
                persistenceStore: persistenceStore
            ),
            makeLoggingMiddleware(),
            makeWaveformMiddleware(waveformRingBuffer: waveformBuffer),
            makeOTAMiddleware(otaRepo: otaRepo),
        ]

        let store = Store(
            initialState: AppState(),
            reducer: AppReducer.reduce,
            middlewares: middleware
        )

        let diagnosticPanelModel = DiagnosticPanelModel(
            dependencies: DiagnosticPanelDependencies(
                kpiSnapshotProvider: { deviceRepo.metricsCollector.kpiSnapshot() },
                logEntriesProvider: { LoggingRegistry.shared.ringBuffer.snapshot() },
                stateTransitionsProvider: { StateTransitionRecorder.shared.recentTransitions },
                metricDiagnosticsProvider: { MetricKitManager.shared.recentDiagnostics },
                metricsSnapshotProvider: {
                    let snapshot = deviceRepo.metricsCollector.snapshot()
                    return MetricsSnapshotJSON(
                        totalSamplesReceived: snapshot.totalSamplesReceived,
                        samplesLost: snapshot.samplesLost,
                        reconnectCount: snapshot.reconnectCount,
                        bytesReceived: snapshot.bytesReceived
                    )
                },
                latestFeatureVectorProvider: {
                    guard let latestFeatures = store.state.inference.latestFeatures else { return nil }
                    return FeatureVectorSnapshotJSON(
                        contractVersion: latestFeatures.contractVersion,
                        values: latestFeatures.values
                    )
                },
                latestInferenceProvider: {
                    guard let latestResult = store.state.inference.latestResult else { return nil }
                    return InferenceSnapshotJSON(
                        label: latestResult.label,
                        probabilities: latestResult.probabilities,
                        inferenceTimeMs: latestResult.inferenceTimeMs,
                        modelVersion: latestResult.modelVersion
                    )
                },
                systemInfoProvider: { SystemInfo.current }
            )
        )

        return AppShell(
            store: store,
            diagnosticPanelModel: diagnosticPanelModel,
            runtimeServices: makeRuntimeServices(persistenceStore: persistenceStore)
        )
    }

    @MainActor
    public static func makeStore() -> Store<AppState, Action> {
        makeAppShell().store
    }

    private static func makeRuntimeServices(persistenceStore: SwiftDataStore?) -> RuntimeServices? {
        guard let persistenceStore else { return nil }
        do {
            let waveformFileStore = try WaveformFileStore()
            let cleanupTask = RetentionCleanupTask(
                store: persistenceStore,
                waveformFileStore: waveformFileStore
            )
            let scheduler = BackgroundTaskScheduler(cleanupTask: cleanupTask)
            scheduler.activate()
            return RuntimeServices(retentionScheduler: scheduler)
        } catch {
            HRSenseLogging.error(.perf, "Failed to bootstrap retention services: \(error)")
            return nil
        }
    }

    private static func makePersistenceStore() -> SwiftDataStore? {
        do {
            let modelContainer = try SwiftDataStore.makeModelContainer()
            return SwiftDataStore(modelContainer: modelContainer)
        } catch {
            HRSenseLogging.error(.perf, "Failed to bootstrap persistence store: \(error)")
            return nil
        }
    }
}
