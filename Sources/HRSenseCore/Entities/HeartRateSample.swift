import Foundation

/// Domain entity: a heart rate sample received from the device.
public struct HeartRateSample: Equatable, Sendable {
    /// Local wall-clock timestamp (derived from device t0 + device-relative timestamp).
    public let timestamp: Date
    /// Heart rate in beats per minute.
    public let heartRate: Int
    /// RR intervals in milliseconds (HRV input).
    public let rrIntervals: [Int]
    /// Device sample sequence number (nil if not provided).
    public let sampleSeq: UInt32?
    /// Sensor contact status bitmask.
    public let sensorContact: UInt8?

    public init(
        timestamp: Date,
        heartRate: Int,
        rrIntervals: [Int] = [],
        sampleSeq: UInt32? = nil,
        sensorContact: UInt8? = nil
    ) {
        self.timestamp = timestamp
        self.heartRate = heartRate
        self.rrIntervals = rrIntervals
        self.sampleSeq = sampleSeq
        self.sensorContact = sensorContact
    }
}
