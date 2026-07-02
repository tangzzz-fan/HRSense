import XCTest
@testable import HRSenseProtocol

final class TLVTests: XCTestCase {

    // MARK: - Encoder

    func test_encodeEmpty() {
        let bytes = TLVEncoder.encode([])
        XCTAssertEqual(bytes.count, 0)
    }

    func test_encodeSingle() {
        let record = TLVRecord(tag: .heartRate, value: [72])  // 72 bpm
        let bytes = TLVEncoder.encode([record])
        XCTAssertEqual(bytes, [0x02, 0x01, 72])
    }

    func test_encodeSortsTagsAscending() {
        let r1 = TLVRecord(tag: .battery, value: [85])       // tag 0x04
        let r2 = TLVRecord(tag: .timestamp, value: [0, 0, 0, 0])  // tag 0x01
        let r3 = TLVRecord(tag: .heartRate, value: [72])     // tag 0x02

        let bytes = TLVEncoder.encode([r1, r2, r3])
        // Sorted: timestamp(0x01), heartRate(0x02), battery(0x04)
        let expected: [UInt8] = [
            0x01, 0x04, 0, 0, 0, 0,   // timestamp
            0x02, 0x01, 72,            // heartRate
            0x04, 0x01, 85             // battery
        ]
        XCTAssertEqual(bytes, expected)
    }

    // MARK: - Decoder

    func test_decodeSingle() throws {
        let bytes: [UInt8] = [0x02, 0x01, 72]
        let records = try TLVDecoder.decode(bytes)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].tag, .heartRate)
        XCTAssertEqual(records[0].value, [72])
    }

    func test_decodeMulti() throws {
        let bytes: [UInt8] = [
            0x01, 0x04, 0x64, 0, 0, 0,   // timestamp = 100
            0x02, 0x01, 75                  // heartRate = 75
        ]
        let records = try TLVDecoder.decode(bytes)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].tag, .timestamp)
        XCTAssertEqual(records[0].value, [0x64, 0, 0, 0])
        XCTAssertEqual(records[1].tag, .heartRate)
        XCTAssertEqual(records[1].value, [75])
    }

    func test_truncatedTag() {
        let bytes: [UInt8] = [0x01]  // tag only, no length
        XCTAssertThrowsError(try TLVDecoder.decode(bytes)) { error in
            XCTAssertEqual(error as? TLVDecoder.TLVDecodeError, .truncated)
        }
    }

    func test_truncatedValue() {
        // Declares 10 bytes but only 2 present
        let bytes: [UInt8] = [0x01, 0x0A, 0x64, 0x00]
        XCTAssertThrowsError(try TLVDecoder.decode(bytes)) { error in
            if case let .lengthMismatch(tag, declared, remaining) = error as? TLVDecoder.TLVDecodeError {
                XCTAssertEqual(tag, 0x01)
                XCTAssertEqual(declared, 10)
                XCTAssertEqual(remaining, 2)
            } else {
                XCTFail("Expected lengthMismatch error")
            }
        }
    }

    func test_unknownTagSkipped() throws {
        // Tag 0xFF is not recognised in v1 → skipped
        let bytes: [UInt8] = [0xFF, 0x02, 0xAA, 0xBB]
        let records = try TLVDecoder.decode(bytes)
        // Unknown tags are skipped; 0 records produced
        XCTAssertEqual(records.count, 0)
    }

    // MARK: - Round-trip

    func test_roundTrip() throws {
        let original: [TLVRecord] = [
            TLVRecord(tag: .timestamp, value: [0xE8, 0x03, 0, 0]),  // 1000ms
            TLVRecord(tag: .heartRate, value: [72]),
            TLVRecord(tag: .battery, value: [85]),
            TLVRecord(tag: .sampleSeq, value: [42, 0, 0, 0]),
        ]
        let encoded = TLVEncoder.encode(original)
        let decoded = try TLVDecoder.decode(encoded)
        XCTAssertEqual(decoded, original)
    }
}
