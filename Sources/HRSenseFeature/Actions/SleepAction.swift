import Foundation
import HRSenseCore

/// Sleep-specific actions grouped under the root `Action.sleep` case.
public enum SleepAction: Equatable, Sendable {
    case monitoringStarted(Date)
    case monitoringStopped(Date)
    case historyLoadRequested(limit: Int)
    case historyLoaded([SleepSession])
    case windowPrepared(SleepWindowInput)
    case inferenceStarted
    case inferenceCompleted(SleepStagePrediction)
    case sessionUpdated(SleepSession)
    case sessionPersisted(UUID)
    case reset
}
