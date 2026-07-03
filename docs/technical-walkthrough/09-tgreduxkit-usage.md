# TGReduxKit 在项目中的使用分析

> 本文档分析 TGReduxKit 在 HRSense 项目中的实际使用方式，重点关注异步流处理场景。

## 1. TGReduxKit 概览

TGReduxKit 是一个基于 Swift Observation（iOS 17+）的轻量 Redux 实现，核心概念：

| 概念 | 类型 | 说明 |
|------|------|------|
| Store | `Store<State, Action>` | 单一状态容器，MainActor 串行 reduce |
| Middleware | `(Store, Action, Next) -> Void` | 副作用编排层，拦截 Action |
| Reducer | `(inout State, Action) -> Void` | 纯函数状态变更 |

项目选型 TGReduxKit 而非 TCA 的原因：轻量、无外部依赖、Swift 6 兼容、Observation 驱动。

## 2. 核心 API 使用

### 2.1 Store 创建与注入

```swift
// AppComposition.swift — 组合根
let store = Store(
    initialState: AppState(),
    reducer: AppReducer.reduce,
    middlewares: middleware  // [Middleware<AppState, Action>]
)
```

```swift
// HRSenseAppContainerView.swift — 注入 SwiftUI 环境
RootView()
    .provideStore(store)  // TGReduxKit 的 View 扩展
```

```swift
// RootView.swift — 消费 Store
@Environment(Store<AppState, Action>.self) private var store

// 读取状态
store.state.live.currentHeartRate

// 派发 Action
store.dispatch(.startScanning)
```

### 2.2 Middleware 签名

```swift
typealias Middleware<State, Action> = (Store<State, Action>, Action, @escaping (Action) -> Void) -> Void
```

每个 Middleware 接收三个参数：
- `store`：可读取 state、dispatch action
- `action`：当前被派发的 action
- `next`：调用 `next(action)` 将 action 传递给下一个 middleware（或 reducer）

**关键模式**：Middleware 中可以：
- 调用 `next(action)` 前先执行副作用（前置拦截）
- 调用 `next(action)` 后读取更新后的 state（后置观察）
- 不调用 `next(action)` 来吞掉 action（过滤）
- 在 `Task {}` 中执行异步工作，稍后 dispatch

## 3. 异步流处理典型场景

### 场景一：AsyncStream 桥接（ConnectionMiddleware）

**问题**：BLE 层通过 `AsyncStream` 暴露连接状态变化，需要桥接到 Redux Store。

**实现**：

```swift
// ConnectionMiddleware.swift
public func makeConnectionMiddleware(
    deviceRepo: any DeviceRepository,
    backoffProvider: (@Sendable () -> Int)?
) -> Middleware<AppState, Action> {
    var streamTaskStarted = false

    return { store, action, next in
        // 一次性启动：订阅 4 条 AsyncStream
        if !streamTaskStarted {
            streamTaskStarted = true

            // 流 1：连接状态变化
            Task {
                for await state in deviceRepo.connectionStateStream {
                    await MainActor.run {
                        store.dispatch(.connectionStateChanged(state))
                    }
                }
            }

            // 流 2：恢复的 peripheral ID
            Task {
                for await peripheralIDs in deviceRepo.restoredPeripheralIDsStream {
                    await MainActor.run {
                        store.dispatch(.restoreInitiated(peripheralIDs: peripheralIDs))
                    }
                }
            }

            // 流 3：发现的设备
            Task { for await device in deviceRepo.discoveredDevicesStream { ... } }

            // 流 4：设备信息更新
            Task { for await info in deviceRepo.deviceInfoStream { ... } }
        }
        // ...
    }
}
```

**模式总结**：
- 用 `streamTaskStarted` flag 防止重复订阅
- 每条 `AsyncStream` 在一个独立 `Task` 中消费
- 通过 `await MainActor.run { store.dispatch(...) }` 确保 dispatch 在主线程
- Stream 生命周期与 Middleware 相同（App 全生命周期）

### 场景二：节流批量派发（BLEStreamMiddleware）

**问题**：心率数据以 1Hz 到达，但可能有突发批量数据，需要节流到 ≤2Hz 更新 UI。

```swift
// BLEStreamMiddleware.swift
public func makeBLEStreamMiddleware(
    deviceRepo: any DeviceRepository,
    throttleInterval: TimeInterval = 0.5
) -> Middleware<AppState, Action> {
    { store, action, next in
        next(action)

        switch action {
        case .connectionStateChanged(.connected):
            Task {
                var lastDispatchTime = Date.distantPast
                var batch: [HeartRateSample] = []

                for await sample in deviceRepo.heartRateStream {
                    batch.append(sample)
                    let now = Date()
                    if now.timeIntervalSince(lastDispatchTime) >= throttleInterval {
                        let samples = batch
                        batch = []
                        lastDispatchTime = now
                        await MainActor.run {
                            store.dispatch(.heartRateReceived(samples))
                        }
                    }
                }
            }
        default:
            break
        }
    }
}
```

**模式总结**：
- 连接成功时才启动 stream 消费
- 累积 batch + 时间节流（500ms 窗口）
- 批量 dispatch（一次 dispatch 多个 sample），减少 Reducer 调用次数

### 场景三：Action 触发异步计算（ComputeMiddleware）

**问题**：收到心率数据后，需要异步执行 C++ HRV 计算（CPU 密集），不能阻塞 MainActor。

```swift
// ComputeMiddleware.swift
case .heartRateReceived(let samples):
    // 1. 累积 RR 间期到滑动窗口
    for sample in samples {
        for rr in sample.rrIntervals {
            rrBuffer.append((sample.timestamp, rr))
        }
    }
    // 2. 修剪到 5 分钟窗口
    rrBuffer = rrBuffer.filter { $0.date >= windowStart }

    // 3. 每 30 秒触发一次计算
    if now.timeIntervalSince(lastComputeTime) >= stepInterval, rrBuffer.count >= 2 {
        lastComputeTime = now
        store.dispatch(.computeStarted)  // 立即更新状态

        let rrValues = rrBuffer.map { UInt16($0.rr) }
        Task {
            do {
                let metrics = try computeRepo.computeHRV(from: rrValues)
                await MainActor.run {
                    store.dispatch(.hrvComputed(metrics))
                }
                let features = FeatureVector(metrics: metrics)
                await MainActor.run {
                    store.dispatch(.featuresExtracted(features))
                }
            } catch {
                await MainActor.run {
                    store.dispatch(.errorOccurred(.computeFailed))
                }
            }
        }
    }
```

**模式总结**：
- Middleware 闭包捕获 `rrBuffer` 和 `lastComputeTime` 作为私有状态
- 同步更新 Reducer（`computeStarted`），异步执行计算
- `Task {}` 中执行 C++ 调用（脱离 MainActor），完成后 `await MainActor.run` 回到主线程
- **级联 dispatch**：`computeStarted` → `hrvComputed` → `featuresExtracted`，形成管线

### 场景四：Action 链式推理（InferenceMiddleware）

**问题**：特征提取完成后，触发 CoreML 推理。

```swift
// InferenceMiddleware.swift
case .featuresExtracted(let features):
    store.dispatch(.inferenceStarted)  // 同步更新状态
    Task {
        do {
            let result = try await inferenceRepo.runInference(features: features.values)
            await MainActor.run {
                store.dispatch(.inferenceCompleted(result))
            }
        } catch {
            await MainActor.run {
                store.dispatch(.errorOccurred(.inferenceFailed))
            }
        }
    }
```

**模式总结**：
- 监听上游 Action（`featuresExtracted`），触发下游异步工作
- 形成 **Action 链**：`heartRateReceived` → `computeStarted` → `hrvComputed` → `featuresExtracted` → `inferenceStarted` → `inferenceCompleted`
- 每个 Middleware 只关心自己的那一段，解耦清晰

### 场景五：定时轮询（WaveformMiddleware）

**问题**：波形数据通过 RingBuffer 传递，需要定时轮询取出并 dispatch。

```swift
// WaveformMiddleware.swift
Task {
    while !Task.isCancelled {
        // 后台时降低轮询频率
        let lifecycle = await MainActor.run { store.state.lifecycle }
        if lifecycle == .background {
            try? await Task.sleep(nanoseconds: UInt64(backgroundPollInterval * 1e9))
            continue
        }

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

        try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1e9))  // 100ms = 10Hz
    }
}
```

**模式总结**：
- `while !Task.isCancelled` 长生命周期轮询
- 读取 Store state（`store.state.lifecycle`）来决定行为
- 前台 10Hz、后台降频，节省资源

### 场景六：Action 过滤/吞掉（BackgroundMiddleware）

**问题**：后台时需要丢弃某些不必要的 Action，减少 CPU 和电量消耗。

```swift
// BackgroundMiddleware.swift
{ store, action, next in
    // 根据策略决定是否丢弃 action
    if shouldDrop(action: action, state: store.state, policy: policy) {
        return  // 不调用 next(action)，Action 被吞掉
    }
    next(action)  // 正常传递
}
```

**过滤规则**（后台时）：
- 丢弃 `waveformSamplesReceived` / `waveformMetricsUpdated`（暂停波形渲染）
- 丢弃 `featuresExtracted` / `inferenceStarted` / `inferenceCompleted`（暂停压力推理）
- 丢弃 `computeStarted` / `hrvComputed`（除非正在睡眠监控）

**模式总结**：Middleware 可以不调用 `next(action)` 来实现 Action 拦截/过滤。

### 场景七：后置观察（LoggingMiddleware）

**问题**：记录每个 Action 执行后的状态快照，用于崩溃诊断。

```swift
// LoggingMiddleware.swift
{ store, action, next in
    next(action)           // 先让 reducer 执行
    let after = store.state // 读取更新后的 state

    let entry = "\(action) → connection=\(after.connection) hr=\(after.live.currentHeartRate ?? 0)"
    StateTransitionRecorder.shared.record(entry)
}
```

**模式总结**：`next(action)` 之后读取 `store.state` 获取 reducer 执行后的状态。

## 4. 线程模型总结

```
┌─────────────────────────────────────────────────────────────┐
│ 后台队列 (bleQueue / global)                                │
│   BLE 回调 → AsyncStream.yield()                            │
│   C++ 计算（Task 中）                                       │
│   CoreML 推理（Task 中）                                    │
└────────────────────┬────────────────────────────────────────┘
                     │ await MainActor.run { store.dispatch(...) }
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ MainActor                                                   │
│   Store.dispatch() → Middleware chain → Reducer → State     │
│   SwiftUI 读取 State → View 刷新                            │
└─────────────────────────────────────────────────────────────┘
```

**规则**：
- 所有 `store.dispatch()` 必须在 MainActor 上
- 异步工作（BLE 流消费、C++ 计算、CoreML 推理）在 `Task {}` 中执行
- 结果通过 `await MainActor.run { store.dispatch(...) }` 回到主线程
- Store reduce 串行执行，不存在状态竞争

## 5. Middleware 组合顺序

```swift
let middleware: [Middleware<AppState, Action>] = [
    makeBackgroundMiddleware(),      // 1. 最外层：过滤后台不需要的 Action
    makeConnectionMiddleware(...),   // 2. BLE 连接编排
    makeBLEStreamMiddleware(...),    // 3. 心率数据流
    makeComputeMiddleware(...),      // 4. HRV 计算
    makeInferenceMiddleware(...),    // 5. CoreML 推理
    makeSleepMiddleware(...),        // 6. 睡眠管线
    makeLoggingMiddleware(),         // 7. 日志（后置观察）
    makeWaveformMiddleware(...),     // 8. 波形轮询
    makeOTAMiddleware(...),          // 9. OTA 进度
]
```

**顺序影响**：
- `BackgroundMiddleware` 在最外层，可以吞掉 Action 不让后续 Middleware 处理
- `LoggingMiddleware` 靠后，可以观察到前面所有 Middleware 和 Reducer 产生的最终状态
