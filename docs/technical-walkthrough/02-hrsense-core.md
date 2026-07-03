# 02 · HRSenseCore — 领域层

> **路径**: `Sources/HRSenseCore/`  
> **依赖**: 无  
> **被依赖**: `HRSenseData`, `HRSenseFeature`, `HRSenseCompute`

## 1. 模块定位

`HRSenseCore` 是 Clean Architecture 的 Domain 层——定义所有领域实体、Repository 协议（接口）和 UseCase。上层（Feature）依赖此处的协议，Data 层提供实现，实现**依赖倒置**。

核心原则：
- 不导入 CoreBluetooth、SwiftData、CoreML 等框架
- 不包含任何 I/O 逻辑
- 所有类型均为 `Sendable`，支持 Swift 6 严格并发

## 2. 领域实体

### 2.1 核心数据类型

| 实体 | 说明 |
|------|------|
| `HeartRateSample` | 心率采样点：heartRate, rrIntervals, timestamp, battery, sensorStatus, sampleSeq |
| `RRInterval` | RR 间期（ms） |
| `HRVMetrics` | 14 项 HRV 指标：sdnn, rmssd, pnn50, meanRR, hr, lfPower, hfPower, lfHfRatio, totalPower, sd1, sd2, sampleEntropy, dfaAlpha1, stressIndex |
| `FeatureVector` | 14 维特征向量（喂给 CoreML） |
| `InferenceResult` | 推理结果：label, probabilities, inferenceTimeMs, modelVersion |
| `WaveformSample` | 波形采样：timestamp, value, channelType(ECG/PPG) |
| `WaveformMetrics` | 波形吞吐指标 |

### 2.2 连接与设备

| 实体 | 说明 |
|------|------|
| `DeviceInfo` | 设备信息：peripheralIdentifier, name, model, firmwareVersion, protocolVersion, capabilities |
| `ConnectionState` | 枚举：idle, scanning, connecting, handshaking, connected, disconnecting, disconnected, restored, restoredValidating, restoredConnected |
| `AppLifecycleState` | 枚举：active, background, restoring |

### 2.3 OTA

| 实体 | 说明 |
|------|------|
| `OTAFirmwareImage` | 固件镜像：imageSize, newVersion |
| `OTAProgress` | 进度状态：phase(preparing/transferring/validating/applying/completed/failed), transferProgress, bytesWritten, totalBytes |

### 2.4 睡眠

| 实体 | 说明 |
|------|------|
| `SleepStagePrediction` | 推理结果：stage(Wake/Light/Deep/REM), confidence, timestamp, modelVersion |
| `SleepStageSegment` | 时间段：stage, startAt, endAt |
| `SleepSession` | 一次睡眠：id, date, stages[], modelVersion |
| `SleepWindowInput` | 推理输入窗口：metrics(HRVMetrics), timeContext, cxxFeatures(SleepCXXFeatures) |
| `SleepModelFeatureSpec` | 模型特征合约（18 维特征名+索引映射） |

### 2.5 错误

`AppError` 是全局统一错误枚举，所有错误通过它流入 `AppState.error`：

```swift
enum AppError: Error {
    case connectionTimeout
    case connectionLost
    case bluetoothPoweredOff
    case deviceNotFound
    case handshakeFailed(reason: String)
    case protocolError(detail: String)
    case commandTimeout(opcode: UInt8)
    case computeFailed
    case inferenceFailed
    case sleepInferenceFailed
    case otaFailed(phase: String)
    case persistenceFailed(reason: String)
}
```

连接类错误（`connectionTimeout`, `connectionLost`, `bluetoothPoweredOff`）会额外触发 Reducer 中的强制断连。

### 2.6 持久化模型

`PersistenceModels.swift`（~430 行）定义了跨层传输的持久化记录结构体：`Session`, `HeartRateSampleRecord`, `RRSampleRecord`, `HRVMetricRecord`, `InferenceRecord`, `SleepSession`（持久化版本）, `WaveformBlobRef`, `EventRecord` 等。这些是纯值类型，与 SwiftData `@Model` 隔离。

## 3. Repository 协议

### 3.1 DeviceRepository

BLE 设备通信的抽象接口：

```swift
protocol DeviceRepository: AnyObject, Sendable {
    var connectionState: ConnectionState { get }
    var connectionStateStream: AsyncStream<ConnectionState> { get }
    var discoveredDevicesStream: AsyncStream<DeviceInfo> { get }
    var heartRateStream: AsyncStream<HeartRateSample> { get }
    var deviceInfoStream: AsyncStream<DeviceInfo> { get }
    var restoredPeripheralIDsStream: AsyncStream<[UUID]> { get }

    func startScanning() async
    func stopScanning()
    func connect(to deviceID: UUID) async throws
    func disconnect()
    func sendCommand(_ opcode: UInt8, payload: Data) async throws -> Data
    func performHandshake() async throws -> DeviceInfo
    func restoreConnection(cachedDevice: DeviceInfo?) async throws -> DeviceInfo
}
```

关键设计：所有异步事件通过 `AsyncStream` 暴露，上层 Middleware 用 `for await` 消费。

### 3.2 ComputeRepository

```swift
protocol ComputeRepository: Sendable {
    func computeHRV(from rrIntervals: [UInt16]) async throws -> HRVMetrics
    func extractFeatures(from metrics: HRVMetrics) -> FeatureVector
    func computeSleepFeatures(heartRates: [Double], hrvWindowValues: [Double]) throws -> SleepCXXFeatures
}
```

### 3.3 InferenceRepository

```swift
protocol InferenceRepository: Sendable {
    func infer(features: FeatureVector) async throws -> InferenceResult
}
```

### 3.4 SleepInferenceRepository

```swift
protocol SleepInferenceRepository: Sendable {
    func inferSleepStage(input: SleepWindowInput) async throws -> SleepStagePrediction
}
```

### 3.5 OTARepository

```swift
protocol OTARepository: AnyObject, Sendable {
    var progressStream: AsyncStream<OTAProgress> { get }
    func startOTA(image: OTAFirmwareImage) async throws
    func abortOTA()
    func cancelOTA()
}
```

### 3.6 PersistenceStore

```swift
protocol PersistenceStore: Sendable {
    func saveSession(_ session: Session) async throws
    func saveHeartRateSamples(_ samples: [HeartRateSampleRecord]) async throws
    func saveSleepSession(_ session: SleepSession) async throws
    func querySleepSessions(_ query: SleepSessionQuery) async throws -> [SleepSession]
    // ... 更多查询/保存方法
}
```

### 3.7 WaveformRingBufferProtocol

```swift
protocol WaveformRingBufferProtocol: Sendable {
    func push(_ samples: [WaveformSample])
    func drain() -> [WaveformSample]
    func recordBlock(bytes: Int, blockSeq: UInt32, sampleCount: UInt16)
}
```

## 4. UseCase

三个轻量 UseCase 封装单次业务规则：

- `ConnectDeviceUseCase` — 调用 `deviceRepo.connect()` + `performHandshake()`
- `StartMonitoringUseCase` — 启动心率监控流
- `OTAUpdateUseCase` — 编排 OTA 流程（start → transfer → validate → apply）

UseCase 是纯业务逻辑，通过 Repository 协议访问数据，不感知 BLE/CoreML 细节。
