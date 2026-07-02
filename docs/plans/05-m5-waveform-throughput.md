# M5 · 实时波形高吞吐（ECG/PPG）— 实施计划

## 摘要

实现完整波形通道——从模拟器端合成 ECG/PPG，通过 BLE Notify 高吞吐传输，到 App 端 Canvas 高性能渲染。跨越三个模块：`HRSenseProtocol`（波形编解码器）、`HRSenseSimulatorKit`（波形生成器）、`HRSenseData`+`HRSenseFeature`（环形缓冲区+渲染）。

**硬依赖**：M3（BLE 集成）。

---

## 阶段 1：HRSenseProtocol — 波形块编解码

### 数据模型

```swift
// WaveformBlock.swift
public struct WaveformBlock {
    let waveformType: UInt8    // 1=ECG, 2=PPG
    let sampleRateHz: UInt16
    let blockSeq: UInt32      // 连续块序号
    let startTimestampMs: UInt32
    let sampleBits: UInt8
    let samples: [Int16]
}
```

### 编解码器

| 文件 | 职责 |
|---|---|
| `WaveformEncoder.swift` | 波形块 → 分片帧（DataKind=0x02，TLV 字段 0x10–0x15，MTU 动态计算） |
| `WaveformDecoder.swift` | TLV → WaveformBlock，`detectBlockLoss(prevSeq:currentSeq:)` |
| 修改 `FrameAssembler` | 识别 Type=0x02 且 DataKind=0x02 → 产出 `.waveformBlock(...)` |

### 测试
- 往返 `decode(encode(block)) == block`
- 不同 sampleBits（12/16）正确打包
- blockSeq 缺口检测（连续/丢1/丢多/u32 回绕）
- MTU 边界验证

---

## 阶段 2：HRSenseCore — 领域波形实体

| 文件 | 内容 |
|---|---|
| `WaveformSample.swift` | `type: WaveformType`、`sampleRateHz`、`timestamp`、`value: Float` |
| `WaveformMetrics.swift` | `effectiveThroughputBytesPerSec`、`endToEndLatencyMs`、`blockLossRate`、`uiFrameRate` |
| `WaveformRingBufferProtocol` | `push(_:)`、`readRecent(durationMs:)`、`metricsSnapshot()` |

---

## 阶段 3：HRSenseSimulatorKit — 波形生成器

| 文件 | 职责 |
|---|---|
| `ECGSynthesizer.swift` | PQRST 模板 + 基线漂移 + 噪声，参数可配 |
| `PPGSynthesizer.swift` | 收缩期峰值 + 重搏切迹 + 衰减 |
| `WaveformGenerator.swift` | 协调器，维护相位状态确保块边界连续 |
| `ThroughputTracker.swift` | 发送速率、丢块计数统计 |
| `WaveformFaultInjector.swift` | 丢块/乱序/截断/延迟注入 |
| `WaveformStreamer.swift` | 高吞吐 notify 循环，背压处理 |

---

## 阶段 4：HRSenseData — App 侧环形缓冲区 + MTU

| 文件 | 职责 |
|---|---|
| `WaveformRingBuffer.swift` | 固定容量（~30 秒），线程安全，丢弃最旧块，`readRecent(durationMs:)` |
| `MTUCalculator.swift` | 给定协商 MTU → 计算最大样本数/块 |
| `WaveformRepositoryImpl.swift` | 持有 ring buffer，管理 `localT0` 锚定 |
| `WaveformMetricsCollector.swift` | App 端指标：吞吐、延迟、丢块率、`AsyncStream<WaveformMetrics>` |

---

## 阶段 5：HRSenseFeature — Canvas 渲染视图（核心 UI）

| 文件 | 职责 |
|---|---|
| `WaveformCanvasView.swift` | `TimelineView(.animation)` 驱动 ~60fps，min/max 降采样至像素列，填充多边形 |
| `ThroughputPanelView.swift` | App 侧指标面板（吞吐/延迟/丢块率/帧率/MTU/内存） |
| `WaveformDisplayView.swift` | 组合 Canvas + 指标 + 类型选择器 |
| `WaveformState.swift` / `WaveformAction.swift` / `WaveformReducer.swift` | Redux 状态管理 |
| `WaveformMiddleware.swift` | 订阅波形 AsyncStream，节流 UI 更新，触发指标更新 |

---

## 验收标准（真机 + 模拟器）
- [ ] ≥128Hz 采样率，波形端到端连续 ≥5 分钟
- [ ] 量化：有效吞吐、端到端延迟、丢块率
- [ ] 波形视图渲染 ≥55fps（真机）；环形缓冲内存稳定
- [ ] 注入丢块/乱序/截断：UI 不崩，重组正确，丢块统计准确
- [ ] MTU 动态填充验证（日志显示协商 MTU 和块大小）

## 预估文件数：~25 个源文件 + ~8 个测试文件
