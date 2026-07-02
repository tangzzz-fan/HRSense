import Foundation

/// Scenario step action types.
public enum ScenarioStepAction: String, Codable, Equatable, Sendable {
    case wait
    case setHR
    case startStream
    case stopStream
    case disconnect
    case reconnect
    case injectFault
}

/// A single step in a scenario script.
public struct ScenarioStep: Codable, Equatable, Sendable {
    /// Action to perform.
    public let action: ScenarioStepAction
    /// Delay in milliseconds before this step.
    public let delayMs: UInt32
    /// Optional heart rate value (for setHR).
    public let heartRate: Int?
    /// Optional fault configuration.
    public let fault: FaultConfig?

    public init(
        action: ScenarioStepAction,
        delayMs: UInt32 = 0,
        heartRate: Int? = nil,
        fault: FaultConfig? = nil
    ) {
        self.action = action
        self.delayMs = delayMs
        self.heartRate = heartRate
        self.fault = fault
    }
}

/// Fault injection parameters within a scenario step.
public struct FaultConfig: Codable, Equatable, Sendable {
    public let dropProbability: Double?
    public let corruptCRCProbability: Double?
    public let latencyMs: Int?

    public init(
        dropProbability: Double? = nil,
        corruptCRCProbability: Double? = nil,
        latencyMs: Int? = nil
    ) {
        self.dropProbability = dropProbability
        self.corruptCRCProbability = corruptCRCProbability
        self.latencyMs = latencyMs
    }
}

/// A complete scenario (loaded from JSON).
public struct Scenario: Codable, Equatable, Sendable {
    /// Scenario name.
    public let name: String
    /// Scenario description.
    public let description: String
    /// Ordered list of steps.
    public let steps: [ScenarioStep]

    public init(name: String, description: String, steps: [ScenarioStep]) {
        self.name = name
        self.description = description
        self.steps = steps
    }
}
