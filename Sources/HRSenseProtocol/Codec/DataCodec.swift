import Foundation

/// Encode / decode L4 data frames.
///
/// Data frame body layout:
///   DataKind(1B) | TLV Records ...
public enum DataCodec {
    /// Encode a DeviceSample into frame body bytes (DataKind=0x01).
    public static func encode(_ sample: DeviceSample) -> [UInt8] {
        var result: [UInt8] = []
        result.append(DataKind.heartRate.rawValue)

        var records: [TLVRecord] = []

        // timestamp (u32 LE)
        var ts = sample.timestamp.littleEndian
        var tsBytes: [UInt8] = []
        Swift.withUnsafeBytes(of: &ts) { tsBytes.append(contentsOf: $0) }
        records.append(TLVRecord(tag: .timestamp, value: tsBytes))

        // heart rate (u16 LE)
        if let hr = sample.heartRate {
            var hrLE = hr.littleEndian
            var hrBytes: [UInt8] = []
            Swift.withUnsafeBytes(of: &hrLE) { hrBytes.append(contentsOf: $0) }
            records.append(TLVRecord(tag: .heartRate, value: hrBytes))
        }

        // RR intervals (u16[] LE)
        if !sample.rrIntervals.isEmpty {
            var rrBytes: [UInt8] = []
            for rr in sample.rrIntervals {
                var v = rr.littleEndian
                Swift.withUnsafeBytes(of: &v) { rrBytes.append(contentsOf: $0) }
            }
            records.append(TLVRecord(tag: .rrIntervals, value: rrBytes))
        }

        // battery
        if let bat = sample.battery {
            records.append(TLVRecord(tag: .battery, value: [bat]))
        }

        // sensor status
        if let ss = sample.sensorStatus {
            records.append(TLVRecord(tag: .sensorStatus, value: [ss]))
        }

        // sampleSeq (u32 LE)
        if let seq = sample.sampleSeq {
            var s = seq.littleEndian
            var sBytes: [UInt8] = []
            Swift.withUnsafeBytes(of: &s) { sBytes.append(contentsOf: $0) }
            records.append(TLVRecord(tag: .sampleSeq, value: sBytes))
        }

        result.append(contentsOf: TLVEncoder.encode(records))
        return result
    }

    /// Decode frame body bytes into a DeviceSample.
    /// Returns nil on parse failure or unknown DataKind.
    public static func decode(body: [UInt8]) -> DeviceSample? {
        guard body.count >= 1 else { return nil }
        guard DataKind(rawValue: body[0]) != nil else { return nil }
        let tlvBytes = Array(body.dropFirst())

        let records: [TLVRecord]
        do {
            records = try TLVDecoder.decode(tlvBytes)
        } catch {
            return nil
        }

        var timestamp: UInt32 = 0
        var heartRate: UInt16? = nil
        var rrIntervals: [UInt16] = []
        var battery: UInt8? = nil
        var sensorStatus: UInt8? = nil
        var sampleSeq: UInt32? = nil

        for record in records {
            switch record.tag {
            case .timestamp:
                timestamp = decodeU32LE(record.value)
            case .heartRate:
                if record.value.count >= 2 {
                    heartRate = UInt16(record.value[0]) | (UInt16(record.value[1]) << 8)
                } else if record.value.count == 1 {
                    heartRate = UInt16(record.value[0])
                }
            case .rrIntervals:
                var rrs: [UInt16] = []
                let vals = record.value
                var i = 0
                while i + 1 < vals.count {
                    let rr = UInt16(vals[i]) | (UInt16(vals[i + 1]) << 8)
                    rrs.append(rr)
                    i += 2
                }
                rrIntervals = rrs
            case .battery:
                battery = record.value.first
            case .sensorStatus:
                sensorStatus = record.value.first
            case .sampleSeq:
                sampleSeq = decodeU32LE(record.value)
            default:
                break  // Unknown tag — skip (forward compat)
            }
        }

        return DeviceSample(
            timestamp: timestamp,
            heartRate: heartRate,
            rrIntervals: rrIntervals,
            battery: battery,
            sensorStatus: sensorStatus,
            sampleSeq: sampleSeq
        )
    }

    private static func decodeU32LE(_ bytes: [UInt8]) -> UInt32 {
        guard bytes.count >= 4 else {
            var val: UInt32 = 0
            for (i, b) in bytes.enumerated() {
                val |= UInt32(b) << (i * 8)
            }
            return val
        }
        return UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
    }
}
