import Foundation
import HRSenseProtocol

/// Headless runtime used by the CLI entry and future CI automation.
public final class SimulatorHeadlessRunner: @unchecked Sendable {
    private let peripheral: SimulatedPeripheral
    private let launchOptions: SimulatorLaunchOptions
    private let output: @Sendable (String) -> Void

    private var generator: (any DataGeneratorProtocol)?
    private var waveformStreamer: WaveformStreamer?
    private var scenarioEngine: ScenarioEngine?
    private var streamTimer: DispatchSourceTimer?
    private var streamStartTime: UInt64 = 0

    var isStreaming: Bool { streamTimer != nil }
    var isWaveformStreaming: Bool { waveformStreamer != nil }
    var simulatedPeripheral: SimulatedPeripheral { peripheral }

    public init(
        launchOptions: SimulatorLaunchOptions,
        config: SimulatorConfig = SimulatorConfig(),
        output: @escaping @Sendable (String) -> Void = { print($0) }
    ) {
        self.launchOptions = launchOptions
        self.output = output
        self.peripheral = SimulatedPeripheral(config: config)
        self.generator = Self.makeGenerator(mode: launchOptions.generatorMode)

        peripheral.onStateChanged = { [weak self] state in
            self?.output("simulator.state=\(state)")
        }
        peripheral.commandProcessor.setStreamCallbacks(
            onStart: { [weak self] sampleKinds in
                self?.startStreaming(sampleKinds: sampleKinds)
            },
            onStop: { [weak self] in
                self?.stopStreaming()
            }
        )
    }

    deinit {
        stop()
    }

    public func start() throws {
        if let scenarioPath = launchOptions.scenarioPath {
            try configureScenarioEngine(path: scenarioPath)
        }

        if launchOptions.autoStartAdvertising {
            startAdvertising()
        }

        if launchOptions.autoStartStream {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.startStreaming(sampleKinds: [DataKind.heartRate.rawValue])
            }
        }

        scenarioEngine?.start()
    }

    public func stop() {
        scenarioEngine?.stop()
        stopStreaming()
        peripheral.stopAdvertising()
    }

    public func startAdvertising() {
        peripheral.startAdvertising()
        output("simulator.advertising=started")
    }

    public func startStream() {
        startStreaming(sampleKinds: [DataKind.heartRate.rawValue])
    }

    public func startStreaming(sampleKinds: [UInt8]) {
        startHeartRateStreamingIfNeeded(sampleKinds: sampleKinds)
        startWaveformStreamingIfNeeded(sampleKinds: sampleKinds)
        let sampleKindList = sampleKinds.map(String.init).joined(separator: ",")
        output("simulator.stream=started kinds=\(sampleKindList) mode=\(launchOptions.generatorMode.rawValue)")
    }

    public func stopStream() {
        stopStreaming()
    }

    public func stopStreaming() {
        streamTimer?.cancel()
        streamTimer = nil
        waveformStreamer?.stop()
        waveformStreamer = nil
        generator?.stop()
        output("simulator.stream=stopped")
    }

    private func configureScenarioEngine(path: String) throws {
        let url = URL(fileURLWithPath: path)
        let scenario = try ScenarioParser.parse(url: url)
        let engine = ScenarioEngine(scenario: scenario)

        engine.onHeartRateChange = { [weak self] heartRate in
            self?.setManualHeartRate(heartRate)
        }
        engine.onStreamStart = { [weak self] in
            self?.startStreaming(sampleKinds: [DataKind.heartRate.rawValue])
        }
        engine.onStreamStop = { [weak self] in
            self?.stopStreaming()
        }
        engine.onDisconnect = { [weak self] in
            self?.peripheral.stopAdvertising()
        }
        engine.onReconnect = { [weak self] in
            self?.startAdvertising()
        }
        engine.onFault = { [weak self] fault in
            self?.applyFault(fault)
        }
        engine.onComplete = { [weak self] in
            self?.output("simulator.scenario=completed")
        }

        scenarioEngine = engine
        output("simulator.scenario=loaded path=\(path)")
    }

    private func setManualHeartRate(_ heartRate: Int) {
        if let manualGenerator = generator as? ManualHRGenerator {
            manualGenerator.currentHeartRate = heartRate
        } else {
            let manualGenerator = ManualHRGenerator(heartRate: heartRate)
            if streamTimer != nil {
                manualGenerator.start()
            }
            generator = manualGenerator
        }
        output("simulator.manualHR=\(heartRate)")
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
        output("simulator.fault=applied")
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

    private func startHeartRateStreamingIfNeeded(sampleKinds: [UInt8]) {
        guard sampleKinds.contains(DataKind.heartRate.rawValue) else {
            streamTimer?.cancel()
            streamTimer = nil
            generator?.stop()
            return
        }
        guard streamTimer == nil, let generator else { return }

        self.generator = generator
        self.streamStartTime = DispatchTime.now().uptimeNanoseconds
        generator.start()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self, let generator = self.generator else { return }

            let elapsedMs = UInt32(
                (DispatchTime.now().uptimeNanoseconds - self.streamStartTime) / 1_000_000
            )
            let sample = generator.nextSample(timestampMs: elapsedMs)
            _ = self.peripheral.pushSample(sample)
        }
        timer.resume()
        streamTimer = timer
    }

    private func startWaveformStreamingIfNeeded(sampleKinds: [UInt8]) {
        guard sampleKinds.contains(DataKind.waveform.rawValue) else {
            waveformStreamer?.stop()
            waveformStreamer = nil
            return
        }
        guard waveformStreamer == nil else { return }

        let streamer = WaveformStreamer(generator: .ecg())
        streamer.onBlock = { [weak self] fragment in
            self?.peripheral.pushNotifyFragments([fragment])
        }
        streamer.start()
        waveformStreamer = streamer
    }
}
