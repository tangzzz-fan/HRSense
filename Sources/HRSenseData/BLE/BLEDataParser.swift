import Foundation
import HRSenseProtocol
import HRSenseCore

/// Maps HRSenseProtocol types → HRSenseCore domain entities.
/// Also maintains the t0 timestamp anchor for converting device-relative
/// timestamps to absolute wall-clock timestamps.
public final class BLEDataParser: @unchecked Sendable {

    /// The device's t0 — set when START_STREAM is confirmed.
    private var localT0: Date? = nil

    public init() {}

    /// Mark the START_STREAM acceptance time as the timestamp anchor.
    public func markT0() {
        localT0 = Date()
    }

    /// Reset the t0 anchor (on stop or disconnect).
    public func resetT0() {
        localT0 = nil
    }

    /// Convert a protocol DeviceSample into a domain HeartRateSample.
    /// - Parameter sample: the raw protocol sample.
    /// - Returns: a domain HeartRateSample with absolute timestamps.
    public func parseSample(_ sample: HRSenseProtocol.DeviceSample) -> HeartRateSample {
        let absTime: Date
        if let t0 = localT0 {
            absTime = t0.addingTimeInterval(Double(sample.timestamp) / 1000.0)
        } else {
            absTime = Date()
        }

        return HeartRateSample(
            timestamp: absTime,
            heartRate: Int(sample.heartRate ?? 0),
            rrIntervals: sample.rrIntervals.map { Int($0) },
            sampleSeq: sample.sampleSeq,
            sensorContact: sample.sensorStatus
        )
    }

    /// Parse device info from a HELLO_ACK response payload.
    /// - Parameters:
    ///   - peripheralID: the peripheral UUID.
    ///   - name: local name.
    ///   - protocolVersion: negotiated version.
    ///   - capabilities: capability bitmap raw value.
    ///   - model: model string bytes.
    ///   - firmwareVersion: firmware string bytes.
    /// - Returns: a populated DeviceInfo.
    public func parseDeviceInfo(
        peripheralID: UUID,
        name: String,
        protocolVersion: UInt8,
        capabilities: UInt32,
        model: String,
        firmwareVersion: String
    ) -> DeviceInfo {
        DeviceInfo(
            peripheralIdentifier: peripheralID,
            name: name,
            model: model,
            firmwareVersion: firmwareVersion,
            protocolVersion: protocolVersion,
            capabilities: capabilities
        )
    }

    /// Detect sample sequence gaps for loss statistics.
    /// Returns the number of lost samples between prevSeq and currentSeq.
    public static func detectGap(prevSeq: UInt32, currentSeq: UInt32) -> Int {
        let diff = Int(currentSeq) - Int(prevSeq)
        return max(0, diff - 1)
    }
}
