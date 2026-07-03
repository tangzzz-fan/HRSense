# JD 分析与面试题设计

> 基于 JD.md 的实际业务痛点，设计面向高级 / 资深 iOS 工程师的面试题。重点考察落地能力而非 API 背诵，检验候选人是否真正做过类似功能。

---

## 1. JD 核心痛点分析

| JD 职责 | 背后的真实痛点 | 难度来源 |
|---------|---------------|---------|
| **OTA/DFU 开发** ⭐ | 固件升级是"不可逆操作"——失败可能变砖，必须保证 100% 可靠 | 分片传输 + 断点续传 + CRC 校验 + 超时重试 + 用户中断处理 + 电量不足保护 |
| **BLE 深度优化** | BLE 是"不可靠管道"——系统杀进程、信号波动、多设备干扰 | 连接参数调优 + 断线重连策略 + MTU 协商 + 高吞吐 vs 稳定性权衡 |
| **多方联调 (Protobuf)** | iOS / Android / FW / 算法四端协作——协议定义是契约，改一处全端受影响 | 协议版本管理 + 兼容变更 + 字节序对齐 + 跨端联调效率 |
| **数据计算与可视化** | 实时数据流 + ML 推理 + 波形渲染——性能与正确性双重挑战 | C++ 桥接 + CoreML + 滑动窗口 + 高帧率图表 |
| **崩溃分析与监控** | BLE + IoT 场景的 crash 往往不在 App 层——需要全链路排查能力 | MetricKit + 状态转换记录 + 分层日志 + 现场保全 |

### JD 中隐含的关键能力

1. **区分 App / BLE / FW 问题**：不是"我的代码没问题"，而是能指出"问题在对端"并给出证据
2. **在既有架构上演进**：不是从零设计，而是在已有 Redux + Clean Architecture 上做增量改进
3. **端到端思维**：从用户操作到 BLE 字节到 MCU 中断，全链路可追踪
4. **与嵌入式工程师对话**：理解字节序、MTU、GATT、ACK 等概念

---

## 2. 高级工程师面试题（3-5 年经验）

### 2.1 BLE 连接与通信

**Q1: 描述一次你排查 BLE 连接不稳定问题的完整过程。**

> **考察点**：是否有真实的 BLE debug 经验，而非只写过 happy path。

**期望回答要点**：
- 使用 PacketLogger / Bluetooth Explorer 抓取 HCI 包
- 检查 Connection Interval、Slave Latency、Supervision Timeout
- 区分"连接断开"和"notify 停止"（前者是 L2CAP 断，后者可能是 CCCD 被重置）
- 检查 iOS 后台 BLE 限制（Background Task 过期、CPU 被系统节流）
- 提到 RSSI 波动与距离/干扰的关系

**红旗信号**：
- 只提到 `centralManager.connect()` 和 delegate 回调，没有更深层的分析
- 不了解 Connection Parameters
- 从未用过 PacketLogger

---

**Q2: 一个 BLE 设备每秒推送 128 个样本（每个 2 字节），你会如何设计 App 端的接收和存储方案？需要考虑哪些瓶颈？**

> **考察点**：高吞吐 BLE 数据流的实战经验。

**期望回答要点**：
- MTU 协商（iOS 通常 ~185 bytes），每包最多 ~88 个样本
- notify 回调在主线程，高频时可能积压 → 考虑 Connection Interval 调优
- 接收端用 Ring Buffer（固定容量，自动淘汰旧数据）
- 存储不能每个样本都写磁盘 → 批量写入（阈值 + 超时双触发）
- SwiftUI 不能每帧都更新 → 轮询机制（10Hz 刷新 UI）
- 丢包检测：blockSeq / sampleSeq 序号

**红旗信号**：
- 不知道 MTU 的概念
- 认为 notify 回调在后台线程
- 直接 `append` 到无限数组

---

**Q3: CoreBluetooth 的 State Preservation and Restoration 机制是如何工作的？你遇到过哪些坑？**

> **考察点**：iOS BLE 后台保活的实际经验。

**期望回答要点**：
- 使用 `restoreIdentifier` 初始化 CBCentralManager
- 系统杀掉 App 后，BLE 连接仍保持
- 用户再次打开 App 时，`willRestoreState` 回调恢复 peripheral 引用
- **坑**：restored peripheral 需要重新发现 services（部分缓存）
- **坑**：restored 后的 CCCD 状态可能已重置，需重新订阅
- **坑**：`willRestoreState` 只在 App 被系统恢复时调用，用户手动杀掉不会

**红旗信号**：
- 从未使用过 State Restoration
- 不知道 `willRestoreState` 回调

---

### 2.2 OTA/DFU

**Q4: 描述你设计或参与过的 OTA 流程。如果传输过程中 BLE 断连了，你会怎么处理？**

> **考察点**：OTA 是 JD 的核心职责，必须考察真实经验。

**期望回答要点**：
- 完整的 OTA 生命周期：准备 → 传输 → 校验 → 应用
- 分片传输 + 窗口化 ACK（不是逐块 ACK，否则太慢）
- 断连后的断点续传：设备记住已接收偏移量，重连后从断点继续
- CRC-32 校验（传输完成后，设备计算固件镜像的 CRC 与 App 对比）
- 超时重试策略（单块超时 → 重发；整体超时 → 失败）
- 安全措施：固件签名验证、电量检查（< 20% 不允许 OTA）、版本回退保护
- 用户体验：进度条、取消按钮、失败提示

**红旗信号**：
- 只用过 Nordic DFU Library，不了解底层原理
- 不知道窗口化 ACK
- 没有考虑断连续传

---

**Q5: OTA 传输 1MB 固件，BLE MTU=185，每块有效载荷 170 字节。估算传输时间和需要的块数。如果要优化传输速度，你会从哪些方面入手？**

> **考察点**：工程估算能力 + BLE 传输优化经验。

**参考答案**：
- 块数：1,048,576 / 170 ≈ 6,168 块
- 理论时间：Connection Interval=7.5ms，每 interval 可发 1-4 块（取决于 iOS 版本）
- 乐观估计：6168 × 7.5ms / 4 ≈ 11.5 秒
- 实际时间：30-60 秒（ACK 流控 + 重传 + 系统调度）
- 优化方向：
  - 增大 Connection Interval 内的包数（More Data flag）
  - 窗口化 ACK（每 N 块确认一次，而非逐块）
  - Write Without Response（但需自行处理可靠性）
  - 调整 MTU（iOS 最大可达 512）

---

### 2.3 数据协议与跨端协作

**Q6: 你在项目中如何与固件工程师对齐数据协议？如果两端解析出来的数据不一致，你会怎么排查？**

> **考察点**：跨端联调的实战经验。

**期望回答要点**：
- 协议文档先行（双方签字确认后再写代码）
- 使用共享 schema（Protobuf / FlatBuffers）或 golden bytes 测试
- 字节序对齐（大小端）——这是最常见的坑
- 排查步骤：
  1. 两端各自打印原始 hex bytes
  2. 逐字段对比，找到第一个不一致的字段
  3. 检查字节序、符号（有符号 vs 无符号）、单位（ms vs 1/1024s）
  4. 用 Wireshark / PacketLogger 抓包确认传输层是否正确
- 提到"模拟器"作为调试工具（不需要真机即可测试协议）

**红旗信号**：
- 从未与固件工程师协作过
- 不知道字节序（endianness）的问题
- 只靠"发测试数据看结果"，没有系统化方法

---

### 2.4 性能与内存

**Q7: 一个 App 同时维护以下数据结构，估算内存占用：
- 600 个 HeartRateSample（每个含 timestamp + hr + rrIntervals[4] + seq + contact）
- 3840 个 WaveformSample（每个含 type + sampleRate + timestamp + value）
- 50 条日志字符串（每条 ~100 字符）**

> **考察点**：对 Swift 内存布局的直觉。

**参考答案**：
- `HeartRateSample`：~80 bytes（Date=8, Int×3=24, [Int]=~56 overhead+data, UInt32=4, Bool=1）× 600 ≈ **48 KB**
- `WaveformSample`：~48 bytes（Int×2=16, Date=8, Float=4 + overhead）× 3840 ≈ **184 KB**
- 日志字符串：100 chars × 50 ≈ **5 KB**
- **总计 ≈ 237 KB** — 完全可接受

**追问**：如果波形采样率从 128Hz 提升到 512Hz，Ring Buffer 容量不变，内存会怎样？
- 3840 样本 / 512Hz = 7.5 秒窗口（从 30 秒缩短）
- 内存不变，但时间覆盖范围缩小
- 如果需要保持 30 秒窗口，容量需增大到 15360 → 736 KB

---

## 3. 资深工程师面试题（5+ 年经验）

### 3.1 全局架构能力

**Q8: 假设你需要从零设计一个 BLE 健康设备的 iOS App 架构。描述你的整体设计，包括模块划分、数据流、错误处理、测试策略。**

> **考察点**：全局设计能力，是否能系统化思考而非只关注单点。

**期望回答结构**：
1. **模块划分**：Protocol（编解码）→ Core（领域）→ Data（BLE + 持久化）→ Feature（UI + 状态管理）→ App（组合根）
2. **数据流**：BLE notify → 分片重组 → 领域映射 → 状态管理 → UI
3. **状态管理选型**：为什么选 Redux/TCA 而非 MVVM？（单一状态源、可预测、可测试）
4. **错误处理**：统一错误枚举、每层转换、Reducer 驱动状态重置
5. **测试策略**：Protocol 层 golden bytes、Data 层 Mock BLE、Feature 层 middleware 测试、E2E 集成测试
6. **可观测性**：分层日志、状态转换记录、MetricKit、诊断包导出

**红旗信号**：
- 只有 MVVM + Repository，没有考虑状态管理
- 没有提到错误处理体系
- 没有可观测性设计

---

**Q9: 在你参与过的项目中，描述一次你在既有架构上做重大演进的经历。你如何评估风险、制定迁移计划、保证向后兼容？**

> **考察点**：架构演进能力（JD 明确要求"在既有代码基础上优化、演进与重构"）。

**期望回答要点**：
- 识别技术债务（不是"老板让我重构"，而是自己发现问题）
- 风险评估：影响范围、回滚方案、灰度策略
- 渐进式迁移：新功能用新方案，旧功能分批迁移
- 向后兼容：版本号、能力协商、降级路径
- 测试保障：迁移前后行为一致（golden test / snapshot test）
- 沟通：与团队对齐、文档更新、code review 重点

**红旗信号**：
- "推翻重来"而非渐进演进
- 没有提到风险评估和回滚方案
- 迁移过程中没有测试保障

---

### 3.2 细微处能力

**Q10: 以下 Swift 代码有什么问题？如何改进？**

```swift
final class BLEManager: NSObject, CBCentralManagerDelegate {
    var centralManager: CBCentralManager!
    var connectedPeripheral: CBPeripheral?

    override init() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        centralManager.connect(peripheral)
        connectedPeripheral = peripheral
    }
}
```

> **考察点**：BLE 基础功底的细节掌握程度。

**问题清单**：
1. **`queue: nil`** → 回调在主线程，高频 notify 会阻塞 UI
2. **`scanForPeripherals(withServices: nil)`** → 扫描所有设备，电量消耗大
3. **没有停止扫描** → 连接后应 `stopScan()`
4. **`connectedPeripheral = peripheral`** → 在 `didDiscover` 中赋值，但 `connect` 是异步的，此时未连接
5. **没有持有 peripheral 的强引用** → `connectedPeripheral` 可能被释放（如果 `var` 是 weak 的话，这里虽然不是 weak，但 `connectedPeripheral` 在 `didConnect` 前赋值不安全）
6. **没有 `didConnect` / `didFailToConnect` 回调** → 无法知道连接结果
7. **没有 State Restoration** → App 被杀后 BLE 连接丢失
8. **`centralManager!` 强制解包** → init 中赋值安全，但风格不佳
9. **没有超时处理** → `connect` 可能永远不回调

---

**Q11: 在 Swift 中调用 C 函数 `int compute(const uint16_t *data, size_t count, double *out)` 时，如何确保内存安全？请写出完整的调用代码。**

> **考察点**：Swift-C 桥接的实战经验（JD 加分项）。

**期望回答**：
```swift
func compute(from data: [UInt16]) throws -> Double {
    guard !data.isEmpty else { throw ComputeError.emptyInput }

    var result: Double = 0
    let status = data.withUnsafeBufferPointer { buffer -> Int32 in
        guard let baseAddress = buffer.baseAddress else { return -1 }
        return compute(baseAddress, buffer.count, &result)
    }
    // ↑ 闭包结束后，buffer 指针失效，C 函数不能再访问

    guard status == 0 else { throw ComputeError.computationFailed }
    return result
}
```

**关键检查点**：
- 使用 `withUnsafeBufferPointer`（而非 `UnsafePointer` 手动管理）
- 检查返回值
- 理解指针的生命周期（闭包内有效）
- `&result` 是 caller-allocated output pattern

**红旗信号**：
- 使用 `UnsafeMutablePointer.allocate()` 手动管理
- 不理解 `withUnsafeBufferPointer` 的生命周期
- 没有检查返回值

---

**Q12: 你的 App 在后台运行时，BLE 数据仍然在接收。但 CoreML 推理在后台被系统限制了 CPU 时间。你会如何设计后台执行策略？**

> **考察点**：iOS 后台执行限制 + 策略设计（JD 明确要求"后台任务处理，特别是与 BLE 相关的"）。

**期望回答要点**：
- **区分关键 vs 非关键**：BLE 连接保活（关键）vs ML 推理（可延迟）
- **Background Modes**：`bluetooth-central` 保持 BLE 连接
- **BGTaskScheduler**：注册 `BGAppRefreshTask` 在后台执行清理/推理
- **Middleware 策略**：后台时暂停非核心 action（波形渲染、压力推理），保留睡眠推理
- **State Restoration**：App 被系统杀掉后恢复 BLE 连接
- **CPU 时间预算**：iOS 给后台 App 约 30 秒 CPU 时间，要精打细算
- **权衡**：如果推理结果不紧急，推迟到前台再执行

**红旗信号**：
- 不知道 iOS 后台 CPU 限制
- 认为 BLE 后台不需要 Background Mode
- 没有在后台和前台使用不同策略

---

### 3.3 全局观 + 细微处综合

**Q13: 你接手了一个已有 2 万行代码的 BLE + ML iOS 项目。前两周你会做什么？**

> **考察点**：资深工程师的 onboarding 方法论。

**期望回答结构**：
1. **理解业务**：产品做什么？用户是谁？核心场景是什么？
2. **跑通全链路**：从打开 App 到看到数据，手动走一遍
3. **阅读架构文档**：模块依赖、数据流、状态管理方式
4. **定位关键路径**：BLE 连接 → 数据接收 → 计算 → 推理 → UI
5. **找到技术债务**：代码注释中的 TODO、测试覆盖盲区、已知 bug
6. **建立开发环境**：模拟器、测试设备、PacketLogger、日志工具
7. **与团队沟通**：固件工程师的联调方式、算法工程师的模型交付流程
8. **小 PR 热身**：修一个小 bug 或加一个日志，熟悉 PR 流程

**红旗信号**：
- 直接开始重构
- 不看文档直接改代码
- 不与团队沟通

---

**Q14: 用户报告"App 在睡眠监测时偶尔 crash"。从收到这个报告到发布修复版本，描述你的完整工作流程。**

> **考察点**：端到端的事故处理能力（JD 要求"完善崩溃分析、日志体系、监控"）。

**期望回答结构**：
1. **信息收集**：设备型号、iOS 版本、App 版本、复现步骤
2. **获取 DiagnosticPackage**：引导用户导出 JSON
3. **分析 crash 堆栈**：MetricKit / Xcode Organizer crash report
4. **关联状态转换**：crash 前的 Redux action 序列
5. **定位根因**：分层排查（BLE 层 / 数据层 / 计算层 / UI 层）
6. **复现**：在测试环境复现问题
7. **修复 + 测试**：编写回归测试
8. **灰度发布**：TestFlight → 监控 → 全量
9. **复盘**：为什么测试没覆盖到？需要补什么监控？

**加分回答**：
- 提到"偶发 crash 通常是并发问题"（C++ 计算和 CoreML 推理的竞态）
- 提到检查 `@unchecked Sendable` 的线程安全
- 提到 `WaveformRingBuffer` 的 NSLock 是否有死锁可能

---

## 4. 面试评估矩阵

| 维度 | 高级工程师标准 | 资深工程师标准 |
|------|---------------|---------------|
| **BLE 深度** | 能独立排查连接/传输问题，理解 GATT/CCCD/MTU | 能设计高吞吐 BLE 架构，调优连接参数，处理后台保活 |
| **OTA** | 了解 OTA 流程，能实现分片传输 + 断点续传 | 能设计完整 OTA 系统（窗口 ACK + CRC + 签名 + 降级） |
| **跨端协作** | 能与 FW 工程师对齐协议，排查字节序问题 | 能主导协议设计（TLV/Protobuf），建立跨端 CI 验证 |
| **架构** | 能在既有架构上做增量改进 | 能从零设计分层架构，评估技术债务，制定演进路线 |
| **性能** | 能分析内存/CPU 瓶颈，优化热路径 | 能设计全局性能策略（后台策略、批量 I/O、Ring Buffer） |
| **可观测性** | 能使用日志/调试工具定位问题 | 能设计完整可观测性体系（日志 + MetricKit + 诊断包） |
| **事故处理** | 能按模板排查问题，修复 bug | 能建立事故响应体系，主导复盘，推动预防机制 |
| **沟通** | 能清晰描述技术问题 | 能跨职能沟通（FW / 算法 / 产品），推动技术方案落地 |
