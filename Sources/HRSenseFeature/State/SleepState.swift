import Foundation
import HRSenseCore

/// Sleep monitoring sub-state introduced by M9 phase 5.
public struct SleepState: Equatable, Sendable {
    public enum PipelineStatus: Equatable, Sendable {
        case idle
        case monitoring
        case inferring
        case ready
    }

    public var currentSession: SleepSession?
    public var recentSessions: [SleepSession]
    public var stageHistory: [SleepStageSegment]
    public var isMonitoring: Bool
    public var monitoringStartedAt: Date?
    public var lastInference: SleepStagePrediction?
    public var latestWindowInput: SleepWindowInput?
    public var status: PipelineStatus
    public var lastPersistedSessionID: UUID?

    public init(
        currentSession: SleepSession? = nil,
        recentSessions: [SleepSession] = [],
        stageHistory: [SleepStageSegment] = [],
        isMonitoring: Bool = false,
        monitoringStartedAt: Date? = nil,
        lastInference: SleepStagePrediction? = nil,
        latestWindowInput: SleepWindowInput? = nil,
        status: PipelineStatus = .idle,
        lastPersistedSessionID: UUID? = nil
    ) {
        self.currentSession = currentSession
        self.recentSessions = recentSessions
        self.stageHistory = stageHistory
        self.isMonitoring = isMonitoring
        self.monitoringStartedAt = monitoringStartedAt
        self.lastInference = lastInference
        self.latestWindowInput = latestWindowInput
        self.status = status
        self.lastPersistedSessionID = lastPersistedSessionID
    }
}
