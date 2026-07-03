import CryptoKit
import Foundation
import HRSenseCore

public struct WaveformFileChunk: Equatable, Sendable {
    public let blockSeq: UInt32
    public let timestampOffsetMs: UInt32
    public let samples: [Int16]

    public init(
        blockSeq: UInt32,
        timestampOffsetMs: UInt32,
        samples: [Int16]
    ) {
        self.blockSeq = blockSeq
        self.timestampOffsetMs = timestampOffsetMs
        self.samples = samples
    }
}

public struct WaveformFileReadResult: Equatable, Sendable {
    public let sampleRateHz: Int
    public let sampleBits: Int
    public let chunks: [WaveformFileChunk]

    public init(
        sampleRateHz: Int,
        sampleBits: Int,
        chunks: [WaveformFileChunk]
    ) {
        self.sampleRateHz = sampleRateHz
        self.sampleBits = sampleBits
        self.chunks = chunks
    }
}

public enum WaveformFileStoreError: Error, Equatable {
    case emptyChunks
    case invalidHeader
    case invalidSampleCount
    case unexpectedEOF
    case checksumMismatch
}

/// File-backed storage for waveform chunks. The binary layout is intentionally
/// DB-agnostic so later SwiftData -> GRDB migration does not affect waveform assets.
public struct WaveformFileStore: @unchecked Sendable {
    private static let fileMagic: UInt32 = 0x48525357
    private static let fileVersion: UInt16 = 1

    private let fileManager: FileManager
    private let baseDirectory: URL

    public init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) throws {
        self.fileManager = fileManager
        self.baseDirectory = try baseDirectory ?? Self.makeDefaultBaseDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: self.baseDirectory, withIntermediateDirectories: true)
    }

    public func writeChunks(
        sessionID: UUID,
        type: WaveformType,
        sampleRateHz: Int,
        sampleBits: Int,
        startTimestamp: Date,
        chunks: [WaveformFileChunk]
    ) throws -> WaveformBlobRef {
        guard !chunks.isEmpty else { throw WaveformFileStoreError.emptyChunks }

        let fileURL = makeFileURL(sessionID: sessionID, type: type, startTimestamp: startTimestamp)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let payload = try encodeFile(sampleRateHz: sampleRateHz, sampleBits: sampleBits, chunks: chunks)
        try payload.write(to: fileURL, options: .atomic)

        let checksum = sha256Hex(for: payload)
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? Int64(payload.count)

        return WaveformBlobRef(
            sessionID: sessionID,
            type: type,
            sampleRateHz: sampleRateHz,
            sampleBits: sampleBits,
            startTimestamp: startTimestamp,
            fileURL: fileURL,
            checksumSHA256: checksum,
            fileSizeBytes: fileSize
        )
    }

    public func readChunks(from ref: WaveformBlobRef) throws -> WaveformFileReadResult {
        let data = try Data(contentsOf: ref.fileURL)
        let checksum = sha256Hex(for: data)
        guard checksum == ref.checksumSHA256 else {
            throw WaveformFileStoreError.checksumMismatch
        }
        return try decodeFile(data)
    }

    public func deleteChunks(for ref: WaveformBlobRef) throws {
        guard fileManager.fileExists(atPath: ref.fileURL.path) else { return }
        try fileManager.removeItem(at: ref.fileURL)
    }

    public func verifyChecksum(for ref: WaveformBlobRef) throws -> Bool {
        guard fileManager.fileExists(atPath: ref.fileURL.path) else { return false }
        let data = try Data(contentsOf: ref.fileURL)
        return sha256Hex(for: data) == ref.checksumSHA256
    }

    private func encodeFile(
        sampleRateHz: Int,
        sampleBits: Int,
        chunks: [WaveformFileChunk]
    ) throws -> Data {
        var data = Data()
        data.appendLE(Self.fileMagic)
        data.appendLE(Self.fileVersion)
        data.appendLE(UInt16(clamping: sampleRateHz))
        data.append(UInt8(clamping: sampleBits))
        data.append(0) // reserved for future header expansion

        for chunk in chunks {
            guard chunk.samples.count <= Int(UInt16.max) else {
                throw WaveformFileStoreError.invalidSampleCount
            }

            data.appendLE(chunk.blockSeq)
            data.appendLE(chunk.timestampOffsetMs)
            data.appendLE(UInt16(chunk.samples.count))
            for sample in chunk.samples {
                data.appendLE(UInt16(bitPattern: sample))
            }
        }

        return data
    }

    private func decodeFile(_ data: Data) throws -> WaveformFileReadResult {
        var cursor = 0

        let magic = try data.readUInt32LE(at: &cursor)
        guard magic == Self.fileMagic else {
            throw WaveformFileStoreError.invalidHeader
        }

        let version = try data.readUInt16LE(at: &cursor)
        guard version == Self.fileVersion else {
            throw WaveformFileStoreError.invalidHeader
        }

        let sampleRateHz = Int(try data.readUInt16LE(at: &cursor))
        let sampleBits = Int(try data.readUInt8(at: &cursor))
        _ = try data.readUInt8(at: &cursor) // reserved

        var chunks: [WaveformFileChunk] = []
        while cursor < data.count {
            let blockSeq = try data.readUInt32LE(at: &cursor)
            let timestampOffsetMs = try data.readUInt32LE(at: &cursor)
            let sampleCount = Int(try data.readUInt16LE(at: &cursor))

            var samples: [Int16] = []
            samples.reserveCapacity(sampleCount)
            for _ in 0..<sampleCount {
                let raw = try data.readUInt16LE(at: &cursor)
                samples.append(Int16(bitPattern: raw))
            }

            chunks.append(
                WaveformFileChunk(
                    blockSeq: blockSeq,
                    timestampOffsetMs: timestampOffsetMs,
                    samples: samples
                )
            )
        }

        return WaveformFileReadResult(
            sampleRateHz: sampleRateHz,
            sampleBits: sampleBits,
            chunks: chunks
        )
    }

    private func makeFileURL(
        sessionID: UUID,
        type: WaveformType,
        startTimestamp: Date
    ) -> URL {
        let sessionDirectory = baseDirectory.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        let epochMillis = Int64((startTimestamp.timeIntervalSince1970 * 1000).rounded())
        let filename = "\(type.filenameComponent)_\(epochMillis).bin"
        return sessionDirectory.appendingPathComponent(filename, isDirectory: false)
    }

    private func sha256Hex(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func makeDefaultBaseDirectory(fileManager: FileManager) throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("HRSense", isDirectory: true)
            .appendingPathComponent("waveforms", isDirectory: true)
    }
}

private extension WaveformType {
    var filenameComponent: String {
        switch self {
        case .ecg:
            return "ecg"
        case .ppg:
            return "ppg"
        }
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt8) {
        append(value)
    }

    mutating func appendLE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }

    mutating func appendLE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }

    func readUInt8(at cursor: inout Int) throws -> UInt8 {
        guard cursor + 1 <= count else {
            throw WaveformFileStoreError.unexpectedEOF
        }
        let value = self[cursor]
        cursor += 1
        return value
    }

    func readUInt16LE(at cursor: inout Int) throws -> UInt16 {
        guard cursor + 2 <= count else {
            throw WaveformFileStoreError.unexpectedEOF
        }
        let b0 = UInt16(self[cursor])
        let b1 = UInt16(self[cursor + 1])
        cursor += 2
        return b0 | (b1 << 8)
    }

    func readUInt32LE(at cursor: inout Int) throws -> UInt32 {
        guard cursor + 4 <= count else {
            throw WaveformFileStoreError.unexpectedEOF
        }
        let b0 = UInt32(self[cursor])
        let b1 = UInt32(self[cursor + 1])
        let b2 = UInt32(self[cursor + 2])
        let b3 = UInt32(self[cursor + 3])
        cursor += 4
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
}
