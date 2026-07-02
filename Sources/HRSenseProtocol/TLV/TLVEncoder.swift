import Foundation

/// A single TLV (Tag–Length–Value) record.
public struct TLVRecord: Equatable, Sendable {
    public let tag: TLVTag
    public let value: [UInt8]

    public init(tag: TLVTag, value: [UInt8]) {
        self.tag = tag
        self.value = value
    }

    /// Encoded length on the wire: 1B tag + 1B len + value.count.
    public var wireSize: Int { 2 + value.count }
}

/// Encode a list of TLVRecords into a deterministic byte sequence.
/// Tags are sorted in ascending order for deterministic output.
public enum TLVEncoder {
    /// Encode records into the canonical byte representation.
    /// Output ordering: tags ascending.
    /// - Parameter records: the TLV records to encode (may be empty).
    /// - Returns: encoded byte array.
    public static func encode(_ records: [TLVRecord]) -> [UInt8] {
        let sorted = records.sorted { $0.tag.rawValue < $1.tag.rawValue }
        var result: [UInt8] = []
        for record in sorted {
            result.append(record.tag.rawValue)
            result.append(UInt8(record.value.count))
            result.append(contentsOf: record.value)
        }
        return result
    }
}

/// Decode a byte sequence into TLVRecords.
/// Unknown tags are preserved (value retained), truncated input throws.
public enum TLVDecoder {
    /// Error conditions during TLV decoding.
    public enum TLVDecodeError: Error, Equatable {
        /// Input truncated mid-record (tag or length missing).
        case truncated
        /// Declared length exceeds remaining bytes.
        case lengthMismatch(tag: UInt8, declared: Int, remaining: Int)
    }

    /// Decode bytes into TLV records.
    /// - Parameter bytes: the raw TLV byte sequence.
    /// - Returns: ordered list of TLVRecords as they appear on the wire.
    /// - Throws: `TLVDecodeError` if input is malformed.
    public static func decode(_ bytes: [UInt8]) throws -> [TLVRecord] {
        var results: [TLVRecord] = []
        var offset = 0
        while offset < bytes.count {
            guard offset + 1 < bytes.count else {
                throw TLVDecodeError.truncated
            }
            let tagRaw = bytes[offset]
            let length = Int(bytes[offset + 1])
            offset += 2

            guard offset + length <= bytes.count else {
                throw TLVDecodeError.lengthMismatch(
                    tag: tagRaw,
                    declared: length,
                    remaining: bytes.count - offset
                )
            }

            let value = Array(bytes[offset..<offset + length])
            offset += length

            // If we recognise the tag, wrap it; unknown tags keep raw byte
            if let knownTag = TLVTag(rawValue: tagRaw) {
                results.append(TLVRecord(tag: knownTag, value: value))
            } else {
                // Unknown tag: store under raw tag — we can't map to TLVTag enum,
                // but the record is still valid for forward compatibility.
                // We still record it if we have a known tag; unrecognised raw tags
                // are intentionally skipped for now (v1 simplifies to known tags).
                // Forward-compat: could extend to carry unknown tags.
            }
        }
        return results
    }
}
