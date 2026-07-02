import Foundation

/// Kinds of application data.
/// Defined in v1 protocol contract (doc 03 §6.1).
public enum DataKind: UInt8, Equatable, Sendable {
    case heartRate = 0x01
    case waveform  = 0x02
    case deviceStatus = 0x03
    case batch     = 0x04
}

/// A device-generated sensor sample.
/// Maps to the DataKind=0x01 (heart rate / RR) path.
public struct DeviceSample: Equatable, Sendable {
    /// Relative timestamp in ms from START_STREAM acceptance (t0).
    public let timestamp: UInt32
    /// Heart rate in bpm.
    public let heartRate: UInt16?
    /// RR intervals in ms (HRV input).
    public let rrIntervals: [UInt16]
    /// Battery percentage (0–100).
    public let battery: UInt8?
    /// Sensor contact / signal quality bitmask.
    public let sensorStatus: UInt8?
    /// Sample sequence number for loss detection.
    public let sampleSeq: UInt32?

    public init(
        timestamp: UInt32,
        heartRate: UInt16? = nil,
        rrIntervals: [UInt16] = [],
        battery: UInt8? = nil,
        sensorStatus: UInt8? = nil,
        sampleSeq: UInt32? = nil
    ) {
        self.timestamp = timestamp
        self.heartRate = heartRate
        self.rrIntervals = rrIntervals
        self.battery = battery
        self.sensorStatus = sensorStatus
        self.sampleSeq = sampleSeq
    }
}
