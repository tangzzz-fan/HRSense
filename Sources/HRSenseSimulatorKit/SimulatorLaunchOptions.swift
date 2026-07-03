import Foundation

/// Shared launch options used by both the macOS App shell and the CLI entry.
public struct SimulatorLaunchOptions: Equatable, Sendable {
    public enum LaunchMode: String, Equatable, Sendable {
        case ui
        case headless
    }

    public enum GeneratorMode: String, CaseIterable, Equatable, Sendable {
        case resting
        case exercise
        case manual
        case anomaly
    }

    public var launchMode: LaunchMode
    public var scenarioPath: String?
    public var generatorMode: GeneratorMode
    public var autoStartAdvertising: Bool
    public var autoStartStream: Bool

    public init(
        launchMode: LaunchMode = .ui,
        scenarioPath: String? = nil,
        generatorMode: GeneratorMode = .resting,
        autoStartAdvertising: Bool = true,
        autoStartStream: Bool = true
    ) {
        self.launchMode = launchMode
        self.scenarioPath = scenarioPath
        self.generatorMode = generatorMode
        self.autoStartAdvertising = autoStartAdvertising
        self.autoStartStream = autoStartStream
    }

    /// Parses command line arguments into a unified launch model.
    public static func parse(arguments: [String]) -> SimulatorLaunchOptions {
        var options = SimulatorLaunchOptions()
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--headless":
                options.launchMode = .headless
            case "--ui":
                options.launchMode = .ui
            case "--scenario":
                if index + 1 < arguments.count {
                    options.scenarioPath = arguments[index + 1]
                    index += 1
                }
            case "--mode":
                if index + 1 < arguments.count,
                   let mode = GeneratorMode(rawValue: arguments[index + 1]) {
                    options.generatorMode = mode
                    index += 1
                }
            case "--no-auto-advertising":
                options.autoStartAdvertising = false
            case "--no-auto-stream":
                options.autoStartStream = false
            default:
                break
            }
            index += 1
        }

        return options
    }
}
