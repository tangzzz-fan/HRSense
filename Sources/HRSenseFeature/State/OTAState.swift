import Foundation
import HRSenseCore

/// OTA firmware update sub-state.
public struct OTAState: Equatable, Sendable {
    /// Current phase.
    public var phase: OTAPhase
    /// Progress (0.0–1.0), meaningful only during .transferring.
    public var progress: Double

    public init(phase: OTAPhase = .idle, progress: Double = 0.0) {
        self.phase = phase
        self.progress = progress
    }
}
