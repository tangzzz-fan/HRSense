import Foundation
import HRSenseProtocol

/// Generator operating mode.
public enum GeneratorMode: Equatable, Sendable {
    case resting
    case exercise
    case manual(heartRate: Int)
    case anomaly
    case replay
}

/// Protocol for pluggable data generators.
/// Conformers produce DeviceSample values on demand.
public protocol DataGeneratorProtocol: AnyObject, Sendable {
    /// Current operating mode.
    var mode: GeneratorMode { get }

    /// Called when streaming starts.
    func start()

    /// Called when streaming stops.
    func stop()

    /// Produce the next sample at the given device-relative timestamp.
    /// - Parameter timestampMs: milliseconds since START_STREAM acceptance.
    /// - Returns: a DeviceSample ready for encoding.
    func nextSample(timestampMs: UInt32) -> DeviceSample
}
