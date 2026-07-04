import Foundation

/// Receives GATT fragments and reassembles them into complete frames.
///
/// Thread-safety: this class is not thread-safe. All `feed()` calls must
/// be serialised on the same queue/dispatch context.
public final class FrameAssembler: @unchecked Sendable {

    /// Maximum allowed frame size to prevent memory exhaustion from
    /// malicious/malformed fragments. 64 KiB is generous for BLE frames.
    private static let maxFrameSize = 64 * 1024

    /// Track recently-completed frame identities to detect retransmitted duplicates
    /// without conflating different payload types that happen to reuse the same seq.
    private var seenFrameIdentities: Set<SeenFrameIdentity> = []
    private var seenFrameOrder: [SeenFrameIdentity] = []

    /// Currently in-progress partial frame (per seq).
    /// Keyed by seq; value is the list of fragments received so far (for multi-fragment frames).
    private var partialFrames: [UInt8: PartialFrame] = [:]

    /// Maximum distinct seq slots before we start evicting the oldest.
    /// Realistic BLE throughput: 10–100 frames/s; 16 slots covers several seconds of backlog.
    private static let maxPartialSlots = 16
    private static let maxSeenFrames = 256
    private static let duplicatePrefixLength = 16

    private struct PartialFrame {
        let totalFragments: Int?  // nil if unknown (last fragment not yet received)
        let rawPayload: [UInt8]   // accumulated payload (no per-fragment headers)

        init(fragments: [UInt8]) {
            self.totalFragments = nil
            self.rawPayload = fragments
        }

        init(totalFragments: Int?, rawPayload: [UInt8]) {
            self.totalFragments = totalFragments
            self.rawPayload = rawPayload
        }

        func appending(_ frag: [UInt8], totalFragments: Int?) -> PartialFrame {
            PartialFrame(
                totalFragments: totalFragments ?? self.totalFragments,
                rawPayload: self.rawPayload + frag
            )
        }
    }

    private struct SeenFrameIdentity: Hashable {
        let seq: UInt8
        let payloadCount: Int
        let payloadPrefix: [UInt8]
    }

    public init() {}

    /// Feed one GATT fragment (Data from a notify or write). Returns zero or more
    /// decoded frames. Multiple frames may be returned if the fragment completes
    /// more than one pending frame (edge case from batched processing).
    ///
    /// - Parameter fragment: raw bytes from a BLE characteristic read/notify.
    /// - Returns: array of DecodedFrame (0..n).
    public func feed(_ fragment: Data) -> [DecodedFrame] {
        feed([UInt8](fragment))
    }

    /// Feed raw bytes of one GATT fragment.
    public func feed(_ bytes: [UInt8]) -> [DecodedFrame] {
        guard bytes.count >= 2 else {
            // Fragment too short — cannot even hold FragHdr + seq
            return []
        }

        let hdr = FragmentHeader(rawValue: bytes[0])
        let seq = bytes[1]
        let payload = Array(bytes.dropFirst(2))

        let frameIdentity = makeSeenFrameIdentity(seq: seq, payload: payload)

        // Duplicate detection: only drop when the same seq and same frame signature
        // are seen again. Different frame kinds may legitimately reuse the same seq.
        if hdr.isSingleFragment, let frameIdentity, seenFrameIdentities.contains(frameIdentity) {
            return []
        }

        // For single-fragment frames, no reassembly needed — just one fragment is the whole frame
        if hdr.isSingleFragment {
            if let frameIdentity {
                recordSeenFrameIdentity(frameIdentity)
            }
            return decodeFullFrame(payload).map { [$0] } ?? []
        }

        // Multi-fragment frame
        if hdr.isStart {
            // New frame starting — evict oldest if we're over slot limit
            if partialFrames.count >= Self.maxPartialSlots {
                // Drop the oldest partial frame to make room
                if let oldestSeq = partialFrames.keys.first {
                    partialFrames.removeValue(forKey: oldestSeq)
                }
            }
            partialFrames[seq] = PartialFrame(fragments: payload)
            return []
        }

        // Middle or end fragment — must match an existing partial frame
        guard let pf = partialFrames[seq] else {
            // Orphan fragment (no start seen) — discard
            return []
        }

        if hdr.isEnd {
            // Final fragment — complete the frame
            let fullPayload = pf.rawPayload + payload
            partialFrames.removeValue(forKey: seq)

            if hdr.fragIndex == 0 {
                // Edge case: end fragment with idx 0 is still valid; continue
            }

            guard fullPayload.count <= Self.maxFrameSize else {
                // Oversized — discard
                return []
            }

            if let frameIdentity = makeSeenFrameIdentity(seq: seq, payload: fullPayload) {
                recordSeenFrameIdentity(frameIdentity)
            }

            return decodeFullFrame(fullPayload).map { [$0] } ?? []
        } else {
            // Middle fragment — accumulate
            partialFrames[seq] = pf.appending(payload, totalFragments: nil)
            return []
        }
    }

    /// Decode a complete frame payload (Ver + Type + Body + CRC16) into a DecodedFrame.
    /// Returns nil if CRC mismatch, unknown version, or decode error.
    private func decodeFullFrame(_ bytes: [UInt8]) -> DecodedFrame? {
        guard bytes.count >= 4 else { return nil } // Ver + Type + CRC16 minimum

        let bodyEnd = bytes.count - 2
        let frameMinusCRC = bytes[0..<bodyEnd]
        let crcBytes = bytes[bodyEnd...]
        let declaredCRC = UInt16(crcBytes[bodyEnd]) | (UInt16(crcBytes[bodyEnd + 1]) << 8)

        let computedCRC = CRC16.compute(frameMinusCRC)
        guard declaredCRC == computedCRC else {
            return nil  // CRC mismatch — frame corrupt, discard
        }

        let version = bytes[0]
        guard let type = FrameType(rawValue: bytes[1]) else {
            return nil  // Unknown frame type
        }
        let body = Array(bytes[2..<bodyEnd])

        // Only v1 supported for now
        guard version == ProtocolVersion.v1 else {
            return nil
        }

        switch type {
        case .command:
            guard let command = CommandCodec.decode(body: body) else { return nil }
            return .command(command)
        case .protobufCommand:
            guard let command = ProtobufCommandCodec.decode(body: body) else { return nil }
            return .command(command)
        case .data:
            // Route by DataKind: 0x01 → DeviceSample, 0x02 → WaveformBlock
            if body.first == DataKind.waveform.rawValue {
                guard let wf = WaveformDecoder.decode(body: body) else { return nil }
                return .waveform(wf)
            }
            guard let sample = DataCodec.decode(body: body) else { return nil }
            return .data(sample)
        case .ack:
            guard let ack = ACKCodec.decode(body: body) else { return nil }
            return .ack(ack)
        case .event:
            guard let event = EventCodec.decode(body: body) else { return nil }
            return .event(event)
        }
    }

    private func makeSeenFrameIdentity(seq: UInt8, payload: [UInt8]) -> SeenFrameIdentity? {
        guard !payload.isEmpty else { return nil }
        return SeenFrameIdentity(
            seq: seq,
            payloadCount: payload.count,
            payloadPrefix: Array(payload.prefix(Self.duplicatePrefixLength))
        )
    }

    private func recordSeenFrameIdentity(_ identity: SeenFrameIdentity) {
        guard seenFrameIdentities.insert(identity).inserted else { return }
        seenFrameOrder.append(identity)
        if seenFrameOrder.count > Self.maxSeenFrames {
            let oldest = seenFrameOrder.removeFirst()
            seenFrameIdentities.remove(oldest)
        }
    }

    /// Reset assembler state (e.g., on disconnect).
    public func reset() {
        seenFrameIdentities.removeAll()
        seenFrameOrder.removeAll()
        partialFrames.removeAll()
    }
}
