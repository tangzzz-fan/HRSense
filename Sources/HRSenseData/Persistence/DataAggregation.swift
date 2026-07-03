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
}
