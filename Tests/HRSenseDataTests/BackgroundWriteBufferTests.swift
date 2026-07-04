import XCTest
@testable import HRSenseData

final class BackgroundWriteBufferTests: XCTestCase {
    func test_enqueueFlushesImmediatelyWhenThresholdReached() async throws {
        let recorder = FlushRecorder<Int>()
        let buffer = BackgroundWriteBuffer<Int>(
            threshold: 3,
            flushInterval: 10,
            sink: { values in
                await recorder.record(values)
            }
        )

        try await buffer.enqueue([1, 2])
        let pendingAfterFirstEnqueue = await buffer.pendingCount()
        XCTAssertEqual(pendingAfterFirstEnqueue, 2)

        try await buffer.enqueue([3])

        let pendingAfterThresholdFlush = await buffer.pendingCount()
        let flushesAfterThreshold = await recorder.snapshot()
        XCTAssertEqual(pendingAfterThresholdFlush, 0)
        XCTAssertEqual(flushesAfterThreshold, [[1, 2, 3]])
    }

    func test_enqueueFlushesAfterInterval() async throws {
        let recorder = FlushRecorder<String>()
        let buffer = BackgroundWriteBuffer<String>(
            threshold: 10,
            flushInterval: 0.05,
            sink: { values in
                await recorder.record(values)
            }
        )

        try await buffer.enqueue(["a", "b"])
        let flushCompleted = await waitUntil(timeout: 2) {
            let pendingAfterTimerFlush = await buffer.pendingCount()
            let flushesAfterTimer = await recorder.snapshot()
            return pendingAfterTimerFlush == 0 && flushesAfterTimer == [["a", "b"]]
        }
        XCTAssertTrue(flushCompleted, "Timed flush did not complete within the CI-safe timeout.")
        guard flushCompleted else { return }

        let pendingAfterTimerFlush = await buffer.pendingCount()
        let flushesAfterTimer = await recorder.snapshot()
        XCTAssertEqual(pendingAfterTimerFlush, 0)
        XCTAssertEqual(flushesAfterTimer, [["a", "b"]])
    }

    func test_manualFlushWritesPendingValues() async throws {
        let recorder = FlushRecorder<Int>()
        let buffer = BackgroundWriteBuffer<Int>(
            threshold: 100,
            flushInterval: 10,
            sink: { values in
                await recorder.record(values)
            }
        )

        try await buffer.enqueue([42])
        try await buffer.flush()

        let flushesAfterManualFlush = await recorder.snapshot()
        let pendingAfterManualFlush = await buffer.pendingCount()
        XCTAssertEqual(flushesAfterManualFlush, [[42]])
        XCTAssertEqual(pendingAfterManualFlush, 0)
    }
}

private extension XCTestCase {
    /// Polls an async condition until it succeeds or the timeout elapses.
    func waitUntil(
        timeout: TimeInterval = 2,
        pollInterval: TimeInterval = 0.02,
        _ condition: @escaping () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        return false
    }
}

private actor FlushRecorder<Element: Sendable & Equatable> {
    private var flushes: [[Element]] = []

    func record(_ values: [Element]) {
        flushes.append(values)
    }

    func snapshot() -> [[Element]] {
        flushes
    }
}
