import Foundation

/// Computes optimal MTU-related parameters for waveform streaming.
public enum MTUCalculator: Sendable {
    /// Calculate the maximum samples per block for a given ATT MTU.
    /// - Parameters:
    ///   - mtu: negotiated ATT MTU value.
    ///   - sampleBits: 12 or 16 bits per sample.
    /// - Returns: max samples that fit in one block.
    public static func maxSamplesPerBlock(mtu: Int, sampleBits: Int = 16) -> Int {
        let headerOverhead = 2       // FragHdr + seq
        let frameOverhead = 4        // Ver + Type + CRC16
        let dataKindOverhead = 1     // DataKind byte
        let tlvOverhead = 12         // ~12 bytes for tag+len fields (6 TLV entries × ~2 bytes)
        let payloadCapacity = mtu - headerOverhead - frameOverhead - dataKindOverhead - tlvOverhead
        let bytesPerSample = sampleBits / 8
        return max(1, payloadCapacity / bytesPerSample)
    }

    /// Calculate effective data throughput capacity in bytes/second.
    /// - Parameters:
    ///   - mtu: negotiated MTU.
    ///   - connectionIntervalMs: BLE connection interval in ms.
    /// - Returns: theoretical max bytes/second.
    public static func theoreticalThroughput(mtu: Int, connectionIntervalMs: Double = 30) -> Double {
        let packetsPerSecond = 1000.0 / connectionIntervalMs
        return Double(mtu) * packetsPerSecond
    }
}
