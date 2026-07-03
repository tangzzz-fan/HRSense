# M5 BPM 停更与 Notify 背压问题排查记录

> 注：本文档记录的是第一阶段排查时对 `notify backpressure` 的重点分析，适合作为链路治理与风险评估材料。
> 对于这次 “iOS BPM 停更但 waveform 仍持续更新” 的最终主根因与最终修复，请结合 `m5-bpm-stall-final-root-cause.md` 一起阅读。

## 背景

在最近一轮 iOS 与 Simulator 联调中，出现了一个比波形显示更隐蔽的问题：

- iOS App 与外设仍保持 `connected`
- 波形仍在持续传输或偶发更新
- Simulator 面板上的 HR 数值仍在变化
- 但 iOS App 上的 BPM 在某一时刻后停止更新

更典型的现象是：

- 当 iOS 端 BPM 已经停止更新后
- 在外设面板切换到 `Manual`
- 再手动调整 HR
- iOS App 仍然保持连接状态，但心率数值没有任何变化

这说明问题已经不是简单的 UI 显示异常，而是心率数据链路在某一层停止了有效交付。

## 现象拆解

联调时观察到两个看似矛盾的事实：

1. Simulator 面板上的 HR 数值继续变化
2. iOS App 的 BPM 停在旧值不再刷新

如果只看表面，很容易误判为：

- iOS UI 没刷新
- Redux 状态没更新
- Manual 模式切换没有生效

但沿着代码链路拆解后可以确认，这两个数值其实来自不同观察点：

- Simulator 面板数值来自本地 generator 每秒生成的新 sample
- iOS BPM 数值来自 App 侧收到 `heartRateReceived(...)` 后写入的 `state.live.currentHeartRate`

因此它们不一致时，优先说明的是：

- **本地生成还在继续**
- **但 BLE 数据没有稳定到达 App**

## 根因分析

### 根因 1：Simulator 发送端没有正确处理 BLE Notify 背压

这是这次问题的主根因。

`CBPeripheralManager.updateValue(...)` 并不是“调用就一定送达”的接口。它在发送缓冲已满时会返回 `false`，表示当前不能继续发送，调用方必须：

1. 暂停继续 push
2. 把未发出的数据保存到本地 pending queue
3. 等待 `peripheralManagerIsReady(toUpdateSubscribers:)`
4. 在回调里继续 drain queue

但原始实现中存在三个关键缺口：

- `pushSample(_:)` 直接忽略 `updateValue(...)` 返回值
- `pushNotifyFragments(_:)` 仅打印日志，不缓存失败 payload
- `peripheralManagerIsReady(toUpdateSubscribers:)` 是空实现

这会导致在波形高频发送阶段，一旦 notify 缓冲满了：

- 心率 sample 虽然被本地生成
- 但无法稳定发送到 central
- 且失败不会被重试
- 最终表现为 App BPM 卡死在最后一个成功收到的值

### 根因 2：心率与波形复用同一 Notify 通道，但没有优先级治理

当前 Simulator 的发送模型里：

- 心率是低频、关键状态数据
- 波形是高频、连续大流量数据

两者都走同一条 `0002 Data/Notify` 通道。

在这种模型下，如果没有优先级治理，系统会退化成：

- 谁先占满发送缓冲，谁就挤压另一类数据

结果是：

- 波形可能继续大量尝试发送
- 更关键的心率反而更容易被静默饿死

### 根因 3：Manual 改 HR 后，波形生成器不会自动同步新的 HR

这是次根因，不是 BPM 卡死的直接原因，但会放大联调阶段的认知偏差。

原实现中：

- 心率 generator 切换到 `ManualHRGenerator` 后，后续 sample 会用新 HR
- 但已启动的 `WaveformStreamer` 在创建时就固定了 `WaveformGenerator(heartRate:)`
- 之后即使 slider 改 HR，波形生成器也不会同步更新

这会造成：

- Simulator 面板上 HR 已经变了
- 但波形节律可能仍反映旧 HR

虽然它不是“BPM 完全停更”的主因，但会降低调试时对系统一致性的判断信心。

## 问题本质

这次问题本质上是一个典型的实时流控问题：

- **连接状态仍然存在**
- **生产者仍然继续生成数据**
- **但发送端没有正确处理背压**
- **导致关键数据在链路中被静默丢弃**

它不是单纯的 UI 问题，也不是连接管理问题，而是：

- **BLE Notify 通道缺失 backpressure 处理**
- **关键数据与高吞吐数据没有优先级隔离**

## 修复方案

本轮按最小可落地方案完成了两类修复。

### 修复 A：为 Simulator Notify 引入 pending queue 与重试机制

在 `SimulatedPeripheral` 中新增：

- `NotifyBackpressureBuffer`
- `PendingNotifyPayload`
- `NotifyPayloadPriority`

并将所有 notify 发送统一收敛到同一条发送管线：

1. 所有待发送 payload 先进入本地缓冲
2. 尝试立即 drain
3. 如果 `updateValue(...) == false`
4. 将当前 payload 放回队列头部
5. 等待 `peripheralManagerIsReady(toUpdateSubscribers:)`
6. 在回调中继续发送

这样可以保证：

- 背压发生时不会直接静默丢掉待发数据
- 通道恢复可写时，发送能自动继续

### 修复 B：为心率与控制面消息设置更高优先级

在新的发送缓冲中：

- 心率 sample 使用 `high` 优先级
- 控制/响应消息使用 `high` 优先级
- 波形 fragments 使用 `normal` 优先级

这样在背压阶段，系统会优先保障：

- 心率
- ACK / 命令响应

而不是被高频波形完全占满。

这符合真实业务中的最小治理原则：

- **关键状态优先**
- **连续大流量数据可延后**

### 修复 C：切换 Manual 或切换模式时重建波形流

在 `SimulatorViewModel` 中补充：

- 统一的 `replaceGenerator(...)`
- `restartWaveformStreamingIfNeeded()`

这样在以下场景下：

- 切换 `Resting / Exercise / Manual / Anomaly`
- `Manual` 模式下 slider 调整 HR

如果当前波形正在传输，就会重建波形 streamers，让波形节律与当前 HR 保持一致。

## 架构链路说明

修复后的发送链路可以描述为：

1. 心率 sample 或 waveform fragment 在 Simulator 端生成
2. 被封装为 `PendingNotifyPayload`
3. 根据语义被打上 `high / normal` 优先级
4. 进入 `NotifyBackpressureBuffer`
5. `SimulatedPeripheral` 尝试 drain queue
6. 如果 CoreBluetooth 返回可发送，则继续出队
7. 如果返回不可发送，则保留队头 payload 并等待 `isReady` 回调
8. `peripheralManagerIsReady(toUpdateSubscribers:)` 到来后继续 drain
9. iOS central 收到心率 sample
10. `heartRateReceived(...)` 更新 Redux 状态
11. `RootView` 读取 `currentHeartRate` 刷新 BPM

这条链路的关键变化在于：

- 修复前：发送失败即丢
- 修复后：发送失败进入显式重试路径

## 验证方法

修复后需要重点观察以下信号。

### 1. 运行时行为

在持续波形传输时，切换到 `Manual` 并调整 HR，应看到：

- Simulator 面板 HR 改变
- iOS App 的 BPM 在下一个心率周期内同步更新
- 不再出现长时间停留在旧 BPM 的状态

### 2. 日志特征

应能观察到新的日志语义：

- `NOTIFY sent ...`
- `NOTIFY backpressure ...`

这说明发送端已经从“静默失败”变成“显式观测 + 重试”。

### 3. 一致性验证

在 `Manual` 模式下改变 HR 后，应看到：

- 心率数值变化
- 波形节律也重新贴近新的 HR

这说明本地生成器与波形 streamer 已重新对齐。

## 对实际业务的启示

这个问题并不是 Simulator 特有的玩具问题，而是 BLE 实时设备在真实业务中经常遇到的典型问题。

只要满足以下条件，真机上就可能复现类似风险：

- ECG / PPG / IMU 等高频流数据持续上报
- 心率、血氧、状态事件与波形共用同一链路
- 前后台切换导致调度抖动
- 无线环境不稳定，发送窗口波动

如果发送端不显式处理背压，真实业务里会出现：

- 连接仍在，但指标停更
- 告警或关键事件晚到
- 波形仍有流量，但关键状态反而先失真

因此，对健康设备或实时监测类产品，以下能力应视为基础工程能力：

- notify pending queue
- 背压恢复
- 消息优先级
- 高流量场景的降级策略

## 当前修复范围与后续建议

本轮已经完成的是：

- 最小版 notify 背压重试
- 关键消息优先级
- Manual HR 与波形生成器的一致性修复

后续仍建议继续演进：

1. 为 normal priority queue 增加容量上限与丢弃策略
2. 增加发送统计指标，例如 pending queue 长度、连续 backpressure 次数
3. 在高负载时主动降低波形频率或分辨率
4. 针对真机蓝牙链路补充专项回归场景

## 结论

这次问题的本质并不是“App 明明连着但 UI 偶发不刷新”，而是：

- **BLE Notify 发送端缺少背压处理**
- **高吞吐波形流挤占了关键心率消息**
- **导致连接仍在，但数据语义已经失真**

本轮修复后，Simulator 侧已经具备最小可用的：

- 显式排队
- 背压恢复
- 关键消息优先
- Manual 模式下心率与波形同步更新

这为后续真机联调和鲁棒性验证提供了一个更接近实际业务的基础实现。
