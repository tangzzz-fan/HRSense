import Foundation
import HRSenseCore

enum DataAggregation {
    static func aggregateHeartRate(
        _ samples: [HeartRateSampleRecord],
        interval: HeartRateAggregationInterval,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [HeartRateAggregationBucket] {
        var grouped: [Date: [HeartRateSampleRecord]] = [:]

        for sample in samples {
            let bucketStart = bucketStart(for: sample.timestamp, interval: interval, calendar: calendar)
            grouped[bucketStart, default: []].append(sample)
        }

        return grouped
            .keys
            .sorted()
            .compactMap { bucketStart in
                guard let bucketSamples = grouped[bucketStart], !bucketSamples.isEmpty else { return nil }
                let bpmValues = bucketSamples.map(\.bpm)
                let total = bpmValues.reduce(0, +)
                return HeartRateAggregationBucket(
                    bucketStart: bucketStart,
                    minBPM: bpmValues.min() ?? 0,
                    avgBPM: Double(total) / Double(bpmValues.count),
                    maxBPM: bpmValues.max() ?? 0,
                    sampleCount: bpmValues.count
                )
            }
    }

    static func bucketStart(
        for date: Date,
        interval: HeartRateAggregationInterval,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Date {
        switch interval {
        case .minute:
            return calendar.dateInterval(of: .minute, for: date)?.start ?? date
        case .hour:
            return calendar.dateInterval(of: .hour, for: date)?.start ?? date
        case .day:
            return calendar.startOfDay(for: date)
        }
    }

    static func archiveHeartRate(
        _ samples: [HeartRateSampleRecord],
        interval: HeartRateAggregationInterval,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [ArchivedHeartRateBucket] {
        let grouped = Dictionary(grouping: samples) { sample in
            ArchiveGroupingKey(
                sessionID: sample.sessionID,
                bucketStart: bucketStart(for: sample.timestamp, interval: interval, calendar: calendar)
            )
        }

        return grouped
            .keys
            .sorted()
            .compactMap { key in
                guard let bucketSamples = grouped[key], !bucketSamples.isEmpty else { return nil }
                let bpmValues = bucketSamples.map(\.bpm)
                let total = bpmValues.reduce(0, +)
                return ArchivedHeartRateBucket(
                    id: archiveID(sessionID: key.sessionID, bucketStart: key.bucketStart, interval: interval),
                    sessionID: key.sessionID,
                    interval: interval,
                    bucketStart: key.bucketStart,
                    minBPM: bpmValues.min() ?? 0,
                    avgBPM: Double(total) / Double(bpmValues.count),
                    maxBPM: bpmValues.max() ?? 0,
                    sampleCount: bpmValues.count
                )
            }
    }

    static func archiveRR(
        _ samples: [RRSampleRecord],
        interval: HeartRateAggregationInterval,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [ArchivedRRBucket] {
        let grouped = Dictionary(grouping: samples) { sample in
            ArchiveGroupingKey(
                sessionID: sample.sessionID,
                bucketStart: bucketStart(for: sample.timestamp, interval: interval, calendar: calendar)
            )
        }

        return grouped
            .keys
            .sorted()
            .compactMap { key in
                guard let bucketSamples = grouped[key], !bucketSamples.isEmpty else { return nil }
                let rrValues = bucketSamples.map(\.rrMs)
                let total = rrValues.reduce(0, +)
                return ArchivedRRBucket(
                    id: archiveID(sessionID: key.sessionID, bucketStart: key.bucketStart, interval: interval),
                    sessionID: key.sessionID,
                    interval: interval,
                    bucketStart: key.bucketStart,
                    minRRMs: rrValues.min() ?? 0,
                    avgRRMs: Double(total) / Double(rrValues.count),
                    maxRRMs: rrValues.max() ?? 0,
                    sampleCount: rrValues.count
                )
            }
    }

    private static func archiveID(
        sessionID: UUID,
        bucketStart: Date,
        interval: HeartRateAggregationInterval
    ) -> String {
        let epochSeconds = Int64(bucketStart.timeIntervalSince1970.rounded())
        return "\(sessionID.uuidString)-\(interval.archiveComponent)-\(epochSeconds)"
    }
}

private struct ArchiveGroupingKey: Hashable, Comparable {
    let sessionID: UUID
    let bucketStart: Date

    static func < (lhs: ArchiveGroupingKey, rhs: ArchiveGroupingKey) -> Bool {
        if lhs.sessionID == rhs.sessionID {
            return lhs.bucketStart < rhs.bucketStart
        }
        return lhs.sessionID.uuidString < rhs.sessionID.uuidString
    }
}

private extension HeartRateAggregationInterval {
    var archiveComponent: String {
        switch self {
        case .minute:
            return "minute"
        case .hour:
            return "hour"
        case .day:
            return "day"
        }
    }
}
