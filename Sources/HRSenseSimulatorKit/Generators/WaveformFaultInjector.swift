import Foundation
import HRSenseProtocol

/// Fault injector for waveform blocks — supports drop, reorder, truncation.
public final class WaveformFaultInjector: @unchecked Sendable {
    public var blockDropProbability: Double = 0.0
    public var reorderProbability: Double = 0.0
    public var truncateProbability: Double = 0.0

    private let lock = NSLock()
    private var heldBlock: HRSenseProtocol.WaveformBlock? = nil

    public init() {}

    public func apply(_ block: HRSenseProtocol.WaveformBlock) -> [HRSenseProtocol.WaveformBlock] {
        lock.lock(); defer { lock.unlock() }

        if blockDropProbability > 0, Double.random(in: 0..<1) < blockDropProbability { return [] }

        var blk = block
        if truncateProbability > 0, Double.random(in: 0..<1) < truncateProbability, !blk.samples.isEmpty {
            let keep = max(1, Int(Double(blk.samples.count) * 0.5))
            blk = WaveformBlock(waveformType: blk.waveformType, sampleRateHz: blk.sampleRateHz,
                                 blockSeq: blk.blockSeq, startTimestampMs: blk.startTimestampMs,
                                 sampleBits: blk.sampleBits, samples: Array(blk.samples.prefix(keep)))
        }

        if reorderProbability > 0, Double.random(in: 0..<1) < reorderProbability {
            if let prev = heldBlock { heldBlock = blk; return [blk, prev] }
            else { heldBlock = blk; return [] }
        }

        let result: [HRSenseProtocol.WaveformBlock]
        if let prev = heldBlock { result = [prev, blk]; heldBlock = nil }
        else { result = [blk] }
        return result
    }
}
