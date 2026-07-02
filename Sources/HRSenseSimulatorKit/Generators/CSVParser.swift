import Foundation

/// Simple CSV parser for replay data.
public struct CSVParser: Sendable {
    public init() {}

    /// Parse CSV content into an array of field arrays.
    /// Each inner array represents one row's fields.
    public func parse(_ content: String) throws -> [[String]] {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.map { line in
            line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }
}
