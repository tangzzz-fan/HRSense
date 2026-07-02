import Foundation

/// Fault injector for simulating BLE link impairments.
///
/// Applies to outbound data frames:
///   - dropProbability: randomly discard a packet (0.0–1.0)
///   - corruptCRCProbability: flip a byte in the frame body (0.0–1.0)
///   - latencyMilliseconds: add artificial delay (range)
public final class FaultInjector: @unchecked Sendable {
    /// Probability (0.0–1.0) that a packet is dropped. 0 = no drops.
    public var dropProbability: Double = 0.0

    /// Probability (0.0–1.0) that CRC is corrupted. 0 = no corruption.
    public var corruptCRCProbability: Double = 0.0

    /// Optional latency range in milliseconds. nil = no added latency.
    public var latencyMilliseconds: Range<Int>?

    public init() {}

    /// Apply faults to a frame payload. Returns nil if the packet is dropped.
    /// - Parameter data: the encoded frame Data.
    /// - Returns: the (possibly modified) Data, or nil if dropped.
    public func apply(_ data: Data) -> Data? {
        // Drop
        if dropProbability > 0, Double.random(in: 0..<1) < dropProbability {
            return nil
        }

        var bytes = [UInt8](data)

        // CRC corruption: flip a random byte in the body
        if corruptCRCProbability > 0, Double.random(in: 0..<1) < corruptCRCProbability {
            if bytes.count > 2 {
                let idx = Int.random(in: 2..<bytes.count)
                bytes[idx] ^= 0xFF
            }
        }

        return Data(bytes)
    }
}
