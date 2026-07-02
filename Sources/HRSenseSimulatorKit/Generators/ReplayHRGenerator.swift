import Foundation
import HRSenseProtocol

/// Replay heart-rate generator from a CSV file.
/// CSV format: one row per sample — timestampMs,heartRate,rr1,rr2,...
public final class ReplayHRGenerator: DataGeneratorProtocol, @unchecked Sendable {
    public private(set) var mode: GeneratorMode = .replay

    private struct Row {
        let timestampMs: UInt32
        let heartRate: UInt16
        let rrIntervals: [UInt16]
    }

    private var rows: [Row] = []
    private var index: Int = 0
    private var sampleSeq: UInt32 = 0

    public init() {}

    /// Load replay data from a CSV file path.
    public func loadCSV(url: URL) throws {
        let content = try String(contentsOf: url, encoding: .utf8)
        let parser = CSVParser()
        rows = try parser.parse(content).compactMap { fields in
            guard fields.count >= 2 else { return nil }
            guard let ts = UInt32(fields[0]), let hr = UInt16(fields[1]) else { return nil }
            let rr = fields.dropFirst(2).compactMap { UInt16($0) }
            return Row(timestampMs: ts, heartRate: hr, rrIntervals: rr)
        }
    }

    /// Load from raw CSV content string.
    public func loadCSVString(_ content: String) throws {
        let parser = CSVParser()
        rows = try parser.parse(content).compactMap { fields in
            guard fields.count >= 2 else { return nil }
            guard let ts = UInt32(fields[0]), let hr = UInt16(fields[1]) else { return nil }
            let rr = fields.dropFirst(2).compactMap { UInt16($0) }
            return Row(timestampMs: ts, heartRate: hr, rrIntervals: rr)
        }
    }

    public func start() { index = 0; sampleSeq = 0 }
    public func stop() {}

    public func nextSample(timestampMs: UInt32) -> DeviceSample {
        let seq = sampleSeq
        sampleSeq += 1

        guard !rows.isEmpty else {
            return DeviceSample(timestamp: timestampMs, heartRate: 70, sampleSeq: seq)
        }
        let row = rows[index % rows.count]
        index += 1
        if index >= rows.count { index = 0 }

        return DeviceSample(
            timestamp: timestampMs,
            heartRate: row.heartRate,
            rrIntervals: row.rrIntervals,
            sampleSeq: seq
        )
    }
}
