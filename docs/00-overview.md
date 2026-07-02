# 00 · 项目总览

## 1. 背景

HRSense 是一款连接蓝牙心率设备的 iOS 应用。硬件设备读取用户心率（及潜在的 RR 间期、体动、电量等）数据，通过 BLE 上报给 App。App 负责：

- **实时展示**：心率、趋势、状态。
- **指标计算**：HRV、区间统计等（重计算交由 C++ 计算库）。
- **推理**：基于 CoreML 的端上推理（如状态识别 / 异常检测）。

关键约束：**当前没有实体硬件板**，但**协议等技术选型已基本确定**——需要以**自定义协议栈**的方式在 BLE GATT 之上实现私有协议。为在无硬件条件下完成开发与联调，我们在 **macOS** 上构建一个**模拟设备**扮演 BLE 外设。

## 2. 目标

### 阶段目标（本规划覆盖）
- 明确端到端架构：App 侧 + 模拟设备侧。
- 冻结第一版自定义协议栈与 GATT Profile 定义（可迭代）。
- 定义 App 侧 Clean + Redux 的分层与职责边界。
- 定义 macOS 模拟器的能力（数据生成、场景回放、故障注入）。
- 规划 CoreML 推理与 C++ 计算层的集成方式。
- 给出可并行推进的里程碑路线图。

### 非目标（当前不做）
- 不落地任何实现代码（本阶段仅文档）。
- 不做 C++ 计算库的详细算法设计（仅留 spec 占位，后续细化）。
- 不做真实硬件的固件开发（仅在协议层预留兼容/迁移策略）。
- 不涉及后端 / 云同步 / 账号体系（如需，另立文档）。

## 3. 范围（Scope）

| 领域 | 本阶段产出 |
| --- | --- |
| 整体架构 | 系统上下文、组件、数据流图 |
| 协议 | 自定义协议栈分层 + GATT Profile + 帧格式 + 命令表（v1 草案） |
| App 侧 | Clean 分层 + Redux 数据流 + BLE 接入设计 |
| 模拟设备侧 | macOS Peripheral 设计 + 场景引擎 + 故障注入 |
| 计算 / 推理 | CoreML 管线 + C++ 集成方式（详细算法另立 spec） |
| 路线图 | 双轨里程碑 + 收敛联调节点 |

## 4. 关键设计决策（ADR 摘要）

> 完整决策记录建议后续放入 `docs/adr/`。此处为速览。

1. **中心/外设角色**：iOS 为 Central，macOS 模拟器为 Peripheral，均用 CoreBluetooth。
   - 依据：CoreBluetooth 的 `CBPeripheralManager` 可在 macOS 上发布自定义 GATT 服务，最贴近真实设备行为，且开发闭环全在 Apple 生态内。
2. **协议编解码作为共享 Swift Package**（`HRSenseProtocol`）。
   - 依据：App 与模拟器必须使用完全一致的编解码逻辑，抽成 Package 可单元测试、防止两端协议漂移。
3. **不复用标准 Heart Rate Service（0x180D），改用 128-bit 自定义 UUID + 私有协议**。
   - 依据：需求明确为"自定义协议栈"，需承载私有命令 / 版本协商 / 分片等标准 Profile 无法表达的能力。
4. **协议分层**（GATT 传输 / 分帧可靠传输 / 会话命令 / 应用数据），逐层解耦。
5. **副作用集中在 Redux Middleware**：BLE、计算、推理都是副作用，统一由 Effects/Middleware 编排，Reducer 保持纯函数。
6. **重计算下沉到 C++**：通过 C ABI / Objective-C++ 或 Swift-C++ 互操作桥接（方式在 spec 中定）。
7. **面向真实硬件迁移**：协议内建 `version` 与能力协商，把"模拟器 vs 真机"的差异约束在协议层，App 上层无感。

## 5. 术语表（Glossary）

| 术语 | 含义 |
| --- | --- |
| **Central** | BLE 中心设备，主动扫描/连接。本项目指 iOS App。 |
| **Peripheral** | BLE 外设，广播并提供 GATT 服务。本项目指硬件 / macOS 模拟器。 |
| **GATT** | Generic Attribute Profile，BLE 上基于 Service/Characteristic 的属性协议。 |
| **Service / Characteristic** | GATT 中的服务与特征值；特征值支持 read/write/notify 等。 |
| **MTU** | 单次 ATT 数据传输的最大字节数，决定是否需要分片。 |
| **Notify / Indicate** | 外设主动向中心推送特征值更新（Indicate 带确认）。 |
| **自定义协议栈** | 在 GATT 之上自建的分帧 / 可靠传输 / 命令 / 数据分层协议。 |
| **帧 (Frame)** | 协议栈中一次完整的应用层消息，可能被拆成多个 GATT 分片。 |
| **RR 间期** | 相邻心跳间隔（ms），HRV 计算的基础输入。 |
| **HRV** | 心率变异性，基于 RR 间期序列计算的一组指标。 |
| **Effect / Middleware** | Redux 中处理副作用（异步 / IO）的机制。 |

## 6. 读者与用法

- 新成员：从本页 → `02-architecture` → `03-ble-gatt-protocol` 阅读。
- 实现协议：以 `03-ble-gatt-protocol` 为契约，先做 `HRSenseProtocol` Package。
- 推进开发：按 `01-roadmap` 的双轨里程碑执行。
