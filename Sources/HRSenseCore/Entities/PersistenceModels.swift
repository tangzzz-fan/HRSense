import Foundation

/// A persisted monitoring session spanning one device connection window.
public struct Session: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let deviceID: UUID
    public let startAt: Date
    public let endAt: Date?
    public let firmwareVersion: String

    public init(
        id: UUID = UUID(),
        deviceID: UUID,
        startAt: Date,
        endAt: Date? = nil,
        firmwareVersion: String
    ) {
        self.id = id
        self.deviceID = deviceID
        self.startAt = startAt
        self.endAt = endAt
        self.firmwareVersion = firmwareVersion
    }
}

/// A heart-rate sample prepared for persistence.
public struct HeartRateSampleRecord: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let sessionID: UUID
    public let timestamp: Date
    public let bpm: Int

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        timestamp: Date,
        bpm: Int
    ) {
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.bpm = bpm
    }
}

/// An RR interval prepared for persistence.
public struct RRSampleRecord: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let sessionID: UUID
    public let timestamp: Date
    public let rrMs: Int

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        timestamp: Date,
        rrMs: Int
    ) {
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.rrMs = rrMs
    }
}

/// An HRV metrics window prepared for persistence.
public struct HRVMetricRecord: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let sessionID: UUID
    public let windowStart: Date
    public let windowEnd: Date
    public let metrics: HRVMetrics

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        windowStart: Date,
        windowEnd: Date,
        metrics: HRVMetrics
    ) {
        self.id = id
        self.sessionID = sessionID
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.metrics = metrics
    }
}

/// A stored inference result for historical review or replay.
public struct InferenceRecord: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let sessionID: UUID
    public let timestamp: Date
    public let label: String
    public let confidence: Float
    public let probabilities: [String: Float]
    public let modelVersion: String

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        timestamp: Date,
        label: String,
        confidence: Float,
        probabilities: [String: Float],
        modelVersion: String
    ) {
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.label = label
        self.confidence = confidence
        self.probabilities = probabilities
        self.modelVersion = modelVersion
    }
}

/// Sleep stage labels used by the future hypnogram and sleep model.
public enum SleepStage: String, Equatable, Sendable, Codable, CaseIterable {
    case wake
    case light
    case deep
    case rem
}

/// A time segment for one sleep stage.
public struct SleepStageSegment: Equatable, Sendable, Identifiable, Codable {
    public let id: UUID
    public let stage: SleepStage
    public let startAt: Date
    public let endAt: Date

    public init(
        id: UUID = UUID(),
        stage: SleepStage,
        startAt: Date,
        endAt: Date
    ) {
        self.id = id
        self.stage = stage
        self.startAt = startAt
        self.endAt = endAt
    }
}

/// A persisted sleep session assembled from stage segments.
public struct SleepSession: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let date: Date
    public let sourceSessionID: UUID?
    public let stages: [SleepStageSegment]
    public let modelVersion: String

    public init(
        id: UUID = UUID(),
        date: Date,
        sourceSessionID: UUID? = nil,
        stages: [SleepStageSegment],
        modelVersion: String
    ) {
        self.id = id
        self.date = date
        self.sourceSessionID = sourceSessionID
        self.stages = stages
        self.modelVersion = modelVersion
    }
}

/// Metadata for a waveform blob stored in the file system.
public struct WaveformBlobRef: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let sessionID: UUID
    public let type: WaveformType
    public let sampleRateHz: Int
    public let sampleBits: Int
    public let startTimestamp: Date
    public let fileURL: URL
    public let checksumSHA256: String
    public let fileSizeBytes: Int64

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        type: WaveformType,
        sampleRateHz: Int,
        sampleBits: Int,
        startTimestamp: Date,
        fileURL: URL,
        checksumSHA256: String,
        fileSizeBytes: Int64
    ) {
        self.id = id
        self.sessionID = sessionID
        self.type = type
        self.sampleRateHz = sampleRateHz
        self.sampleBits = sampleBits
        self.startTimestamp = startTimestamp
        self.fileURL = fileURL
        self.checksumSHA256 = checksumSHA256
        self.fileSizeBytes = fileSizeBytes
    }
}

/// A persisted device or application event bound to one session.
public struct EventRecord: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let sessionID: UUID
    public let timestamp: Date
    public let kind: String
    public let payload: [String: String]

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        timestamp: Date,
        kind: String,
        payload: [String: String] = [:]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.kind = kind
        self.payload = payload
    }
}

/// Generic time range filter for persistence queries.
public struct TimeRange: Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public func contains(_ date: Date) -> Bool {
        date >= start && date <= end
    }
}

/// Query options for session history.
public struct SessionQuery: Equatable, Sendable {
    public let deviceID: UUID?
    public let startedWithin: TimeRange?
    public let limit: Int?

    public init(
        deviceID: UUID? = nil,
        startedWithin: TimeRange? = nil,
        limit: Int? = nil
    ) {
        self.deviceID = deviceID
        self.startedWithin = startedWithin
        self.limit = limit
    }
}

/// Query options for heart-rate history.
public struct HeartRateQuery: Equatable, Sendable {
    public let sessionID: UUID
    public let range: TimeRange?
    public let limit: Int?

    public init(
        sessionID: UUID,
        range: TimeRange? = nil,
        limit: Int? = nil
    ) {
        self.sessionID = sessionID
        self.range = range
        self.limit = limit
    }
}

/// Query options for HRV history.
public struct HRVMetricQuery: Equatable, Sendable {
    public let sessionID: UUID
    public let range: TimeRange?

    public init(sessionID: UUID, range: TimeRange? = nil) {
        self.sessionID = sessionID
        self.range = range
    }
}

/// Query options for sleep-session history.
public struct SleepSessionQuery: Equatable, Sendable {
    public let dateRange: TimeRange?
    public let limit: Int?

    public init(dateRange: TimeRange? = nil, limit: Int? = nil) {
        self.dateRange = dateRange
        self.limit = limit
    }
}

/// Aggregation window size used by historical charts.
public enum HeartRateAggregationInterval: Equatable, Sendable {
    case minute
    case hour
    case day
}

/// One aggregated heart-rate bucket for trend charts.
public struct HeartRateAggregationBucket: Equatable, Sendable {
    public let bucketStart: Date
    public let minBPM: Int
    public let avgBPM: Double
    public let maxBPM: Int
    public let sampleCount: Int

    public init(
        bucketStart: Date,
        minBPM: Int,
        avgBPM: Double,
        maxBPM: Int,
        sampleCount: Int
    ) {
        self.bucketStart = bucketStart
        self.minBPM = minBPM
        self.avgBPM = avgBPM
        self.maxBPM = maxBPM
        self.sampleCount = sampleCount
    }
}

/// One archived minute/hour/day heart-rate bucket derived from raw samples.
public struct ArchivedHeartRateBucket: Equatable, Sendable, Identifiable {
    public let id: String
    public let sessionID: UUID
    public let interval: HeartRateAggregationInterval
    public let bucketStart: Date
    public let minBPM: Int
    public let avgBPM: Double
    public let maxBPM: Int
    public let sampleCount: Int

    public init(
        id: String,
        sessionID: UUID,
        interval: HeartRateAggregationInterval,
        bucketStart: Date,
        minBPM: Int,
        avgBPM: Double,
        maxBPM: Int,
        sampleCount: Int
    ) {
        self.id = id
        self.sessionID = sessionID
        self.interval = interval
        self.bucketStart = bucketStart
        self.minBPM = minBPM
        self.avgBPM = avgBPM
        self.maxBPM = maxBPM
        self.sampleCount = sampleCount
    }
}

/// Archived RR bucket derived from raw RR intervals for long-term retention.
public struct ArchivedRRBucket: Equatable, Sendable, Identifiable {
    public let id: String
    public let sessionID: UUID
    public let interval: HeartRateAggregationInterval
    public let bucketStart: Date
    public let minRRMs: Int
    public let avgRRMs: Double
    public let maxRRMs: Int
    public let sampleCount: Int

    public init(
        id: String,
        sessionID: UUID,
        interval: HeartRateAggregationInterval,
        bucketStart: Date,
        minRRMs: Int,
        avgRRMs: Double,
        maxRRMs: Int,
        sampleCount: Int
    ) {
        self.id = id
        self.sessionID = sessionID
        self.interval = interval
        self.bucketStart = bucketStart
        self.minRRMs = minRRMs
        self.avgRRMs = avgRRMs
        self.maxRRMs = maxRRMs
        self.sampleCount = sampleCount
    }
}

/// Retention knobs for future cleanup and archival tasks.
public struct RetentionPolicy: Equatable, Sendable {
    public let waveformRetentionDays: Int
    public let rawSampleRetentionDays: Int
    public let maxTotalStorageBytes: Int64

    public init(
        waveformRetentionDays: Int = 7,
        rawSampleRetentionDays: Int = 30,
        maxTotalStorageBytes: Int64 = 500 * 1024 * 1024
    ) {
        self.waveformRetentionDays = waveformRetentionDays
        self.rawSampleRetentionDays = rawSampleRetentionDays
        self.maxTotalStorageBytes = maxTotalStorageBytes
    }
}

/// Summary returned by cleanup tasks.
public struct StoragePurgeResult: Equatable, Sendable {
    public let deletedWaveformFileCount: Int
    public let deletedWaveformBytes: Int64
    public let deletedHeartRateSampleCount: Int
    public let deletedRRSampleCount: Int
    public let reclaimedBytes: Int64

    public init(
        deletedWaveformFileCount: Int = 0,
        deletedWaveformBytes: Int64 = 0,
        deletedHeartRateSampleCount: Int = 0,
        deletedRRSampleCount: Int = 0,
        reclaimedBytes: Int64 = 0
    ) {
        self.deletedWaveformFileCount = deletedWaveformFileCount
        self.deletedWaveformBytes = deletedWaveformBytes
        self.deletedHeartRateSampleCount = deletedHeartRateSampleCount
        self.deletedRRSampleCount = deletedRRSampleCount
        self.reclaimedBytes = reclaimedBytes
    }
}
