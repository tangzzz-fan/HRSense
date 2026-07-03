import SwiftUI
import HRSenseSimulatorKit
import HRSenseProtocol

/// ViewModel that bridges the shared simulator core into SwiftUI state.
@MainActor
@Observable
final class SimulatorViewModel {
    private let launchOptions: SimulatorLaunchOptions
    private let peripheral: SimulatedPeripheral

    private var generator: (any DataGeneratorProtocol)?
    private var scenarioEngine: ScenarioEngine?
    private var streamTimer: DispatchSourceTimer?
    private var streamStartTime: UInt64 = 0

    var connectionStatus: String = "Idle"
    var isAdvertising: Bool = false
    var currentHeartRate: Int = 70
    var sampleCount: Int = 0
    var isStreaming: Bool = false
    var deviceState: DeviceState = .advertising
    var selectedGeneratorMode: SimulatorLaunchOptions.GeneratorMode

    init(launchOptions: SimulatorLaunchOptions = SimulatorLaunchOptions()) {
        let config = SimulatorConfig()
        self.launchOptions = launchOptions
        self.peripheral = SimulatedPeripheral(config: config)
        self.selectedGeneratorMode = launchOptions.generatorMode
        self.generator = Self.makeGenerator(mode: launchOptions.generatorMode)

        peripheral.onStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.deviceState = state
                self?.updateStatus()
            }
        }
    }

    func handleLaunchOnAppear() {
        if let scenarioPath = launchOptions.scenarioPath {
            try? configureScenarioEngine(path: scenarioPath)
        }

        if launchOptions.autoStartAdvertising {
            startAdvertising()
        }

        if launchOptions.launchMode == .headless, launchOptions.autoStartStream {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.startStream()
            }
        }

        scenarioEngine?.start()
    }

    func startAdvertising() {
        peripheral.startAdvertising()
        isAdvertising = true
        connectionStatus = "Advertising..."
    }

    func stopAdvertising() {
        peripheral.stopAdvertising()
        isAdvertising = false
        connectionStatus = "Stopped"
    }

    func startStream() {
        guard streamTimer == nil, let generator else { return }

        isStreaming = true
        streamStartTime = DispatchTime.now().uptimeNanoseconds
        generator.start()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self, let generator = self.generator, self.isStreaming else { return }

            let elapsedMs = UInt32(
                (DispatchTime.now().uptimeNanoseconds - self.streamStartTime) / 1_000_000
            )
            let sample = generator.nextSample(timestampMs: elapsedMs)
            _ = self.peripheral.pushSample(sample)
            self.currentHeartRate = Int(sample.heartRate ?? 0)
            self.sampleCount += 1
        }
        timer.resume()
        streamTimer = timer

        let command = Command.startStream()
        _ = peripheral.commandProcessor.process(command: command, seq: 0)
        updateStatus()
    }

    func stopStream() {
        isStreaming = false
        streamTimer?.cancel()
        streamTimer = nil
        generator?.stop()

        let command = Command.stopStream()
        _ = peripheral.commandProcessor.process(command: command, seq: 0)
        updateStatus()
    }

    func selectGeneratorMode(_ mode: SimulatorLaunchOptions.GeneratorMode) {
        selectedGeneratorMode = mode
        generator = Self.makeGenerator(mode: mode)
    }

    func setManualHR(_ heartRate: Int) {
        currentHeartRate = heartRate
        if let manualGenerator = generator as? ManualHRGenerator {
            manualGenerator.currentHeartRate = heartRate
        }
    }

    private func configureScenarioEngine(path: String) throws {
        let scenario = try ScenarioParser.parse(url: URL(fileURLWithPath: path))
        let engine = ScenarioEngine(scenario: scenario)

        engine.onHeartRateChange = { [weak self] heartRate in
            Task { @MainActor in
                self?.setManualGeneratorIfNeeded()
                self?.setManualHR(heartRate)
            }
        }
        engine.onStreamStart = { [weak self] in
            Task { @MainActor in
                self?.startStream()
            }
        }
        engine.onStreamStop = { [weak self] in
            Task { @MainActor in
                self?.stopStream()
            }
        }
        engine.onDisconnect = { [weak self] in
            Task { @MainActor in
                self?.stopAdvertising()
            }
        }
        engine.onReconnect = { [weak self] in
            Task { @MainActor in
                self?.startAdvertising()
            }
        }
        engine.onFault = { [weak self] fault in
            self?.applyFault(fault)
        }

        scenarioEngine = engine
    }

    private func setManualGeneratorIfNeeded() {
        if generator is ManualHRGenerator {
            return
        }
        let manualGenerator = ManualHRGenerator(heartRate: currentHeartRate)
        if isStreaming {
            manualGenerator.start()
        }
        generator = manualGenerator
        selectedGeneratorMode = .manual
    }

    private func applyFault(_ fault: FaultConfig) {
        if let dropProbability = fault.dropProbability {
            peripheral.faultInjector.dropProbability = dropProbability
        }
        if let corruptCRCProbability = fault.corruptCRCProbability {
            peripheral.faultInjector.corruptCRCProbability = corruptCRCProbability
        }
        if let latencyMs = fault.latencyMs {
            peripheral.faultInjector.latencyMilliseconds = latencyMs..<(latencyMs + 1)
        }
    }

    private func updateStatus() {
        switch deviceState {
        case .advertising:
            connectionStatus = "Advertising"
        case .connected:
            connectionStatus = "Connected (subscribed)"
        case .handshakeDone:
            connectionStatus = "Handshake Done"
        case .streaming:
            connectionStatus = "Streaming (\(sampleCount) samples)"
        }
    }

    private static func makeGenerator(
        mode: SimulatorLaunchOptions.GeneratorMode
    ) -> any DataGeneratorProtocol {
        switch mode {
        case .resting:
            return RestingHRGenerator()
        case .exercise:
            return ExerciseHRGenerator()
        case .manual:
            return ManualHRGenerator()
        case .anomaly:
            return AnomalyHRGenerator()
        }
    }
}
