import XCTest
@testable import HRSenseProtocol

final class FragmentHeaderTests: XCTestCase {

    func test_singleFragment() {
        let hdr = FragmentHeader(start: true, end: true, fragIndex: 0)
        XCTAssertTrue(hdr.isSingleFragment)
        XCTAssertTrue(hdr.isStart)
        XCTAssertTrue(hdr.isEnd)
        XCTAssertEqual(hdr.fragIndex, 0)
    }

    func test_firstFragment() {
        let hdr = FragmentHeader(start: true, end: false, fragIndex: 0)
        XCTAssertTrue(hdr.isStart)
        XCTAssertFalse(hdr.isEnd)
        XCTAssertFalse(hdr.isSingleFragment)
    }

    func test_middleFragment() {
        let hdr = FragmentHeader(start: false, end: false, fragIndex: 3)
        XCTAssertFalse(hdr.isStart)
        XCTAssertFalse(hdr.isEnd)
        XCTAssertEqual(hdr.fragIndex, 3)
    }

    func test_lastFragment() {
        let hdr = FragmentHeader(start: false, end: true, fragIndex: 7)
        XCTAssertFalse(hdr.isStart)
        XCTAssertTrue(hdr.isEnd)
        XCTAssertEqual(hdr.fragIndex, 7)
    }

    func test_fragIndexClamp() {
        // Index 63 is the max (6 bits)
        let hdr = FragmentHeader(start: false, end: false, fragIndex: 63)
        XCTAssertEqual(hdr.fragIndex, 63)
        // Index 64 would overflow — clamped to 0 by bitmask
        let hdr2 = FragmentHeader(start: false, end: false, fragIndex: 64)
        XCTAssertEqual(hdr2.fragIndex, 0)
    }

    func test_rawValueEncoding() {
        // START=1, END=1, IDX=0 → 0b11000000 = 0xC0
        let hdr = FragmentHeader(start: true, end: true, fragIndex: 0)
        XCTAssertEqual(hdr.rawValue, 0xC0)
    }
}
