# 06 · HRSenseSimulatorKit — 模拟器

> **路径**: `Sources/HRSenseSimulatorKit/`  
> **依赖**: `HRSenseProtocol`  
> **被依赖**: `HRSenseSimulatorUI`, `HRSenseSimulator`(CLI)

## 1. 模块定位

macOS 模拟器不是临时桩——它是**持久性开发/CI 资产**，即使真实硬件到来后仍用于 CI 回归、离线开发、故障注入测试。

核心能力：
- 模拟 BLE GATT Peripheral（与 App 端对称）
- 多种数据生成器（静息/运动/异常/手动/重放）
- 场景引擎（JSON 脚本驱动）
- 故障注入（丢包/CRC 错误/延迟/断连）
- 无头模式（CLI / CI）

## 2. SimulatedPeripheral（~360 行）

封装 `CBPeripheralManager`，实现 BLE 外设：

**GATT 配置**：与 App 端完全对称的 4 个 Characteristic（0002/0003/0004/0005），使用相同的 128-bit UUID。

**线程模型**：所有 BLE 状态在 `bleQueue` 上串行访问。

**关键组件**：

- `ControlWriteRouter`：接收 App 端写入 0003 的命令，通过 `FrameAssembler` 重组后交给 `CommandProcessor` 处理
- `CommandProcessor`：路由每条命令到对应处理器
- `FaultInjector`：对出站数据注入丢包/CRC 错误/延迟
- `generator`：当前数据生成器（可运行时切换）

**数据推送**：

```swift
func pushSample(_ sample: DeviceSample) -> Bool {
    // 编码为帧 → 可能注入故障 → updateValue(notifyChar)
}
```

## 3. CommandProcessor（~158 行）

处理 App 端命令并产生响应：

| 命令 | 处理 |
|------|------|
| `HELLO` | 状态→connected，返回 HELLO_ACK（版本、能力、模型、固件版本） |
| `GET_INFO` | 返回设备信息 |
| `START_STREAM` | 状态→streaming，触发 `onStreamStart` 回调 |
| `STOP_STREAM` | 状态→idle，触发 `onStreamStop` 回调 |
| `SET_CONFIG` | ACK |
| 未知 opcode | 返回 ERROR ACK |

`encodeSample()` 方法将 `DeviceSample` 编码为帧分片，由 streaming timer 定时调用。

## 4. 数据生成器

所有生成器遵循统一协议：

```swift
protocol DataGeneratorProtocol: AnyObject {
    func start()
    func stop()
    func nextSample(timestampMs: UInt32) -> DeviceSample
}
```

| 生成器 | 说明 |
|--------|------|
| `RestingHRGenerator` | 静息心率：基础 65–75 BPM + 呼吸变异 + 随机 RR |
| `ExerciseHRGenerator` | 运动心率：线性爬升到 140–170 BPM + 运动伪影 |
| `AnomalyHRGenerator` | 异常心率：突发心动过速/过缓 + 异常 RR |
| `ManualHRGenerator` | 手动设置固定心率 |
| `ReplayHRGenerator` | CSV 文件回放 |
| `ECGSynthesizer` | 合成 ECG 波形：PQRST 波 + 基线漂移 + 噪声 |
| `PPGSynthesizer` | 合成 PPG 波形：脉搏波 + 呼吸调制 |
| `WaveformGenerator` | 波形生成器协议实现（ECG/PPG） |
| `WaveformStreamer` | 将波形按块（block）定时推送 |

**ThroughputTracker**：跟踪波形推送吞吐率（bytes/s, blocks/s）。

**WaveformFaultInjector**：专门对波形数据注入故障（块丢弃、CRC 损坏）。

## 5. 场景引擎

### 5.1 ScenarioParser

从 JSON 文件解析场景定义：

```json
{
  "name": "Exercise Test",
  "steps": [
    { "delayMs": 1000, "action": "startStream" },
    { "delayMs": 5000, "action": "setHR", "heartRate": 120 },
    { "delayMs": 3000, "action": "injectFault", "fault": { "dropProbability": 0.1 } },
    { "delayMs": 2000, "action": "stopStream" }
  ]
}
```

### 5.2 ScenarioEngine

按顺序执行场景步骤，通过回调控制模拟器：

```swift
engine.onHeartRateChange = { hr in ... }
engine.onStreamStart = { ... }
engine.onStreamStop = { ... }
engine.onDisconnect = { ... }
engine.onReconnect = { ... }
engine.onFault = { faultConfig in ... }
engine.onComplete = { ... }
```

每个步骤的 `delayMs` 控制时间间隔。

## 6. OTA 模拟

### 6.1 OTAStateMachine

模拟器端的 OTA 状态机：idle → receiving → validating → applying → complete

### 6.2 OTAEventHandler

处理 App 端发来的 OTA 命令：
- `OTA_START` → 校验镜像大小/CRC → 返回 `OTA_START_ACK`（含 resumeOffset / maxChunkSize）
- `OTA_WINDOW_BEGIN` + chunk → 累积到 `OTAImageBuffer` → 返回 `OTA_WINDOW_ACK`（含 recvOffset + windowCRC32）
- `OTA_VALIDATE` → CRC32 校验 → 返回结果
- `OTA_APPLY` → 模拟固件更新 → 更新 firmwareVersion

### 6.3 OTAPreconditionChecker

OTA 前置条件检查（电量、状态等）。

## 7. FaultInjector

模拟器端故障注入器：

```swift
class FaultInjector {
    var dropProbability: Double = 0       // 丢包率
    var corruptCRCProbability: Double = 0 // CRC 损坏率
    var latencyMilliseconds: Range<Int> = 0..<1  // 延迟范围
}
```

在 `pushSample()` 中，每帧分片按概率：
1. 丢弃（模拟丢包）
2. 篡改 CRC（模拟传输损坏）
3. 延迟发送（模拟网络延迟）

## 8. Headless 模式

### 8.1 SimulatorHeadlessRunner（~215 行）

无头运行时，供 CLI 和 CI 使用：

```swift
let runner = SimulatorHeadlessRunner(launchOptions: options)
try runner.start()
// 自动广播、按场景驱动数据流
```

支持：
- `--scenario path.json`：加载场景脚本
- `--generator resting|exercise|manual|anomaly`：选择数据生成器
- `--auto-start`：自动开始广播和推流

### 8.2 SimulatorLaunchOptions

解析命令行参数，支持 `--port`, `--scenario`, `--generator`, `--auto-start-advertising`, `--auto-start-stream` 等。

## 9. DeviceStateMachine

模拟器端设备状态机：

```
advertising → connected → handshaken → streaming ⇄ idle
```

通过 `DeviceEvent` 触发转换。
