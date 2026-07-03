import XCTest
@testable import HRSenseCore
@testable import HRSenseData

final class RetentionCleanupTaskTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func test_runDeletesExpiredWaveformFilesAndRawSamples() async throws {
        let store = try makeStore()
        let waveformStore = try WaveformFileStore(baseDirectory: tempDirectory)
        let sessionID = UUID()
        let now = Date(timeIntervalSince1970: 1_725_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let oldDate = calendar.date(byAdding: .day, value: -10, to: now) ?? now
        let recentDate = calendar.date(byAdding: .day, value: -1, to: now) ?? now

        let oldRef = try writeRef(
            waveformStore: waveformStore,
            sessionID: sessionID,
            startTimestamp: oldDate,
            blockSeq: 1
        )
        let recentRef = try writeRef(
            waveformStore: waveformStore,
            sessionID: sessionID,
            startTimestamp: recentDate,
            blockSeq: 2
        )

        try await store.saveWaveformBlobRefs([oldRef, recentRef])
        try await store.saveHeartRateSamples([
            HeartRateSampleRecord(sessionID: sessionID, timestamp: oldDate, bpm: 58),
            HeartRateSampleRecord(sessionID: sessionID, timestamp: recentDate, bpm: 66),
        ])
        try await store.saveRRSamples([
            RRSampleRecord(sessionID: sessionID, timestamp: oldDate, rrMs: 910),
            RRSampleRecord(sessionID: sessionID, timestamp: recentDate, rrMs: 780),
        ])

        let cleanupTask = RetentionCleanupTask(
            store: store,
            waveformFileStore: waveformStore,
            policy: RetentionPolicy(
                waveformRetentionDays: 7,
                rawSampleRetentionDays: 7,
                maxTotalStorageBytes: .max
            )
        )

        let result = try await cleanupTask.run(now: now)
        let remainingRefs = try await store.listWaveformBlobRefs()
        let remainingHeartRate = try await store.queryHeartRate(HeartRateQuery(sessionID: sessionID))
        let archivedHeartRate = try await store.listArchivedHeartRateBuckets()
        let archivedRR = try await store.listArchivedRRBuckets()
        let firstArchivedHeartRate = try XCTUnwrap(archivedHeartRate.first)
        let firstArchivedRR = try XCTUnwrap(archivedRR.first)

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldRef.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentRef.fileURL.path))
        XCTAssertEqual(remainingRefs.map(\.id), [recentRef.id])
        XCTAssertEqual(remainingHeartRate.map(\.bpm), [66])
        XCTAssertEqual(archivedHeartRate.count, 1)
        XCTAssertEqual(firstArchivedHeartRate.sessionID, sessionID)
        XCTAssertEqual(firstArchivedHeartRate.sampleCount, 1)
        XCTAssertEqual(firstArchivedHeartRate.avgBPM, 58, accuracy: 0.0001)
        XCTAssertEqual(archivedRR.count, 1)
        XCTAssertEqual(firstArchivedRR.sampleCount, 1)
        XCTAssertEqual(firstArchivedRR.avgRRMs, 910, accuracy: 0.0001)
        XCTAssertEqual(result.deletedWaveformFileCount, 1)
        XCTAssertEqual(result.deletedWaveformBytes, oldRef.fileSizeBytes)
        XCTAssertEqual(result.deletedHeartRateSampleCount, 1)
        XCTAssertEqual(result.deletedRRSampleCount, 1)
        XCTAssertEqual(result.reclaimedBytes, oldRef.fileSizeBytes)
    }

    func test_runTrimsOldestWaveformsWhenStorageBudgetExceeded() async throws {
        let store = try makeStore()
        let waveformStore = try WaveformFileStore(baseDirectory: tempDirectory)
        let sessionID = UUID()
        let now = Date(timeIntervalSince1970: 1_725_000_000)

        let oldestRef = try writeRef(
            waveformStore: waveformStore,
            sessionID: sessionID,
            startTimestamp: now.addingTimeInterval(-300),
            blockSeq: 1
        )
        let middleRef = try writeRef(
            waveformStore: waveformStore,
            sessionID: sessionID,
            startTimestamp: now.addingTimeInterval(-200),
            blockSeq: 2
        )
        let newestRef = try writeRef(
            waveformStore: waveformStore,
            sessionID: sessionID,
            startTimestamp: now.addingTimeInterval(-100),
            blockSeq: 3
        )

        try await store.saveWaveformBlobRefs([oldestRef, middleRef, newestRef])

        let budget = middleRef.fileSizeBytes + newestRef.fileSizeBytes
        let cleanupTask = RetentionCleanupTask(
            store: store,
            waveformFileStore: waveformStore,
            policy: RetentionPolicy(
                waveformRetentionDays: 30,
                rawSampleRetentionDays: 30,
                maxTotalStorageBytes: budget
            )
        )

        let result = try await cleanupTask.run(now: now)
        let remainingRefs = try await store.listWaveformBlobRefs()

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldestRef.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: middleRef.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newestRef.fileURL.path))
        XCTAssertEqual(remainingRefs.map(\.id), [middleRef.id, newestRef.id])
        XCTAssertEqual(result.deletedWaveformFileCount, 1)
        XCTAssertEqual(result.deletedWaveformBytes, oldestRef.fileSizeBytes)
        XCTAssertEqual(result.reclaimedBytes, oldestRef.fileSizeBytes)
    }

    func test_runArchivesMultipleRawSamplesIntoOneMinuteBucket() async throws {
        let store = try makeStore()
        let waveformStore = try WaveformFileStore(baseDirectory: tempDirectory)
        let sessionID = UUID()
        let now = Date(timeIntervalSince1970: 1_725_000_000)
        let oldDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: -8, to: now) ?? now

        try await store.saveHeartRateSamples([
            HeartRateSampleRecord(sessionID: sessionID, timestamp: oldDate, bpm: 60),
            HeartRateSampleRecord(sessionID: sessionID, timestamp: oldDate.addingTimeInterval(10), bpm: 66),
            HeartRateSampleRecord(sessionID: sessionID, timestamp: oldDate.addingTimeInterval(20), bpm: 72),
        ])
        try await store.saveRRSamples([
            RRSampleRecord(sessionID: sessionID, timestamp: oldDate, rrMs: 1000),
            RRSampleRecord(sessionID: sessionID, timestamp: oldDate.addingTimeInterval(10), rrMs: 900),
        ])

        let cleanupTask = RetentionCleanupTask(
            store: store,
            waveformFileStore: waveformStore,
            policy: RetentionPolicy(
                waveformRetentionDays: 7,
                rawSampleRetentionDays: 7,
                maxTotalStorageBytes: .max
            )
        )

        _ = try await cleanupTask.run(now: now)

        let archivedHeartRate = try await store.listArchivedHeartRateBuckets()
        let archivedRR = try await store.listArchivedRRBuckets()
        let remainingHeartRate = try await store.queryHeartRate(HeartRateQuery(sessionID: sessionID))
        let firstArchivedHeartRate = try XCTUnwrap(archivedHeartRate.first)
        let firstArchivedRR = try XCTUnwrap(archivedRR.first)

        XCTAssertTrue(remainingHeartRate.isEmpty)
        XCTAssertEqual(archivedHeartRate.count, 1)
        XCTAssertEqual(firstArchivedHeartRate.minBPM, 60)
        XCTAssertEqual(firstArchivedHeartRate.maxBPM, 72)
        XCTAssertEqual(firstArchivedHeartRate.avgBPM, 66, accuracy: 0.0001)
        XCTAssertEqual(firstArchivedHeartRate.sampleCount, 3)
        XCTAssertEqual(archivedRR.count, 1)
        XCTAssertEqual(firstArchivedRR.minRRMs, 900)
        XCTAssertEqual(firstArchivedRR.maxRRMs, 1000)
        XCTAssertEqual(firstArchivedRR.avgRRMs, 950, accuracy: 0.0001)
        XCTAssertEqual(firstArchivedRR.sampleCount, 2)
    }

    private func makeStore() throws -> SwiftDataStore {
        let container = try SwiftDataStore.makeModelContainer(isStoredInMemoryOnly: true)
        return SwiftDataStore(modelContainer: container)
    }

    private func writeRef(
        waveformStore: WaveformFileStore,
        sessionID: UUID,
        startTimestamp: Date,
        blockSeq: UInt32
    ) throws -> WaveformBlobRef {
        try waveformStore.writeChunks(
            sessionID: sessionID,
            type: .ecg,
            sampleRateHz: 128,
            sampleBits: 16,
            startTimestamp: startTimestamp,
            chunks: [
                WaveformFileChunk(
                    blockSeq: blockSeq,
                    timestampOffsetMs: 0,
                    samples: [12, -7, 30, 14, -3, 6]
                )
            ]
        )
    }
}
