import XCTest
@testable import HRSenseCore
@testable import HRSenseData

final class WaveformFileStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func test_writeReadAndVerifyChecksumRoundTripsChunks() throws {
        let store = try WaveformFileStore(baseDirectory: tempDirectory)
        let sessionID = UUID()
        let startTimestamp = Date(timeIntervalSince1970: 1_725_000_000)
        let chunks = [
            WaveformFileChunk(blockSeq: 1, timestampOffsetMs: 0, samples: [120, -80, 45]),
            WaveformFileChunk(blockSeq: 2, timestampOffsetMs: 24, samples: [60, 61, 62, 63]),
        ]

        let ref = try store.writeChunks(
            sessionID: sessionID,
            type: .ecg,
            sampleRateHz: 128,
            sampleBits: 16,
            startTimestamp: startTimestamp,
            chunks: chunks
        )
        let result = try store.readChunks(from: ref)
        let checksumMatches = try store.verifyChecksum(for: ref)

        XCTAssertEqual(result.sampleRateHz, 128)
        XCTAssertEqual(result.sampleBits, 16)
        XCTAssertEqual(result.chunks, chunks)
        XCTAssertTrue(checksumMatches)
        XCTAssertEqual(ref.type, .ecg)
        XCTAssertEqual(ref.sampleRateHz, 128)
        XCTAssertEqual(ref.sampleBits, 16)
    }

    func test_writeUsesPlannedSessionDirectoryAndFilenameLayout() throws {
        let store = try WaveformFileStore(baseDirectory: tempDirectory)
        let sessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let startTimestamp = Date(timeIntervalSince1970: 1_725_000_123)

        let ref = try store.writeChunks(
            sessionID: sessionID,
            type: .ppg,
            sampleRateHz: 256,
            sampleBits: 12,
            startTimestamp: startTimestamp,
            chunks: [WaveformFileChunk(blockSeq: 7, timestampOffsetMs: 0, samples: [1, 2, 3])]
        )

        XCTAssertTrue(ref.fileURL.path.contains(sessionID.uuidString))
        XCTAssertEqual(ref.fileURL.lastPathComponent, "ppg_1725000123000.bin")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ref.fileURL.path))
    }

    func test_verifyChecksumDetectsTamperedFileAndReadFails() throws {
        let store = try WaveformFileStore(baseDirectory: tempDirectory)
        let ref = try store.writeChunks(
            sessionID: UUID(),
            type: .ecg,
            sampleRateHz: 128,
            sampleBits: 16,
            startTimestamp: Date(timeIntervalSince1970: 1_725_000_000),
            chunks: [WaveformFileChunk(blockSeq: 1, timestampOffsetMs: 0, samples: [10, 20, 30])]
        )

        var data = try Data(contentsOf: ref.fileURL)
        data[data.count - 1] ^= 0xFF
        try data.write(to: ref.fileURL, options: .atomic)

        let checksumMatches = try store.verifyChecksum(for: ref)

        XCTAssertFalse(checksumMatches)
        XCTAssertThrowsError(try store.readChunks(from: ref)) { error in
            XCTAssertEqual(error as? WaveformFileStoreError, .checksumMismatch)
        }
    }

    func test_deleteChunksRemovesWaveformFile() throws {
        let store = try WaveformFileStore(baseDirectory: tempDirectory)
        let ref = try store.writeChunks(
            sessionID: UUID(),
            type: .ecg,
            sampleRateHz: 128,
            sampleBits: 16,
            startTimestamp: Date(timeIntervalSince1970: 1_725_000_000),
            chunks: [WaveformFileChunk(blockSeq: 1, timestampOffsetMs: 0, samples: [5, 6, 7])]
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: ref.fileURL.path))

        try store.deleteChunks(for: ref)

        XCTAssertFalse(FileManager.default.fileExists(atPath: ref.fileURL.path))
    }
}
