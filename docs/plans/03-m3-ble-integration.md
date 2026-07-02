# M3 · App BLE 接入层 — 实施计划

## 摘要

iOS App 连接模拟器、发现服务、订阅并正确解码数据，端到端实时 HR，断线自动重连。创建 `HRSenseCore`（Domain）和 `HRSenseData`（Data）两个模块。M3 是第一个联调节点 🔗。

**硬依赖**：M1（协议库）、M2（模拟器）。

---

## 阶段 1：HRSenseCore — 领域层（零外部依赖）

### Entities

| 文件 | 关键类型 |
|---|---|
| `HeartRateSample.swift` | `timestamp: Date`、`heartRate: Int`、`rrIntervals: [Int]`、`sampleSeq: UInt32?`、`sensorContact` |
| `RRInterval.swift` | `timestamp: Date`、`intervalMs: Int` |
| `DeviceInfo.swift` | `peripheralIdentifier`、`name`、`model`、`firmwareVersion`、`protocolVersion`、`capabilities` |
| `Capabilities.swift` | `OptionSet`、`rawValue: UInt32`、bit0–bit10 静态常量 |
| `ConnectionState.swift` | 枚举：`idle`/`scanning`/`connecting`/`handshaking`/`connected`/`disconnecting`/`disconnected` |
| `AppError.swift` | 规范错误枚举（见 `docs/04` §8.5） |
| `DeviceEvent.swift` | `batteryLevelChanged`/`sensorContactChanged`/`error` |
| `StubTypes.swift` | M5/M8 占位类型（`HRVMetrics`、`InferenceResult`、`OTAPhase`） |

### Repository 协议 + UseCase

| 文件 | 关键 API |
|---|---|
| `DeviceRepository.swift` | `connectionState`、`startScanning()`、`connect(to:)`、`disconnect()`、`heartRateStream: AsyncStream` |
| `ComputeRepository.swift` | `computeHRV(from:)` — M5 占位 |
| `InferenceRepository.swift` | `runInference(features:)` — M8 占位 |
| `ConnectDeviceUseCase.swift` | 封装 `repository.connect(to:)` |
| `StartMonitoringUseCase.swift` | 封装 `repository.startScanning()` |

---

## 阶段 2：HRSenseData — BLE 数据层

### BLE 封装

| 文件 | 职责 |
|---|---|
| `BLECentralDataSource.swift` | **唯一导入 CoreBluetooth 的文件**。`CBCentralManager` 封装，委托回调桥接至 `AsyncStream` |
| `BLEDataParser.swift` | `HRSenseProtocol` 类型 → 领域实体映射，t0 时间戳锚定 |
| `BLEConnectionStateMachine.swift` | Actor，显式状态转换 + 指数退避（1s→2s→4s→...→60s） |
| `BLEReconnectionHandler.swift` | 自动重连循环编排 |

### Repository 实现

| 文件 | 职责 |
|---|---|
| `DeviceRepositoryImpl.swift` | 中央编排器：连接流（connect→discover→subscribe→HELLO→HELLO_ACK→START_STREAM）、数据接收循环、断连处理、重连流 |
| `ComputeRepositoryImpl.swift` | M5 占位桩 |
| `InferenceRepositoryImpl.swift` | M8 占位桩 |

### 可观测性

| 文件 | 职责 |
|---|---|
| `MetricsCollector.swift` | 线程安全计数器：`totalSamplesReceived`、`samplesLost`、`reconnectCount` |

---

## 阶段 3：App 外壳

| 文件 | 职责 |
|---|---|
| `AppComposition.swift` | 构造 `DeviceRepositoryImpl`，装配依赖 |
| `HRSenseAppApp.swift` | `@main` 入口，创建 Store（临时） |
| `DebugConnectionView.swift` | M3 调试视图：连接状态、设备列表、心率值、重连计数 |

---

## 关键流程

### 连接流程
1. `connect(peripheral)` → 状态机切换 `.connecting`
2. 发现服务/特征 → 缓存句柄
3. 订阅通知特征
4. 发送 HELLO → 等待 HELLO_ACK（2s 超时 × 3 次重试）
5. 发送 START_STREAM → 标记 `t0`
6. 状态机切换 `.connected`，重置退避

### 数据接收循环
- notify 字节 → `FrameAssembler.feed` → `.data(sample)` → `parser.parseSample` → yield 至 `heartRateStream`
- `sampleSeq` 缺口检测 → `MetricsCollector.recordSamplesLost`

### 断连 + 重连
- 检测断连 → 状态机切换 `.disconnected` → 退避延迟 → 重新扫描/连接/握手

---

## 验收标准（真机 + 模拟器）
- [ ] 端到端实时 HR 显示，连续 ≥10 分钟无崩溃、无内存增长
- [ ] 断连后自动重连并恢复数据
- [ ] 5% 丢包注入：HR 仍连续，丢样被统计
- [ ] 版本/能力协商在日志中可见

## 预估文件数：~18 个源文件 + ~10 个测试文件
