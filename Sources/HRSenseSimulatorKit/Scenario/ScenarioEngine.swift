import Foundation

/// Drives a Scenario by executing its steps in sequence with timed delays.
///
/// The engine is designed for headless (CI) mode: it steps through a script
/// and fires a callback when a new HR value or action is needed.
public final class ScenarioEngine: @unchecked Sendable {
    public let scenario: Scenario
    private var currentStepIndex: Int = 0
    private var running = false

    /// Called when a step action requires the simulator to change HR.
    public var onHeartRateChange: ((Int) -> Void)?
    /// Called when a step action requires stream start.
    public var onStreamStart: (() -> Void)?
    /// Called when a step action requires stream stop.
    public var onStreamStop: (() -> Void)?
    /// Called when a step action requires disconnect.
    public var onDisconnect: (() -> Void)?
    /// Called when a step action requires reconnecting.
    public var onReconnect: (() -> Void)?
    /// Called when a fault injection is requested.
    public var onFault: ((FaultConfig) -> Void)?
    /// Called when all steps have been executed.
    public var onComplete: (() -> Void)?

    public init(scenario: Scenario) {
        self.scenario = scenario
    }

    /// Start executing the scenario. Steps run sequentially with their delays.
    public func start() {
        guard !running else { return }
        running = true
        currentStepIndex = 0
        executeNextStep()
    }

    /// Stop the scenario engine.
    public func stop() {
        running = false
    }

    private func executeNextStep() {
        guard running else { return }
        guard currentStepIndex < scenario.steps.count else {
            onComplete?()
            return
        }

        let step = scenario.steps[currentStepIndex]
        let delay = TimeInterval(step.delayMs) / 1000.0

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.running else { return }
            self.apply(step)
            self.currentStepIndex += 1
            self.executeNextStep()
        }
    }

    private func apply(_ step: ScenarioStep) {
        switch step.action {
        case .setHR:
            if let hr = step.heartRate {
                onHeartRateChange?(hr)
            }
        case .startStream:
            onStreamStart?()
        case .stopStream:
            onStreamStop?()
        case .disconnect:
            onDisconnect?()
        case .reconnect:
            onReconnect?()
        case .injectFault:
            if let fault = step.fault {
                onFault?(fault)
            }
        case .wait:
            break  // delay already handled
        }
    }
}
