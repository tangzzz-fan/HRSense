# Simulator Headless 与 Waveform 生产路径补全方案

## 背景

当前工程在 `M2/M3/M5` 交界处存在两个真实断点：

1. `HRSenseSimulator` 的 headless 模式虽然能启动广播与定时推样，但 `START_STREAM/STOP_STREAM` 还没有真正驱动运行时数据流。
2. App 侧虽然已经具备 `WaveformRingBuffer`、`WaveformMiddleware` 和波形 UI，但 `BLECentralDataSource` 收到 `.waveform(let block)` 后只记录日志，没有进入生产缓冲与展示链路。

这两个断点会导致当前行为出现“协议 ACK 看似正常，但生产路径并未闭环”的假阳性。

## 旧实现问题

### 1. Headless 模式问题

- `CommandProcessor` 会对 `START_STREAM/STOP_STREAM` 返回 ACK，但没有真正控制 `SimulatorHeadlessRunner` 的流启动/停止。
- `SimulatorHeadlessRunner` 当前只会定时下发 HR/RR `DeviceSample`，没有接入 `WaveformStreamer`。
- 结果是 simulator 更像“独立定时器 + 命令响应器”，而不是“由 central 命令驱动的外设”。

### 2. Waveform 生产路径问题

- `BLECentralDataSource.handleNotifyData()` 能解出 `.waveform(let block)`，但没有把 block 转成 `WaveformSample`。
- `WaveformRingBuffer.recordBlock(...)` 与 `push(...)` 已实现，但没有被生产 BLE 路径调用。
- `WaveformMiddlewareTests` 目前只验证 fake buffer 轮询，不验证真实 block 入缓冲路径。

## 设计目标

- 让 `START_STREAM/STOP_STREAM` 真正控制 headless simulator 的流生命周期。
- 让 simulator 可以按 `sampleKinds` 同时或分别下发 HR/RR 与 waveform。
- 让 App 在收到 waveform block 后，完成：
  - block loss 统计
  - bytes / throughput 统计
  - `WaveformSample` 转换
  - `WaveformRingBuffer.push(...)`
- 为以上行为补齐单元测试和生产路径测试。

## 非目标

- 不在本次引入 iPhone 真机 BLE E2E 自动化。
- 不在本次实现远程配置的 waveform 类型切换 UI。
- 不在本次重构 `DeviceRepository` 为独立 `waveformStream` 抽象。

## 方案

### 模块 1：Headless 命令绑定

#### 设计

- 为 `CommandProcessor` 增加可更新的 stream 回调：
  - `onStreamStart(sampleKinds: [UInt8])`
  - `onStreamStop()`
- `SimulatorHeadlessRunner` 在初始化时将上述回调绑定到自身：
  - `START_STREAM` → `startStreaming(sampleKinds:)`
  - `STOP_STREAM` → `stopStreaming()`

#### 原理

命令处理器负责协议层状态机，runner 负责运行时资源（timer / generator / streamer）。两者通过回调连接后，协议 ACK 与真实行为才能一致。

### 模块 2：Simulator waveform 下发

#### 设计

- `SimulatorHeadlessRunner` 增加 `WaveformStreamer`。
- 当 `sampleKinds` 包含 `0x02` 时，启动 waveform 流。
- `WaveformStreamer` 产生的 fragments 通过 `SimulatedPeripheral` 的 notify 通道下发。
- `SimulatedPeripheral` 增加通用 notify fragment 推送接口，供 command response 与 waveform 共用。

#### 原理

`WaveformStreamer` 已经负责 block 级波形生成、故障注入与 fragmentation。本次只需要把它纳入 runner 生命周期，而不是重写一套波形发送逻辑。

### 模块 3：App waveform 入 ring buffer

#### 设计

- `BLECentralDataSource` 新增 `waveformRingBuffer` 注入。
- `BLEDataParser` 新增 `parseWaveformBlock(_:) -> [WaveformSample]`。
- 在 `.waveform(let block)` 分支中：
  - 调用 `recordBlock(bytes:blockSeq:sampleCount:)`
  - 调用 `push(samples)`

#### 原理

最短闭环路径是在 `BLECentralDataSource` 直接消费 `DecodedFrame.waveform`。这样无需先引入新的 `waveformStream` 抽象，就能把“协议层 -> buffer -> middleware -> UI”打通。

### 模块 4：测试补齐

#### 计划

- `HRSenseSimulatorKitTests`
  - `CommandProcessorTests`：验证 `START_STREAM/STOP_STREAM` 回调触发
  - `SimulatorHeadlessRunnerTests`：验证 remote command 能驱动 runner 启停与 sampleKinds 解析
- `HRSenseDataTests`
  - `BLEDataParserTests`：验证 waveform block → samples 的时间与类型映射
  - `WaveformRingBufferTests`：验证真实 buffer 的 push / eviction / metrics
  - `BLECentralDataSourceWaveformTests`：验证 `.waveform(block)` 进入 `WaveformRingBuffer`

## 流程描述

1. iOS App 完成握手，发送 `START_STREAM(sampleKinds: [0x01, 0x02])`
2. simulator `CommandProcessor` 解析 `sampleKinds`
3. `SimulatorHeadlessRunner` 启动 HR timer 与 waveform streamer
4. waveform fragments 经 `SimulatedPeripheral` notify 下发
5. App `BLECentralDataSource` 解出 `.waveform(let block)`
6. `BLEDataParser` 转换为 `[WaveformSample]`
7. `WaveformRingBuffer.recordBlock(...)` + `push(...)`
8. `WaveformMiddleware` 定时轮询 buffer
9. Redux 更新 `AppState.waveform`
10. `RootView` 读取状态并渲染

## 模块 / 功能 + 时间

| 模块 | 功能 | 预计时间 | 说明 |
| --- | --- | --- | --- |
| Simulator 命令绑定 | `START_STREAM/STOP_STREAM` 驱动 runner | 30 分钟 | 修正 ACK 与真实行为脱节 |
| Simulator 波形发送 | 接入 `WaveformStreamer` 与 notify push | 45 分钟 | 复用现有 waveform 生成器 |
| App 波形消费 | `.waveform(block)` → ring buffer | 45 分钟 | 增加 parser + buffer 注入 |
| Data 层测试 | parser / ring buffer / central data source | 45 分钟 | 补真实生产路径测试 |
| Simulator 测试 | command / runner lifecycle | 30 分钟 | 覆盖 remote start/stop |
| 构建验证 | `swift test` + `xcodebuild` | 20 分钟 | 保证 iOS 构建链不回退 |

## 预期收益

- 修复 simulator “ACK 成功但未真正流式下发”的结构性问题。
- 打通 waveform 的真实生产路径，而不是继续依赖 fake buffer 测试。
- 为后续真机联调提供可信的 headless 行为基线。
