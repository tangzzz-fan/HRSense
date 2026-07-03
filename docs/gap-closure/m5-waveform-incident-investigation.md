# M5 波形显示问题排查记录

## 背景

在最近一次联调中，项目已经可以正常连接、握手、恢复连接和展示心率，但 iOS App 内的波形区域存在两个明显现象：

- UI 中波形区域没有正确进入可视状态
- `PPG` 选择器不可用，或切换后没有实际图形

同时日志中出现如下特征组合：

- 有 `heartRateReceived(...)`
- 有 `waveformMetricsUpdated(...)`
- 没有 `waveformSamplesReceived(...)`

这是一个很重要的排障线索，因为它说明：

- 链路中某一层已经开始更新波形统计指标
- 但 Redux 和 UI 没有拿到真正的 `WaveformSample`

换句话说，问题不一定在 UI 绘制本身，也可能在更前面的数据生成或分发链路。

## 初始现象

联调时可观察到：

1. 连接状态为 `restoredConnected`
2. 心率日志持续更新
3. 波形 metrics 日志持续更新
4. 波形视图没有对应地进入稳定显示状态
5. `PPG` 无法正确切换

典型日志如下：

```text
waveformMetricsUpdated → connection=restoredConnected hr=69 err=nil
heartRateReceived(1 samples) → connection=restoredConnected hr=69 err=nil
waveformMetricsUpdated → connection=restoredConnected hr=69 err=nil
```

这个组合说明：

- 心率链路是通的
- 波形 middleware 至少在持续轮询
- 但实际波形样本没有可靠进入状态树

## 排查路径

这次排查按从后往前的方式推进，优先回答“数据到底丢在哪一层”。

### 第 1 步：先检查 UI 是否画错

首先检查：

- `RootView`
- `WaveformDisplayView`
- `WaveformCanvasView`

这里很快发现两个问题：

1. `WaveformCanvasView` 对已经归一化过的波形值又额外做了一次 `/1000`
2. `RootView` 和 `AppReducer` 没有正确把 ECG / PPG 两路样本分开

这会导致：

- 即使样本进入了 UI，也可能几乎画成一条直线
- 即使选择了 `PPG`，UI 也可能仍然在读 `ecgSamples`

### 第 2 步：再检查 Redux 是否收到真实样本

继续对照 action 链路后发现：

- `waveformMetricsUpdated` 会持续出现
- `waveformSamplesReceived` 没有对应出现

这说明单纯修 UI 不足以解决全部问题，因为真正的波形样本并没有稳定进入状态树。

### 第 3 步：检查 `WaveformMiddleware` 和 ring buffer

`WaveformMiddleware` 的行为是：

- 周期性从 `WaveformRingBuffer` 读取最近 5 秒样本
- 如果 `samples` 非空，则派发 `waveformSamplesReceived`
- 无论是否有样本，都会派发 `waveformMetricsUpdated`

因此如果日志中只有 `waveformMetricsUpdated`，而没有 `waveformSamplesReceived`，就意味着：

- middleware 本身仍在运行
- 但 `WaveformRingBuffer.readRecent(...)` 返回了空样本

### 第 4 步：检查 `BLEDataParser` 和中央接收侧

检查 `BLEDataParser`、`BLECentralDataSource` 后确认：

- `WaveformBlock` 能被解码为 `[WaveformSample]`
- 解码后的样本会被写入 `WaveformRingBuffer`

因此，如果 ring buffer 最终为空，更可能是上游根本没有收到真正的 waveform block。

### 第 5 步：检查 Simulator 的实际发送路径

继续回溯到 macOS Simulator 侧，发现两个运行路径并不一致：

1. `SimulatorHeadlessRunner`
   - 已接入 `WaveformStreamer`
   - 能在 `START_STREAM(sampleKinds)` 后真正发送 waveform block

2. `SimulatorViewModel`
   - 原实现只会每秒推送一个 `DeviceSample`
   - 没有把 `WaveformStreamer` 接到 `SimulatedPeripheral.pushNotifyFragments(...)`

这就是本次问题的关键根因：

- App 请求了 `heartRate + waveform`
- 但 Simulator UI 运行路径实际上只发了 heart rate
- 因此 iOS 侧只有心率数据，没有真实 waveform block

## 根因总结

这次问题最终不是单点故障，而是两类问题叠加：

### 根因 1：Simulator UI 路径没有真正发 waveform

这是主根因。

`SimulatorViewModel.startStream()` 原先只是：

- 启动心率 generator
- 每秒推送一个低频 `DeviceSample`

它没有像 headless 路径那样：

- 根据 `START_STREAM(sampleKinds)` 判断是否需要波形
- 启动 `WaveformStreamer`
- 把 waveform fragments 通过 `SimulatedPeripheral.pushNotifyFragments(...)` 发出去

直接后果是：

- iOS App 能收到心率
- ring buffer 拿不到 waveform block
- Redux 也就拿不到 `waveformSamplesReceived`

### 根因 2：展示层对已收到的波形处理也不正确

这是次根因。

即使后续样本进入了状态树，原 UI 仍有两个问题：

1. `WaveformCanvasView` 振幅缩放错误
2. `AppReducer` / `RootView` 对 ECG / PPG 路由不正确

直接后果是：

- 波形可能非常扁，几乎看不见
- `PPG` 切换没有真实意义

## 修复内容

本轮最终做了两类修复。

### A. 修复 Simulator 发送链

在 `SimulatorViewModel` 中补齐：

- `commandProcessor.setStreamCallbacks(...)`
- `startStreaming(sampleKinds:)`
- `stopStreaming()`
- `startWaveformStreamingIfNeeded(sampleKinds:)`

同时让 Simulator UI 路径也像 headless 一样：

- 在收到 `START_STREAM` 时按 sampleKinds 决定是否发 waveform
- 默认支持 `heartRate + waveform`
- 补发 ECG + PPG 两路波形 block

### B. 修复 iOS 展示链

在 iOS 侧补齐：

- `AppReducer` 按 `WaveformType` 分流样本
- `RootView` 按当前选中的类型读取 `ecgSamples` / `ppgSamples`
- `WaveformCanvasView` 去掉错误的 `/1000` 缩放

## 验证思路

修复后应重点观察以下几个信号：

### 运行时日志

应该从原来的：

- `heartRateReceived`
- `waveformMetricsUpdated`

变成同时出现：

- `waveformSamplesReceived(...)`
- `waveformMetricsUpdated(...)`

### UI 状态

应该看到：

- 波形区域进入 `Live`
- ECG 可见
- `PPG` 可以点击
- 切换到 `PPG` 后能看到另一条波形，而不是空白

### 构建回归

本轮修复后，以下构建应通过：

- `HRSenseSimulator`
- `HRSenseApp`

## 经验总结

这次问题说明一个很典型的风险：

- **headless 路径能工作，并不代表 Simulator UI 路径也具备同样的数据能力**

在协议/流式系统中，尤其要避免：

- 测试路径和演示路径逻辑分叉
- 两条路径只共享“心率 demo”，却没有共享“高吞吐 waveform”能力

因此后续建议把下面两件事作为常规联调检查项：

1. `START_STREAM(sampleKinds)` 是否在所有运行入口都一致生效
2. 运行时是否同时出现 `waveformSamplesReceived` 和 `waveformMetricsUpdated`

## 相关代码落点

- `Sources/HRSenseSimulatorUI/SimulatorViewModel.swift`
- `Sources/HRSenseFeature/Reducer/AppReducer.swift`
- `Sources/HRSenseFeature/Views/RootView.swift`
- `Sources/HRSenseFeature/Views/WaveformCanvasView.swift`
- `Sources/HRSenseFeature/Middleware/WaveformMiddleware.swift`
- `Sources/HRSenseData/WaveformRingBuffer.swift`
- `Sources/HRSenseData/BLE/BLEDataParser.swift`
