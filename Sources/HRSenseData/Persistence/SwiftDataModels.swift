import Foundation
import SwiftData
import HRSenseCore

@Model
final class SessionModel {
    @Attribute(.unique) var id: UUID
    var deviceID: UUID
    var startAt: Date
    var endAt: Date?
    var firmwareVersion: String

    init(id: UUID, deviceID: UUID, startAt: Date, endAt: Date?, firmwareVersion: String) {
        self.id = id
        self.deviceID = deviceID
        self.startAt = startAt
        self.endAt = endAt
        self.firmwareVersion = firmwareVersion
    }

    convenience init(domain: Session) {
        self.init(
            id: domain.id,
            deviceID: domain.deviceID,
            startAt: domain.startAt,
            endAt: domain.endAt,
            firmwareVersion: domain.firmwareVersion
        )
    }

    func apply(_ domain: Session) {
        deviceID = domain.deviceID
        startAt = domain.startAt
        endAt = domain.endAt
        firmwareVersion = domain.firmwareVersion
    }

    func toDomain() -> Session {
        Session(id: id, deviceID: deviceID, startAt: startAt, endAt: endAt, firmwareVersion: firmwareVersion)
    }
}

@Model
final class HeartRateSampleModel {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var timestamp: Date
    var bpm: Int

    init(id: UUID, sessionID: UUID, timestamp: Date, bpm: Int) {
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.bpm = bpm
    }

    convenience init(domain: HeartRateSampleRecord) {
        self.init(id: domain.id, sessionID: domain.sessionID, timestamp: domain.timestamp, bpm: domain.bpm)
    }

    func apply(_ domain: HeartRateSampleRecord) {
        sessionID = domain.sessionID
        timestamp = domain.timestamp
        bpm = domain.bpm
    }

    func toDomain() -> HeartRateSampleRecord {
        HeartRateSampleRecord(id: id, sessionID: sessionID, timestamp: timestamp, bpm: bpm)
    }
}

@Model
final class RRSampleModel {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var timestamp: Date
    var rrMs: Int

    init(id: UUID, sessionID: UUID, timestamp: Date, rrMs: Int) {
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.rrMs = rrMs
    }

    convenience init(domain: RRSampleRecord) {
        self.init(id: domain.id, sessionID: domain.sessionID, timestamp: domain.timestamp, rrMs: domain.rrMs)
    }

    func apply(_ domain: RRSampleRecord) {
        sessionID = domain.sessionID
        timestamp = domain.timestamp
        rrMs = domain.rrMs
    }

    func toDomain() -> RRSampleRecord {
        RRSampleRecord(id: id, sessionID: sessionID, timestamp: timestamp, rrMs: rrMs)
    }
}

@Model
final class HRVMetricRecordModel {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var windowStart: Date
    var windowEnd: Date
    var sdnn: Double
    var rmssd: Double
    var pnn50: Double
    var meanRR: Double
    var hr: Double
    var lfPower: Double
    var hfPower: Double
    var lfHfRatio: Double
    var totalPower: Double
    var sd1: Double
    var sd2: Double
    var sampleEntropy: Double
    var dfaAlpha1: Double
    var stressIndex: Double

    init(id: UUID, sessionID: UUID, windowStart: Date, windowEnd: Date, metrics: HRVMetrics) {
        self.id = id
        self.sessionID = sessionID
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.sdnn = metrics.sdnn
        self.rmssd = metrics.rmssd
        self.pnn50 = metrics.pnn50
        self.meanRR = metrics.meanRR
        self.hr = metrics.hr
        self.lfPower = metrics.lfPower
        self.hfPower = metrics.hfPower
        self.lfHfRatio = metrics.lfHfRatio
        self.totalPower = metrics.totalPower
        self.sd1 = metrics.sd1
        self.sd2 = metrics.sd2
        self.sampleEntropy = metrics.sampleEntropy
        self.dfaAlpha1 = metrics.dfaAlpha1
        self.stressIndex = metrics.stressIndex
    }

    convenience init(domain: HRVMetricRecord) {
        self.init(
            id: domain.id,
            sessionID: domain.sessionID,
            windowStart: domain.windowStart,
            windowEnd: domain.windowEnd,
            metrics: domain.metrics
        )
    }

    func apply(_ domain: HRVMetricRecord) {
        sessionID = domain.sessionID
        windowStart = domain.windowStart
        windowEnd = domain.windowEnd
        sdnn = domain.metrics.sdnn
        rmssd = domain.metrics.rmssd
        pnn50 = domain.metrics.pnn50
        meanRR = domain.metrics.meanRR
        hr = domain.metrics.hr
        lfPower = domain.metrics.lfPower
        hfPower = domain.metrics.hfPower
        lfHfRatio = domain.metrics.lfHfRatio
        totalPower = domain.metrics.totalPower
        sd1 = domain.metrics.sd1
        sd2 = domain.metrics.sd2
        sampleEntropy = domain.metrics.sampleEntropy
        dfaAlpha1 = domain.metrics.dfaAlpha1
        stressIndex = domain.metrics.stressIndex
    }

    func toDomain() -> HRVMetricRecord {
        HRVMetricRecord(
            id: id,
            sessionID: sessionID,
            windowStart: windowStart,
            windowEnd: windowEnd,
            metrics: HRVMetrics(
                sdnn: sdnn,
                rmssd: rmssd,
                pnn50: pnn50,
                meanRR: meanRR,
                hr: hr,
                lfPower: lfPower,
                hfPower: hfPower,
                lfHfRatio: lfHfRatio,
                totalPower: totalPower,
                sd1: sd1,
                sd2: sd2,
                sampleEntropy: sampleEntropy,
                dfaAlpha1: dfaAlpha1,
                stressIndex: stressIndex
            )
        )
    }
}

@Model
final class InferenceRecordModel {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var timestamp: Date
    var label: String
    var confidence: Float
    var probabilitiesData: Data
    var modelVersion: String

    init(id: UUID, sessionID: UUID, timestamp: Date, label: String, confidence: Float, probabilitiesData: Data, modelVersion: String) {
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.label = label
        self.confidence = confidence
        self.probabilitiesData = probabilitiesData
        self.modelVersion = modelVersion
    }

    convenience init(domain: InferenceRecord) {
        self.init(
            id: domain.id,
            sessionID: domain.sessionID,
            timestamp: domain.timestamp,
            label: domain.label,
            confidence: domain.confidence,
            probabilitiesData: PersistenceJSONCodec.encode(domain.probabilities),
            modelVersion: domain.modelVersion
        )
    }

    func apply(_ domain: InferenceRecord) {
        sessionID = domain.sessionID
        timestamp = domain.timestamp
        label = domain.label
        confidence = domain.confidence
        probabilitiesData = PersistenceJSONCodec.encode(domain.probabilities)
        modelVersion = domain.modelVersion
    }

    func toDomain() -> InferenceRecord {
        InferenceRecord(
            id: id,
            sessionID: sessionID,
            timestamp: timestamp,
            label: label,
            confidence: confidence,
            probabilities: PersistenceJSONCodec.decode(probabilitiesData, defaultValue: [:]),
            modelVersion: modelVersion
        )
    }
}

@Model
final class SleepSessionModel {
    @Attribute(.unique) var id: UUID
    var date: Date
    var sourceSessionID: UUID?
    var stagesData: Data
    var modelVersion: String

    init(id: UUID, date: Date, sourceSessionID: UUID?, stagesData: Data, modelVersion: String) {
        self.id = id
        self.date = date
        self.sourceSessionID = sourceSessionID
        self.stagesData = stagesData
        self.modelVersion = modelVersion
    }

    convenience init(domain: SleepSession) {
        self.init(
            id: domain.id,
            date: domain.date,
            sourceSessionID: domain.sourceSessionID,
            stagesData: PersistenceJSONCodec.encode(domain.stages),
            modelVersion: domain.modelVersion
        )
    }

    func apply(_ domain: SleepSession) {
        date = domain.date
        sourceSessionID = domain.sourceSessionID
        stagesData = PersistenceJSONCodec.encode(domain.stages)
        modelVersion = domain.modelVersion
    }

    func toDomain() -> SleepSession {
        SleepSession(
            id: id,
            date: date,
            sourceSessionID: sourceSessionID,
            stages: PersistenceJSONCodec.decode(stagesData, defaultValue: []),
            modelVersion: modelVersion
        )
    }
}

@Model
final class WaveformBlobRefModel {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var typeRawValue: UInt8
    var sampleRateHz: Int
    var sampleBits: Int
    var startTimestamp: Date
    var filePath: String
    var checksumSHA256: String
    var fileSizeBytes: Int64

    init(
        id: UUID,
        sessionID: UUID,
        typeRawValue: UInt8,
        sampleRateHz: Int,
        sampleBits: Int,
        startTimestamp: Date,
        filePath: String,
        checksumSHA256: String,
        fileSizeBytes: Int64
    ) {
        self.id = id
        self.sessionID = sessionID
        self.typeRawValue = typeRawValue
        self.sampleRateHz = sampleRateHz
        self.sampleBits = sampleBits
        self.startTimestamp = startTimestamp
        self.filePath = filePath
        self.checksumSHA256 = checksumSHA256
        self.fileSizeBytes = fileSizeBytes
    }

    convenience init(domain: WaveformBlobRef) {
        self.init(
            id: domain.id,
            sessionID: domain.sessionID,
            typeRawValue: domain.type.rawValue,
            sampleRateHz: domain.sampleRateHz,
            sampleBits: domain.sampleBits,
            startTimestamp: domain.startTimestamp,
            filePath: domain.fileURL.path,
            checksumSHA256: domain.checksumSHA256,
            fileSizeBytes: domain.fileSizeBytes
        )
    }

    func apply(_ domain: WaveformBlobRef) {
        sessionID = domain.sessionID
        typeRawValue = domain.type.rawValue
        sampleRateHz = domain.sampleRateHz
        sampleBits = domain.sampleBits
        startTimestamp = domain.startTimestamp
        filePath = domain.fileURL.path
        checksumSHA256 = domain.checksumSHA256
        fileSizeBytes = domain.fileSizeBytes
    }

    func toDomain() -> WaveformBlobRef {
        WaveformBlobRef(
            id: id,
            sessionID: sessionID,
            type: WaveformType(rawValue: typeRawValue) ?? .ecg,
            sampleRateHz: sampleRateHz,
            sampleBits: sampleBits,
            startTimestamp: startTimestamp,
            fileURL: URL(fileURLWithPath: filePath),
            checksumSHA256: checksumSHA256,
            fileSizeBytes: fileSizeBytes
        )
    }
}

@Model
final class EventRecordModel {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var timestamp: Date
    var kind: String
    var payloadData: Data

    init(id: UUID, sessionID: UUID, timestamp: Date, kind: String, payloadData: Data) {
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.kind = kind
        self.payloadData = payloadData
    }

    convenience init(domain: EventRecord) {
        self.init(
            id: domain.id,
            sessionID: domain.sessionID,
            timestamp: domain.timestamp,
            kind: domain.kind,
            payloadData: PersistenceJSONCodec.encode(domain.payload)
        )
    }

    func apply(_ domain: EventRecord) {
        sessionID = domain.sessionID
        timestamp = domain.timestamp
        kind = domain.kind
        payloadData = PersistenceJSONCodec.encode(domain.payload)
    }

    func toDomain() -> EventRecord {
        EventRecord(
            id: id,
            sessionID: sessionID,
            timestamp: timestamp,
            kind: kind,
            payload: PersistenceJSONCodec.decode(payloadData, defaultValue: [:])
        )
    }
}

private enum PersistenceJSONCodec {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? encoder.encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ data: Data, defaultValue: T) -> T {
        guard let value = try? decoder.decode(T.self, from: data) else {
            return defaultValue
        }
        return value
    }
}
