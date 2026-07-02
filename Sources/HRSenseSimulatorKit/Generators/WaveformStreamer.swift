import Foundation
import HRSenseProtocol

/// Streams waveform blocks via a high-throughput notify loop.
///
/// Uses a configurable block interval (default ~50ms; 20 blocks/s) and
/// integrates with the SimulatedPeripheral for GATT notify push.
public final class WaveformStreamer: @unchecked Sendable {

    /// Samples per block — computed from MTU and sample rate for optimal throughput.
    public let samplesPerBlock: Int

    /// Block interval in seconds.
    public let blockInterval: TimeInterval

    private let generator: WaveformGenerator
    private let faultInjector: WaveformFaultInjector
    private let throughputTracker: ThroughputTracker

    /// Callback: streamer produces a block → caller pushes via BLE.
    public var onBlock: ((Data) -> Void)?

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.hrsense.simulator.waveform")
    private var running = false

    public init(
        generator: WaveformGenerator,
        faultInjector: WaveformFaultInjector = WaveformFaultInjector(),
        throughputTracker: ThroughputTracker = ThroughputTracker(),
        mtu: Int = 185,
        blockInterval: TimeInterval = 0.05  // 20 blocks/second
    ) {
        self.generator = generator
        self.faultInjector = faultInjector
        self.throughputTracker = throughputTracker
        self.blockInterval = blockInterval
        self.samplesPerBlock = WaveformEncoder.maxSamplesPerBlock(mtu: mtu, sampleBits: 16)
    }

    public func start() {
        guard !running else { return }
        running = true
        throughputTracker.start()
        generator.reset()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: blockInterval)
        timer.setEventHandler { [weak self] in
            guard let self, self.running else { return }
            let block = self.generator.nextBlock(count: self.samplesPerBlock)

            let blocks = self.faultInjector.apply(block)
            for blk in blocks {
                let fragments = WaveformEncoder.encode(block: blk, seq: UInt8(blk.blockSeq & 0xFF), mtu: 185)
                for frag in fragments {
                    self.throughputTracker.recordBlock(bytes: frag.count)
                    DispatchQueue.main.async { self.onBlock?(frag) }
                }
            }
        }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        running = false
        timer?.cancel()
        timer = nil
    }

    public var throughputBytesPerSec: Double { throughputTracker.throughputBytesPerSec }
    public var blockLossRate: Double { throughputTracker.blockLossRate }
    public var blocksSent: Int { throughputTracker.blocksSent }
    public var faults: WaveformFaultInjector { faultInjector }
}
