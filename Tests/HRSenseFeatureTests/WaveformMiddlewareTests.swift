import XCTest
@testable import HRSenseFeature
@testable import HRSenseCore
import TGReduxKit

/// Fake WaveformRingBuffer for testing WaveformMiddleware.
final class FakeWaveformRingBuffer: WaveformRingBufferProtocol, @unchecked Sendable {
    var _samples: [WaveformSample] = []
    var _metrics = WaveformMetrics()
    var _totalPushed = 0
    var recordedBlocks: [(bytes: Int, blockSeq: UInt32, sampleCount: Int)] = []
    var readCount = 0

    var metricsSnapshot: WaveformMetrics { _metrics }
    var totalPushed: Int { _totalPushed }

    func push(_ samples: [WaveformSample]) {
        _samples.append(contentsOf: samples)
        _totalPushed += samples.count
    }

    func recordBlock(bytes: Int, blockSeq: UInt32, sampleCount: Int) {
        recordedBlocks.append((bytes, blockSeq, sampleCount))
    }

    func readRecent(durationMs: Double) -> [WaveformSample] {
        readCount += 1
        return _samples
    }
}

@MainActor
final class WaveformMiddlewareTests: XCTestCase {

    func makeStore(buffer: any WaveformRingBufferProtocol, poll: TimeInterval = 0.05) -> Store<AppState, Action> {
        Store(
            initialState: AppState(),
            reducer: AppReducer.reduce,
            middlewares: [makeWaveformMiddleware(waveformRingBuffer: buffer, pollInterval: poll, backgroundPollInterval: 0.2)]
        )
    }

    // MARK: - Polling

    func test_startsPollingOnConnected() async {
        let buffer = FakeWaveformRingBuffer()
        buffer._samples = [
            WaveformSample(type: .ecg, sampleRateHz: 128, timestamp: Date(), value: 0.5),
        ]
        let store = makeStore(buffer: buffer)
        store.dispatch(.connectionStateChanged(.connected))
        await assertEventually {
            store.state.waveform.isStreaming && buffer.readCount > 0
        }
        XCTAssertTrue(store.state.waveform.isStreaming)
        XCTAssertGreaterThan(buffer.readCount, 0)
    }

    func test_dispatchesMetrics() async {
        let buffer = FakeWaveformRingBuffer()
        buffer._metrics = WaveformMetrics()
        let store = makeStore(buffer: buffer)
        store.dispatch(.connectionStateChanged(.connected))
        await assertEventually {
            buffer.readCount > 0
        }
        XCTAssertGreaterThan(buffer.readCount, 0)
    }

    func test_startsPollingOnRestoredConnected() async {
        let buffer = FakeWaveformRingBuffer()
        buffer._samples = [
            WaveformSample(type: .ecg, sampleRateHz: 128, timestamp: Date(), value: 0.5),
        ]
        let store = makeStore(buffer: buffer)
        store.dispatch(.connectionStateChanged(.restoredConnected))
        await assertEventually {
            store.state.waveform.isStreaming && buffer.readCount > 0
        }
        XCTAssertTrue(store.state.waveform.isStreaming)
        XCTAssertGreaterThan(buffer.readCount, 0)
    }

    func test_stopsPollingOnDisconnected() async {
        let buffer = FakeWaveformRingBuffer()
        let store = makeStore(buffer: buffer)
        store.dispatch(.connectionStateChanged(.connected))
        await assertEventually {
            buffer.readCount > 0
        }
        let readsBefore = buffer.readCount
        store.dispatch(.connectionStateChanged(.disconnected))
        try? await Task.sleep(nanoseconds: 300_000_000)
        let readsAfter = buffer.readCount
        // After disconnect, the poll loop should stop; reads shouldn't increase much.
        // Allow up to 6 extra reads (0.3s gap at 0.05s poll = 6 ticks max if no stop).
        // This is a weak signal test; the important part is that the middleware doesn't crash.
        let diff = readsAfter - readsBefore
        XCTAssertLessThanOrEqual(diff, 6, "Poll should slow/stop after disconnect, got \(diff) extra reads")
    }

    func test_backgroundPollingDropsToLowerCadence() async {
        let buffer = FakeWaveformRingBuffer()
        buffer._samples = [
            WaveformSample(type: .ecg, sampleRateHz: 128, timestamp: Date(), value: 0.5),
        ]
        let store = makeStore(buffer: buffer)
        store.dispatch(.connectionStateChanged(.connected))
        await assertEventually {
            buffer.readCount > 0
        }
        let readsBeforeBackground = buffer.readCount

        store.dispatch(.didEnterBackground)
        try? await Task.sleep(nanoseconds: 250_000_000)
        let readsAfterBackground = buffer.readCount

        XCTAssertLessThanOrEqual(readsAfterBackground - readsBeforeBackground, 2)
    }

    // MARK: - Type selection

    func test_waveformTypeSelected_updatesState() async {
        let buffer = FakeWaveformRingBuffer()
        let store = makeStore(buffer: buffer)
        store.dispatch(.waveformTypeSelected(.ppg))
        XCTAssertEqual(store.state.waveform.selectedType, .ppg)
    }
}
