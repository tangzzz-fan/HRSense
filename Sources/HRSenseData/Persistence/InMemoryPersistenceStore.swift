import Foundation
import HRSenseCore

/// Lightweight M9 bootstrap store used to validate the storage boundary before
/// wiring a real SwiftData and file-backed implementation.
public actor InMemoryPersistenceStore: PersistenceStore {
    private var sessions: [Session] = []
    private var heartRateSamples: [HeartRateSampleRecord] = []
    private var rrSamples: [RRSampleRecord] = []
    private var hrvMetrics: [HRVMetricRecord] = []
    private var inferenceRecords: [InferenceRecord] = []
    private var sleepSessions: [SleepSession] = []
    private var waveformRefs: [WaveformBlobRef] = []
    private var eventRecords: [EventRecord] = []

    public init() {}

    public func saveSession(_ session: Session) async throws {
        upsert(&sessions, value: session, id: session.id)
    }

    public func saveHeartRateSamples(_ samples: [HeartRateSampleRecord]) async throws {
        heartRateSamples.append(contentsOf: samples)
        heartRateSamples.sort { $0.timestamp < $1.timestamp }
    }

    public func saveRRSamples(_ samples: [RRSampleRecord]) async throws {
        rrSamples.append(contentsOf: samples)
        rrSamples.sort { $0.timestamp < $1.timestamp }
    }

    public func saveHRVMetrics(_ records: [HRVMetricRecord]) async throws {
        hrvMetrics.append(contentsOf: records)
        hrvMetrics.sort { $0.windowStart < $1.windowStart }
    }

    public func saveInferenceRecords(_ records: [InferenceRecord]) async throws {
        inferenceRecords.append(contentsOf: records)
        inferenceRecords.sort { $0.timestamp < $1.timestamp }
    }

    public func saveSleepSession(_ session: SleepSession) async throws {
        upsert(&sleepSessions, value: session, id: session.id)
    }

    public func saveWaveformBlobRefs(_ refs: [WaveformBlobRef]) async throws {
        waveformRefs.append(contentsOf: refs)
        waveformRefs.sort { $0.startTimestamp < $1.startTimestamp }
    }

    public func saveEventRecords(_ records: [EventRecord]) async throws {
        eventRecords.append(contentsOf: records)
        eventRecords.sort { $0.timestamp < $1.timestamp }
    }

    public func querySessions(_ query: SessionQuery) async throws -> [Session] {
        var result = sessions

        if let deviceID = query.deviceID {
            result = result.filter { $0.deviceID == deviceID }
        }
        if let range = query.startedWithin {
            result = result.filter { range.contains($0.startAt) }
        }

        result.sort { $0.startAt > $1.startAt }
        if let limit = query.limit {
            result = Array(result.prefix(limit))
        }
        return result
    }

    public func queryHeartRate(_ query: HeartRateQuery) async throws -> [HeartRateSampleRecord] {
        var result = heartRateSamples.filter { $0.sessionID == query.sessionID }
        if let range = query.range {
            result = result.filter { range.contains($0.timestamp) }
        }

        result.sort { $0.timestamp < $1.timestamp }
        if let limit = query.limit {
            result = Array(result.suffix(limit))
        }
        return result
    }

    public func queryHRVMetrics(_ query: HRVMetricQuery) async throws -> [HRVMetricRecord] {
        var result = hrvMetrics.filter { $0.sessionID == query.sessionID }
        if let range = query.range {
            result = result.filter { range.contains($0.windowStart) }
        }
        return result.sorted { $0.windowStart < $1.windowStart }
    }

    public func querySleepSessions(_ query: SleepSessionQuery) async throws -> [SleepSession] {
        var result = sleepSessions
        if let range = query.dateRange {
            result = result.filter { range.contains($0.date) }
        }

        result.sort { $0.date > $1.date }
        if let limit = query.limit {
            result = Array(result.prefix(limit))
        }
        return result
    }

    public func aggregateHeartRate(
        sessionID: UUID,
        interval: HeartRateAggregationInterval,
        range: TimeRange?
    ) async throws -> [HeartRateAggregationBucket] {
        let samples = try await queryHeartRate(
            HeartRateQuery(sessionID: sessionID, range: range)
        )
        return DataAggregation.aggregateHeartRate(samples, interval: interval)
    }

    public func purgeExpiredData(
        now: Date,
        policy: RetentionPolicy
    ) async throws -> StoragePurgeResult {
        let waveformCutoff = Calendar(identifier: .gregorian).date(
            byAdding: .day,
            value: -policy.waveformRetentionDays,
            to: now
        ) ?? now
        let rawSampleCutoff = Calendar(identifier: .gregorian).date(
            byAdding: .day,
            value: -policy.rawSampleRetentionDays,
            to: now
        ) ?? now

        let oldWaveforms = waveformRefs.filter { $0.startTimestamp < waveformCutoff }
        let oldHeartRate = heartRateSamples.filter { $0.timestamp < rawSampleCutoff }
        let oldRR = rrSamples.filter { $0.timestamp < rawSampleCutoff }

        waveformRefs.removeAll { $0.startTimestamp < waveformCutoff }
        heartRateSamples.removeAll { $0.timestamp < rawSampleCutoff }
        rrSamples.removeAll { $0.timestamp < rawSampleCutoff }

        let deletedWaveformBytes = oldWaveforms.reduce(Int64.zero) { $0 + $1.fileSizeBytes }

        return StoragePurgeResult(
            deletedWaveformFileCount: oldWaveforms.count,
            deletedWaveformBytes: deletedWaveformBytes,
            deletedHeartRateSampleCount: oldHeartRate.count,
            deletedRRSampleCount: oldRR.count,
            reclaimedBytes: deletedWaveformBytes
        )
    }

    private func upsert<T: Identifiable>(_ values: inout [T], value: T, id: T.ID) where T.ID: Equatable {
        if let index = values.firstIndex(where: { $0.id == id }) {
            values[index] = value
        } else {
            values.append(value)
        }
    }
}
