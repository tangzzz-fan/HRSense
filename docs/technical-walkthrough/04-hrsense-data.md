# 04 · HRSenseData — 数据层

> **路径**: `Sources/HRSenseData/`  
> **依赖**: `HRSenseProtocol`, `HRSenseCore`, `HRSenseCompute`  
> **被依赖**: `HRSenseAppUI`（通过组合根）

## 1. 模块定位

`HRSenseData` 是 Clean Architecture 的 Data 层——实现 `HRSenseCore` 定义的 Repository 协议，封装所有 I/O 细节：BLE 通信、持久化、OTA 传输、ML 服务适配。

**关键约束**：`HRSenseFeature` 绝不直接 import `HRSenseData`，两者仅通过 `HRSenseCore` 的协议接口通信。

## 2. BLE Central（CoreBluetooth 封装）

### 2.1 BLECentralDataSource（~644 行）

项目中**唯一**导入 CoreBluetooth 的文件。将 CBCentralManager/CBPeripheral 的 delegate 回调桥接为 AsyncStream。

**GATT Characteristic 映射**（128-bit 自定义 UUID，Nordic 风格 Short ID）：

| UUID Short | 用途 | 属性 |
|-----------|------|------|
| 0002 | Data/Notify | 设备→App 数据（心率、波形、事件） |
| 0003 | Control/Write | App→设备命令（Write With Response） |
| 0004 | Info | 设备元数据（Read） |
| 0005 | OTA Data | 固件镜像块（Write Without Response） |

**线程模型**：所有 CoreBluetooth 状态隔离在 `bleQueue`（串行 DispatchQueue）上，AsyncStream continuation 可从任意线程 yield。

**核心组件**：

- `HandshakeReadinessGate`：跟踪 notify/write 特征发现 + notify 订阅状态，三者均就绪后才发射 `.handshaking`
- `PendingCommandTimeoutCoordinator`：追踪当前待响应的命令，支持超时取消
- `FrameAssembler`：每连接一个实例，断连时 reset

**命令发送模式**：

```swift
// 发送并等待响应（写 0003，响应从 0002 notify 到达）
func sendCommandAndWait(_ command: Command, timeout: TimeInterval) async throws -> DecodedFrame

// OTA 专用：发送控制命令 + 等待 notify 响应
func sendOTAControlAndWait(_ command: OTACommand, timeout: TimeInterval) async throws -> OTACommand

// OTA 数据通道：Write Without Response
func sendOTAChunk(_ chunk: Data)
```

**Notify 数据路由**：

```
handleNotifyData(data)
    → 先尝试 OTA 裸解码（无帧头，直接 opcode+payload）
    → 若失败，走 FrameAssembler.feed() → DecodedFrame 路由：
        .data(sample) → heartRateStream
        .command(cmd) → commandResponseContinuation
        .ack(ack)     → commandResponseContinuation
        .waveform(block) → waveformRingBuffer
```

**State Preservation/Restoration**：通过 `CBCentralManagerOptionRestoreIdentifierKey` 支持后台恢复，`willRestoreState` 中恢复已连接的 peripheral。

### 2.2 BLEConnectionStateMachine

简单的连接状态跟踪器，管理指数退避（backoff）计数器。

### 2.3 BLEDataParser

将协议层 `DeviceSample` / `WaveformBlock` 转换为领域层 `HeartRateSample` / `WaveformSample`，处理时间戳转换（设备相对 ms → Date）。

## 3. Repository 实现

### 3.1 DeviceRepositoryImpl

包装 `BLECentralDataSource`，实现 `DeviceRepository` 协议：
- `connect()` → BLE connect → service discovery → characteristic discovery → handshake
- `performHandshake()` → HELLO → 等待 HELLO_ACK → START_STREAM
- `restoreConnection()` → 验证 restored peripheral → 重新发现服务 → 重握手

### 3.2 ComputeRepositoryImpl

包装 `ComputeBridge`，将同步 C 调用适配为 `async` 接口。

### 3.3 InferenceRepositoryImpl

包装 `CoreMLService`：
```swift
func infer(features: FeatureVector) async throws -> InferenceResult {
    // ComputeBridge.extractFeatures() → CoreMLService.predict() → InferenceResult
}
```

### 3.4 SleepInferenceRepositoryImpl

调用睡眠阶段分类器（`SleepStageService`，使用 `CoreMLService` 的 `sleepStageClassifier` 配置）。

### 3.5 OTARepositoryImpl（~242 行）

编排完整 OTA 流程：

```
1. OTA_START (0003) → 等待 OTA_START_ACK → 获取 resumeOffset / maxChunkSize / maxWindow
2. 循环：OTA_WINDOW_BEGIN (0003) → 写入 chunk (0005) → 等待 OTA_WINDOW_ACK (0002)
   - 每窗口最多 3 次重试
   - 校验 ACK 中的 recvOffset 和 windowCRC32
3. OTA_VALIDATE (0003) → 等待 OTA_VALIDATE_RESULT → 校验 CRC
4. OTA_APPLY (0003) → 提交新固件
```

支持断点续传：如果 `resumeOffset > 0` 且 CRC32 匹配，从断点继续。

## 4. 持久化

### 4.1 SwiftDataStore（~335 行）

基于 SwiftData 的 `@ModelActor` actor，实现 `PersistenceStore` 协议：

```swift
@ModelActor
public actor SwiftDataStore: PersistenceStore { ... }
```

SwiftData Model 类型（在 `SwiftDataModels.swift`，~598 行）：

| Model | 说明 |
|-------|------|
| `SessionModel` | 监控会话 |
| `HeartRateSampleModel` | 心率采样 |
| `RRSampleModel` | RR 间期 |
| `HRVMetricRecordModel` | HRV 指标记录 |
| `InferenceRecordModel` | 推理记录 |
| `SleepSessionModel` | 睡眠会话 |
| `WaveformBlobRefModel` | 波形文件引用 |
| `EventRecordModel` | 事件记录 |
| `ArchivedHeartRateBucketModel` | 归档心率桶 |
| `ArchivedRRBucketModel` | 归档 RR 桶 |

**隔离原则**：上层只通过 `PersistenceStore` 协议访问，不接触 `@Model`、`ModelContext` 等 SwiftData 类型。未来可替换为 GRDB/SQLite。

### 4.2 InMemoryPersistenceStore（~159 行）

纯内存实现，用于测试。

### 4.3 WaveformFileStore（~281 行）

波形原始数据以二进制文件存储（Documents/waveforms/），与结构化数据库解耦。格式：文件头 + 连续 sample block。

### 4.4 RetentionCleanupTask（~129 行）

数据保留清理：按配置天数删除过期的心率/RR/HRV/推理记录和对应波形文件。

### 4.5 BackgroundTaskScheduler（~131 行）

使用 `BGAppRefreshTask` 调度后台清理任务。

### 4.6 DataAggregation（~146 行）

心率/RR 数据归档聚合：将高频采样压缩为时间桶（bucket），减少长期存储量。

## 5. 辅助组件

### 5.1 WaveformRingBuffer（~79 行）

有界环形缓冲区，存储最近的波形采样（~60s @ 128Hz = 7680 点），支持 `push` / `drain`。

### 5.2 MetricsCollector（~144 行）

实时指标采集器：bytesReceived, samplesReceived, samplesLost, reconnectCount, commandTimeouts, OTA 统计。提供 `kpiSnapshot()` 和 `snapshot()` 给诊断面板。

### 5.3 MTUCalculator

根据连接协商的 MTU 计算有效载荷大小。

### 5.4 SleepStageService（~135 行）

睡眠阶段推理服务：加载 18 维特征的 CoreML 模型，输出 4 类睡眠阶段概率。
