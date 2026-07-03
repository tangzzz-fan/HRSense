# M5 当前项目中的背压处理时机分析

## 先说结论

这次 BPM 停更问题的**最终主根因**已经确认是协议层 `FrameAssembler` 的 duplicate 判定过粗，而不是背压本身。

但是，这并不意味着当前项目“不需要背压处理”。

更准确的结论是：

- **这次事故的主根因不在背压**
- **当前项目仍然存在多个明确需要背压治理的链路**
- **如果不做背压处理，项目在高吞吐、后台、弱链路、OTA 等场景中仍会暴露稳定性问题**

所以这份文档回答的不是：

- “这次问题是不是背压导致的”

而是：

- **当前项目在什么时机会真正需要背压处理**
- **哪些链路已经有雏形，哪些链路还只是最小版**

## 什么叫背压

在当前项目上下文里，背压可以理解为：

- 上游生产数据的速度
- 大于下游链路、缓冲或消费者处理速度

于是系统必须显式做下面几件事中的一种或多种：

1. 排队
2. 限速
3. 优先级调度
4. 丢弃低价值数据
5. 等待下游恢复可用

如果不做，系统就会退化成：

- 数据被静默丢弃
- 关键数据被低价值大流量挤压
- UI 和算法看到的是“连接还在，但数据语义已经失真”

## 当前项目里最需要背压处理的场景

## 1. Simulator Peripheral -> iOS App 的 Notify 发送

这是当前项目里最明确、最直接、最典型的背压点。

### 为什么这里一定需要

`SimulatedPeripheral` 通过：

- `CBPeripheralManager.updateValue(...)`

向 iOS central 推送：

- 心率 sample
- waveform fragments
- 控制响应
- OTA 响应

而 `updateValue(...)` 本身就是一个典型的背压接口：

- 返回 `true`：本次发送被系统接受
- 返回 `false`：当前 notify 缓冲已满，必须暂停并等待 `peripheralManagerIsReady(toUpdateSubscribers:)`

这意味着这里不是“可能需要背压”，而是：

- **天然就必须做背压治理**

### 当前项目里会在什么时候触发

最容易触发的时机有：

- ECG / PPG waveform 持续高频发送时
- 同时还要发送 heartRate sample 时
- 连接恢复后短时间内多类消息集中涌入时
- UI 线程调度波动，导致 push 节奏抖动时

### 当前已经做了什么

当前已经补了最小版治理：

- pending queue
- `peripheralManagerIsReady(...)` 后继续 drain
- 心率 / 响应高于 waveform 的优先级

### 后续还应该做什么

当前仍建议继续增强：

- waveform normal queue 的容量上限
- 达到上限后的低优先级丢弃策略
- backpressure 指标上报
- 高负载时主动降 waveform 发送频率

## 2. OTA 数据写入通道

当前 OTA 数据通道使用：

- `CBPeripheral.writeValue(..., type: .withoutResponse)`

对应代码路径在：

- `BLECentralDataSource.sendOTAChunk(_:)`

### 为什么这里也需要背压

`Write Without Response` 的本质也是高吞吐写入通道。

即便当前实现把窗口节奏治理放在：

- `OTA_WINDOW_ACK`

这一层，仍然说明这里本质上是背压问题，只不过采用的是：

- **协议级 window ack**

而不是完全依赖系统级回调。

### 当前项目里会在什么时候触发

会在下面场景出现明显压力：

- 固件镜像较大
- MTU 提升后单窗口吞吐增大
- 外设处理速度跟不上 chunk 推送速度
- App 侧持续 withoutResponse 写入但设备侧 flash / 校验耗时较长

### 当前的治理方式

这里当前的核心治理不是本地队列，而是：

- `OTA_WINDOW_BEGIN`
- 发送一窗口 chunk
- 等 `OTA_WINDOW_ACK`
- 再继续下一窗口

这本质上仍是背压治理，只是背压控制权部分上移到了协议层。

## 3. WaveformRingBuffer -> Redux/UI 的消费链

这一层不属于 BLE 发送背压，但属于**应用内消费背压**。

当前链路是：

- `BLECentralDataSource` 收到 waveform block
- `BLEDataParser` 解码为 `[WaveformSample]`
- `WaveformRingBuffer.push(...)`
- `WaveformMiddleware` 定时 `readRecent(...)`
- Redux 更新
- UI 绘制

### 为什么这里也会需要背压思维

如果波形进入 App 的速度持续高于：

- ring buffer 容量
- middleware 拉取频率
- UI 渲染能力

那么系统必须要有明确的降级语义。

当前项目在这里已经有一些天然的“软背压”处理：

- ring buffer 固定容量，满了就丢最旧数据
- middleware 只读取最近 5 秒窗口
- 后台时 waveform polling 降频

### 当前项目何时会暴露

典型场景包括：

- 更高采样率波形
- 更长展示窗口
- 前台 UI 繁忙导致绘图滞后
- 同时叠加 diagnostics / logging / inference

### 它与 BLE 背压的区别

这里不是“系统通知你不能再发”，而是：

- **消费者处理不过来**
- 所以需要窗口裁剪、容量限制和降频

这仍然是背压治理，只是发生在 App 内部处理链。

## 4. Compute / Inference 链的事件节流

当前 stress 推理链是：

- `heartRateReceived`
- `ComputeMiddleware`
- 5 分钟窗口 + 10 秒步长
- `hrvComputed`
- `featuresExtracted`
- `InferenceMiddleware`
- `CoreMLService`

### 这里为什么也有背压问题

如果没有窗口与步长限制，那么每次 sample 到来都触发：

- HRV 计算
- 特征拼装
- CoreML 推理

这会直接导致：

- 计算频率过高
- 主线程状态更新过密
- 推理资源被无意义消耗

### 当前项目已经如何处理

这里当前已经有一层很典型的“计算背压”：

- 5 分钟窗口
- 10 秒步长
- 只有积累足够 RR 后才触发

这本质上是：

- **对计算链做节流和采样**

所以它虽然不像 BLE 那样依赖系统回调，但也属于背压治理范畴。

## 5. Sleep 推理链

当前 sleep 链路是：

- `hrvComputed`
- 构造 `SleepWindowInput`
- `SleepInferenceRepository`
- `SleepStageService`
- CoreML 或 fallback

### 为什么这里也需要背压思维

睡眠推理不是每个 sample 都值得跑一次。

如果没有触发门槛和窗口稳定性约束，会导致：

- session 持续被短周期噪声驱动
- stage 频繁抖动
- 落库压力和 UI 更新频率不必要升高

### 当前项目现状

当前 sleep 触发点复用了：

- `hrvComputed`

也就是说，sleep 推理实际上已经继承了上游 compute 的节流。

这是一种间接背压治理方式：

- 先控制 `hrvComputed` 的产生速率
- 再控制 sleep inference 的进入频率

## 6. Logging / Diagnostics 输出链

当前项目的日志与诊断链虽然不是本轮主线，但从工程上看也需要背压思维。

原因很简单：

- BLE 高频事件
- waveform 更新
- action/state transition
- diagnostics snapshot

如果全部高频原样输出，会导致：

- 调试信号淹没有用信号
- I/O 压力上升
- 后台运行成本升高

当前项目已经在后台场景中对 logging 做了降级，这本质上也是：

- **对低价值高频输出进行限流**

## 当前项目里“不需要单独做背压”的场景

为了避免泛化，也要明确有些地方当前不需要额外引入复杂背压机制。

### 1. stress CoreML 模型本身的输入层

`CoreMLService.predict(features:)` 接受的是：

- 已经定长、已被节流后的 14 维特征向量

这里的输入规模非常小，且上游已经做了窗口与步长控制，所以：

- 不需要在 `CoreMLService` 内再做复杂队列

### 2. sleep CoreML 模型本身的输入层

同理，sleep 模型当前吃的是：

- 18 维 `SleepWindowInput`

输入是小向量，不是高频波形流，因此：

- 模型推理服务本身不是当前背压主战场

## 对当前项目的最终判断

如果要给“背压什么时候需要处理”做一个项目级结论，可以这样理解：

### 一级必须做

- `SimulatedPeripheral` 的 BLE notify 发送
- OTA withoutResponse / window ack 发送链

这些是**协议/链路层强背压点**，必须治理。

### 二级应该做

- `WaveformRingBuffer -> Middleware -> UI`
- logging / diagnostics 高频输出
- compute / sleep inference 的触发节流

这些是**应用内消费背压点**，需要通过容量、窗口、降频、节流来治理。

### 当前暂不需要复杂化

- `CoreMLService` 的模型调用层本身

因为它当前消费的是已经被抽象和节流后的小规模特征向量，而不是原始高频流。

## 建议

针对当前项目，我建议把背压治理分成三层来建设：

1. **链路层**
   - notify queue
   - isReady drain
   - OTA window ack

2. **应用层**
   - waveform window 限制
   - background 降频
   - logging 降级

3. **计算层**
   - 计算步长
   - 推理触发门槛
   - 睡眠窗口稳定性策略

这样后续再讨论“哪里要不要做背压处理”时，就不会把所有问题都堆到 BLE 层，也不会误把协议错误和背压问题混为一谈。
