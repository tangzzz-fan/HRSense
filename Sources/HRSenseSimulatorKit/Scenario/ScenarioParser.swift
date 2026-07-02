import Foundation

/// Parse a Scenario JSON file into a Scenario model.
public enum ScenarioParser: Sendable {
    /// Load and decode a Scenario from a file URL.
    public static func parse(url: URL) throws -> Scenario {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(Scenario.self, from: data)
    }

    /// Parse a Scenario from a JSON string.
    public static func parse(json: String) throws -> Scenario {
        guard let data = json.data(using: .utf8) else {
            throw ScenarioParseError.invalidUTF8
        }
        let decoder = JSONDecoder()
        return try decoder.decode(Scenario.self, from: data)
    }
}

public enum ScenarioParseError: Error, Equatable {
    case invalidUTF8
    case fileNotFound
}
