# 波形流管线（ECG/PPG）

> 高吞吐 BLE 波形数据的采集、缓冲、丢包检测与 UI 渲染。

---

## 1. 数据流全貌

```
┌─────────────────────────────────────────────────────────────┐
│  模拟器: WaveformStreamer                                    │
│  ─ DispatchSourceTimer (50ms/20Hz)                          │
│  ─ WaveformGenerator.nextBlock(count)                       │
│  ─ WaveformEncoder.encode → 分片                            │
│  ─ onBlock → BLE notify push                                │
└───────────────────────────────┬─────────────────────────────┘
                                │ BLE notify (高频)
                                ▼
┌─────────────────────────────────────────────────────────────┐
│  BLECentralDataSource                                        │
│  ─ didUpdateValueFor (waveformCharUUID)                     │
│  ─ WaveformDecoder → WaveformBlock                          │
│  ─ AsyncStream<WaveformBlock>.yield(block)                  │
└───────────────────────────────┬─────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────┐
│  BLEDataParser.parseWaveformBlock()                          │
│  ─ 时间戳映射 (t0 + block.startTs + index/sampleRate)       │
│  ─ 归一化 (rawValue / 32768 for 16-bit)                     │
│  ─ → [WaveformSample]                                       │
└───────────────────────────────┬─────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────┐
│  WaveformRingBuffer (NSLock 保护)                            │
│  ─ push(samples): 追加 + 容量淘汰 (3840 ≈ 30s@128Hz)        │
│  ─ recordBlock(bytes, blockSeq): 丢块检测                    │
│  ─ readRecent(durationMs): 按时间窗口读取                    │
└───────────────────────────────┬─────────────────────────────┘
                                │ 10Hz 轮询
                                ▼
┌─────────────────────────────────────────────────────────────┐
│  WaveformMiddleware                                          │
│  ─ Task { while true { sleep(100ms); read buffer; dispatch }│
│  ─ 后台模式: 降频到 500ms                                    │
│  ─ dispatch(.waveformSamplesReceived) + (.waveformMetrics)  │
└───────────────────────────────┬─────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────┐
│  Reducer → AppState.waveform                                 │
│  ─ ecgSamples: [WaveformSample] (最近 7680 ≈ 60s@128Hz)    │
│  ─ metrics: WaveformMetrics (吞吐率/丢块率)                 │
│                                                             │
│  SwiftUI WaveformChartView 自动更新                          │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 吞吐量计算

| 参数 | 值 | 说明 |
|------|-----|------|
| 采样率 | 128 Hz | ECG/PPG 典型值 |
| 每样本 | 2 bytes (Int16) | 16-bit 分辨率 |
| 每秒原始数据 | 256 bytes | 128 × 2 |
| BLE MTU | ~185 bytes | iOS 协商后 |
| 每块样本数 | ~88 samples | (185 - 帧头) / 2 |
| 块发送间隔 | 50 ms (20 Hz) | 模拟器默认 |
| 理论吞吐 | ~1760 samples/s | 20 × 88 |

---

## 3. WaveformRingBuffer 实现

```swift
public final class WaveformRingBuffer: WaveformRingBufferProtocol, @unchecked Sendable {
    private let capacity: Int          // 默认 3840 样本
    private let lock = NSLock()
    private var buffer: [WaveformSample] = []
    private var _totalPushed: Int = 0
    private var _totalBlocksReceived: Int = 0
    private var _totalBlocksLost: Int = 0
    private var _lastBlockSeq: UInt32 = 0

    public func push(_ samples: [WaveformSample]) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(contentsOf: samples)
        _totalPushed += samples.count
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)  // 淘汰旧数据
        }
    }

    public func readRecent(durationMs: Double) -> [WaveformSample] {
        lock.lock(); defer { lock.unlock() }
        guard let lastTS = buffer.last?.timestamp else { return [] }
        let cutoff = lastTS.addingTimeInterval(-durationMs / 1000.0)
        return buffer.filter { $0.timestamp >= cutoff }
    }
}
```

### 丢块检测

```swift
public func recordBlock(bytes: Int, blockSeq: UInt32, sampleCount: Int) {
    lock.lock(); defer { lock.unlock() }
    _totalBlocksReceived += 1
    if !_firstBlock {
        // 处理 UInt32 溢出回绕
        let diff = currentSeq.subtractingReportingOverflow(prevSeq).partialValue
        _totalBlocksLost += max(0, Int(diff) - 1)
    }
    _lastBlockSeq = blockSeq
}
```

---

## 4. WaveformMiddleware 轮询策略

```swift
public func makeWaveformMiddleware(
    waveformRingBuffer: any WaveformRingBufferProtocol,
    pollInterval: TimeInterval = 0.1,           // 前台 10Hz
    backgroundPollInterval: TimeInterval = 0.5  // 后台 2Hz
) -> Middleware<AppState, Action> {
    var pollTaskStarted = false

    return { store, action, next in
        next(action)

        if (action == .connectionStateChanged(.connected)), !pollTaskStarted {
            pollTaskStarted = true
            Task {
                while !Task.isCancelled {
                    // 后台降频
                    let lifecycle = await MainActor.run { store.state.lifecycle }
                    let interval = lifecycle == .background
                        ? backgroundPollInterval : pollInterval

                    let samples = waveformRingBuffer.readRecent(durationMs: 5000)
                    let metrics = waveformRingBuffer.metricsSnapshot

                    if !samples.isEmpty {
                        await MainActor.run {
                            store.dispatch(.waveformSamplesReceived(samples))
                        }
                    }
                    await MainActor.run {
                        store.dispatch(.waveformMetricsUpdated(metrics))
                    }

                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                }
            }
        }

        if case .connectionStateChanged(.disconnected) = action {
            pollTaskStarted = false
        }
    }
}
```

---

## 5. 归一化因子

| ADC 位数 | 原始范围 | 归一化除数 | 输出范围 |
|---------|---------|-----------|---------|
| 12-bit | 0–4095 | 2048.0 | ≈ [-1.0, 1.0] |
| 16-bit | -32768–32767 | 32768.0 | [-1.0, 1.0] |

```swift
private func normalizationDivisor(sampleBits: UInt8) -> Float {
    switch sampleBits {
    case 12: return 2048.0
    case 16: return 32768.0
    default: return 32768.0
    }
}
```

---

## 6. 为什么用轮询而非推送？

| 方案 | 优点 | 缺点 |
|------|------|------|
| **AsyncStream 推送** | 实时性好 | 128Hz 数据量会淹没 Redux pipeline，每个样本一次 dispatch |
| **10Hz 轮询** | Redux 状态更新频率恒定，与采样率解耦 | 最多 100ms 延迟 |

**选择轮询的理由**：
- 波形 UI 刷新率通常 30-60fps，10Hz 数据供给已足够
- 固定频率的 dispatch 不会随采样率线性增长
- 后台模式可降频到 2Hz，节省 CPU

---

## 7. Reducer 有界缓冲

```swift
case .waveformSamplesReceived(let samples):
    state.waveform.ecgSamples.append(contentsOf: samples)
    // 保持最近 7680 样本 (~60s @ 128 Hz)
    let maxSamples = 7680
    if state.waveform.ecgSamples.count > maxSamples {
        state.waveform.ecgSamples = Array(state.waveform.ecgSamples.suffix(maxSamples))
    }
```

**两层有界缓冲**：
1. `WaveformRingBuffer`：3840 样本（~30s），线程安全
2. `AppState.waveform.ecgSamples`：7680 样本（~60s），主线程

---

## 8. 重点难点

| 难点 | 说明 |
|------|------|
| **CoreBluetooth 高频回调** | notify 在主线程调度，高频时可能积压，需控制连接参数 |
| **Ring Buffer 线程安全** | BLE 回调在后台队列写，SwiftUI 在主线程读，`NSLock` 保护 |
| **UInt32 溢出处理** | `subtractingReportingOverflow` 处理 blockSeq 回绕 |
| **双层缓冲容量管理** | Ring Buffer 30s + State 60s，避免内存无限增长 |
| **前后台自适应** | 前台 100ms、后台 500ms 轮询间隔 |
