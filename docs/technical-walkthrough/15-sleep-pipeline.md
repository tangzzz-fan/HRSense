# 睡眠分期管线

> 从 HRV 指标到睡眠阶段（Wake/Light/Deep/REM）的完整编排，含 C++ 特征计算、推理、Session 合并与持久化。

---

## 1. 管线总览

```
hrvComputed (每 30s)
    │
    ├── 1. 追加 SleepMetricSnapshot 到 history
    │       (保留最近 4 小时的 RMSSD 序列)
    │
    ├── 2. makeSleepWindowInput()
    │       ├── 从 AppState.live 取最近 5 分钟的 HeartRateSample
    │       ├── 从 AppState.sleep 取 session 起始时间
    │       ├── 调用 C++ hrs_compute_hr_trend()
    │       ├── 调用 C++ hrs_compute_circadian_variation()
    │       └── 组装 SleepWindowInput (18 维特征)
    │
    ├── 3. dispatch(.sleep(.windowPrepared))
    │       dispatch(.sleep(.inferenceStarted))
    │
    ├── 4. Task {
    │       sleepInferenceRepository.inferSleepStage(input)
    │       dispatch(.sleep(.inferenceCompleted(prediction)))
    │   }
    │
    ├── 5. mergeSleepPrediction()
    │       ├── 同 stage → 延长当前 segment
    │       └── 不同 stage → 新建 segment
    │
    ├── 6. dispatch(.sleep(.sessionUpdated))
    │
    └── 7. persistenceStore.saveSleepSession()
            dispatch(.sleep(.sessionPersisted))
            → 触发 historyLoadRequested (连锁)
```

---

## 2. SleepMiddleware 核心逻辑

```swift
case .hrvComputed(let metrics):
    guard store.state.sleep.isMonitoring else { break }
    guard let latestSample = store.state.live.recentSamples.last else { break }

    // ① 追加 RMSSD 快照到历史（4 小时窗口）
    metricsHistory.append(SleepMetricSnapshot(timestamp: latestSample.timestamp, rmssd: metrics.rmssd))
    let historyCutoff = latestSample.timestamp.addingTimeInterval(-circadianHistoryDuration)
    metricsHistory.removeAll { $0.timestamp < historyCutoff }

    // ② 构建 SleepWindowInput（18 维特征）
    guard let input = makeSleepWindowInput(
        state: store.state, metrics: metrics,
        computeRepository: computeRepository,
        metricsHistory: metricsHistory, ...
    ) else { break }

    // ③ 启动推理
    store.dispatch(.sleep(.windowPrepared(input)))
    store.dispatch(.sleep(.inferenceStarted))

    Task {
        let prediction = try await sleepInferenceRepository.inferSleepStage(input: input)
        await MainActor.run { store.dispatch(.sleep(.inferenceCompleted(prediction))) }

        // ④ 合并到 Session
        let updatedSession = mergeSleepPrediction(prediction, into: store.state.sleep.currentSession, ...)
        await MainActor.run { store.dispatch(.sleep(.sessionUpdated(updatedSession))) }

        // ⑤ 持久化
        if let persistenceStore {
            try await persistenceStore.saveSleepSession(updatedSession)
            await MainActor.run { store.dispatch(.sleep(.sessionPersisted(updatedSession.id))) }
        }
    }
```

---

## 3. SleepWindowInput 18 维特征构成

| 索引 | 特征 | 来源 | 说明 |
|------|------|------|------|
| 0-13 | 14 个 HRV 指标 | C++ `hrs_compute_hrv` | SDNN, RMSSD, LF/HF 等 |
| 14 | hrTrend | C++ `hrs_compute_hr_trend` | 窗口内心率线性趋势斜率 |
| 15 | circadianVariation | C++ `hrs_compute_circadian_variation` | 4 小时 HRV 归一化波动范围 |
| 16 | minutesSinceSessionStart | 时间计算 | 距离监测开始经过的分钟数 |
| 17 | localClockMinutes | 本地时钟 | 当前时刻（小时×60+分钟），捕获昼夜节律 |

### C++ 特征计算（`ComputeBridge.swift`）

```swift
public func computeSleepFeatures(
    heartRates: [Double],
    hrvWindowValues: [Double]
) throws -> SleepCXXFeatures {
    var hrTrend = 0.0
    let hrTrendResult = heartRates.withUnsafeBufferPointer { buf in
        hrs_compute_hr_trend(buf.baseAddress, buf.count, &hrTrend)
    }
    // ... 同理计算 circadianVariation
    return SleepCXXFeatures(hrTrend: hrTrend, circadianVariation: circadianVariation)
}
```

- `hrs_compute_hr_trend`：线性回归斜率（心率上升 → 正值，可能清醒；下降 → 负值，可能深睡）
- `hrs_compute_circadian_variation`：归一化极差（反映长周期 HRV 波动，深睡时更稳定）

---

## 4. SleepStageService 推理与降级

```swift
public final class SleepStageService: @unchecked Sendable {
    private let mlService: CoreMLService  // 18 维 → 4 分类

    public func predict(input: SleepWindowInput) -> SleepStagePrediction {
        // 优先尝试 CoreML
        if let modelPrediction = predictWithCoreML(input: input) {
            return modelPrediction
        }
        // 降级到规则引擎
        return fallbackPrediction(input: input)
    }
}
```

### 规则引擎降级（4 条规则）

```swift
private func makeFallbackProbabilities(input: SleepWindowInput) -> [SleepStage: Float] {
    let metrics = input.metrics

    // 规则 1: 清醒 — 高心率或高压力
    if metrics.hr >= 82 || metrics.stressIndex >= 550 {
        return [.wake: 0.82, .light: 0.10, .rem: 0.05, .deep: 0.03]
    }

    // 规则 2: 深睡 — 高副交感活性 + 低心率 + 心率下降趋势
    if metrics.rmssd >= 65, metrics.hfPower >= metrics.lfPower,
       metrics.hr <= 58, hrTrend <= 0 {
        return [.deep: 0.76, .light: 0.14, .rem: 0.07, .wake: 0.03]
    }

    // 规则 3: REM — 高复杂度 + 适中心率 + 低 LF/HF + 昼夜波动 + 时间约束
    if metrics.sampleEntropy >= 1.25, metrics.hr <= 72,
       metrics.lfHfRatio < 1.5, circadianVariation >= 0.2,
       localClockMinutes >= 60, minutesSinceSessionStart >= 30 {
        return [.rem: 0.68, .light: 0.18, .deep: 0.08, .wake: 0.06]
    }

    // 规则 4: 默认 — 浅睡
    return [.light: 0.64, .rem: 0.18, .deep: 0.12, .wake: 0.06]
}
```

---

## 5. Sleep Session 合并逻辑

```swift
private func mergeSleepPrediction(
    _ prediction: SleepStagePrediction,
    into currentSession: SleepSession?, ...
) -> SleepSession {
    if let currentSession {
        var stages = currentSession.stages
        if let last = stages.last, last.stage == prediction.stage {
            // 同 stage → 延长当前 segment
            stages[stages.count - 1] = SleepStageSegment(
                id: last.id, stage: last.stage,
                startAt: last.startAt, endAt: prediction.timestamp
            )
        } else {
            // 不同 stage → 新建 segment
            stages.append(SleepStageSegment(
                stage: prediction.stage,
                startAt: stages.last?.endAt ?? prediction.timestamp,
                endAt: prediction.timestamp
            ))
        }
        return SleepSession(id: currentSession.id, stages: stages, ...)
    }

    // 首个预测 → 新建 Session
    let sessionDate = calendar.startOfDay(for: prediction.timestamp)
    return SleepSession(date: sessionDate, stages: [SleepStageSegment(...)], ...)
}
```

### 合并规则图示

```
时间轴:  ─────────────────────────────────────────────────►

预测 1:  Light
预测 2:  Light    → 合并为 Light(1→2)
预测 3:  Light    → 合并为 Light(1→3)
预测 4:  Deep     → 新建 Deep(3→4)
预测 5:  Deep     → 合并为 Deep(3→5)
预测 6:  REM      → 新建 REM(5→6)

结果:
  ┌────── Light ──────┐┌── Deep ──┐┌─ REM ─┐
  1                    3           5         6
```

---

## 6. 持久化后连锁加载

```swift
// SleepMiddleware
default:
    if case .sleep(.sessionPersisted) = action {
        store.dispatch(.sleep(.historyLoadRequested(limit: 7)))
    }
    break
```

**设计意图**：持久化成功后自动刷新历史列表，确保 UI 的睡眠记录实时更新。

**防循环**：`historyLoadRequested` → `historyLoaded` 不会产生 `sessionPersisted`，故不会无限循环。

---

## 7. 连接生命周期与睡眠监测

```swift
case .connectionStateChanged(.connected), .connectionStateChanged(.restoredConnected):
    store.dispatch(.sleep(.monitoringStarted(nowProvider())))

case .connectionStateChanged(.disconnected):
    store.dispatch(.sleep(.monitoringStopped(nowProvider())))
```

- 连接建立 → 自动开始睡眠监测
- 连接断开 → 停止监测（Session 保留但不再更新）

---

## 8. 重点难点

### 8.1 C++ 特征计算可能失败
```swift
let cxxFeatures = (try? computeRepository.computeSleepFeatures(...))
    ?? SleepCXXFeatures()  // 失败时使用零值默认
```
- `try?` + `??` 确保管线不中断
- 但零值特征（hrTrend=0, circadianVariation=0）可能导致推理结果偏差

### 8.2 跨午夜 Session 分割
- `calendar.startOfDay(for: prediction.timestamp)` 确定 session 日期
- 同一次睡眠可能产生两个 session（如 23:00–07:00）
- 当前实现中 `mergeSleepPrediction` 未显式处理跨天，需依赖 session 的 date 字段

### 8.3 4 小时 RMSSD 历史
- `circadianHistoryDuration = 4 * 60 * 60`
- 用于计算 `circadianVariation`（需要长时间窗口的 HRV 波动）
- 内存开销：4h × 2/min = ~480 个 `SleepMetricSnapshot`（每个约 16 bytes → ~7.5 KB）
