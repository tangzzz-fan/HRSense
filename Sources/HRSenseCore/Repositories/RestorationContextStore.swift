import Foundation

/// Abstraction for persisted BLE restoration eligibility.
///
/// Feature and Data layers use this boundary instead of talking to `UserDefaults`
/// directly so the startup policy stays testable and storage remains replaceable.
public protocol RestorationContextStore: Sendable {
    /// Load the last eligible restoration context, if any.
    func load() -> RestorationContext?

    /// Persist a successful connection as the next restoration candidate.
    func save(_ context: RestorationContext)

    /// Remove any persisted restoration eligibility.
    func clear()
}
