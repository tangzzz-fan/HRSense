import XCTest
import SwiftData
@testable import HRSenseCore
@testable import HRSenseData

final class SwiftDataStoreTests: XCTestCase {
    func test_saveAndQuerySessionsReturnsNewestFirst() async throws {
        let store = try makeStore()
        let deviceID = UUID()
        let base = Date(timeIntervalSince1970: 1_725_000_000)

        try await store.saveSession(
            Session(deviceID: deviceID, startAt: base.addingTimeInterval(-300), firmwareVersion: "1.0.0")
        )
        let latest = Session(deviceID: deviceID, startAt: base, firmwareVersion: "1.0.1")
        try await store.saveSession(latest)

        let sessions = try await store.querySessions(SessionQuery(deviceID: deviceID))

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.first?.id, latest.id)
    }

    func test_saveHeartRateAndAggregateByMinute() async throws {
        let store = try makeStore()
        let sessionID = UUID()
        let base = Date(timeIntervalSince1970: 1_725_000_000)

        try await store.saveHeartRateSamples([
            HeartRateSampleRecord(sessionID: sessionID, timestamp: base, bpm: 61),
            HeartRateSampleRecord(sessionID: sessionID, timestamp: base.addingTimeInterval(10), bpm: 65),
            HeartRateSampleRecord(sessionID: sessionID, timestamp: base.addingTimeInterval(75), bpm: 72),
        ])

        let buckets = try await store.aggregateHeartRate(
            sessionID: sessionID,
            interval: .minute,
            range: nil
        )

        XCTAssertEqual(buckets.count, 2)
        XCTAssertEqual(buckets[0].avgBPM, 63, accuracy: 0.0001)
        XCTAssertEqual(buckets[1].maxBPM, 72)
    }

    func test_saveSleepSessionRoundTripsThroughSwiftDataMapping() async throws {
        let store = try makeStore()
        let sleep = SleepSession(
            date: Date(timeIntervalSince1970: 1_725_000_000),
            stages: [
                SleepStageSegment(
                    stage: .light,
                    startAt: Date(timeIntervalSince1970: 1_725_000_000),
                    endAt: Date(timeIntervalSince1970: 1_725_000_300)
                ),
                SleepStageSegment(
                    stage: .deep,
                    startAt: Date(timeIntervalSince1970: 1_725_000_300),
                    endAt: Date(timeIntervalSince1970: 1_725_000_900)
                ),
            ],
            modelVersion: "sleep-placeholder-v1"
        )

        try await store.saveSleepSession(sleep)
        let sessions = try await store.querySleepSessions(SleepSessionQuery())

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first, sleep)
    }

    func test_purgeExpiredDataRemovesOldStructuredRecords() async throws {
        let store = try makeStore()
        let sessionID = UUID()
        let now = Date(timeIntervalSince1970: 1_725_000_000)
        let oldDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: -40, to: now) ?? now
        let recentDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: -2, to: now) ?? now

        try await store.saveHeartRateSamples([
            HeartRateSampleRecord(sessionID: sessionID, timestamp: oldDate, bpm: 59),
            HeartRateSampleRecord(sessionID: sessionID, timestamp: recentDate, bpm: 66),
        ])
        try await store.saveRRSamples([
            RRSampleRecord(sessionID: sessionID, timestamp: oldDate, rrMs: 900),
            RRSampleRecord(sessionID: sessionID, timestamp: recentDate, rrMs: 780),
        ])
        try await store.saveWaveformBlobRefs([
            WaveformBlobRef(
                sessionID: sessionID,
                type: .ecg,
                sampleRateHz: 128,
                sampleBits: 16,
                startTimestamp: oldDate,
                fileURL: URL(fileURLWithPath: "/tmp/expired-waveform.bin"),
                checksumSHA256: "expired",
                fileSizeBytes: 5120
            )
        ])

        let result = try await store.purgeExpiredData(now: now, policy: RetentionPolicy())
        let remainingHeartRate = try await store.queryHeartRate(HeartRateQuery(sessionID: sessionID))

        XCTAssertEqual(result.deletedWaveformFileCount, 1)
        XCTAssertEqual(result.deletedHeartRateSampleCount, 1)
        XCTAssertEqual(result.deletedRRSampleCount, 1)
        XCTAssertEqual(result.reclaimedBytes, 5120)
        XCTAssertEqual(remainingHeartRate.map(\.bpm), [66])
    }

    private func makeStore() throws -> SwiftDataStore {
        let container = try SwiftDataStore.makeModelContainer(isStoredInMemoryOnly: true)
        return SwiftDataStore(modelContainer: container)
    }
}
