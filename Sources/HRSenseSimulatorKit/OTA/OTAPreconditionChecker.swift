import Foundation
import HRSenseProtocol

/// Precondition checks before OTA can start.
public enum OTAPreconditionChecker: Sendable {

    /// Check whether OTA can proceed.
    /// - Parameters:
    ///   - batteryPercent: current battery level (0–100).
    ///   - currentVersion: existing firmware version.
    ///   - targetVersion: proposed new version.
    /// - Returns: nil if all checks pass, or a status code describing the failure.
    public static func check(
        batteryPercent: UInt8,
        currentVersion: String,
        targetVersion: String
    ) -> OTAStatusCode? {
        // Battery check
        guard batteryPercent >= 30 else {
            return .lowBattery
        }

        // Downgrade check (simple string comparison — can be semantic later)
        guard targetVersion > currentVersion else {
            return .downgradeDenied
        }

        return nil
    }
}
