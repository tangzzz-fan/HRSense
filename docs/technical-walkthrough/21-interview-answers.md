# 面试题参考答案

> 基于 HRSense 项目实际代码的参考回答。每题包含"核心思路"、"详细回答"和"项目代码对照"，供面试官评估时参考。

---

## Part A — 高级工程师（Q1-Q7）

---

### Q1: 描述一次你排查 BLE 连接不稳定问题的完整过程

**核心思路**：分层排查法 + 工具链 + 数据驱动。

**详细回答**：

我在一个项目中遇到过：用户反馈"App 连着连着数据就不更新了"，不是断开，而是"静默死亡"——连接状态显示已连接，但没有任何数据推送。

**Step 1: 确定问题层级**

先看 CBCentralManager 的 delegate 回调：

```
didConnect ✅ → didDiscoverServices ✅ → didDiscoverCharacteristics ✅
→ didUpdateNotificationStateFor ✅ → didUpdateValueFor ❌（不再调用）
```

连接没断，但 notify 停了。这说明问题不在 L1（连接层），而在 L2（CCCD/notify 层）。

**Step 2: 抓包确认**

用 macOS 的 PacketLogger（HCI 级别抓包）看到：
- Connection Interval = 30ms（设备请求的）
- 在某个时刻，设备发送了 `Connection Update Request`，把 Interval 改到了 200ms
- 之后 iOS 发送了 `Read By Type` 查询 CCCD
- 但设备的 CCCD 响应里 notify bit 变成了 0（被关闭）

**根因**：固件在 Connection Update 时重新初始化了 CCCD 状态。这是固件 bug，不是 App 问题。

**给固件工程师的证据**：
- HCI 包的时间戳
- CCCD 写入请求 vs 读取结果不一致
- 问题只在 Connection Update 后出现

**Step 3: App 端临时缓解**

在 App 端增加了"notify 健康检查"——如果 5 秒没有收到任何 notify 数据但连接仍存活，主动重新订阅 CCCD：

```swift
// 健康检查定时器
notifyHealthCheckTask = bleQueue.asyncAfter(deadline: .now() + 5) {
    guard self._connectedPeripheral != nil,
          self.lastNotifyTimestamp.timeIntervalSinceNow < -5 else { return }
    // 重新订阅 CCCD
    self._connectedPeripheral?.setNotifyValue(true, for: self._notifyCharacteristic!)
}
```

**关键点**：
- 区分"连接断开"和"notify 停止"——前者是 L2CAP 断（`didDisconnectPeripheral`），后者是 CCCD 被重置
- Connection Parameters 很关键——Connection Interval、Slave Latency、Supervision Timeout 直接影响稳定性
- 后台时 iOS 系统会延长 Connection Interval，如果设备端的 Supervision Timeout 太短（比如 4 秒），后台容易超时断开
- RSSI 是辅助指标——如果 RSSI < -90 dBm，基本是信号问题

---

### Q2: 128Hz BLE 数据流的接收和存储方案设计

**核心思路**：生产者-消费者模型 + 有界缓冲 + 批量落盘 + UI 解耦。

**详细回答**：

**1. 吞吐量分析**

```
128 Hz × 2 bytes = 256 bytes/sec
BLE MTU ≈ 185 bytes → 每包最多 ~88 个样本
Connection Interval = 7.5ms → 理论 133 packets/sec
实际需要 ~1.5 packets/sec（128/88 ≈ 1.5）
```

吞吐量不高，真正的瓶颈不在带宽，而在：
- **notify 回调频率**：每秒 ~1.5 次回调（不算高频）
- **但如果是多路数据**（心率 + 波形），波形块会更多：128 samples / 88 per block ≈ 1.5 blocks/sec × 185 bytes = 278 bytes/sec
- **如果采样率升到 256Hz**，block 频率翻倍

**2. 接收层：专用 BLE 队列**

```swift
// 所有 CoreBluetooth 回调在 bleQueue 上执行
private let bleQueue = DispatchQueue(label: "com.hrsense.app.ble")

// CBCentralManager 使用 bleQueue（而非主线程）
_centralManager = CBCentralManager(delegate: self, queue: bleQueue, options: options)
```

**关键决策**：`queue: nil` 会让所有回调在主线程执行。对于高吞吐场景，应该用专用队列避免阻塞 UI。

**3. 缓冲层：Ring Buffer**

```swift
public final class WaveformRingBuffer: @unchecked Sendable {
    private let capacity: Int          // 3840 samples = 30s @ 128Hz
    private let lock = NSLock()        // 轻量级锁
    private var buffer: [WaveformSample] = []

    public func push(_ samples: [WaveformSample]) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(contentsOf: samples)
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
    }
}
```

**为什么用 Ring Buffer 而不是无限数组**：
- 内存有界（3840 × ~48 bytes ≈ 185 KB）
- 自动淘汰旧数据
- 消费者（UI）任何时候读取，都只看到最近 30 秒

**为什么用 NSLock 而不是 Actor**：
- notify 回调在 `bleQueue`，UI 读取在主线程
- NSLock 开销极小（~100ns），适合这种短临界区
- Actor 的 await 会引入异步开销，在高频场景下不划算

**4. 存储层：批量写入**

```swift
// BackgroundWriteBuffer — 阈值 + 超时双触发
actor BackgroundWriteBuffer {
    private var pending: [Data] = []
    private let threshold = 100
    private let flushInterval: UInt64 = 5_000_000_000  // 5s

    func append(_ data: Data) {
        pending.append(data)
        if pending.count >= threshold {
            await flush()
        } else {
            scheduleFlushIfNeeded()
        }
    }
}
```

**不能每个样本都写磁盘**——128 次/秒的磁盘 I/O 会严重耗电，且在后台模式下更容易触发系统限制。

**5. UI 层：轮询而非推送**

```swift
// WaveformMiddleware — 10Hz 轮询更新 UI
private let pollingInterval: TimeInterval = 0.1  // 100ms
```

**为什么不用 push（每次数据到达就 dispatch action）**：
- 128Hz 的 action dispatch 会让 Redux pipeline 过载
- 每个 action 经过所有 middleware → reducer → UI 更新
- SwiftUI 的 body 重算开销巨大
- 用户视觉感知上限 ~60Hz，10Hz 轮询足够平滑

**6. 丢包检测：blockSeq**

```swift
// WaveformLossDetector — 处理 UInt32 溢出回绕
static func detectBlockLoss(prevSeq: UInt32, currentSeq: UInt32) -> Int {
    let diff = currentSeq.subtractingReportingOverflow(prevSeq).partialValue
    return max(0, Int(diff) - 1)
}
```

**为什么用 `subtractingReportingOverflow`**：
- blockSeq 是 UInt32，49.7 天后溢出回绕到 0
- 普通减法 `currentSeq - prevSeq` 在回绕时会得到一个巨大的数
- `subtractingReportingOverflow` 正确处理回绕，返回差值的 partial value

---

### Q3: CoreBluetooth State Preservation and Restoration

**核心思路**：系统帮你保活 BLE 连接，但恢复时需要重新建立所有 GATT 层状态。

**详细回答**：

**机制原理**：

1. 用 `restoreIdentifier` 初始化 CBCentralManager
2. 当 App 在后台被系统杀掉时，BLE 连接由蓝牙芯片保持（不依赖 App 进程）
3. 当有新的 BLE 事件（notify 数据到达）时，系统重启 App 进程
4. App 重启后，系统用相同的 `restoreIdentifier` 创建新的 CBCentralManager
5. 系统回调 `willRestoreState`，传入之前连接的 peripherals
6. App 重新获取 peripheral 引用，继续工作

**项目中的实现**：

```swift
// 初始化
let options = [CBCentralManagerOptionRestoreIdentifierKey: "com.hrsense.ble-central-restore"]
_centralManager = CBCentralManager(delegate: self, queue: bleQueue, options: options)

// 恢复回调
public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
    guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral]
    else { return }

    for peripheral in peripherals {
        peripheral.delegate = self  // ← 必须重新设置 delegate
    }

    if let connected = peripherals.first(where: { $0.state == .connected }) {
        _connectedPeripheral = connected
    }

    emitState(.restored)
}
```

**踩过的坑**：

**坑 1: peripheral.delegate 不会自动恢复**

恢复后必须 `peripheral.delegate = self`，否则所有 CBPeripheralDelegate 回调都不会触发。我最初忘了这一步，恢复后设备推送数据但 App 完全没收到。

**坑 2: 需要重新 discoverServices**

恢复后的 peripheral，services 数组可能为空。虽然某些情况下系统会缓存，但不能依赖：

```swift
public func beginRestoredConnectionValidation() {
    bleQueue.async {
        self._handshakeReadinessGate.reset()
        peripheral.delegate = self
        self.emitState(.restoredValidating)
        peripheral.discoverServices([self.serviceUUID])  // ← 必须重新发现
    }
}
```

**坑 3: CCCD 状态可能已重置**

恢复后 `characteristic.isNotifying` 可能为 false。需要重新订阅：

```swift
// 在 didDiscoverCharacteristicsFor 中
case notifyCharUUID:
    _notifyCharacteristic = c
    peripheral.setNotifyValue(true, for: c)  // ← 恢复后也要重新订阅
```

**坑 4: 用户手动杀掉 App 不会触发恢复**

`willRestoreState` 只在系统杀掉 App（内存压力、后台超时）时触发。如果用户从多任务界面手动滑动杀掉 App，BLE 连接会被彻底断开，不会恢复。这是很多开发者误解的地方。

**坑 5: willRestoreState 只在第一次 CBCentralManager 初始化时回调**

如果你有多个 CBCentralManager（不推荐），只有第一个的 restoreIdentifier 会触发 willRestoreState。

---

### Q4: OTA 流程设计 + 断连处理

**核心思路**：OTA 是一个"不可逆操作"——固件被刷写后无法回退，所以必须设计成一个高度可靠的传输 + 校验 + 应用流程。

**详细回答**：

**完整 OTA 生命周期**：

```
Phase 0: 准备
  → 检查电量（< 20% 拒绝 OTA）
  → 校验固件文件（本地 SHA-256 + 版本号 > 当前版本）
  → 发送 OTA_START 命令 → 设备进入 OTA 模式

Phase 1: 传输
  → 设备回复 OTA_START_ACK（包含 resume_offset = 断点续传偏移量）
  → 发送 OTA_WINDOW_BEGIN（告知窗口大小 N）
  → 循环发送 N 个 chunk（Write Without Response on 0005）
  → 等待 OTA_WINDOW_ACK（设备确认收到 N 个 chunk）
  → 重复直到所有数据传输完毕

Phase 2: 校验
  → 发送 OTA_VALIDATE 命令
  → 设备计算 CRC-32 并返回 OTA_VALIDATE_RESULT
  → App 对比本地计算的 CRC-32 → 不一致则失败

Phase 3: 应用
  → 发送 OTA_APPLY 命令
  → 设备刷写固件 + 重启
  → App 等待设备重新广播 → 重新连接 → 验证新固件版本号
```

**断连处理**：

断连可能发生在任何阶段。关键设计：**设备记住进度，App 从断点续传**。

```swift
// 断连后自动重连
public func centralManager(_ central: CBCentralManager, 
                           didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    // 不清除 OTA 进度状态
    // 触发重连（指数退避）
    connectionStateMachine.transition(to: .disconnected)
    scheduleReconnect()
}

// 重连后恢复 OTA
func resumeOTA() async throws {
    // 重新发送 OTA_START → 设备返回 resume_offset
    let ack = try await sendOTAControlAndWait(.otaStart(imageSize: totalSize))
    guard case .otaStartAck(let resumeOffset) = ack else { throw AppError.otaFailed(phase: "resume") }
    
    // 从 resumeOffset 继续传输
    currentOffset = resumeOffset
    // 重新发送 OTA_WINDOW_BEGIN → 继续传输
}
```

**窗口化 ACK 设计**（关键性能优化）：

```
不使用逐块 ACK（太慢）：
  App → chunk 1 → wait ACK → chunk 2 → wait ACK → ...
  每个 chunk 需要 ~2 个 Connection Interval（发 + 收 ACK）
  6168 chunks × 2 × 7.5ms = 92.5 秒 ❌

使用窗口化 ACK：
  App → chunk 1 → chunk 2 → ... → chunk N → wait ACK → chunk N+1 → ...
  每 N 个 chunk 只需 1 次 ACK
  6168 / N 次 ACK × 2 × 7.5ms + 传输时间
  如果 N = 16，约 30 秒 ✅
```

**安全措施**：
- 固件签名：设备验证固件的数字签名（Ed25519 / ECDSA），防止恶意固件
- 电量保护：App 和设备都检查电量
- 版本回退保护：设备拒绝刷入更旧版本的固件
- 双重 CRC：App 和设备各自计算 CRC-32，必须一致

---

### Q5: OTA 传输估算

**核心思路**：从底层参数推导理论值，再叠加实际因素。

**详细回答**：

**基本参数**：
```
固件大小：1 MB = 1,048,576 bytes
MTU = 185 bytes
每块有效载荷 = 170 bytes（185 - 15 bytes 协议头）
块数 = 1,048,576 / 170 = 6,168.1 → 6,169 块（向上取整）
```

**理论最快时间**：

```
Connection Interval = 7.5ms（iOS 允许的最小值）
每 interval 可发送的数据包数：
  - iOS 15+：最多 4 个数据包 per connection event
  - 但 OTA chunk 用 Write Without Response，可以更灵活

理论传输速率（无 ACK 开销）：
  6169 chunks / (4 chunks per interval) × 7.5ms = 11.56 秒

但必须加 ACK 流控：
  窗口大小 N = 16 chunks
  每个窗口需要 1 次 ACK（~1 connection interval）
  窗口数 = 6169 / 16 ≈ 386 个窗口
  ACK 开销 = 386 × 7.5ms ≈ 2.9 秒
  
理论总时间 ≈ 11.56 + 2.9 ≈ 14.5 秒
```

**实际因素**：
- 重传（丢包率 ~1-3%）：+5-10%
- 系统调度延迟（iOS 不是实时系统）：+20-50%
- Connection Interval 可能被系统改为 30ms 或更长
- 其他 App 的蓝牙活动干扰

**实际预期：30-60 秒**

**优化方向**：

1. **增大 MTU**：iOS 支持最大 512 bytes MTU，有效载荷从 170 提升到 ~497 bytes，块数减少 65%
2. **增大窗口大小**：N 从 16 增到 64，减少 ACK 次数
3. **Connection Interval 调优**：请求最小 CI = 7.5ms（但系统可能不批准）
4. **压缩固件**：如果固件有大量 0x00 或重复段，可以用 RLE 压缩
5. **差量更新**：只传输变化部分（需要固件端支持 diff patch）

---

### Q6: 与固件工程师对齐数据协议

**核心思路**：协议即契约 + 自动化验证 + 系统化排查。

**详细回答**：

**协作流程**：

1. **协议文档先行**：
   - 所有命令、数据帧、TLV 格式在文档中定义
   - 双方 review 后确认，修改需走变更流程
   - 文档包含：字段名、类型、字节序、单位、取值范围、示例字节

2. **共享 Schema 或 Golden Bytes**：
   - 如果用 Protobuf：共享 `.proto` 文件，iOS / Android / FW 各生成各的代码
   - 如果用自定义 TLV：维护 golden bytes 文件——已知的输入→输出映射
   - CI 自动化测试：确保每次编码变更不破坏 golden bytes

3. **模拟器作为联调工具**：
   - 不需要真机即可测试协议
   - 模拟器实现完全相同的协议栈（`HRSenseProtocol` 共享）
   - 可以注入故障（丢包、CRC 错误、乱序）验证鲁棒性

**排查不一致的系统化方法**：

```
Step 1: 两端各自打印原始 hex bytes
  App:  收到 notify 数据 → print(data.hexString)
  FW:   发送前 → printf("%02X ", byte)

Step 2: 对比传输层
  用 PacketLogger 抓 HCI 包 → 确认 BLE 传输层数据与 FW 发送的完全一致
  如果 HCI 包和 FW 不一致 → BLE 芯片/协议栈问题
  如果 HCI 包和 App 不一致 → iOS CoreBluetooth 问题（极少见）

Step 3: 逐字段对比
  找到第一个不一致的字段 → 检查：
  - 字节序（big-endian vs little-endian）— 这是最常见的坑
  - 有符号 vs 无符号（int16 vs uint16）
  - 单位（毫秒 vs 1/1024 秒 vs 微秒）
  - 字节偏移（对齐填充 vs packed）
  - 数组长度（固定 vs 变长 + 长度前缀）

Step 4: 构建最小复现
  用模拟器发送已知的 golden bytes → App 解析 → 验证结果
  如果模拟器正确但真机错误 → 传输层问题
  如果模拟器也错误 → 解析逻辑问题
```

**常见的坑**：
- **字节序**：BLE 规范是 little-endian，但有些 MCU 默认 big-endian
- **RR 间期精度**：BLE 标准 Heart Rate Profile 用 1/1024 秒，但自定义协议常用毫秒
- **填充对齐**：C struct 可能有 padding，BLE 传输通常是 packed（无 padding）
- **数组长度**：如果 RR 数组长度可变，需要约定编码方式（长度前缀 vs 末尾 0x00 终止）

---

### Q7: 内存估算

**核心思路**：Swift 内存布局 + 堆 vs 栈 + 引用计数开销。

**详细回答**：

**HeartRateSample（struct, value type）**：

```swift
struct HeartRateSample: Sendable, Equatable {
    let timestamp: Date        // 8 bytes (TimeInterval = Double)
    let heartRate: UInt8?      // 2 bytes (UInt8 + Optional tag)
    let rrIntervals: [Int]     // 24 bytes (Array header) + n × 8 bytes (heap data)
    let sampleSeq: UInt32      // 4 bytes
    let contactDetected: Bool  // 1 byte
}
// struct 总大小 ≈ 40 bytes (inline) + 24+32=56 bytes (heap for [Int] of 4 elements)
// = ~96 bytes per sample
// 但 Array<Int> 的 heap allocation 有 ~32 bytes overhead
// 实际 ≈ 40 + 32 + 4×8 = 104 bytes
```

不过如果 rrIntervals 通常只有 2-4 个元素：
- 实际 ~80 bytes per sample（包含 heap overhead）
- 600 samples × 80 = **48 KB**

**WaveformSample（struct, value type）**：

```swift
struct WaveformSample: Sendable, Equatable {
    let type: WaveformType     // 1 byte (enum)
    let sampleRate: Int        // 8 bytes
    let timestamp: Date        // 8 bytes
    let value: Float           // 4 bytes
}
// struct 总大小 ≈ 24 bytes (with alignment padding)
```

3840 × 24 = **~92 KB**（加上 Array 存储的 heap allocation ~92 KB → **~184 KB**）

**日志字符串**：

```swift
// LogRingBuffer 存储 [String]
// 每条 String ≈ 16 bytes (inline) + 100 bytes (heap for UTF-8 buffer)
// 50 条 × 116 bytes ≈ 5.8 KB
```

**总计**：
```
HeartRateSample:  48 KB
WaveformSample:  184 KB
Log strings:       6 KB
──────────────────────
Total:           ~238 KB
```

这在 iOS 上微不足道（可用内存通常 > 1 GB），所以这些数据结构完全不会成为内存瓶颈。

**追问：采样率提升到 512Hz**：

```
Ring Buffer 容量不变（3840 samples）：
  时间窗口 = 3840 / 512 = 7.5 秒（从 30 秒缩短到 7.5 秒）
  内存不变 = 184 KB

如果要保持 30 秒窗口：
  容量 = 512 × 30 = 15,360 samples
  内存 = 15,360 × 24 + heap ≈ 736 KB
  
仍然可接受，但需要考虑：
  - 读取时的 filter 操作变慢（15360 次比较 vs 3840）
  - push 时的 append 频率变高（512Hz vs 128Hz）
  - Ring Buffer 的 removeFirst 开销（可以用循环索引优化）
```

---

## Part B — 资深工程师（Q8-Q14）

---

### Q8: 从零设计 BLE 健康设备 iOS App 架构

**核心思路**：分层架构 + 单一状态源 + 可观测性 + 可测试性。不是选框架，而是做决策。

**详细回答**：

**第一层：模块划分**

```
HRSenseProtocol     ← L1-L4 协议栈（帧/编解码/TLV/CRC）
      │
      ├── HRSenseCore          ← 领域层（实体/Repository 接口/UseCase）
      │     ├── HRSenseComputeCxx  ← C++ 计算层
      │     ├── HRSenseCompute     ← Swift 桥接 + CoreML
      │     ├── HRSenseData        ← BLE + 持久化 + OTA
      │     └── HRSenseFeature     ← Redux + Middleware + SwiftUI
      │           └── HRSenseAppUI     ← 组合根
      │
      └── HRSenseSimulatorKit  ← 模拟器（与 App 共享 Protocol）
```

**为什么这么分**：
- **Protocol 独立**：iOS App 和 macOS 模拟器共享同一份编解码代码，协议变更只需改一处
- **Core 纯净**：只有实体和接口，零依赖。可以单独编译、单独测试
- **Data 封装 CoreBluetooth**：全项目只有一个文件 import CoreBluetooth，上层完全不感知 BLE API
- **Feature 是 Redux 层**：Middleware 处理异步，Reducer 处理状态转换，View 只观察状态

**第二层：数据流**

```
BLE notify → FrameAssembler（分片重组）→ DecodedFrame
  → BLEDataParser（领域映射）→ HeartRateSample / WaveformBlock
  → AsyncStream → Middleware.dispatch(action)
  → Reducer（状态更新）→ AppState
  → SwiftUI（@ObservableObject → View.body 重算）
```

**关键设计决策**：
- **AsyncStream 而非 delegate 传递**：BLE 回调转为 AsyncStream，上层用 for-await 消费，解耦 BLE 线程与 Redux 线程
- **Middleware 在主线程 dispatch**：保证 Reducer 永远在主线程执行，避免状态竞态
- **FrameAssembler 持久化**：每个连接维护一个 assembler，正确处理跨 notify 的分片帧

**第三层：状态管理——为什么选 Redux 而非 MVVM**

| 维度 | MVVM | Redux/TCA |
|------|------|----------|
| 状态来源 | 分散在各 ViewModel | 单一 AppState |
| 异步流 | 各自处理 | Middleware 统一 |
| 可测试性 | Mock VM 困难 | dispatch(action) → 检查 state |
| 状态转换 | 散布在各处 | Reducer 一个函数 |
| 时间旅行调试 | 不可能 | action 序列可重放 |

BLE + IoT 场景的状态复杂度极高（连接状态 + 数据状态 + 推理状态 + OTA 状态 + 睡眠状态），如果用 MVVM，状态会分散在 5-6 个 ViewModel 中，互相通知形成蜘蛛网。Redux 的单一状态源让所有状态转换可追踪。

**第四层：错误处理**

```swift
// 统一错误枚举——所有层的错误都映射到 AppError
public enum AppError: Error, Equatable {
    case bluetoothUnauthorized
    case connectionLost
    case commandTimeout(opcode: UInt8)
    case protocolError(detail: String)
    case computeFailed
    case inferenceFailed
    case otaFailed(phase: String)
    // ... 15 种错误
}

// Reducer 驱动状态重置
func reduce(state: inout AppState, action: Action) {
    case .errorOccurred(let error):
        state.error = error
        switch error {
        case .computeFailed: state.metrics.computationStatus = .idle
        case .inferenceFailed: state.inference.status = .idle
        default: break
        }
}
```

**关键**：错误不只是 "弹个 toast"。不同类型的错误需要重置不同的子状态——computeFailed 需要重置计算状态，connectionLost 需要重置连接状态。Reducer 是唯一知道"错误类型 → 状态变更"映射的地方。

**第五层：测试策略**

| 层 | 测试类型 | 示例 |
|----|---------|------|
| Protocol | Golden bytes | 已知输入 → 编码 → 与固定字节对比 |
| Data | Mock BLE | Mock CBCentralManager，验证状态机转换 |
| Feature | Middleware 测试 | dispatch(action) → 检查后续 actions |
| E2E | 模拟器集成 | 模拟器发送场景 → 检查 AppState |

**第六层：可观测性**

```
日志：8 分类（bleRaw/bleFrame/bleConn/protoCmd/state/ota/computeInfer/perf）
状态：StateTransitionRecorder（最近 50 条 Redux 状态转换）
指标：MetricsCollector（连接成功率、丢包率、吞吐率）
系统：MetricKit（crash/hang/CPU 异常 + 关联状态转换）
诊断：DiagnosticPanelView（6 KPI + JSON 导出）
```

**为什么可观测性不是可选项**：
BLE + IoT 的问题经常发生在用户端、不在开发者面前。如果 App 没有内建的可观测性，你只能跟用户说"请复现一下让我看看"——但他们通常无法复现。DiagnosticPackage 让用户一键导出现场快照，开发者拿到 JSON 就能分析。

---

### Q9: 在既有架构上做重大演进的经历

**核心思路**：渐进式、可回滚、有测试保障。不是"我觉得旧代码烂"，而是"系统性地评估和迁移"。

**详细回答**：

**场景**：将一个 MVVM 架构的 BLE App 迁移到 Redux 架构。

**1. 识别问题（不是拍脑袋）**

```
问题信号：
- 连接状态变化时，3 个 ViewModel 各自更新，出现不一致
- 后台 BLE 恢复后，ViewModel 状态与 BLE 实际状态不同步
- 添加新功能需要改动 4-5 个文件
- 测试只能覆盖 ViewModel 的初始状态，无法测试状态转换
```

**2. 风险评估**

```
| 风险 | 影响 | 缓解 |
|------|------|------|
| 迁移期间新旧代码共存 | 状态不一致 | 功能维度切分，非文件维度 |
| Redux 学习曲线 | 团队效率 | 先迁移 1 个模块作为试点 |
| 状态定义错误 | 全局 bug | 类型安全的 AppState + 编译期检查 |
| 回滚需求 | 代码浪费 | 保持旧代码不被删除直到验证完成 |
```

**3. 迁移计划（渐进式）**

```
Phase 1 (2 周): 定义 AppState + Reducer + Store
  → 与旧 ViewModel 共存
  → 新状态只观察、不驱动 UI

Phase 2 (3 周): 迁移连接管理
  → ConnectionViewModel → ConnectionMiddleware
  → 旧 ViewModel 改为观察 Redux state

Phase 3 (3 周): 迁移数据流
  → DataViewModel → BLEStreamMiddleware
  → 验证数据一致性

Phase 4 (2 周): 迁移 UI
  → SwiftUI View 直接观察 Store
  → 删除旧 ViewModel

Phase 5 (1 周): 清理
  → 删除废弃代码
  → 补充测试
```

**4. 向后兼容保证**

- **功能维度切分**：不混用新旧代码。要么整个功能用新架构，要么整个用旧架构
- **接口不变**：上层 UI 通过 Repository 协议访问数据，底层切换对上层透明
- **能力协商**：对于协议变更，通过 HELLO 握手的能力位协商，新旧设备都能通信

**5. 测试保障**

```swift
// Golden test: 确保迁移前后行为一致
func testConnectionFlowMigration() {
    // 用旧代码跑一遍连接流程，记录状态序列
    let oldStates = runOldConnectionFlow()
    // 用新代码跑相同流程
    let newStates = runNewConnectionFlow()
    // 对比最终状态（忽略实现细节）
    XCTAssertEqual(oldStates.finalMetrics, newStates.finalMetrics)
}
```

**6. 沟通**

- 写迁移文档（不是给自己看的，是给 6 个月后的自己和新同事看的）
- Code review 重点标注"这是迁移变更"，reviewer 知道上下文
- 每周 sync 进度，blockers 提前暴露

---

### Q10: 代码审查——BLE 代码的 9 个问题

**核心思路**：从 API 正确性、线程安全、资源管理、健壮性四个维度审查。

**详细回答**：

```swift
final class BLEManager: NSObject, CBCentralManagerDelegate {
    var centralManager: CBCentralManager!          // ⚠️ 问题 8
    var connectedPeripheral: CBPeripheral?

    override init() {
        centralManager = CBCentralManager(delegate: self, queue: nil)  // ⚠️ 问题 1
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: nil)        // ⚠️ 问题 2
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        centralManager.connect(peripheral)                              // ⚠️ 问题 3, 4, 5
        connectedPeripheral = peripheral                                // ⚠️ 问题 4
    }
    // ⚠️ 问题 6, 7, 9: 缺失的回调和功能
}
```

**问题 1: `queue: nil` — 所有回调在主线程**

`CBCentralManager(delegate:queue:)` 传 nil 意味着所有 delegate 回调在主线程执行。对于 BLE 高吞吐场景（波形数据），主线程会被阻塞，导致 UI 卡顿。应该用专用队列：

```swift
private let bleQueue = DispatchQueue(label: "com.app.ble")
centralManager = CBCentralManager(delegate: self, queue: bleQueue)
```

**问题 2: `scanForPeripherals(withServices: nil)` — 全量扫描**

扫描所有设备会显著增加功耗。应该指定目标 service UUID：

```swift
centralManager.scanForPeripherals(withServices: [targetServiceUUID])
```

**问题 3: 没有停止扫描**

连接后应停止扫描，否则系统继续消耗电量：

```swift
func didConnect(peripheral) {
    centralManager.stopScan()
}
```

**问题 4: 在 `didDiscover` 中赋值 `connectedPeripheral`**

`connect()` 是异步的。此时 peripheral 尚未连接，赋值语义不正确。应该在 `didConnect` 回调中赋值：

```swift
func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    self.connectedPeripheral = peripheral
}
```

**问题 5: 对同一 peripheral 重复 connect**

`didDiscover` 可能多次触发（如果 allowDuplicates），每次都会调用 connect。应该检查是否已连接：

```swift
guard connectedPeripheral == nil else { return }
```

**问题 6: 没有 `didConnect` / `didFailToConnect` 回调**

无法知道连接结果。必须实现这两个回调：

```swift
func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    peripheral.delegate = self
    peripheral.discoverServices([serviceUUID])
}

func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    // 处理连接失败
}
```

**问题 7: 没有 State Restoration**

App 被系统杀掉后 BLE 连接丢失。需要使用 restoreIdentifier：

```swift
let options = [CBCentralManagerOptionRestoreIdentifierKey: "com.app.ble-restore"]
centralManager = CBCentralManager(delegate: self, queue: bleQueue, options: options)
```

**问题 8: `centralManager!` 强制解包**

虽然 init 中赋值是安全的（super.init 后），但隐式解包是反模式。可以用 lazy 或可选绑定。

**问题 9: 没有超时处理**

`connect()` 可能永远不回调（设备已关机但还在广播范围内）。应该加超时：

```swift
connectTimeoutTask = Task {
    try await Task.sleep(for: .seconds(10))
    guard stillConnecting else { return }
    centralManager.cancelPeripheralConnection(peripheral)
}
```

**修正后的核心骨架**：

```swift
final class BLEManager: NSObject, CBCentralManagerDelegate {
    private let bleQueue = DispatchQueue(label: "com.app.ble")
    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private let serviceUUID = CBUUID(string: "...")

    override init() {
        super.init()
        centralManager = CBCentralManager(
            delegate: self, queue: bleQueue,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "com.app.ble"]
        )
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: [serviceUUID])
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard connectedPeripheral == nil else { return }
        central.stopScan()
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
    }
}
```

---

### Q11: Swift 调用 C 函数——内存安全

**核心思路**：caller-allocated + withUnsafeBufferPointer + 检查返回值。

**详细回答**：

```swift
func compute(from data: [UInt16]) throws -> Double {
    guard !data.isEmpty else { throw ComputeError.emptyInput }

    var result: Double = 0
    let status = data.withUnsafeBufferPointer { buffer -> Int32 in
        guard let baseAddress = buffer.baseAddress else { return -1 }
        return compute(baseAddress, buffer.count, &result)
    }
    // ↑ 闭包结束后，buffer 指针失效

    guard status == 0 else { throw ComputeError.computationFailed }
    return result
}
```

**三个关键安全保证**：

1. **withUnsafeBufferPointer 的生命周期**：
   - buffer 指针只在闭包内有效
   - C 函数必须在闭包内完成所有访问
   - 如果 C 函数存储了指针并在闭包后访问 → undefined behavior
   - 我们的 C 函数是同步的，在闭包内返回 → 安全

2. **caller-allocated output（`&result`）**：
   - Swift 端分配 `var result: Double = 0`
   - 传 `&result` 给 C 函数（C 收到 `double *out`）
   - C 函数只写入，不释放 → 没有 ownership 问题
   - 如果 C 函数返回的是 C 函数内部 malloc 的内存 → 需要手动 free → 容易泄漏

3. **返回值检查**：
   - C 函数返回 int 状态码
   - 0 = 成功，非 0 = 失败
   - 不检查就使用 result → 可能读到未初始化的值

**HRSense 项目中的实际模式**：

```swift
// ComputeBridge.swift
var metrics = hrs_hrv_metrics_t()       // caller-allocated
let result = rrIntervalsMs.withUnsafeBufferPointer { buf in
    hrs_compute_hrv(buf.baseAddress, buf.count, &metrics)  // C fills
}
guard result == 0 else { throw ComputeError.computationFailed }
// 手动映射 C struct → Swift struct
return HRVMetrics(sdnn: metrics.sdnn, rmssd: metrics.rmssd, ...)
```

**为什么手动映射而非直接暴露 C struct**：
- C struct 的命名不符合 Swift 规范（snake_case vs camelCase）
- C struct 可能包含 padding 字段
- 隔离 C ABI 变更——C 端字段重命名不影响 Swift 上层

---

### Q12: 后台执行策略设计

**核心思路**：iOS 后台是"受限环境"——不是什么都不能做，而是要区分优先级，精打细算 CPU 预算。

**详细回答**：

**iOS 后台的三个限制层**：

| 层级 | 限制 | 绕过方式 |
|------|------|----------|
| CPU 时间 | ~30 秒（后台任务） | Background Mode 可延长 |
| 网络/BLE | 默认暂停 | bluetooth-central Background Mode |
| 内存 | 优先被杀 | 控制内存占用 |

**策略设计**：

```
前台：一切正常
  ├── BLE 连接 + 数据传输 ✅
  ├── CoreML 推理 ✅
  ├── 波形渲染 ✅
  ├── 日志全量 ✅
  └── 用户扫描 ✅

后台：保留关键功能
  ├── BLE 连接保活 ✅（bluetooth-central Background Mode）
  ├── BLE State Restoration ✅
  ├── 睡眠推理 ✅（如果正在监测睡眠）
  ├── 心率/RR 接收 ✅（数据量小）
  ├── 压力推理 ❌（非紧急，推迟到前台）
  ├── 波形渲染 ❌（UI 不可见，无需更新）
  ├── 波形轮询 ❌（Ring Buffer 继续接收，但不读）
  └── 用户扫描 ❌（停止，省电）
```

**Middleware 实现**：

```swift
// BackgroundMiddleware — 条件式 action 拦截
private func shouldDrop(action: Action, state: AppState, policy: BackgroundExecutionPolicy) -> Bool {
    guard state.lifecycle == .background else { return false }

    switch action {
    case .waveformSamplesReceived, .waveformMetricsUpdated:
        return policy.pauseWaveformRenderingInBackground

    case .featuresExtracted, .inferenceStarted, .inferenceCompleted:
        return policy.pauseStressInferenceInBackground

    case .computeStarted, .hrvComputed:
        // 关键：睡眠监测时不暂停计算
        return policy.pauseComputeInBackgroundUnlessSleepMonitoring && !state.sleep.isMonitoring

    default:
        return false
    }
}
```

**关键设计决策**：

1. **条件式暂停**：不是一刀切暂停所有计算。如果用户正在监测睡眠，后台仍然需要 C++ 计算和睡眠推理——这是核心功能。但通用的压力推理可以暂停。

2. **Ring Buffer 在后台继续工作**：BLE 数据仍然到达（Background Mode），Ring Buffer 继续接收和存储。只是 UI 不读取。回到前台时，Ring Buffer 里有完整的后台数据。

3. **BGTaskScheduler 补充**：
```swift
// 注册后台刷新任务（如持久化清理）
BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.hrsense.cleanup", using: nil) {
    task in
    let retentionTask = RetentionCleanupTask(store: store)
    Task { await retentionTask.execute() }
    task.setTaskCompletedWithSuccess(true)
}
```

4. **CPU 预算分配**：
```
30 秒后台 CPU 预算的分配：
  BLE 数据处理：~5s（每秒接收数据并缓存）
  睡眠推理（如果需要）：~10s（CoreML 推理）
  持久化写入：~5s（批量写入）
  系统开销：~10s
```

如果超出预算，iOS 会杀死 App。所以后台不能做太多事——这也是为什么要把压力推理推迟到前台。

---

### Q13: 接手 2 万行 BLE + ML 项目的前两周

**核心思路**：先理解再行动。资深工程师的 onboarding 不是"快速出活"，而是"建立全局认知，避免踩坑"。

**详细回答**：

**Week 1: 理解 + 跑通**

| 天 | 活动 | 产出 |
|----|------|------|
| Day 1 | 产品体验 + 与 PM 沟通 | 核心场景清单、用户画像 |
| Day 2 | 全链路跑通（真机 + 模拟器） | 从扫描到数据可视化的完整路径 |
| Day 3 | 阅读架构文档 + 模块依赖图 | 理解分层、状态管理方式 |
| Day 4 | 阅读 Protocol 层 + BLE 层 | 理解帧格式、命令流程、连接状态机 |
| Day 5 | 阅读 Feature 层 + 关键 Middleware | 理解 Redux action 流、线程模型 |

**Week 2: 深入 + 小 PR**

| 天 | 活动 | 产出 |
|----|------|------|
| Day 6 | 跑全量测试 + 分析覆盖率 | 知道哪些路径没测到 |
| Day 7 | 与 FW 工程师联调一次 | 理解联调流程、工具链 |
| Day 8 | 与算法工程师沟通 | 理解模型交付流程、特征契约 |
| Day 9 | 修一个小 bug 或加一个日志改进 | 熟悉 PR 流程、CI、Code Review |
| Day 10 | 整理技术债务清单 | 优先级排序、与 lead 讨论 |

**关键原则**：

1. **先看再改**：不要第一周就说"这个架构有问题要重构"。你可能还没理解它为什么这样设计。

2. **建立开发环境**：
   - 模拟器能跑（不需要真机即可开发）
   - PacketLogger 已安装
   - 日志工具已配置
   - CI 能通过

3. **找到关键路径**：BLE 连接 → HELLO 握手 → START_STREAM → 数据接收 → HRV 计算 → CoreML 推理 → UI 更新。这是系统的"主动脉"，理解它就理解了 80% 的系统。

4. **小 PR 热身**：不是修大 bug，而是修一个小问题（比如日志格式不一致），目的是走通 PR → Review → CI → Merge 的完整流程。

5. **记录问题但不急于解决**：
   - 看到 `// TODO: fix this`
   - 看到测试覆盖盲区
   - 看到潜在的线程安全问题
   - 记下来，排优先级，与 lead 讨论

---

### Q14: "App 在睡眠监测时偶尔 crash" — 完整工作流程

**核心思路**：偶发 crash = 并发问题，直到证明不是。系统性地收集证据 → 缩小范围 → 定位根因 → 修复 + 预防。

**详细回答**：

**Step 1: 信息收集（Day 1）**

```
引导用户提供：
1. 设备型号 + iOS 版本（iPhone 15, iOS 17.4）
2. App 版本号（2.1.0 build 42）
3. 复现频率（"大概 3 天一次"）
4. 复现条件（"通常是凌晨 3-4 点"）
5. DiagnosticPackage JSON
```

**Step 2: 获取 DiagnosticPackage**

```
如果用户有 DiagnosticPanelView（DEBUG 模式下三击 Logo 触发）：
→ 导出 JSON → 发送给开发者

如果没有：
→ 引导用户通过 TestFlight feedback 提交
→ 或从 Xcode Organizer 拉取 crash report
```

**Step 3: 分析 Crash 堆栈**

```
从 MetricKit / Xcode Organizer 获取 crash report:

Thread 0 (Main):
  #0 libsystem_kernel    __pthread_kill
  #1 libsystem_c         abort
  #2 HRSenseCompute      hrs_compute_hrv (hrv.cpp:142)
  #3 HRSenseCompute      ComputeBridge.computeHRV (ComputeBridge.swift:24)
  #4 HRSenseFeature      ComputeMiddleware (ComputeMiddleware.swift:67)

→ crash 在 C++ 的 hrs_compute_hrv 中，abort 被调用
→ 通常是断言失败或数组越界
```

**Step 4: 关联状态转换**

```
从 StateTransitionRecorder 获取 crash 前的 action 序列：

12:00:00 .connectionEstablished
12:00:01 .handshakeCompleted
03:15:22 .didEnterBackground
03:15:23 .computeStarted       ← 后台触发计算
03:15:23 .hrvComputed           ← 第一次成功
03:16:00 .computeStarted       ← 又一次触发
03:16:00 .sleepFeaturesComputed
03:16:01 CRASH                  ← C++ 层崩溃
```

**关键线索**：两次 `computeStarted` 间隔只有 38 秒，且发生在后台。

**Step 5: 定位根因**

```
假设 1: RR 数组为空 → C++ 断言失败
  验证：检查 ComputeMiddleware 的 guard 条件
  发现：guard rrIntervals.count >= 2 → 已经检查了

假设 2: 并发访问共享状态
  验证：ComputeBridge 是 Sendable，但是否有共享状态？
  检查 hrs_compute_hrv 的 C++ 代码：
    → 使用了 static 局部变量缓存 Lomb-Scargle 频率表
    → 两个线程同时调用 → 数据竞争 → 数组越界 → abort

根因：C++ 层的 static 局部变量在并发调用时不安全。
```

**Step 6: 复现**

```
在模拟器中构造场景：
1. 同时触发两个 ComputeMiddleware（一个由 .computeStarted，一个由 sleep pipeline）
2. 传入相同的 RR 数组
3. 用 TSAN (Thread Sanitizer) 检测
→ 确认数据竞争
```

**Step 7: 修复 + 测试**

```swift
// 方案 A: 给 C++ 函数加 mutex（简单但阻塞）
// 方案 B: 确保调用方串行化（在 Middleware 层加 queue）
// 方案 C: 去掉 C++ static 变量（最佳但改动大）

// 选择方案 B（风险最低）：
private let computeQueue = DispatchQueue(label: "com.hrsense.compute")

func computeHRV(from rr: [UInt16]) throws -> HRVMetrics {
    try computeQueue.sync {
        var metrics = hrs_hrv_metrics_t()
        let result = rr.withUnsafeBufferPointer { buf in
            hrs_compute_hrv(buf.baseAddress, buf.count, &metrics)
        }
        guard result == 0 else { throw ComputeError.computationFailed }
        return HRVMetrics(...)
    }
}
```

**Step 8: 灰度发布**

```
Day 1: TestFlight 内部测试（确认不 crash）
Day 3: TestFlight 灰度（100 人，观察 MetricKit）
Day 7: 全量发布

监控指标：
- Crash rate < 0.1%
- 特别关注 hrs_compute_hrv 的 crash 是否消失
```

**Step 9: 复盘**

```
| 问题 | 回答 |
|------|------|
| 为什么测试没覆盖到 | 单元测试只测单次调用，没有测并发 |
| 需要补什么测试 | C++ 并发压力测试（100 线程同时调用） |
| 需要补什么监控 | C++ 函数入口/出口日志（computeInfer 分类） |
| 根本原因 | C++ 代码假设单线程调用，但 Swift 端有多个 Middleware 并发 |
| 长期改进 | 迁移到 Swift 6 的严格并发检查，编译期发现此类问题 |
```

**加分分析**：

这个项目中有几个 `@unchecked Sendable` 类型（如 `WaveformRingBuffer`、`BLECentralDataSource`）。`@unchecked` 意味着编译器不检查线程安全，全靠开发者保证。对于 C++ 层的 static 变量，Swift 的 `@unchecked Sendable` 完全无法保护——这是一个系统性风险，迁移到 Swift 6 的严格并发模式是 P0 优先级。
