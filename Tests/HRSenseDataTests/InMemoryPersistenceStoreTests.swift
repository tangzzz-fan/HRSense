import XCTest
@testable import HRSenseCore
@testable import HRSenseData

final class InMemoryPersistenceStoreTests: XCTestCase {
    func test_querySessionsFiltersByDeviceAndReturnsNewestFirst() async throws {
        let store = InMemoryPersistenceStore()
        let deviceID = UUID()
        let otherDeviceID = UUID()
        let now = Date(timeIntervalSince1970: 1_725_000_000)

        try await store.saveSession(
            Session(deviceID: deviceID, startAt: now.addingTimeInterval(-600), firmwareVersion: "1.0.0")
        )
        try await store.saveSession(
            Session(deviceID: otherDeviceID, startAt: now.addingTimeInterval(-300), firmwareVersion: "1.0.1")
        )
        let latest = Session(deviceID: deviceID, startAt: now, firmwareVersion: "1.0.2")
        try await store.saveSession(latest)

        let sessions = try await store.querySessions(SessionQuery(deviceID: deviceID))

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.first?.id, latest.id)
        XCTAssertTrue(sessions.allSatisfy { $0.deviceID == deviceID })
    }

    func test_queryHeartRateRespectsTimeRangeAndLimit() async throws {
        let store = InMemoryPersistenceStore()
        let sessionID = UUID()
        let base = Date(timeIntervalSince1970: 1_725_000_000)

        try await store.saveHeartRateSamples([
            HeartRateSampleRecord(sessionID: sessionID, timestamp: base, bpm: 70),
            HeartRateSampleRecord(sessionID: sessionID, timestamp: base.addingTimeInterval(10), bpm: 72),
            HeartRateSampleRecord(sessionID: sessionID, timestamp: base.addingTimeInterval(20), bpm: 74),
        ])

        let records = try await store.queryHeartRate(
            HeartRateQuery(
                sessionID: sessionID,
                range: TimeRange(start: base.addingTimeInterval(5), end: base.addingTimeInterval(25)),
                limit: 1
            )
        )

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.bpm, 74)
    }

    func test_aggregateHeartRateBuildsMinuteBuckets() async throws {
        let store = InMemoryPersistenceStore()
        let sessionID = UUID()
        let base = Date(timeIntervalSince1970: 1_725_000_000)

        try await store.saveHeartRateSamples([
            HeartRateSampleRecord(sessionID: sessionID, timestamp: base, bpm: 60),
            HeartRateSampleRecord(sessionID: sessionID, timestamp: base.addingTimeInterval(15), bpm: 66),
            HeartRateSampleRecord(sessionID: sessionID, timestamp: base.addingTimeInterval(75), bpm: 72),
        ])

        let buckets = try await store.aggregateHeartRate(
            sessionID: sessionID,
            interval: .minute,
            range: nil
        )

        XCTAssertEqual(buckets.count, 2)
        XCTAssertEqual(buckets[0].minBPM, 60)
        XCTAssertEqual(buckets[0].maxBPM, 66)
        XCTAssertEqual(buckets[0].avgBPM, 63, accuracy: 0.0001)
        XCTAssertEqual(buckets[0].sampleCount, 2)
        XCTAssertEqual(buckets[1].avgBPM, 72, accuracy: 0.0001)
    }

    func test_purgeExpiredDataRemovesOldWaveformsAndRawSamples() async throws {
        let store = InMemoryPersistenceStore()
        let sessionID = UUID()
        let now = Date(timeIntervalSince1970: 1_725_000_000)
        let oldDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: -40, to: now) ?? now
        let recentDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: -2, to: now) ?? now

        try await store.saveHeartRateSamples([
            HeartRateSampleRecord(sessionID: sessionID, timestamp: oldDate, bpm: 62),
            HeartRateSampleRecord(sessionID: sessionID, timestamp: recentDate, bpm: 68),
        ])
        try await store.saveRRSamples([
            RRSampleRecord(sessionID: sessionID, timestamp: oldDate, rrMs: 820),
            RRSampleRecord(sessionID: sessionID, timestamp: recentDate, rrMs: 780),
        ])
        try await store.saveWaveformBlobRefs([
            WaveformBlobRef(
                sessionID: sessionID,
                type: .ecg,
                sampleRateHz: 128,
                sampleBits: 16,
                startTimestamp: oldDate,
                fileURL: URL(fileURLWithPath: "/tmp/old.bin"),
                checksumSHA256: "old",
                fileSizeBytes: 4096
            ),
            WaveformBlobRef(
                sessionID: sessionID,
                type: .ppg,
                sampleRateHz: 128,
                sampleBits: 16,
                startTimestamp: recentDate,
                fileURL: URL(fileURLWithPath: "/tmp/recent.bin"),
                checksumSHA256: "recent",
                fileSizeBytes: 2048
            ),
        ])

        let result = try await store.purgeExpiredData(now: now, policy: RetentionPolicy())
        let remainingSamples = try await store.queryHeartRate(HeartRateQuery(sessionID: sessionID))

        XCTAssertEqual(result.deletedWaveformFileCount, 1)
        XCTAssertEqual(result.deletedWaveformBytes, 4096)
        XCTAssertEqual(result.deletedHeartRateSampleCount, 1)
        XCTAssertEqual(result.deletedRRSampleCount, 1)
        XCTAssertEqual(result.reclaimedBytes, 4096)
        XCTAssertEqual(remainingSamples.map(\.bpm), [68])
    }

    func test_querySleepSessionsReturnsLatestSessionsFirst() async throws {
        let store = InMemoryPersistenceStore()
        let older = SleepSession(
            date: Date(timeIntervalSince1970: 1_725_000_000),
            stages: [
                SleepStageSegment(
                    stage: .light,
                    startAt: Date(timeIntervalSince1970: 1_725_000_000),
                    endAt: Date(timeIntervalSince1970: 1_725_000_600)
                )
            ],
            modelVersion: "sleep-placeholder-v1"
        )
        let newer = SleepSession(
            date: Date(timeIntervalSince1970: 1_725_086_400),
            stages: [
                SleepStageSegment(
                    stage: .deep,
                    startAt: Date(timeIntervalSince1970: 1_725_086_400),
                    endAt: Date(timeIntervalSince1970: 1_725_087_000)
                )
            ],
            modelVersion: "sleep-placeholder-v1"
        )

        try await store.saveSleepSession(older)
        try await store.saveSleepSession(newer)

        let sessions = try await store.querySleepSessions(SleepSessionQuery(limit: 1))

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, newer.id)
    }
}
