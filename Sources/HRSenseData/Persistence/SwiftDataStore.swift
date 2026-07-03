import Foundation
import SwiftData
import HRSenseCore

@ModelActor
public actor SwiftDataStore: PersistenceStore {
    public nonisolated static func makeModelContainer(
        isStoredInMemoryOnly: Bool = false
    ) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: isStoredInMemoryOnly)
        return try ModelContainer(
            for: SessionModel.self,
            HeartRateSampleModel.self,
            RRSampleModel.self,
            ArchivedHeartRateBucketModel.self,
            ArchivedRRBucketModel.self,
            HRVMetricRecordModel.self,
            InferenceRecordModel.self,
            SleepSessionModel.self,
            WaveformBlobRefModel.self,
            EventRecordModel.self,
            configurations: configuration
        )
    }

    public func saveSession(_ session: Session) async throws {
        if let existing = try fetchAll(SessionModel.self).first(where: { $0.id == session.id }) {
            existing.apply(session)
        } else {
            modelContext.insert(SessionModel(domain: session))
        }
        try saveIfNeeded()
    }

    public func saveHeartRateSamples(_ samples: [HeartRateSampleRecord]) async throws {
        try upsert(samples, as: HeartRateSampleModel.self) { model, value in
            model.apply(value)
        } create: { value in
            HeartRateSampleModel(domain: value)
        }
    }

    public func saveRRSamples(_ samples: [RRSampleRecord]) async throws {
        try upsert(samples, as: RRSampleModel.self) { model, value in
            model.apply(value)
        } create: { value in
            RRSampleModel(domain: value)
        }
    }

    public func saveHRVMetrics(_ records: [HRVMetricRecord]) async throws {
        try upsert(records, as: HRVMetricRecordModel.self) { model, value in
            model.apply(value)
        } create: { value in
            HRVMetricRecordModel(domain: value)
        }
    }

    public func saveInferenceRecords(_ records: [InferenceRecord]) async throws {
        try upsert(records, as: InferenceRecordModel.self) { model, value in
            model.apply(value)
        } create: { value in
            InferenceRecordModel(domain: value)
        }
    }

    public func saveSleepSession(_ session: SleepSession) async throws {
        if let existing = try fetchAll(SleepSessionModel.self).first(where: { $0.id == session.id }) {
            existing.apply(session)
        } else {
            modelContext.insert(SleepSessionModel(domain: session))
        }
        try saveIfNeeded()
    }

    public func saveWaveformBlobRefs(_ refs: [WaveformBlobRef]) async throws {
        try upsert(refs, as: WaveformBlobRefModel.self) { model, value in
            model.apply(value)
        } create: { value in
            WaveformBlobRefModel(domain: value)
        }
    }

    public func saveEventRecords(_ records: [EventRecord]) async throws {
        try upsert(records, as: EventRecordModel.self) { model, value in
            model.apply(value)
        } create: { value in
            EventRecordModel(domain: value)
        }
    }

    public func querySessions(_ query: SessionQuery) async throws -> [Session] {
        var models = try fetchAll(SessionModel.self, sortBy: [SortDescriptor(\.startAt, order: .reverse)])

        if let deviceID = query.deviceID {
            models = models.filter { $0.deviceID == deviceID }
        }
        if let range = query.startedWithin {
            models = models.filter { range.contains($0.startAt) }
        }
        if let limit = query.limit {
            models = Array(models.prefix(limit))
        }

        return models.map { $0.toDomain() }
    }

    public func queryHeartRate(_ query: HeartRateQuery) async throws -> [HeartRateSampleRecord] {
        var models = try fetchAll(HeartRateSampleModel.self, sortBy: [SortDescriptor(\.timestamp, order: .forward)])
            .filter { $0.sessionID == query.sessionID }

        if let range = query.range {
            models = models.filter { range.contains($0.timestamp) }
        }
        if let limit = query.limit {
            models = Array(models.suffix(limit))
        }

        return models.map { $0.toDomain() }
    }

    public func queryHRVMetrics(_ query: HRVMetricQuery) async throws -> [HRVMetricRecord] {
        var models = try fetchAll(HRVMetricRecordModel.self, sortBy: [SortDescriptor(\.windowStart, order: .forward)])
            .filter { $0.sessionID == query.sessionID }

        if let range = query.range {
            models = models.filter { range.contains($0.windowStart) }
        }

        return models.map { $0.toDomain() }
    }

    public func querySleepSessions(_ query: SleepSessionQuery) async throws -> [SleepSession] {
        var models = try fetchAll(SleepSessionModel.self, sortBy: [SortDescriptor(\.date, order: .reverse)])

        if let range = query.dateRange {
            models = models.filter { range.contains($0.date) }
        }
        if let limit = query.limit {
            models = Array(models.prefix(limit))
        }

        return models.map { $0.toDomain() }
    }

    public func aggregateHeartRate(
        sessionID: UUID,
        interval: HeartRateAggregationInterval,
        range: TimeRange?
    ) async throws -> [HeartRateAggregationBucket] {
        let records = try await queryHeartRate(
            HeartRateQuery(sessionID: sessionID, range: range)
        )
        return DataAggregation.aggregateHeartRate(records, interval: interval)
    }

    public func purgeExpiredData(
        now: Date,
        policy: RetentionPolicy
    ) async throws -> StoragePurgeResult {
        let calendar = Calendar(identifier: .gregorian)
        let waveformCutoff = calendar.date(byAdding: .day, value: -policy.waveformRetentionDays, to: now) ?? now
        let rawSampleCutoff = calendar.date(byAdding: .day, value: -policy.rawSampleRetentionDays, to: now) ?? now

        let oldWaveforms = try fetchAll(WaveformBlobRefModel.self).filter { $0.startTimestamp < waveformCutoff }
        let oldHeartRate = try fetchAll(HeartRateSampleModel.self).filter { $0.timestamp < rawSampleCutoff }
        let oldRR = try fetchAll(RRSampleModel.self).filter { $0.timestamp < rawSampleCutoff }

        for model in oldWaveforms {
            modelContext.delete(model)
        }
        for model in oldHeartRate {
            modelContext.delete(model)
        }
        for model in oldRR {
            modelContext.delete(model)
        }

        try saveIfNeeded()

        let deletedWaveformBytes = oldWaveforms.reduce(Int64.zero) { $0 + $1.fileSizeBytes }
        return StoragePurgeResult(
            deletedWaveformFileCount: oldWaveforms.count,
            deletedWaveformBytes: deletedWaveformBytes,
            deletedHeartRateSampleCount: oldHeartRate.count,
            deletedRRSampleCount: oldRR.count,
            reclaimedBytes: deletedWaveformBytes
        )
    }

    func listWaveformBlobRefs() throws -> [WaveformBlobRef] {
        try fetchAll(
            WaveformBlobRefModel.self,
            sortBy: [SortDescriptor(\.startTimestamp, order: .forward)]
        )
        .map { $0.toDomain() }
    }

    func listHeartRateSamples(before cutoff: Date) throws -> [HeartRateSampleRecord] {
        try fetchAll(
            HeartRateSampleModel.self,
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        .filter { $0.timestamp < cutoff }
        .map { $0.toDomain() }
    }

    func listRRSamples(before cutoff: Date) throws -> [RRSampleRecord] {
        try fetchAll(
            RRSampleModel.self,
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        .filter { $0.timestamp < cutoff }
        .map { $0.toDomain() }
    }

    func saveArchivedHeartRateBuckets(_ buckets: [ArchivedHeartRateBucket]) throws {
        try upsert(buckets, as: ArchivedHeartRateBucketModel.self) { model, value in
            model.apply(value)
        } create: { value in
            ArchivedHeartRateBucketModel(domain: value)
        }
    }

    func saveArchivedRRBuckets(_ buckets: [ArchivedRRBucket]) throws {
        try upsert(buckets, as: ArchivedRRBucketModel.self) { model, value in
            model.apply(value)
        } create: { value in
            ArchivedRRBucketModel(domain: value)
        }
    }

    func listArchivedHeartRateBuckets() throws -> [ArchivedHeartRateBucket] {
        try fetchAll(
            ArchivedHeartRateBucketModel.self,
            sortBy: [SortDescriptor(\.bucketStart, order: .forward)]
        )
        .map { $0.toDomain() }
    }

    func listArchivedRRBuckets() throws -> [ArchivedRRBucket] {
        try fetchAll(
            ArchivedRRBucketModel.self,
            sortBy: [SortDescriptor(\.bucketStart, order: .forward)]
        )
        .map { $0.toDomain() }
    }

    func deleteWaveformBlobRefs(ids: [UUID]) throws -> Int {
        guard !ids.isEmpty else { return 0 }

        let idSet = Set(ids)
        let models = try fetchAll(WaveformBlobRefModel.self)
            .filter { idSet.contains($0.id) }

        for model in models {
            modelContext.delete(model)
        }

        try saveIfNeeded()
        return models.count
    }

    private func fetchAll<Model: PersistentModel>(
        _ type: Model.Type,
        sortBy: [SortDescriptor<Model>] = []
    ) throws -> [Model] {
        let descriptor = FetchDescriptor<Model>(sortBy: sortBy)
        return try modelContext.fetch(descriptor)
    }

    private func saveIfNeeded() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    private func upsert<Domain: Identifiable, Model: PersistentModel>(
        _ values: [Domain],
        as modelType: Model.Type,
        apply: (Model, Domain) -> Void,
        create: (Domain) -> Model
    ) throws where Domain.ID: Equatable {
        guard !values.isEmpty else { return }

        let existing = try fetchAll(modelType)

        for value in values {
            let identifier = AnyHashable(value.id)
            var matchedModel: Model?
            for candidate in existing {
                if persistentModelID(candidate) == identifier {
                    matchedModel = candidate
                    break
                }
            }

            if let model = matchedModel {
                apply(model, value)
            } else {
                modelContext.insert(create(value))
            }
        }

        try saveIfNeeded()
    }

    private func persistentModelID<Model: PersistentModel>(_ model: Model) -> AnyHashable? {
        switch model {
        case let model as SessionModel:
            return AnyHashable(model.id)
        case let model as HeartRateSampleModel:
            return AnyHashable(model.id)
        case let model as RRSampleModel:
            return AnyHashable(model.id)
        case let model as ArchivedHeartRateBucketModel:
            return AnyHashable(model.id)
        case let model as ArchivedRRBucketModel:
            return AnyHashable(model.id)
        case let model as HRVMetricRecordModel:
            return AnyHashable(model.id)
        case let model as InferenceRecordModel:
            return AnyHashable(model.id)
        case let model as SleepSessionModel:
            return AnyHashable(model.id)
        case let model as WaveformBlobRefModel:
            return AnyHashable(model.id)
        case let model as EventRecordModel:
            return AnyHashable(model.id)
        default:
            return nil
        }
    }
}
