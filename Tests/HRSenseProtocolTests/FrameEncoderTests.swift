import XCTest
@testable import HRSenseProtocol

final class FrameEncoderTests: XCTestCase {

    func test_singleFragmentEncoding() {
        let sample = DeviceSample(timestamp: 100, heartRate: 65)
        let fragments = encodeData(sample, seq: 0, mtu: 185)

        XCTAssertEqual(fragments.count, 1, "Small sample should fit in one fragment")
        let bytes = [UInt8](fragments[0])
        // 2B header (FragHdr+seq) + frame (ver+type+dataKind+TLV+CRC)
        // Frame: 1 ver + 1 type + 1 dataKind + TLV(~10) + 2 CRC ≈ ~17 bytes
        XCTAssertGreaterThan(bytes.count, 10)
        XCTAssertEqual(bytes[1], 0) // seq
    }

    func test_multiFragmentEncoding() {
        let bigRR = Array(repeating: UInt16(800), count: 100)
        let sample = DeviceSample(timestamp: 0, heartRate: 70, rrIntervals: bigRR)
        let fragments = encodeData(sample, seq: 5, mtu: 50)

        XCTAssertGreaterThan(fragments.count, 1)

        // First fragment: START=1, END=0
        let firstBytes = [UInt8](fragments[0])
        let firstHdr = FragmentHeader(rawValue: firstBytes[0])
        XCTAssertTrue(firstHdr.isStart)
        XCTAssertFalse(firstHdr.isEnd)
        XCTAssertEqual(firstBytes[1], 5) // seq

        // Last fragment: START=0, END=1
        let lastBytes = [UInt8](fragments.last!)
        let lastHdr = FragmentHeader(rawValue: lastBytes[0])
        XCTAssertFalse(lastHdr.isStart)
        XCTAssertTrue(lastHdr.isEnd)
    }

    func test_mtuBoundary() {
        let sample = DeviceSample(timestamp: 0, heartRate: 72)
        let fragments = encodeData(sample, seq: 0, mtu: 30)

        // Each fragment payload ≤ mtu
        for frag in fragments {
            XCTAssertLessThanOrEqual(frag.count, 30)
        }
    }

    func test_allFragmentIndicesUnique() {
        let rr = Array(repeating: UInt16(900), count: 80)
        let sample = DeviceSample(timestamp: 0, heartRate: 70, rrIntervals: rr)
        let fragments = encodeData(sample, seq: 1, mtu: 30)

        var seen: Set<UInt8> = []
        for frag in fragments {
            let bytes = [UInt8](frag)
            let hdr = FragmentHeader(rawValue: bytes[0])
            XCTAssertFalse(seen.contains(hdr.fragIndex), "Duplicate frag index \(hdr.fragIndex)")
            seen.insert(hdr.fragIndex)
        }
    }
}
