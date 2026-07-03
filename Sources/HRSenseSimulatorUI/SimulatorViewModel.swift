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
    private var waveformStreamers: [WaveformStreamer] = []
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
        peripheral.commandProcessor.setStreamCallbacks(
            onStart: { [weak self] sampleKinds in
                Task { @MainActor in
                    self?.startStreaming(sampleKinds: sampleKinds)
                }
            },
            onStop: { [weak self] in
                Task { @MainActor in
                    self?.stopStreaming()
                }
            }
        )
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
        let command = Command.startStream(
            sampleKinds: [DataKind.heartRate.rawValue, DataKind.waveform.rawValue]
        )
        _ = peripheral.commandProcessor.process(command: command, seq: 0)
    }

    func stopStream() {
        let command = Command.stopStream()
        _ = peripheral.commandProcessor.process(command: command, seq: 0)
    }

    func selectGeneratorMode(_ mode: SimulatorLaunchOptions.GeneratorMode) {
        replaceGenerator(with: Self.makeGenerator(mode: mode), mode: mode)
    }

    func setManualHR(_ heartRate: Int) {
        currentHeartRate = heartRate
        if let manualGenerator = generator as? ManualHRGenerator {
            manualGenerator.currentHeartRate = heartRate
            restartWaveformStreamingIfNeeded()
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
                self?.startStreaming(sampleKinds: [DataKind.heartRate.rawValue, DataKind.waveform.rawValue])
            }
        }
        engine.onStreamStop = { [weak self] in
            Task { @MainActor in
                self?.stopStreaming()
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
        replaceGenerator(with: manualGenerator, mode: .manual)
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

    private func startStreaming(sampleKinds: [UInt8]) {
        startHeartRateStreamingIfNeeded(sampleKinds: sampleKinds)
        startWaveformStreamingIfNeeded(sampleKinds: sampleKinds)
        updateStatus()
    }

    private func stopStreaming() {
        isStreaming = false
        streamTimer?.cancel()
        streamTimer = nil
        waveformStreamers.forEach { $0.stop() }
        waveformStreamers.removeAll()
        generator?.stop()
        updateStatus()
    }

    private func replaceGenerator(
        with newGenerator: any DataGeneratorProtocol,
        mode: SimulatorLaunchOptions.GeneratorMode
    ) {
        if isStreaming {
            newGenerator.start()
        }
        generator = newGenerator
        selectedGeneratorMode = mode
        restartWaveformStreamingIfNeeded()
    }

    private func restartWaveformStreamingIfNeeded() {
        guard !waveformStreamers.isEmpty else { return }
        waveformStreamers.forEach { $0.stop() }
        waveformStreamers.removeAll()
        startWaveformStreamingIfNeeded(sampleKinds: [DataKind.waveform.rawValue])
    }

    private func startHeartRateStreamingIfNeeded(sampleKinds: [UInt8]) {
        guard sampleKinds.contains(DataKind.heartRate.rawValue), streamTimer == nil, let generator else { return }

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
    }

    private func startWaveformStreamingIfNeeded(sampleKinds: [UInt8]) {
        guard sampleKinds.contains(DataKind.waveform.rawValue) else {
            waveformStreamers.forEach { $0.stop() }
            waveformStreamers.removeAll()
            return
        }
        guard waveformStreamers.isEmpty else { return }

        let generators: [WaveformGenerator] = [
            .ecg(sampleRateHz: 128, heartRate: Double(currentHeartRate)),
            .ppg(sampleRateHz: 64, heartRate: Double(currentHeartRate)),
        ]

        waveformStreamers = generators.map { generator in
            let streamer = WaveformStreamer(generator: generator)
            streamer.onBlock = { [weak self] fragment in
                self?.peripheral.pushNotifyFragments([fragment])
            }
            streamer.start()
            return streamer
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
