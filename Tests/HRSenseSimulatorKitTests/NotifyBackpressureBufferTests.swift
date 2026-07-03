import XCTest
@testable import HRSenseSimulatorKit

final class NotifyBackpressureBufferTests: XCTestCase {
    func test_highPriorityPayloadsDrainBeforeNormalPayloads() {
        var buffer = NotifyBackpressureBuffer()

        buffer.enqueue([
            PendingNotifyPayload(data: Data([0x01]), priority: .normal, source: "waveform"),
            PendingNotifyPayload(data: Data([0x02]), priority: .normal, source: "waveform"),
        ])
        buffer.enqueue([
            PendingNotifyPayload(data: Data([0xA0]), priority: .high, source: "sample")
        ])

        XCTAssertEqual(buffer.popNext()?.data, Data([0xA0]))
        XCTAssertEqual(buffer.popNext()?.data, Data([0x01]))
        XCTAssertEqual(buffer.popNext()?.data, Data([0x02]))
        XCTAssertNil(buffer.popNext())
    }

    func test_prependRestoresPayloadToFrontOfSamePriorityQueue() {
        var buffer = NotifyBackpressureBuffer()
        let first = PendingNotifyPayload(data: Data([0x10]), priority: .high, source: "sample")
        let second = PendingNotifyPayload(data: Data([0x11]), priority: .high, source: "sample")

        buffer.enqueue([first, second])

        XCTAssertEqual(buffer.popNext(), first)

        let blocked = PendingNotifyPayload(data: Data([0x12]), priority: .high, source: "sample")
        buffer.prepend(blocked)

        XCTAssertEqual(buffer.popNext(), blocked)
        XCTAssertEqual(buffer.popNext(), second)
        XCTAssertTrue(buffer.isEmpty)
    }
}
