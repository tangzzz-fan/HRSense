# 工程最佳实践剖析

> 以资深 iOS 开发专家视角，梳理 HRSense 项目中值得学习的设计模式与工程实践。

---

## 1. 闭环设计（Closed-Loop Design）

### 1.1 什么是闭环

"闭环"指系统的每个操作都有明确的开始、执行、结果反馈与错误处理路径，不存在"发射后不管"的操作。

### 1.2 项目中的闭环体现

#### ① Action 闭环：每个操作都有对应的状态转换

```
connect → connectionStateChanged(.connecting) → connectionStateChanged(.connected)
                                              → errorOccurred(.connectionTimeout)

computeStarted → hrvComputed(metrics)
               → errorOccurred(.computeFailed)

inferenceStarted → inferenceCompleted(result)
                 → errorOccurred(.inferenceFailed)
```

**原则**：每个"开始"动作都有对应的"完成"和"失败"路径，Reducer 中显式处理所有状态。

#### ② BLE 命令闭环：Write With Response + 超时 + 重试

```swift
// 文档 03-ble-gatt-protocol.md §8
// 所有 App→设备命令使用 Write With Response（ATT 层确认）
// 语义层面：取数类命令回专用响应帧，其余回 ACK 帧
// 命令超时 2s、重试最多 3 次
```

#### ③ OTA 闭环：完整生命周期

```
OTA_START → WINDOW_BEGIN → [chunk × N] → WINDOW_ACK → VALIDATE → APPLY
     ↓          ↓               ↓              ↓           ↓         ↓
  准备中     开始传输       逐块发送       确认窗口     校验 CRC   应用固件
                                                        ↓
                                              completed / failed
```

#### ④ 睡眠监测闭环：从采集到持久化

```
连接建立 → monitoringStarted → hrvComputed → windowPrepared → inferenceStarted
    → inferenceCompleted → sessionUpdated → sessionPersisted → historyLoaded
断连    → monitoringStopped
```

每个环节都有对应的 Action 和 State 转换。

---

## 2. 可观测性设计（Observability）

### 2.1 分层日志系统

```swift
// 8 个日志分类 + 5 个级别
public enum HRSenseLogCategory: String, CaseIterable {
    case bleRaw       // 原始 BLE 字节 (hex dump)
    case bleFrame     // 分片/重组/CRC/序号
    case bleConn      // 扫描/连接/断连/重连/MTU
    case protoCmd     // 命令/响应/ACK/协商
    case state        // Redux 状态转换
    case ota          // OTA 阶段/进度/错误
    case computeInfer // 计算 + 推理计时
    case perf         // 吞吐量/丢包/帧率
}

public enum HRSenseLogLevel: Int, Comparable {
    case debug, info, notice, error, fault
}
```

**亮点设计**：
- **运行时过滤**：`LogFilter` 支持动态开关每个 category 和调整最低 level
- **@autoclosure 消息**：避免不必要的字符串构造开销
- **OSLog 桥接**：`OSLogHRSenseLogger` 将日志转发到系统 Console.app
- **双写**：同时写 OSLog 和 `LogRingBuffer`（供导出）

```swift
public static func info(_ category: HRSenseLogCategory, _ message: @autoclosure () -> String) {
    let msg = message()
    LoggingRegistry.shared.ringBuffer.append(LogEntry(...))  // 写 Ring Buffer
    LoggingRegistry.shared.logger.log(.info, category: category, msg)  // 写 OSLog
}
```

### 2.2 状态转换记录（Crash 取证）

```swift
// LoggingMiddleware.swift
public final class StateTransitionRecorder: @unchecked Sendable {
    private var transitions: [String] = []  // Ring buffer，容量 50

    public func record(_ transition: String) {
        transitions.append(transition)
        if transitions.count > capacity {
            transitions.removeFirst(transitions.count - capacity)
        }
    }
}

// 每个 action 执行后记录
let entry = "\(action) → connection=\(after.connection) hr=\(after.live.currentHeartRate ?? 0) err=\(after.error)"
StateTransitionRecorder.shared.record(entry)
```

**价值**：Crash 发生时，`MetricKitManager` 读取最近 50 条状态转换，嵌入 crash report，帮助定位"crash 前发生了什么"。

### 2.3 MetricKit 集成

```swift
// MetricKitManager.swift
public func didReceive(_ payloads: [MXDiagnosticPayload]) {
    for payload in payloads {
        let transitions = StateTransitionRecorder.shared.recentTransitions

        if let crashDiag = payload.crashDiagnostics {
            for crash in crashDiag {
                let info = "CRASH: reason=\(crash.terminationReason ?? "unknown")"
                appendDiagnostic(info, transitions: transitions)
            }
        }

        if let hangDiag = payload.hangDiagnostics {
            let duration = hang.hangDuration.value / 1_000_000_000.0
            let info = "HANG: duration=\(String(format: "%.1f", duration))s"
            appendDiagnostic(info, transitions: transitions)
        }

        if let cpuDiag = payload.cpuExceptionDiagnostics {
            let info = "CPU_EXCEPTION: count=\(cpuDiag.count)"
            appendDiagnostic(info, transitions: transitions)
        }
    }
}
```

**闭环**：MetricKit → 关联状态转换 → DiagnosticPanelView 展示 → 导出 JSON 分享

### 2.4 实时 KPI 仪表盘

```swift
// DiagnosticPanelView — 6 个核心 KPI
kpiRow("Connection Rate",     "\(kpi.connectionSuccessRate)%")
kpiRow("Reconnects",          "\(kpi.reconnectCount)")
kpiRow("Cmd Timeout Rate",    "\(kpi.commandTimeoutRate)%")
kpiRow("Sample Loss Rate",    "\(kpi.sampleLossRate)%")
kpiRow("Throughput",          "\(kpi.throughputBytesPerSec) B/s")
kpiRow("OTA Success Rate",    "\(kpi.otaSuccessRate)%")
```

**设计原则**：
- 所有关键路径都有对应的 KPI 指标
- `MetricsCollector` 用 `NSLock` 保护，线程安全
- 1 秒定时刷新，开发阶段可实时观察

### 2.5 诊断包导出（Diagnostic Export）

```swift
public struct DiagnosticPackage: Codable {
    public let logEntries: [LogEntry]              // 最近 500 条日志
    public let stateTransitions: [String]          // 最近 50 条状态转换
    public let metricsSnapshot: MetricsSnapshotJSON // KPI 快照
    public let latestFeatureVector: FeatureVectorSnapshotJSON?  // 最新特征向量
    public let latestInference: InferenceSnapshotJSON?          // 最新推理结果
    public let systemInfo: SystemInfo              // App 版本 / OS / 设备
}
```

**一键导出**：JSON → 临时文件 → ShareLink → 发送给开发者分析。

---

## 3. 后台执行策略（Background Middleware）

### 3.1 精细化 Action 过滤

```swift
private func shouldDrop(action: Action, state: AppState, policy: BackgroundExecutionPolicy) -> Bool {
    guard state.lifecycle == .background else { return false }

    switch action {
    case .waveformSamplesReceived, .waveformMetricsUpdated:
        return policy.pauseWaveformRenderingInBackground     // 后台不更新波形

    case .featuresExtracted, .inferenceStarted, .inferenceCompleted:
        return policy.pauseStressInferenceInBackground       // 后台不做压力推理

    case .computeStarted, .hrvComputed:
        return policy.pauseComputeInBackgroundUnlessSleepMonitoring && !state.sleep.isMonitoring
        // 后台有睡眠监测时继续计算，否则暂停

    default:
        return false  // BLE 连接、OTA 等不受影响
    }
}
```

**设计亮点**：
- **策略驱动**：`BackgroundExecutionPolicy` 可配置
- **条件保留**：睡眠监测期间不暂停计算
- **窄范围拦截**：只 drop 非必要的 UI/ML 动作，不影响核心 BLE 连通性

### 3.2 后台清理任务

```swift
// BackgroundTaskScheduler — 注册 BGAppRefreshTask
public func activate() {
    register()           // 注册 iOS BGTask
    scheduleNextRun()    // 调度下次运行（15 分钟后）
    runLaunchSweep()     // 启动时立即执行一次清理
}
```

**三层保障**：
1. **启动时清理**：每次 App 启动立即执行 retention cleanup
2. **后台任务**：iOS BGAppRefreshTask 定期触发
3. **过期归档**：原始数据 → 分钟级聚合 → 删除原始

---

## 4. 错误处理体系

### 4.1 统一错误枚举

```swift
public enum AppError: Error, Equatable, Sendable {
    case bluetoothUnauthorized
    case bluetoothPoweredOff
    case deviceNotFound
    case connectionTimeout
    case connectionLost
    case handshakeFailed(reason: String)
    case commandTimeout(opcode: UInt8)
    case protocolError(detail: String)
    case decodeError
    case computeFailed
    case inferenceFailed
    case sleepInferenceFailed
    case persistenceFailed(reason: String)
    case modelLoadFailed
    case otaFailed(phase: String)
}
```

**设计原则**：
- 所有到达 UI 的错误必须表达为 `AppError`
- `Equatable` 支持 UI 去重和测试断言
- `LocalizedError` 提供用户友好的描述
- 关联值（如 `opcode: UInt8`）提供调试上下文

### 4.2 Reducer 中的错误驱动状态转换

```swift
case .errorOccurred(let error):
    state.error = error
    // 错误类型驱动对应的子状态重置
    switch error {
    case .computeFailed:     state.metrics.computationStatus = .idle
    case .inferenceFailed:   state.inference.status = .idle
    case .sleepInferenceFailed: state.sleep.status = .idle
    default: break
    }
    // 连接类错误强制断连
    switch error {
    case .connectionTimeout, .connectionLost, .bluetoothPoweredOff:
        state.connection = .disconnected
    default: break
    }
```

---

## 5. 依赖注入与组合根

### 5.1 Composition Root 模式

```swift
// AppComposition.swift — 所有依赖在此组装
public static func makeAppShell() -> AppShell {
    // 1. 创建基础设施
    let waveformBuffer = WaveformRingBuffer()
    let bleDataSource = BLECentralDataSource(waveformRingBuffer: waveformBuffer)

    // 2. 创建 Repository 实现
    let deviceRepo = DeviceRepositoryImpl(bleDataSource: bleDataSource)
    let computeRepo = ComputeRepositoryImpl()
    let inferenceRepo = InferenceRepositoryImpl()

    // 3. 组装 Middleware
    let middleware = [
        makeConnectionMiddleware(deviceRepo: deviceRepo, ...),
        makeComputeMiddleware(computeRepo: computeRepo),
        // ...
    ]

    // 4. 创建 Store
    let store = Store(initialState: AppState(), reducer: AppReducer.reduce, middlewares: middleware)

    // 5. 组装诊断面板
    let diagnosticPanelModel = DiagnosticPanelModel(dependencies: ...)

    return AppShell(store: store, diagnosticPanelModel: diagnosticPanelModel, ...)
}
```

**原则**：
- View 层不做依赖构造，只接收 `Store` 和 `ViewModel`
- 所有 `Repository` 以协议类型注入，支持替换为 Mock
- 闭包注入（如 `backoffProvider`）避免循环引用

### 5.2 依赖倒置

```
HRSenseCore (Domain)     → 定义 Repository 协议
HRSenseData (Infra)      → 实现 Repository 协议
HRSenseFeature (UI)      → 消费 Repository 协议（通过 Middleware）
HRSenseAppUI (Composition) → 将实现注入到消费者
```

---

## 6. 持久化设计

### 6.1 批量写入（BackgroundWriteBuffer）

```swift
public actor BackgroundWriteBuffer<Element: Sendable> {
    public func enqueue(_ elements: [Element]) async throws {
        pending.append(contentsOf: elements)

        if pending.count >= threshold {  // 阈值触发
            try await flush()
        } else {
            scheduleFlushIfNeeded()      // 定时触发（5s 间隔）
        }
    }
}
```

**设计亮点**：
- **Actor 隔离**：Swift actor 自动保证串行访问
- **双触发条件**：阈值（100 条）或超时（5s），先到先触发
- **不阻塞生产者**：BLE 数据接收不因 I/O 等待

### 6.2 数据保留策略

```swift
// RetentionCleanupTask — 分级保留
policy.rawSampleRetentionDays = 7       // 原始样本保留 7 天
policy.waveformRetentionDays = 30       // 波形文件保留 30 天
policy.maxTotalStorageBytes = 500 MB    // 总存储上限

// 过期前归档：原始数据 → 分钟级聚合 → 删除原始
```

### 6.3 波形文件存储

```swift
// WaveformFileStore — 文件系统存储（非 SQLite）
// 大块二进制数据不适合放数据库，用文件系统 + 数据库引用
store.saveWaveformBlobRef(fileID: ..., fileSize: ..., startTimestamp: ...)
waveformFileStore.writeChunks(data, fileID: ...)
```

**原则**：结构化元数据 → SwiftData，大块二进制 → 文件系统。

---

## 7. 并发安全模式

### 7.1 @unchecked Sendable + NSLock

```swift
public final class WaveformRingBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [WaveformSample] = []

    public func push(_ samples: [WaveformSample]) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(contentsOf: samples)
    }
}
```

**适用场景**：需要引用语义（共享状态）且无法用 actor 的场合。

### 7.2 Actor 隔离

```swift
public actor BackgroundWriteBuffer<Element: Sendable> { ... }
public actor RetentionCleanupTask { ... }
```

**适用场景**：独立的工作单元，无跨 actor 调用开销的场景。

### 7.3 MainActor.run 包裹 dispatch

```swift
// 所有 store.dispatch 都包裹在 MainActor.run 中
Task {
    let metrics = try computeRepo.computeHRV(from: rrValues)
    await MainActor.run {
        store.dispatch(.hrvComputed(metrics))
    }
}
```

**不变量**：`Store.dispatch()` 永远在 MainActor 上执行，Reducer 无需考虑并发。
