import Foundation

// MARK: - Remaining stub types (full definitions in M5/M6)

/// Placeholder — full definition in M6.
public enum OTAPhase: Equatable, Sendable {
    case idle
    case preparing
    case transferring(progress: Double)
    case validating
    case applying
    case completed(newVersion: String)
    case failed(error: String)
}
