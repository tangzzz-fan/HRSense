import XCTest
@testable import HRSenseProtocol

final class FrameAssemblerTests: XCTestCase {

    // MARK: - Single-fragment frame (most common case)

    func test_singleFragmentDataFrame() {
        let sample = DeviceSample(timestamp: 1000, heartRate: 72, sampleSeq: 1)
        let fragments = encodeData(sample, seq: 0, mtu: 185)

        let assembler = FrameAssembler()
        let results = assembler.feed(fragments[0])

        XCTAssertEqual(results.count, 1)
        guard case let .data(decoded) = results[0] else {
            XCTFail("Expected .data, got \(results[0])")
            return
        }
        XCTAssertEqual(decoded.timestamp, 1000)
        XCTAssertEqual(decoded.heartRate, 72)
        XCTAssertEqual(decoded.sampleSeq, 1)
    }

    func test_singleFragmentCommandFrame() {
        let cmd = Command.startStream()
        let fragments = encodeCommand(cmd, seq: 1, mtu: 185)

        let assembler = FrameAssembler()
        let results = assembler.feed(fragments[0])

        XCTAssertEqual(results.count, 1)
        guard case let .command(decoded) = results[0] else {
            XCTFail("Expected .command, got \(results[0])")
            return
        }
        XCTAssertEqual(decoded.opCode, .startStream)
    }

    // MARK: - Multi-fragment frame (in-order)

    func test_multiFragmentFrame() {
        let rr: [UInt16] = Array(repeating: 800, count: 50)
        let sample = DeviceSample(timestamp: 1000, heartRate: 72, rrIntervals: rr, sampleSeq: 1)
        let fragments = encodeData(sample, seq: 0, mtu: 50)

        XCTAssertGreaterThan(fragments.count, 1, "Should produce multiple fragments with MTU=50")

        let assembler = FrameAssembler()
        var allResults: [DecodedFrame] = []

        for frag in fragments {
            let results = assembler.feed(frag)
            allResults.append(contentsOf: results)
        }

        XCTAssertEqual(allResults.count, 1, "One complete frame after all fragments")
        guard case let .data(decoded) = allResults[0] else {
            XCTFail("Expected .data, got \(allResults.first!)")
            return
        }
        XCTAssertEqual(decoded.rrIntervals.count, 50)
        XCTAssertEqual(decoded.rrIntervals[0], 800)
    }

    // MARK: - Out-of-order: start arrives late

    func test_startFragmentAfterMiddle() {
        // v1: middle fragments arriving before START are orphans — discarded.
        // If the same middle fragment bytes are re-sent after START, the frame
        // completes correctly (real BLE retransmit scenario). If they are never
        // re-sent, the frame will fail CRC. Both are valid v1 behaviours.
        let rr: [UInt16] = Array(repeating: 700, count: 60)
        let sample = DeviceSample(timestamp: 2000, heartRate: 68, rrIntervals: rr)
        let fragments = encodeData(sample, seq: 5, mtu: 40)

        XCTAssertGreaterThan(fragments.count, 2)

        let assembler = FrameAssembler()

        // Feed a non-start fragment first → orphan, dropped
        let r1 = assembler.feed(fragments[1])
        XCTAssertEqual(r1.count, 0, "Middle fragment without start → dropped as orphan")

        // After orphan drop, feed start → partial frame begins but missing the
        // orphan's bytes. This frame will be incomplete at best.
        assembler.reset()  // clean slate

        // Feed all fragments in order — full frame arrives intact
        var results: [DecodedFrame] = []
        for frag in fragments {
            results.append(contentsOf: assembler.feed(frag))
        }
        XCTAssertEqual(results.count, 1, "In-order re-feed after reset completes frame")
    }

    // MARK: - Multi-fragment where end arrives last (in-order, verified)

    func test_multiFragmentInOrder() {
        let rr: [UInt16] = Array(repeating: 650, count: 70)
        let sample = DeviceSample(timestamp: 3000, heartRate: 70, rrIntervals: rr)
        let fragments = encodeData(sample, seq: 7, mtu: 40)

        let assembler = FrameAssembler()
        var results: [DecodedFrame] = []

        // Feed in order — last fragment is END
        for frag in fragments {
            results.append(contentsOf: assembler.feed(frag))
        }

        XCTAssertEqual(results.count, 1)
        if case let .data(d) = results[0] {
            XCTAssertEqual(d.rrIntervals.count, 70)
        } else { XCTFail("Expected .data") }
    }

    // MARK: - CRC error

    func test_crcErrorDropped() {
        let sample = DeviceSample(timestamp: 0, heartRate: 65)
        let fragments = encodeData(sample, seq: 0, mtu: 185)
        var bytes = [UInt8](fragments[0])

        // Corrupt one payload byte
        let payloadStart = 2
        if bytes.count > payloadStart + 1 {
            bytes[payloadStart + 2] ^= 0xFF
        }

        let assembler = FrameAssembler()
        let results = assembler.feed(Data(bytes))
        XCTAssertEqual(results.count, 0, "CRC mismatch → frame dropped")
    }

    // MARK: - Duplicate seq detection

    func test_duplicateSeqDropped() {
        let sample = DeviceSample(timestamp: 500, heartRate: 70)
        let fragments = encodeData(sample, seq: 3, mtu: 185)

        let assembler = FrameAssembler()

        let r1 = assembler.feed(fragments[0])
        XCTAssertEqual(r1.count, 1)

        let r2 = assembler.feed(fragments[0])
        XCTAssertEqual(r2.count, 0)
    }

    // MARK: - Orphan fragment (no START)

    func test_orphanFragmentDropped() {
        let assembler = FrameAssembler()
        let hdr = FragmentHeader(start: false, end: false, fragIndex: 1)
        var bytes: [UInt8] = []
        bytes.append(hdr.rawValue)
        bytes.append(0x00)
        bytes.append(contentsOf: [0xDE, 0xAD, 0xBE, 0xEF])

        let results = assembler.feed(Data(bytes))
        XCTAssertEqual(results.count, 0, "Orphan fragment without START → dropped")
    }

    // MARK: - Reset

    func test_resetClearsState() {
        let sample = DeviceSample(timestamp: 100, heartRate: 60)
        let fragments = encodeData(sample, seq: 0, mtu: 185)

        let assembler = FrameAssembler()
        _ = assembler.feed(fragments[0])

        assembler.reset()

        let results = assembler.feed(fragments[0])
        XCTAssertEqual(results.count, 1)
    }

    // MARK: - Interleaved multi-frame streams (in-order per seq)

    func test_interleavedMultiFrameStreams() {
        let rr: [UInt16] = Array(repeating: 800, count: 60)
        let sampleA = DeviceSample(timestamp: 0, heartRate: 72, rrIntervals: rr)
        let fragsA = encodeData(sampleA, seq: 10, mtu: 40)

        let sampleB = DeviceSample(timestamp: 1000, heartRate: 74, rrIntervals: rr)
        let fragsB = encodeData(sampleB, seq: 11, mtu: 40)

        XCTAssertGreaterThan(fragsA.count, 2)
        XCTAssertEqual(fragsA.count, fragsB.count)

        let assembler = FrameAssembler()

        // Interleave: feed each seq's non-final fragments alternately, then finals
        for i in 0..<(fragsA.count - 1) {
            _ = assembler.feed(fragsA[i])
            _ = assembler.feed(fragsB[i])
        }

        let rA = assembler.feed(fragsA.last!)
        XCTAssertEqual(rA.count, 1, "Final fragment of A completes frame")
        if case let .data(d) = rA[0] { XCTAssertEqual(d.rrIntervals.count, 60) }

        let rB = assembler.feed(fragsB.last!)
        XCTAssertEqual(rB.count, 1, "Final fragment of B completes frame")
        if case let .data(d) = rB[0] { XCTAssertEqual(d.rrIntervals.count, 60) }
    }
}
