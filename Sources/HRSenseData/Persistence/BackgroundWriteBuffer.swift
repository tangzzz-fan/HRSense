import Foundation

/// Batches persistence writes so BLE/UI producers do not block on every sample.
public actor BackgroundWriteBuffer<Element: Sendable> {
    public typealias Sink = @Sendable ([Element]) async throws -> Void

    private let threshold: Int
    private let flushIntervalNanoseconds: UInt64
    private let sink: Sink

    private var pending: [Element] = []
    private var scheduledFlushTask: Task<Void, Never>?

    public init(
        threshold: Int = 100,
        flushInterval: TimeInterval = 5,
        sink: @escaping Sink
    ) {
        self.threshold = threshold
        self.flushIntervalNanoseconds = UInt64(max(flushInterval, 0) * 1_000_000_000)
        self.sink = sink
    }

    deinit {
        scheduledFlushTask?.cancel()
    }

    public func enqueue(_ elements: [Element]) async throws {
        guard !elements.isEmpty else { return }

        pending.append(contentsOf: elements)

        if pending.count >= threshold {
            try await flush()
            return
        }

        scheduleFlushIfNeeded()
    }

    public func flush() async throws {
        guard !pending.isEmpty else {
            scheduledFlushTask?.cancel()
            scheduledFlushTask = nil
            return
        }

        let batch = pending
        pending.removeAll(keepingCapacity: true)
        scheduledFlushTask?.cancel()
        scheduledFlushTask = nil

        try await sink(batch)
    }

    public func pendingCount() -> Int {
        pending.count
    }

    private func scheduleFlushIfNeeded() {
        guard scheduledFlushTask == nil, flushIntervalNanoseconds > 0 else { return }

        let flushDelay = flushIntervalNanoseconds
        scheduledFlushTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: flushDelay)
            } catch {
                return
            }
            guard let self else { return }
            try? await self.flush()
        }
    }
}
