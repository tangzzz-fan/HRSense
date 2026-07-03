import Foundation
import HRSenseCore
import HRSenseProtocol

/// Coordinates M9 retention work across structured metadata and waveform files.
/// Raw samples are purged via `PersistenceStore`, while waveform assets are
/// deleted from disk before their metadata is removed.
public actor RetentionCleanupTask {
    private let store: SwiftDataStore
    private let waveformFileStore: WaveformFileStore
    private let policy: RetentionPolicy
    private let calendar: Calendar
    private let nowProvider: @Sendable () -> Date

    public init(
        store: SwiftDataStore,
        waveformFileStore: WaveformFileStore,
        policy: RetentionPolicy = RetentionPolicy(),
        calendar: Calendar = Calendar(identifier: .gregorian),
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.waveformFileStore = waveformFileStore
        self.policy = policy
        self.calendar = calendar
        self.nowProvider = nowProvider
    }

    public func run() async throws -> StoragePurgeResult {
        try await run(now: nowProvider())
    }

    public func run(now: Date) async throws -> StoragePurgeResult {
        let waveformCutoff = calendar.date(
            byAdding: .day,
            value: -policy.waveformRetentionDays,
            to: now
        ) ?? now
        let rawSampleCutoff = calendar.date(
            byAdding: .day,
            value: -policy.rawSampleRetentionDays,
            to: now
        ) ?? now

        let allWaveformRefs = try await store.listWaveformBlobRefs()
        let expiredWaveforms = allWaveformRefs.filter { $0.startTimestamp < waveformCutoff }

        try await archiveRawSamples(before: rawSampleCutoff)
        try deleteWaveformFiles(for: expiredWaveforms)
        let purgeResult = try await store.purgeExpiredData(now: now, policy: policy)
        let storageTrimResult = try await trimWaveformsToStorageLimit()
        let totalResult = purgeResult.merging(storageTrimResult)

        HRSenseLogging.info(
            .perf,
            "Retention cleanup finished: deletedFiles=\(totalResult.deletedWaveformFileCount) reclaimedBytes=\(totalResult.reclaimedBytes)"
        )

        return totalResult
    }

    private func archiveRawSamples(before cutoff: Date) async throws {
        let heartRateSamples = try await store.listHeartRateSamples(before: cutoff)
        let rrSamples = try await store.listRRSamples(before: cutoff)

        let archivedHeartRate = DataAggregation.archiveHeartRate(
            heartRateSamples,
            interval: .minute,
            calendar: calendar
        )
        let archivedRR = DataAggregation.archiveRR(
            rrSamples,
            interval: .minute,
            calendar: calendar
        )

        try await store.saveArchivedHeartRateBuckets(archivedHeartRate)
        try await store.saveArchivedRRBuckets(archivedRR)

        HRSenseLogging.info(
            .perf,
            "Archived raw samples: heartRateBuckets=\(archivedHeartRate.count) rrBuckets=\(archivedRR.count)"
        )
    }

    private func trimWaveformsToStorageLimit() async throws -> StoragePurgeResult {
        let refs = try await store.listWaveformBlobRefs()
        let totalBytes = refs.reduce(Int64.zero) { $0 + $1.fileSizeBytes }
        guard totalBytes > policy.maxTotalStorageBytes else {
            return StoragePurgeResult()
        }

        var bytesAfterTrim = totalBytes
        var refsToDelete: [WaveformBlobRef] = []

        for ref in refs where bytesAfterTrim > policy.maxTotalStorageBytes {
            refsToDelete.append(ref)
            bytesAfterTrim -= ref.fileSizeBytes
        }

        try deleteWaveformFiles(for: refsToDelete)
        _ = try await store.deleteWaveformBlobRefs(ids: refsToDelete.map(\.id))

        let deletedBytes = refsToDelete.reduce(Int64.zero) { $0 + $1.fileSizeBytes }
        return StoragePurgeResult(
            deletedWaveformFileCount: refsToDelete.count,
            deletedWaveformBytes: deletedBytes,
            reclaimedBytes: deletedBytes
        )
    }

    private func deleteWaveformFiles(for refs: [WaveformBlobRef]) throws {
        for ref in refs {
            try waveformFileStore.deleteChunks(for: ref)
        }
    }
}

private extension StoragePurgeResult {
    func merging(_ other: StoragePurgeResult) -> StoragePurgeResult {
        StoragePurgeResult(
            deletedWaveformFileCount: deletedWaveformFileCount + other.deletedWaveformFileCount,
            deletedWaveformBytes: deletedWaveformBytes + other.deletedWaveformBytes,
            deletedHeartRateSampleCount: deletedHeartRateSampleCount + other.deletedHeartRateSampleCount,
            deletedRRSampleCount: deletedRRSampleCount + other.deletedRRSampleCount,
            reclaimedBytes: reclaimedBytes + other.reclaimedBytes
        )
    }
}
