# 线上事故分析定位与解决策略

> 本文档建立 HRSense 项目的线上事故响应体系，覆盖事故分级、信息收集、定位方法论、典型案例排查路径与复盘机制。

---

## 1. 事故分级

| 级别 | 定义 | 示例 | 响应时间 |
|------|------|------|---------|
| **P0 - 阻断性** | 核心功能不可用，无 workaround | BLE 无法连接、OTA 变砖、App 启动即 crash | < 1 小时 |
| **P1 - 严重** | 核心功能降级，有 workaround | 睡眠分期全为 Light、波形丢块率 > 20%、推理结果异常 | < 4 小时 |
| **P2 - 一般** | 非核心功能异常 | 诊断面板 KPI 不准、OTA 进度条卡顿、日志分类不生效 | < 24 小时 |
| **P3 - 轻微** | 体验瑕疵 | UI 文案错误、颜色不一致、动画不流畅 | 下个迭代 |

---

## 2. 信息收集（第一现场保全）

### 2.1 利用已有的可观测性体系

HRSense 已建成的可观测性基础设施（详见 [16-best-practices](./16-best-practices.md)）为事故定位提供了关键数据：

| 数据源 | 收集方式 | 保留窗口 | 事故用途 |
|--------|---------|---------|---------|
| **LogRingBuffer** | 自动记录所有 HRSenseLogging 输出 | 最近 500 条 | 事故前的操作序列和错误 |
| **StateTransitionRecorder** | LoggingMiddleware 自动记录 | 最近 50 条 | crash 前的 Redux 状态转换链 |
| **MetricKit** | 系统自动采集 crash/hang/CPU | 24h 延迟上报 | crash 堆栈 + 关联状态转换 |
| **MetricsCollector** | KPI 计数器 | 进程生命周期 | 连接成功率、丢包率、吞吐率 |
| **DiagnosticPackage** | 用户/测试手动导出 | JSON 文件 | 完整现场快照 |

### 2.2 用户报告模板

当用户反馈问题时，引导提供：

```
1. 设备型号 + iOS 版本
2. App 版本号
3. 问题描述（何时、做了什么、期望 vs 实际）
4. DiagnosticPackage JSON（如有）
5. 屏幕录制（如有）
6. 是否能复现？复现步骤？
```

### 2.3 自动收集增强（建议补充）

```swift
// 建议在 App 启动时上报 DiagnosticPackage 摘要
func reportSessionStart() {
    let package = DiagnosticPackage(
        logEntries: LoggingRegistry.shared.ringBuffer.snapshot(),
        stateTransitions: StateTransitionRecorder.shared.recentTransitions,
        metricsSnapshot: deviceRepo.metricsCollector.snapshot().toJSON(),
        systemInfo: SystemInfo.current
    )
    // 发送到后端 / 保存到本地 / TestFlight feedback
}
```

---

## 3. 定位方法论

### 3.1 全链路分层排查

BLE + IoT 场景的核心方法论：**自底向上，逐层排除**。

```
┌─────────────────────────────────────────┐
│ L7: UI 层 — 用户看到的现象               │  "App 不显示心率"
├─────────────────────────────────────────┤
│ L6: Redux State — AppState 是否正确      │  state.live.currentHeartRate == nil?
├─────────────────────────────────────────┤
│ L5: Middleware — action 是否被 dispatch  │  日志中有 .heartRateReceived?
├─────────────────────────────────────────┤
│ L4: 数据解析 — DeviceSample 是否正确     │  BLEDataParser 输出是否合理?
├─────────────────────────────────────────┤
│ L3: 协议解码 — Frame 是否正确重组        │  FrameAssembler 是否有 CRC 错误?
├─────────────────────────────────────────┤
│ L2: BLE 传输 — notify 是否到达           │  didUpdateValueFor 是否被调用?
├─────────────────────────────────────────┤
│ L1: BLE 连接 — 设备是否连接              │  CBCentralManager.state? connection state?
├─────────────────────────────────────────┤
│ L0: 硬件 — 设备是否开机/在范围内          │  设备 LED 状态?
└─────────────────────────────────────────┘
```

### 3.2 二分法定位

当全链路排查效率低时，用二分法快速缩小范围：

```
步骤 1: 问题出在 App 还是设备？
  → 用另一台手机连接同一设备，问题是否复现？
  → 如果复现 → 设备/固件问题
  → 如果不复现 → App 问题

步骤 2: 问题出在 BLE 层还是应用层？
  → 检查 BLE 连接状态（已连接？RSSI 正常？）
  → 如果 BLE 正常 → 应用层问题
  → 如果 BLE 异常 → BLE 层问题

步骤 3: 问题出在数据通道还是命令通道？
  → 心率数据是否正常推送？
  → 命令（START_STREAM）是否正常响应？
```

### 3.3 时间线分析法

从 DiagnosticPackage 的日志中提取时间线：

```
12:00:01 [bleConn] Scanning started
12:00:03 [bleConn] Peripheral discovered: HRSense-001
12:00:03 [bleConn] Connecting...
12:00:04 [bleConn] Connected, discovering services
12:00:05 [bleConn] Services discovered, subscribing to notify
12:00:05 [bleConn] CCCD written, notify enabled
12:00:06 [protoCmd] HELLO sent
12:00:06 [protoCmd] HELLO_ACK received (v1, caps=0x2F)
12:00:06 [protoCmd] START_STREAM sent
12:00:07 [protoCmd] START_STREAM ACK received
12:00:07 [data]     First DeviceSample: hr=72, rr=[830,835]
12:00:08 [data]     DeviceSample: hr=72, rr=[832]
...
12:05:32 [bleConn] Connection lost! reason=unknown
12:05:33 [bleConn] Reconnecting in 1s (backoff)
12:05:34 [bleConn] Scanning...
... ← 此处之后没有重新连接成功 → 问题范围缩小到重连逻辑
```

---

## 4. 典型事故场景与排查路径

### 4.1 BLE 无法连接

```
排查路径：
1. CBCentralManager.state == .poweredOn?
   → 否：蓝牙未开启 / 未授权
   → 是：继续

2. scanForPeripherals 是否发现设备？
   → 否：设备未广播 / 超出范围 / 设备已被其他手机连接
   → 是：继续

3. connect(peripheral) 回调状态？
   → didFailToConnect：连接被拒绝（设备端问题）
   → 无回调（超时）：信号弱 / 设备重启
   → didConnect：继续

4. discoverServices 回调？
   → 空 services：设备 GATT 数据库异常（固件 bug）
   → 有 services：继续

5. CCCD 写入是否成功？
   → 否：特征属性不包含 notify（固件配置错误）
   → 是：连接建立成功，问题在应用层
```

### 4.2 心率数据不更新

```
排查路径：
1. didUpdateValueFor(notifyCharUUID) 是否被调用？
   → 否：CCCD 未正确写入 / 设备未推送
   → 是：继续

2. FrameAssembler.feed() 是否产出 DecodedFrame？
   → 否：数据不完整（BLE 丢包）/ CRC 校验失败
   → 是：继续

3. BLEDataParser.parseSample() 输出是否合理？
   → hr == 0 且 rr 为空：设备发送空数据
   → hr > 255：解码错误
   → 正常：继续

4. BLEStreamMiddleware 是否 dispatch(.heartRateReceived)?
   → 否：节流逻辑可能吞掉了所有数据（throttleInterval 过大）
   → 是：继续

5. Reducer 是否正确更新 AppState？
   → 检查 state.live.recentSamples 是否增长
   → 检查 state.live.currentHeartRate 是否更新

6. SwiftUI View 是否刷新？
   → 检查 @EnvironmentObject store 是否正确注入
   → 检查 View 的 body 是否依赖 currentHeartRate
```

### 4.3 OTA 失败

```
排查路径：
1. OTA 在哪个阶段失败？
   → preparing：固件文件不存在 / 读取失败
   → transferring：传输中断（BLE 断连）
   → validating：CRC-32 校验失败（传输丢块）
   → applying：设备拒绝应用（固件版本不匹配）

2. transferring 中断：
   → 检查 BLE 连接是否断开
   → 检查窗口 ACK 流控是否超时
   → 检查 MTU 是否变化（iOS 可能重新协商）

3. validating 失败：
   → 对比 App 计算的 CRC-32 和设备返回的 CRC-32
   → 检查是否有重复传输的块（窗口 ACK 误判）
   → 检查固件镜像是否被篡改（磁盘损坏）

4. 断点续传验证：
   → 断连后重新 OTA，设备是否正确报告已接收偏移量？
   → App 是否从正确偏移继续传输？
```

### 4.4 睡眠分期结果异常（全为 Light）

```
排查路径：
1. SleepMiddleware 是否被触发？
   → 检查日志中 .hrvComputed 是否出现
   → 检查 state.sleep.isMonitoring == true

2. SleepWindowInput 特征是否合理？
   → 导出 DiagnosticPackage，检查 latestFeatureVector
   → 18 维特征是否全为 0？（C++ 计算失败）
   → hrTrend / circadianVariation 是否有值？

3. CoreML 模型是否加载成功？
   → 检查 CoreMLService.activeModelVersion
   → 如果是 "sleep-stage-fallback-v1"：模型未加载，使用规则引擎

4. 规则引擎降级路径：
   → 检查 SleepStageService.makeFallbackProbabilities 的输入
   → 如果 metrics.hr 始终 < 82 且 rmssd < 65 且 sampleEntropy < 1.25
   → 则始终命中默认规则（返回 Light: 0.64）

5. 根因：
   → HRV 指标本身异常（C++ 输入数据有问题）
   → 或模型加载失败且规则引擎阈值不适配当前用户
```

### 4.5 App 后台被系统杀死

```
排查路径：
1. MetricKit 是否报告 crash / termination？
   → 检查 MXDiagnosticPayload
   → reason == "permittedBackgroundDurationExpired"：后台时间超时
   → reason == "memoryPressure"：内存压力被杀

2. BLE 后台保活配置：
   → Info.plist 是否包含 "bluetooth-central" background mode?
   → CBCentralManager 是否使用 restore identifier?

3. 内存分析：
   → WaveformRingBuffer 容量是否过大？（3840 samples × ~48 bytes = ~185 KB）
   → AppState.live.recentSamples 是否超过 600？
   → 日志 Ring Buffer 是否超过 500 条？

4. CPU 分析：
   → WaveformMiddleware 后台轮询间隔是否太短？（应为 500ms）
   → ComputeMiddleware 是否在后台频繁触发 C++ 计算？
```

---

## 5. 工具链

### 5.1 Xcode Instruments

| 模板 | 用途 |
|------|------|
| **Time Profiler** | Middleware dispatch 耗时、C++ 计算耗时 |
| **Allocations** | Ring Buffer 内存增长、recentSamples 泄漏 |
| **Core Animation** | SwiftUI 波形渲染帧率 |
| **Network** | BLE 数据传输量（配合 PacketLogger） |

### 5.2 PacketLogger (Apple Bluetooth)

```bash
# 启用 macOS PacketLogger
# 可抓取 HCI 级别的 BLE 包
# 用于分析：
# - notify 是否到达 iOS 系统层（区分设备 vs App 问题）
# - 连接参数（Connection Interval, Slave Latency）
# - MTU 协商结果
```

### 5.3 Console.app

```bash
# 使用 HRSenseLogging 的 OSLog 输出
# 在 Console.app 中过滤：
#   subsystem: com.hrsense
#   category: bleConn / bleFrame / protoCmd / state / ...
# 实时观察日志流
```

### 5.4 自研诊断工具

| 工具 | 功能 | 入口 |
|------|------|------|
| **DiagnosticPanelView** | 6 KPI 实时仪表盘 | 三击 Logo 触发（DEBUG） |
| **LogFilter** | 运行时开关日志分类和级别 | DiagnosticPanelView UI |
| **DiagnosticPackage Export** | JSON 导出 + ShareLink | DiagnosticPanelView 按钮 |
| **MetricKitManager** | Crash/Hang/CPU 诊断 + 关联状态转换 | 自动采集 |
| **StateTransitionRecorder** | 最近 50 条 Redux 状态转换 | 嵌入 crash report |

---

## 6. 事故复盘模板

每次 P0/P1 事故后必须完成：

```markdown
## 事故报告

### 基本信息
- 事故级别：P0 / P1
- 发现时间：
- 恢复时间：
- 影响范围：

### 时间线
| 时间 | 事件 |
|------|------|
| HH:MM | 用户报告 / 监控告警 |
| HH:MM | 开始排查 |
| HH:MM | 定位根因 |
| HH:MM | 发布修复 |

### 根因分析
- 直接原因：
- 根本原因：
- 为什么没在测试阶段发现：

### 修复方案
- 短期：
- 长期：

### Action Items
| 编号 | 行动 | 负责人 | 截止日 |
|------|------|--------|--------|
| 1 | | | |

### 经验教训
- 什么做得好：
- 什么需要改进：
- 需要补充的测试/监控：
```

---

## 7. 预防机制

### 7.1 上线前检查清单

- [ ] 所有 P0 路径有对应的单元测试
- [ ] BLE 断连 → 重连 → 数据恢复端到端验证
- [ ] OTA 中断 → 断点续传验证
- [ ] CoreML 模型加载失败 → fallback 路径验证
- [ ] 后台模式 → 非核心动作被 BackgroundMiddleware 拦截
- [ ] DiagnosticPackage 可正常导出
- [ ] MetricKit 订阅已激活
- [ ] 日志分类全部可用（不会被编译优化移除）

### 7.2 灰度发布策略

```
Day 1: 内部测试（10 人）
Day 3: TestFlight 灰度（100 人）
Day 7: TestFlight 全量（1000 人）
Day 10: App Store 发布

每个阶段监控：
- Crash rate < 0.1%
- BLE 连接成功率 > 95%
- OTA 成功率 > 98%
```

### 7.3 自动化监控（建议补充）

```swift
// 建议：启动时自动上报关键指标
struct StartupHealthCheck {
    func check() -> HealthReport {
        HealthReport(
            crashRate: MetricKitManager.shared.crashRate,
            bleConnectionSuccessRate: metricsCollector.connectionSuccessRate,
            otaSuccessRate: metricsCollector.otaSuccessRate,
            sampleLossRate: metricsCollector.sampleLossRate
        )
    }
}
```
