# 名词解释与 BLE 自定义协议分析

> 本文档包含两部分：项目中涉及的专业名词解释表，以及为什么本项目必须自定义 BLE GATT 协议的分析。

---

## 第一部分：名词解释表

### 生理与医学指标

| 缩写 | 全称 | 中文 | 说明 |
|------|------|------|------|
| **HR** | Heart Rate | 心率 | 每分钟心跳次数（BPM），最基础的生命体征 |
| **RR** | RR Interval | RR 间期 | 相邻两次心跳 R 波之间的时间间隔（ms），是 HRV 分析的原始输入 |
| **HRV** | Heart Rate Variability | 心率变异性 | RR 间期的变化程度，反映自主神经系统（交感/副交感）的调节能力 |
| **SDNN** | Standard Deviation of NN | NN 标准差 | 所有正常心跳间期的标准差，HRV 时域指标，反映整体变异性 |
| **RMSSD** | Root Mean Square of Successive Differences | 连续差均方根 | 相邻 RR 间期差值的均方根，反映副交感神经（迷走神经）活性 |
| **pNN50** | Percentage of NN50 | NN50 百分比 | 相邻 RR 间期差值 >50ms 的占比，也是副交感活性指标 |
| **LF** | Low Frequency | 低频功率 | 0.04–0.15 Hz 频段的功率谱，混合交感/副交感影响 |
| **HF** | High Frequency | 高频功率 | 0.15–0.4 Hz 频段的功率谱，主要反映副交感活性 |
| **LF/HF** | LF/HF Ratio | 低高频比 | 交感-副交感平衡指标，比值升高提示交感（压力）占优 |
| **DFA α1** | Detrended Fluctuation Analysis alpha1 | 去趋势波动分析 | 短期分形相关指数，反映心跳的复杂自相似结构 |
| **Sample Entropy** | — | 样本熵 | 时间序列复杂度的非线性度量，值越低表示越规律（可能提示压力/疲劳） |
| **Poincaré SD1/SD2** | — | 庞加莱图指标 | SD1 反映短期变异（副交感），SD2 反映长期变异（整体） |

### 睡眠分期

| 缩写 | 全称 | 中文 | 说明 |
|------|------|------|------|
| **Wake** | — | 清醒 | 睡眠分期中的清醒阶段 |
| **Light** | Light Sleep | 浅睡 | N1+N2 阶段，占总睡眠约 50-60% |
| **Deep** | Deep Sleep / SWS | 深睡 | N3 阶段（慢波睡眠），身体修复 |
| **REM** | Rapid Eye Movement | 快速眼动 | 做梦阶段，记忆巩固 |
| **Hypnogram** | — | 睡眠图 | 时间轴上展示各睡眠阶段的图表 |

### BLE 与通信

| 缩写 | 全称 | 中文 | 说明 |
|------|------|------|------|
| **BLE** | Bluetooth Low Energy | 低功耗蓝牙 | 蓝牙 4.0+ 的低功耗模式，适合传感器/可穿戴 |
| **GATT** | Generic Attribute Profile | 通用属性配置文件 | BLE 通信的核心协议，定义 Service/Characteristic 的数据交换方式 |
| **GAP** | Generic Access Profile | 通用访问配置文件 | 控制设备发现、连接、广播的协议层 |
| **MTU** | Maximum Transmission Unit | 最大传输单元 | 单次 ATT 操作可携带的最大字节数，iOS 通常协商到 ~185 字节 |
| **ATT** | Attribute Protocol | 属性协议 | GATT 的底层传输协议，定义 Read/Write/Notify 等操作 |
| **CCCD** | Client Characteristic Configuration Descriptor | 客户端特征配置描述符 | UUID `0x2902`，Central 写入此描述符来启用/禁用 Notify 或 Indicate |
| **Notify** | — | 通知 | Peripheral→Central 的无确认推送（best-effort） |
| **Indicate** | — | 指示 | Peripheral→Central 的有确认推送（需要 ATT ACK） |
| **Write With Response** | — | 有响应写入 | Central→Peripheral 写入，ATT 层返回确认 |
| **Write Without Response** | — | 无响应写入 | Central→Peripheral 写入，无 ATT 确认（更高吞吐） |
| **UUID** | Universally Unique Identifier | 通用唯一标识符 | BLE 中用于标识 Service/Characteristic，标准用 16-bit，自定义用 128-bit |
| **OTA/DFU** | Over-The-Air / Device Firmware Update | 空中升级 | 通过 BLE 传输固件镜像并更新设备固件 |

### 数据与信号

| 缩写 | 全称 | 中文 | 说明 |
|------|------|------|------|
| **ECG** | Electrocardiogram | 心电图 | 心脏电信号波形，采样率通常 128-512 Hz |
| **PPG** | Photoplethysmogram | 光电容积脉搏波 | 光学信号波形（绿光/红光），用于光学心率传感器 |
| **TLV** | Tag-Length-Value | 标签-长度-值 | 一种轻量级的数据编码格式，本项目用于自定义协议的数据层 |
| **CRC** | Cyclic Redundancy Check | 循环冗余校验 | 数据完整性校验算法，本项目用 CRC-16/CCITT-FALSE（帧校验）和 CRC-32（OTA 镜像校验） |
| **FFT** | Fast Fourier Transform | 快速傅里叶变换 | 将时域信号转换为频域，用于计算 LF/HF 等频域 HRV 指标 |

### 架构与框架

| 缩写 | 全称 | 中文 | 说明 |
|------|------|------|------|
| **SPM** | Swift Package Manager | Swift 包管理器 | 本项目的依赖管理工具，所有模块以 SPM target 组织 |
| **TCA** | The Composable Architecture | 可组合架构 | 社区流行的 Swift 架构框架，本项目评估后选择了更轻量的自建 Redux |
| **CoreML** | — | Core ML | Apple 端上机器学习框架，用于加载模型并执行推理 |
| **SwiftData** | — | Swift Data | Apple 的 Swift 原生持久化框架（iOS 17+），本项目用于结构化数据存储 |

---

## 第二部分：标准 BLE 心率 vs 自定义 GATT——什么时候必须自定义？

### 1. 标准 BLE Heart Rate Service（0x180D）能做什么

标准 BLE 心率 Profile（Bluetooth SIG 定义）使用固定的 16-bit UUID：

| Characteristic | UUID | 内容 |
|---------------|------|------|
| Heart Rate Measurement | `0x2A37` | HR(8/16-bit) + Sensor Contact + Energy Expended + **RR-Intervals** |
| Body Sensor Location | `0x2A38` | 传感器佩戴位置 |
| Heart Rate Control Point | `0x2A39` | 重置 Energy Expended |

**标准流程非常简单**：

```
1. Central 连接 Peripheral
2. 发现 Heart Rate Service (0x180D)
3. 订阅 Heart Rate Measurement (0x2A37) 的 Notify（写 CCCD）
4. 每秒收到一个 notify，解析固定格式的字节 → HR + RR
5. 断连 → 重连
```

市面上大多数心率带（Polar H10、Wahoo TICKR、Garmin HRM）都遵循这个标准。用 CoreBluetooth 连接它们只需要几十行代码：

```swift
// 标准 BLE 心率——不需要自定义 GATT
let heartRateServiceUUID = CBUUID(string: "180D")
let heartRateMeasurementUUID = CBUUID(string: "2A37")

centralManager.scanForPeripherals(withServices: [heartRateServiceUUID])
// 连接 → 发现服务 → setNotifyValue(true) → 解析标准格式
```

### 2. 标准 Heart Rate Service 的局限

| 能力 | 标准 HR Service | 本项目的需要 | 差距 |
|------|----------------|-------------|------|
| 心率数据 | HR(8/16-bit) + RR + 能耗 | HR + RR + 电量 + 传感器状态 + 采样序号 | 标准格式缺少电量、传感器状态、序号 |
| 多传感器 | 不支持 | ECG + PPG 波形流（128Hz+） | 标准完全不支持高吞吐波形 |
| 命令控制 | 仅重置能耗 | HELLO 握手、START/STOP_STREAM、SET_CONFIG | 标准只有一个 Control Point |
| 版本协商 | 无 | 协议版本 + 能力位图协商 | 标准无此概念 |
| 可靠传输 | 无（纯 best-effort） | 命令需要 ACK + 超时重传 + CRC 校验 | 标准无可靠性保证 |
| 大帧传输 | 无（单 notify ≤ MTU） | 大于 MTU 的数据需要分片重组 | 标准无分片机制 |
| OTA 升级 | 无（另有 OTA Service） | 完整的固件传输 + 窗口 ACK + CRC 校验 | 标准 OTA 是独立 profile |
| 数据完整性 | 无 | CRC-16 帧校验 + 序号丢包检测 | 标准无校验 |
| 双向通信 | 几乎单向（设备→App） | 双向：App→设备命令 + 设备→App 数据/响应 | 标准以单向下行数据为主 |

### 3. 什么时候必须自定义 GATT

#### 必须自定义的场景

| 场景 | 原因 |
|------|------|
| **传输非标准数据类型** | 如 ECG/PPG 波形、加速度、皮肤温度等标准 Profile 未覆盖的传感器 |
| **需要双向命令/响应** | 如远程控制设备配置、启停采集、切换模式——标准 Profile 通常只有少量控制点 |
| **需要版本/能力协商** | 设备与 App 需要动态发现对方支持的功能子集 |
| **需要可靠传输** | 关键命令需要 ACK + 超时重传，标准 Notify 是 fire-and-forget |
| **需要大帧分片** | 传输 >MTU 的数据块（如 OTA 固件、批量历史数据） |
| **需要数据完整性校验** | 帧级 CRC、序号丢包统计 |
| **需要 OTA 固件升级** | 虽然有标准 Nordic DFU Service，但很多厂商仍自定义以匹配私有协议 |
| **多类型数据统一封装** | 心率 + RR + 波形 + 事件 + 命令在同一通道复用 |

#### 不需要自定义的场景（直接用标准 Profile）

| 场景 | 使用的标准 Profile |
|------|-------------------|
| 纯心率监测（HR + RR） | Heart Rate Service `0x180D` |
| 纯血氧监测 | Pulse Oximeter Service `0x1822` |
| 计步器 | Running Speed and Cadence `0x1814` |
| 体温 | Health Thermometer `0x1809` |
| 电池电量 | Battery Service `0x180F` |
| 固件升级（Nordic 芯片） | Nordic DFU Service（虽然不是 SIG 标准，但已是事实标准） |

### 4. HRSense 为什么必须自定义

本项目的核心需求是**心率变异性分析 + 端上 ML 推理 + 睡眠监测**，而非简单的心率显示。逐条分析：

#### 4.1 HRV 分析需要远超标准 Profile 的数据

标准 Heart Rate Measurement 的 RR-Interval 字段：

```
标准格式（0x2A37）：
[Flags(1B)] [HR(1-2B)] [Energy(0-2B)] [RR(0-N × 2B)]
```

- RR 间期以 **1/1024 秒**为单位（不是毫秒）
- 没有 `sampleSeq` 序号——无法检测丢包
- 没有 `timestamp`——无法精确对齐时间窗口
- 没有传感器状态——无法判断信号质量

HRSense 的自定义数据帧：

```
自定义 L4 格式：
[DataKind(1B)] [TLV: timestamp(u32) + heartRate(u16) + rrIntervals(u16[]) 
               + battery(u8) + sensorStatus(u8) + sampleSeq(u32)]
```

**差异**：精确毫秒时间戳、丢包检测序号、传感器质量位、电量——这些字段标准 Profile 都没有。

#### 4.2 ML 推理管线需要命令与响应

标准 Profile 是"设备一直推数据，App 被动接收"。本项目需要：

```
App → 设备: START_STREAM(sampleKinds=[心率, ECG波形])
App → 设备: SET_CONFIG(sampleRate=256Hz)
App → 设备: STOP_STREAM
```

这些**控制命令**在标准 Heart Rate Service 中完全不存在。

#### 4.3 高吞吐波形流（ECG/PPG）

ECG 波形采样率 128-512 Hz，每样本 2 字节（Int16），每秒产生 256-1024 字节——远超 MTU（~185 字节）。

这意味着：
- 必须将多个样本打包成 **WaveformBlock**
- 必须**按 MTU 分片**传输
- 必须有 `blockSeq` 做丢块检测
- 接收端必须**重组分片**

标准 Heart Rate Service 完全没有这些机制。

#### 4.4 OTA 固件升级

OTA 需要：
- 传输完整固件镜像（几十 KB ~ 几 MB）
- 窗口化传输 + ACK 流控
- CRC-32 校验
- 断点续传
- 版本协商

虽然 Nordic 有 DFU Service，但它是芯片厂商特定的。本项目定义了独立的 OTA 命令集（`OTA_START` → `WINDOW_BEGIN` → `WINDOW_ACK` → `VALIDATE` → `APPLY`），嵌入自定义协议栈中统一管理。

#### 4.5 模拟器对称性

项目要求 iOS App 和 macOS 模拟器使用**完全相同的协议代码**（`HRSenseProtocol` 共享包）。标准 Profile 的解析代码是平台无关的，但自定义协议的编解码逻辑需要统一——这通过将 `HRSenseProtocol` 抽成共享 SPM 包实现。

### 5. 对比总结

```
标准 BLE Heart Rate Service (0x180D)
┌──────────────────────────────────────────────┐
│  Peripheral ──notify──► Central              │
│  固定格式: HR + RR + Energy                  │
│  无需握手，连上就推数据                       │
│  无需命令控制                                 │
│  无可靠性保证                                 │
│  无 OTA                                       │
│                                               │
│  适用于：心率带、运动手表等纯心率展示场景      │
└──────────────────────────────────────────────┘

HRSense 自定义协议栈
┌──────────────────────────────────────────────┐
│  双向通信: 命令(上行) + 数据/响应(下行)       │
│  分层协议: L2(帧/CRC) → L3(命令) → L4(TLV)  │
│  HELLO 握手 + 能力协商                        │
│  分片重组 (支持 >MTU 数据)                    │
│  序号丢包检测 + CRC-16 帧校验                 │
│  HR + RR + ECG/PPG 波形 + 电量 + 传感器状态  │
│  OTA 固件升级 (窗口 ACK + CRC-32)             │
│  共享编解码包 (App + 模拟器对称)              │
│                                               │
│  适用于：医疗级 HRV 分析 + ML 推理 + 多传感器  │
└──────────────────────────────────────────────┘
```

### 6. 决策建议

如果你在做一个 BLE 产品：

| 需求 | 建议 |
|------|------|
| 只展示心率 | 用标准 Heart Rate Service |
| 展示心率 + 简单 RR | 用标准 Heart Rate Service（已含 RR） |
| 需要 HRV 分析 + 精确时间戳 | 自定义（标准 RR 精度不足，且无 timestamp） |
| 需要 ECG/PPG 波形 | 必须自定义 |
| 需要 OTA | 可用 Nordic DFU 或自定义 |
| 需要命令控制 | 必须自定义 |
| 需要跨平台（iOS+Android+FW）共享协议 | 自定义 + 共享 schema（TLV 或 Protobuf） |
