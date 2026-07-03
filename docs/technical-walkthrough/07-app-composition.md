# 07 · HRSenseAppUI — App 壳与组合根

> **路径**: `Sources/HRSenseAppUI/`  
> **依赖**: `HRSenseFeature`, `HRSenseData`, `TGReduxKit`  
> **入口**: `Apps/HRSenseApp/`（iOS）+ `Apps/HRSenseSimulator/`（macOS）

## 1. 模块定位

`HRSenseAppUI` 是 iOS App 的组合根（Composition Root）——负责将所有层的实现组装在一起，建立依赖关系。它也是项目中**唯一**同时依赖 `HRSenseFeature` 和 `HRSenseData` 的模块。

## 2. 组合根（AppComposition）

`AppComposition.makeAppShell()` 在 `@MainActor` 上执行，构造完整的运行时依赖图：

### 2.1 实例化顺序

```swift
1. WaveformRingBuffer            // 波形环形缓冲区
2. BLECentralDataSource          // BLE 数据源（CoreBluetooth）
3. DeviceRepositoryImpl          // 设备 Repository（包装 BLE）
4. ComputeRepositoryImpl         // 计算 Repository（包装 C++）
5. InferenceRepositoryImpl       // 推理 Repository（包装 CoreML）
6. SleepInferenceRepositoryImpl  // 睡眠推理 Repository
7. SwiftDataStore                // 持久化（SwiftData）
8. MetricKitManager.shared       // MetricKit 早期启动
9. OTARepositoryImpl             // OTA Repository（闭包注入 BLE 方法）
```

### 2.2 Middleware 组装

```swift
let middleware: [Middleware<AppState, Action>] = [
    makeBackgroundMiddleware(),           // 前后台生命周期
    makeConnectionMiddleware(             // BLE 连接编排 + 自动重连
        deviceRepo: deviceRepo,
        backoffProvider: { bleDataSource.connectionStateMachine.nextBackoff() }
    ),
    makeBLEStreamMiddleware(              // 心率数据流（节流 2Hz）
        deviceRepo: deviceRepo
    ),
    makeComputeMiddleware(                // HRV 计算
        computeRepo: computeRepo
    ),
    makeInferenceMiddleware(              // CoreML 推理
        inferenceRepo: inferenceRepo
    ),
    makeSleepMiddleware(                  // 睡眠管线
        computeRepository: computeRepo,
        sleepInferenceRepository: sleepInferenceRepo,
        persistenceStore: persistenceStore
    ),
    makeLoggingMiddleware(),              // 日志记录
    makeWaveformMiddleware(               // 波形数据
        waveformRingBuffer: waveformBuffer
    ),
    makeOTAMiddleware(                    // OTA 升级
        otaRepo: otaRepo
    ),
]
```

### 2.3 Store 创建

```swift
let store = Store(
    initialState: AppState(),
    reducer: AppReducer.reduce,
    middlewares: middleware
)
```

`Store` 来自 `TGReduxKit`——基于 Swift Observation 的轻量 Redux 实现，iOS 17+，MainActor 串行 reduce。

### 2.4 诊断面板

`DiagnosticPanelModel` 通过闭包注入多个数据源，按需拉取数据：
- `kpiSnapshotProvider` → `MetricsCollector.kpiSnapshot()`
- `logEntriesProvider` → `LoggingRegistry.shared.ringBuffer.snapshot()`
- `stateTransitionsProvider` → `StateTransitionRecorder.shared.recentTransitions`
- `metricDiagnosticsProvider` → `MetricKitManager.shared.recentDiagnostics`
- `metricsSnapshotProvider` → 完整 metrics 快照（JSON 可序列化）
- `latestFeatureVectorProvider` → 当前推理特征向量
- `latestInferenceProvider` → 最近推理结果
- `systemInfoProvider` → `SystemInfo.current`

### 2.5 运行时服务

```swift
struct RuntimeServices {
    let retentionScheduler: BackgroundTaskScheduler  // 后台清理调度
}
```

由 `makeRuntimeServices()` 创建：
1. `WaveformFileStore` — 波形文件存储
2. `RetentionCleanupTask` — 数据清理任务（SwiftData + 波形文件）
3. `BackgroundTaskScheduler` — BGTask 调度器

## 3. 依赖注入模式

整个项目采用**构造函数注入 + 闭包注入**，不使用任何 DI 框架：

```
Repository 协议 (HRSenseCore)
    ↑ 实现
Repository 实现 (HRSenseData)
    ↑ 实例化 & 传入
Middleware 工厂函数 (HRSenseFeature)
    ↑ 组装
AppComposition (HRSenseAppUI)
    ↓ 产出
Store<AppState, Action>
    ↓ 注入
SwiftUI Views（通过 @Environment）
```

**OTA 闭包注入示例**：

```swift
let otaRepo = OTARepositoryImpl(
    sendOTAControl: { [bleDataSource] command in
        try await bleDataSource.sendOTAControl(command)
    },
    sendOTAChunk: { [bleDataSource] chunk in
        bleDataSource.sendOTAChunk(chunk)
    },
    // ...
)
```

## 4. App 入口

### 4.1 iOS App（Apps/HRSenseApp/）

薄 Xcode 壳，只有：
- `HRSenseIOSApp.swift`：`@main` 入口
- `Info.plist`：BLE 权限（`NSBluetoothAlwaysUsageDescription`）

启动时调用 `AppComposition.makeAppShell()`，将 `Store` 注入 SwiftUI 环境。

### 4.2 macOS Simulator（Apps/HRSenseSimulator/）

薄 Xcode 壳，入口指向 `HRSenseSimulator` 可执行 target 或 `HRSenseSimulatorUI`。

## 5. 端到端数据流（完整路径）

```
[设备/模拟器]
    ↓ BLE notify (0002)
[BLECentralDataSource.handleNotifyData]
    ↓ FrameAssembler.feed() → DecodedFrame.data(sample)
    ↓ BLEDataParser.parseSample()
    ↓ heartRateContinuation.yield(HeartRateSample)
[ConnectionMiddleware]
    ↓ for await state in connectionStateStream → dispatch(.connectionStateChanged)
[BLEStreamMiddleware]
    ↓ for await sample in heartRateStream (throttle 500ms)
    ↓ dispatch(.heartRateReceived([samples]))
[AppReducer]
    ↓ state.live.recentSamples.append(suffix 600)
    ↓ state.live.currentHeartRate = latest
[RootView]
    ↓ @Environment Store → 读取 state.live.currentHeartRate
    ↓ SwiftUI 刷新 → 显示 "72 BPM"
[ComputeMiddleware]
    ↓ 检查 RR 间期窗口 ≥ 2
    ↓ computeRepo.computeHRV(rrIntervals)
    ↓ dispatch(.hrvComputed(metrics))
[InferenceMiddleware]
    ↓ computeRepo.extractFeatures(metrics) → [Float](14)
    ↓ dispatch(.featuresExtracted(vector))
    ↓ inferenceRepo.infer(features) → InferenceResult
    ↓ dispatch(.inferenceCompleted(result))
[RootView]
    ↓ 显示 "Baseline (70%)" 或 "Stress (70%)"
[SleepMiddleware]
    ↓ 构建 SleepWindowInput（5min 窗口 + C++ 特征）
    ↓ sleepInferenceRepo.inferSleepStage(input)
    ↓ mergeSleepPrediction → SleepSession
    ↓ persistenceStore.saveSleepSession()
    ↓ dispatch(.sleep(.sessionUpdated))
[RootView]
    ↓ SleepHypnogramView 绘制阶段时间线
```

## 6. 项目构建

```bash
# SPM 包（库 + 测试）
swift build
swift test

# iOS App（通过 xcworkspace）
xcodebuild -workspace HRSense.xcworkspace -scheme HRSenseApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# macOS Simulator
xcodebuild -workspace HRSense.xcworkspace -scheme HRSenseSimulator \
  -destination 'platform=macOS' build
```

**规则**：始终打开 `HRSense.xcworkspace`，不要单独打开子 `.xcodeproj`。
