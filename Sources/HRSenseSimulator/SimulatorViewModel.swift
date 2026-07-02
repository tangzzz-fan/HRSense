import SwiftUI
import HRSenseSimulatorKit
import HRSenseProtocol

/// ViewModel that bridges SimulatedPeripheral to SwiftUI state.
@MainActor
@Observable
final class SimulatorViewModel {
    private let peripheral: SimulatedPeripheral
    private var generator: (any DataGeneratorProtocol)?

    private var streamTimer: DispatchSourceTimer?
    private var streamStartTime: UInt64 = 0

    // MARK: - Published state (UI-bound)

    var connectionStatus: String = "Idle"
    var isAdvertising: Bool = false
    var currentHeartRate: Int = 70
    var sampleCount: Int = 0
    var isStreaming: Bool = false
    var deviceState: DeviceState = .advertising
    var selectedGeneratorMode: String = "resting"

    // MARK: - Scenarios

    private var scenarioEngine: ScenarioEngine?

    // MARK: - Init

    init() {
        let config = SimulatorConfig()
        self.peripheral = SimulatedPeripheral(config: config)
        self.generator = RestingHRGenerator()

        peripheral.onStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.deviceState = state
                self?.updateStatus()
            }
        }
    }

    // MARK: - Public actions

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
        guard let gen = generator else { return }
        isStreaming = true
        streamStartTime = DispatchTime.now().uptimeNanoseconds
        gen.start()

        // 1 Hz timer
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isStreaming else { return }
            let elapsedMs = UInt32((DispatchTime.now().uptimeNanoseconds - self.streamStartTime) / 1_000_000)
            let sample = gen.nextSample(timestampMs: elapsedMs)
            self.peripheral.pushSample(sample)
            self.currentHeartRate = Int(sample.heartRate ?? 0)
            self.sampleCount += 1
        }
        timer.resume()
        self.streamTimer = timer

        // Send START_STREAM command (simulate App side)
        let cmd = Command.startStream()
        let _ = peripheral.commandProcessor.process(command: cmd, seq: 0)

        updateStatus()
    }

    func stopStream() {
        isStreaming = false
        streamTimer?.cancel()
        streamTimer = nil
        generator?.stop()

        let cmd = Command.stopStream()
        let _ = peripheral.commandProcessor.process(command: cmd, seq: 0)

        updateStatus()
    }

    func toggleGeneratorMode() {
        switch selectedGeneratorMode {
        case "resting":
            generator = RestingHRGenerator()
        case "exercise":
            generator = ExerciseHRGenerator()
        case "manual":
            generator = ManualHRGenerator(heartRate: currentHeartRate)
        case "anomaly":
            generator = AnomalyHRGenerator()
        default:
            generator = RestingHRGenerator()
        }
    }

    func setManualHR(_ hr: Int) {
        currentHeartRate = hr
        if let gen = generator as? ManualHRGenerator {
            gen.currentHeartRate = hr
        }
    }

    // MARK: - Headless mode

    func startHeadless(scenarioPath: String? = nil) {
        startAdvertising()
        // Stream starts immediately in headless mode
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.startStream()
        }
    }

    // MARK: - Private

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
}
