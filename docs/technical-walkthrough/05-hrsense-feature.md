# 05 · HRSenseFeature — 展示层（Redux + SwiftUI）

> **路径**: `Sources/HRSenseFeature/`  
> **依赖**: `HRSenseCore`, `HRSenseProtocol`, `TGReduxKit`  
> **被依赖**: `HRSenseAppUI`

## 1. 模块定位

`HRSenseFeature` 是 Clean Architecture 的 Presentation 层，采用 Redux 单向数据流：

```
View → dispatch(Action) → Middleware → Reducer → State → View 刷新
```

**关键约束**：
- 绝不直接 import `HRSenseData`
- Reducer 是纯函数 `(inout State, Action) -> Void`
- 所有 I/O（BLE、计算、推理）在 Middleware 中执行
- Store reduce 在 MainActor 串行，SwiftUI 在主线程消费

## 2. State（状态树）

`AppState` 是单一状态根，所有字段 `Equatable`：

```swift
struct AppState: Equatable, Sendable {
    var lifecycle: AppLifecycleState       // active / background / restoring
    var connection: ConnectionState        // 完整连接状态机
    var discoveredDevices: [DeviceInfo]    // 扫描发现的设备
    var device: DeviceInfo?                // 当前连接设备
    var live: LiveState                    // 实时心率（currentHeartRate, recentSamples[≤600]）
    var metrics: MetricsState              // HRV 指标 + 计算状态
    var inference: InferenceState          // ML 推理结果 + 状态
    var ota: OTAState                      // OTA 进度
    var sleep: SleepState                  // 睡眠监控 + 会话 + 阶段历史
    var waveform: WaveformState            // 波形数据（ECG/PPG，≤7680 点）
    var error: AppError?                   // 当前错误
}
```

**有界窗口**：
- `recentSamples`：最多 600 条（~10 min @ 1Hz）
- `waveform.ecgSamples`：最多 7680 条（~60s @ 128Hz）
- UI 刷新 ≤ 2Hz，趋势线下采样至 ~120 点

## 3. Action（动作枚举）

单一 `Action` 枚举覆盖所有状态变更：

```swift
enum Action: Equatable, Sendable {
    // 生命周期
    case didEnterBackground, willEnterForeground
    case restoreInitiated(peripheralIDs: [UUID])
    case restoreConnectionRestored(peripheralIDs: [UUID])
    case restoreFailed(reason: String)

    // 扫描 & 连接
    case startScanning, stopScanning
    case deviceDiscovered(DeviceInfo)
    case connect(deviceID: UUID), disconnect
    case connectionStateChanged(ConnectionState)
    case deviceInfoUpdated(DeviceInfo)

    // 数据
    case heartRateReceived([HeartRateSample])
    case deviceEvent(DeviceEvent)

    // 计算 & 推理
    case computeStarted, hrvComputed(HRVMetrics)
    case inferenceStarted, inferenceCompleted(InferenceResult)
    case featuresExtracted(FeatureVector)

    // 睡眠
    case sleep(SleepAction)

    // OTA
    case otaStateChanged(OTAState)

    // 波形
    case waveformSamplesReceived([WaveformSample])
    case waveformMetricsUpdated(WaveformMetrics)
    case waveformTypeSelected(WaveformType)

    // 错误
    case errorOccurred(AppError), dismissError
    case clearSamples
}
```

## 4. Reducer（纯函数）

`AppReducer.reduce(state:inout, action:)` 按 Action 分支处理，关键规则：

| Action | 状态变更 |
|--------|---------|
| `heartRateReceived` | 追加到 recentSamples，suffix(600) 截断 |
| `connectionStateChanged(.connected)` | 清除 error |
| `connectionStateChanged(.disconnected)` | 清空 device |
| `errorOccurred` | 设置 error；连接类错误强制 `.disconnected` |
| `computeStarted` | metrics.computationStatus = .computing |
| `hrvComputed` | 更新 latestHRV，computationStatus = .ready |
| `inferenceCompleted` | 更新 latestResult，status = .completed |
| `sleep(SleepAction)` | 委托给 `reduceSleep` 子 reducer |

Reducer **不执行任何副作用**——所有 I/O 在 Middleware 中。

## 5. Middleware（副作用编排）

每个 Middleware 对应一个关注点，函数签名：`(Store, Action, Next) -> Void`

### 5.1 ConnectionMiddleware

- 一次性订阅 `deviceRepo.connectionStateStream` / `discoveredDevicesStream` / `deviceInfoStream` / `restoredPeripheralIDsStream`
- `connect` → `deviceRepo.connect()` + `performHandshake()`
- `connectionStateChanged(.disconnected)` → 指数退避自动重连
- `restoreInitiated` → `deviceRepo.restoreConnection()`

### 5.2 BLEStreamMiddleware

- `connectionStateChanged(.connected)` → 订阅 `deviceRepo.heartRateStream`
- 节流至 ≤ 2Hz（500ms 间隔批量 dispatch）

### 5.3 ComputeMiddleware

- `heartRateReceived` → 检查 RR 间期窗口（≥2 个 RR）→ `computeRepo.computeHRV()` → dispatch `hrvComputed`

### 5.4 InferenceMiddleware

- `hrvComputed` → `computeRepo.extractFeatures()` → dispatch `featuresExtracted` → `inferenceRepo.infer()` → dispatch `inferenceCompleted`

### 5.5 SleepMiddleware（~225 行）

最复杂的 Middleware，编排睡眠管线：

1. `connectionStateChanged(.connected)` → 启动睡眠监控
2. `hrvComputed` → 构建 `SleepWindowInput`（5 分钟窗口 + 4 小时昼夜历史）→ 调用 `sleepInferenceRepo.inferSleepStage()` → 合并预测到 `SleepSession` → 持久化
3. `sessionPersisted` → 重新加载历史记录

关键辅助：
- `mergeSleepPrediction`：相同阶段合并延长时间段，不同阶段新增段
- `makeSleepWindowInput`：从 live samples + HRV 历史构建 18 维特征输入

### 5.6 WaveformMiddleware

- 订阅 `waveformRingBuffer.drain()` 定时输出 → dispatch `waveformSamplesReceived`

### 5.7 OTAMiddleware

- 订阅 `otaRepo.progressStream` → dispatch `otaStateChanged`

### 5.8 LoggingMiddleware

- 记录每个 Action 到 `LoggingRegistry`（环形缓冲区）+ `StateTransitionRecorder`

### 5.9 BackgroundMiddleware

- `didEnterBackground` / `willEnterForeground` → 日志 + 必要资源释放/恢复

## 6. Views（SwiftUI）

### 6.1 RootView（~354 行）

主视图，组合所有子视图：
- 连接状态（颜色指示灯 + Scan/Disconnect 按钮）
- 设备发现列表（Connect 按钮）
- 设备信息（model + firmware version）
- 实时心率（大字体数字）
- 推理结果（Stress/Baseline + 概率 + 推理时间）
- 睡眠监控（当前会话 + SleepHypnogramView + 特征合约显示）
- 历史睡眠会话（最近 3 次）
- 波形显示（ECG/PPG 切换）
- 错误横幅

### 6.2 专用视图

| 视图 | 说明 |
|------|------|
| `SleepHypnogramView` | Canvas 绘制睡眠阶段时间线（Wake/Light/Deep/REM 色带） |
| `WaveformCanvasView` | Canvas 实时绘制 ECG/PPG 波形 |
| `WaveformDisplayView` | 波形 + 通道选择器 |
| `DiagnosticPanelView` | KPI 面板：吞吐、丢包、重连次数、日志导出 |
| `OTAUpgradeView` | OTA 升级 UI：进度条 + 状态 |
| `ThroughputPanelView` | 吞吐统计面板 |

## 7. Observability（可观测性）

### 7.1 DiagnosticPanelModel

聚合多源诊断数据：
- `KPISnapshot`：来自 MetricsCollector
- `LogEntries`：来自 LoggingRegistry 环形缓冲
- `StateTransitions`：来自 StateTransitionRecorder
- `MetricKitDiagnostics`：来自 MetricKitManager
- `MetricsSnapshotJSON` / `FeatureVectorSnapshotJSON` / `InferenceSnapshotJSON`

### 7.2 MetricKitManager

订阅 MetricKit 的 crash/hang 诊断，支持 `MXMetricManager` 回调。
