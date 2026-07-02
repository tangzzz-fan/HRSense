import XCTest
@testable import HRSenseProtocol

/// CRC-16/CCITT-FALSE golden-value test.
final class CRC16Tests: XCTestCase {

    func test_goldenValue() {
        // CRC16("123456789") == 0x29B1 (per protocol contract §4.2.1)
        let input = Array("123456789".utf8)
        let result = CRC16.compute(input)
        XCTAssertEqual(result, 0x29B1, "Golden value CRC16('123456789') must equal 0x29B1")
    }

    func test_emptyData() {
        let result = CRC16.compute([])
        // CRC-16/CCITT-FALSE of empty data: init=0xFFFF, no bytes → 0xFFFF
        XCTAssertEqual(result, 0xFFFF)
    }

    func test_singleByte() {
        let result = CRC16.compute([0x00])
        // Known value: CRC-16/CCITT-FALSE of [0x00] = 0xE1F0
        XCTAssertEqual(result, 0xE1F0)
    }

    func test_knownVector() {
        // "A" → CRC-16/CCITT-FALSE = 0xB915
        let result = CRC16.compute(Array("A".utf8))
        XCTAssertEqual(result, 0xB915)
    }

    func test_dataConvenience() {
        let input = Data("123456789".utf8)
        XCTAssertEqual(CRC16.compute(input), 0x29B1)
    }

    func test_sliceConvenience() {
        let bytes: [UInt8] = [0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39]
        let slice = bytes[0..<bytes.count]
        XCTAssertEqual(CRC16.compute(slice), 0x29B1)
    }
}
