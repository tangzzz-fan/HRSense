import Foundation

/// Domain entity: OTA progress tracking.
public struct OTAProgress: Equatable, Sendable {
    /// Current phase.
    public let phase: OTAPhase
    /// Transfer progress (0.0–1.0), monotonic.
    public let transferProgress: Double
    /// Total bytes written so far.
    public let bytesWritten: Int
    /// Total image size.
    public let totalBytes: Int

    public init(
        phase: OTAPhase = .idle,
        transferProgress: Double = 0.0,
        bytesWritten: Int = 0,
        totalBytes: Int = 0
    ) {
        self.phase = phase
        self.transferProgress = transferProgress
        self.bytesWritten = bytesWritten
        self.totalBytes = totalBytes
    }
}
