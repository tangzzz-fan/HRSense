# M4 · Redux 展示层（Clean + Redux）— 实施计划

## 摘要

将数据流接入 Redux，完成实时展示与状态管理。M4 创建 `HRSenseFeature` 模块（State/Action/Reducer/Middleware/SwiftUI Views）。M4 假设 M3 交付物（`HRSenseCore` 实体与 Repository 协议、`HRSenseData` BLE 数据源实现）已存在。

**关键约束**：`HRSenseFeature` 不得直接导入 `HRSenseData`。中间件通过 `HRSenseCore` 中定义的 Repository 协议注入。

---

## 阶段 1：前置 — 新增 `AppError`

在 `Sources/HRSenseCore/Entities/AppError.swift` 中定义（纯域枚举，无框架依赖）：

```swift
public enum AppError: Equatable {
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
    case modelLoadFailed
    case otaFailed(phase: String)
}
```

---

## 阶段 2：State 与 Action 类型

### State（`Sources/HRSenseFeature/State/`）

| 文件 | 关键字段 |
|---|---|
| `AppState.swift` | `connection`、`device`、`live`、`metrics`、`inference`、`ota`、`error` — 根状态结构体，全部 Equatable |
| `LiveState.swift` | `currentHeartRate: Int?`、`recentSamples: [HeartRateSample]`（有界 ~600 点）、`lastUpdated: Date?` |
| `MetricsState.swift` | `latestHRV: HRVMetrics?`、`computationStatus` |
| `InferenceState.swift` | `latestResult: InferenceResult?`、`inferenceStatus` |
| `OTAState.swift` | `phase`、`progress`（M4 占位桩） |

### Action（`Sources/HRSenseFeature/Actions/Action.swift`）

`Action` 作为全局根枚举在此集中维护；后续 M8（特征提取/推理）与 M10（生命周期/恢复）只允许在同一根枚举上增量扩展，不新增旁路 action 体系。

```swift
public enum Action {
    case startScanning, stopScanning
    case deviceDiscovered(DeviceInfo)
    case connect(deviceID: String), disconnect
    case connectionStateChanged(ConnectionState)
    case heartRateReceived([HeartRateSample])
    case deviceEvent(DeviceEvent)
    case hrvComputed(HRVMetrics)
    case inferenceCompleted(InferenceResult)
    case dismissError, clearSamples
    case errorOccurred(AppError)
    case otaStateChanged(OTAState)
}
```

---

## 阶段 3：Reducer（纯函数）

`Sources/HRSenseFeature/Reducer/AppReducer.swift` — `(inout AppState, Action) -> Void`

关键规则：

| Action | State 变更 |
|---|---|
| `heartRateReceived` | 追加至 `recentSamples`，`suffix(600)` 截断 |
| `connectionStateChanged` | 更新 `connection`，connected 时清 `error` |
| `hrvComputed` | 设置 `metrics.latestHRV` |
| `inferenceCompleted` | 设置 `inference.latestResult` |
| `errorOccurred` | 设置 `error`；连接类错误则设 `connection = .disconnected` |
| `dismissError` | `error = nil` |

Reducer 纯函数测试：给初始 State + Action，断言输出 State。

---

## 阶段 4：假 Repository（测试替身）

`Tests/HRSenseFeatureTests/TestDoubles/FakeRepository.swift`：
- `FakeDeviceRepository` — 可配置的 `heartRateStream`、`connect`、`scanForDevices`
- `FakeComputeRepository` — 可配置的 `computeHRV`
- `FakeInferenceRepository` — 可配置的 `runInference`

---

## 阶段 5：中间件

### ConnectionMiddleware

工厂函数 `makeConnectionMiddleware(deviceRepo:)`：
- `startScanning` → 调用 `deviceRepo.startScan()`，发现设备后 dispatch
- `connect(id)` → 调用 `deviceRepo.connect(id)`
- `disconnect` → 调用 `deviceRepo.disconnect()`
- `connectionStateChanged(.disconnected)` → 指数退避重连（1s→2s→4s→...→60s），`connected` 时重置退避

### BLEStreamMiddleware

工厂函数 `makeBLEStreamMiddleware(deviceRepo:, throttleInterval: 0.5)`：
- `connectionStateChanged(.connected)` → 订阅 `deviceRepo.heartRateStream()`，2Hz 节流批量 dispatch
- 断连时取消流订阅

### ComputeMiddleware / InferenceMiddleware（M4 占位桩）

记录样本数量日志，实际计算延后至 M8。

### 中间件测试

使用 spy 模式跟踪 dispatch 的 Action 序列，通过假 Repository 注入数据，断言中间件产生正确的 Action 序列。

---

## 阶段 6：SwiftUI Views

| View | 职责 |
|---|---|
| `HeartRateView` | 大号当前心率数值，`nil` 时显示 "--" |
| `HRTrendChart` | Swift Charts，LTTB 降采样至 ~120 点 |
| `ConnectionStatusView` | 颜色+标签映射，扫描/断开按钮 |
| `ErrorBannerView` | `AppError` → 可读消息，下滑 dismiss |
| `RootView` | 组合所有子视图，`.provideStore(store)` |

---

## 阶段 7-8：集成

更新 `Package.swift` 添加 `HRSenseFeature` target（依赖 `HRSenseCore` + `TGReduxKit`，不依赖 `HRSenseData`）。

更新 `AppComposition.swift`：实例化 Repository 实现、注入中间件工厂、创建 Store。

```swift
Store(
    initialState: AppState(),
    reducer: appReducer,
    middlewares: [
        makeConnectionMiddleware(deviceRepo: deviceRepo),
        makeBLEStreamMiddleware(deviceRepo: deviceRepo),
        makeComputeMiddleware(computeRepo: computeRepo),
        makeInferenceMiddleware(inferenceRepo: inferenceRepo),
    ]
)
```

---

## 文件清单（~22 个文件）

```
Sources/HRSenseCore/Entities/AppError.swift            [CREATE — 前置]
Sources/HRSenseFeature/
├── State/AppState.swift, LiveState.swift, MetricsState.swift,
│         InferenceState.swift, OTAState.swift
├── Actions/Action.swift
├── Reducer/AppReducer.swift
├── Middleware/ConnectionMiddleware.swift, BLEStreamMiddleware.swift,
│              ThrottleMiddleware.swift, ComputeMiddleware.swift,
│              InferenceMiddleware.swift
└── Views/RootView.swift, HeartRateView.swift, HRTrendChart.swift,
           ConnectionStatusView.swift, ErrorBannerView.swift
Tests/HRSenseFeatureTests/
├── ReducerTests.swift
├── MiddlewareTests.swift
├── ConnectionMiddlewareTests.swift
└── TestDoubles/FakeRepository.swift
```
