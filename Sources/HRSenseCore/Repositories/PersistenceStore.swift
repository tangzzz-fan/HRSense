import Foundation

/// Storage boundary for M9. Upper layers depend on this protocol instead of
/// binding directly to SwiftData, GRDB, or filesystem-specific details.
public protocol PersistenceStore: Sendable {
    func saveSession(_ session: Session) async throws
    func saveHeartRateSamples(_ samples: [HeartRateSampleRecord]) async throws
    func saveRRSamples(_ samples: [RRSampleRecord]) async throws
    func saveHRVMetrics(_ records: [HRVMetricRecord]) async throws
    func saveInferenceRecords(_ records: [InferenceRecord]) async throws
    func saveSleepSession(_ session: SleepSession) async throws
    func saveWaveformBlobRefs(_ refs: [WaveformBlobRef]) async throws
    func saveEventRecords(_ records: [EventRecord]) async throws

    func querySessions(_ query: SessionQuery) async throws -> [Session]
    func queryHeartRate(_ query: HeartRateQuery) async throws -> [HeartRateSampleRecord]
    func queryHRVMetrics(_ query: HRVMetricQuery) async throws -> [HRVMetricRecord]
    func querySleepSessions(_ query: SleepSessionQuery) async throws -> [SleepSession]

    func aggregateHeartRate(
        sessionID: UUID,
        interval: HeartRateAggregationInterval,
        range: TimeRange?
    ) async throws -> [HeartRateAggregationBucket]

    func purgeExpiredData(
        now: Date,
        policy: RetentionPolicy
    ) async throws -> StoragePurgeResult
}
