# 20 · Protobuf 混合协议落地实施方案

## 0. 目标

本方案用于把仓库中已有的 Protobuf 讨论，从“文档层设计”推进到“可运行、可验证、可灰度”的实现阶段。

当前项目已经有两类事实：

1. **真实实现事实**
   - `HRSenseProtocol` 已经完整落地 TLV + 自定义分帧协议
   - App 与 Simulator 共享同一份 `HRSenseProtocol`
   - 当前握手、数据、波形、OTA 都建立在 TLV / 自定义紧凑编码之上

2. **文档规划事实**
   - `proto/` 目录已预留
   - `protobuf-integration-and-schema-governance` 已定义治理原则
   - 文档已经明确 Protobuf 只能在协议负载边界引入，不得替换 GATT / CRC / 分帧

本次目标不是“大爆炸式替换 TLV”，而是构建 **TLV + Protobuf 共存** 的最小闭环。

---

## 1. 当前设计中的问题

### 1.1 只有讨论，没有可运行实现

当前仓库里 Protobuf 仍停留在纸面：

- 没有 `.proto` schema
- 没有 `SwiftProtobuf` 依赖
- 没有代码生成脚本
- 没有运行时编解码器
- 没有双端灰度协商与回退验证

这意味着：

- 文档说“可选 Protobuf”
- 但工程并不具备真正开启它的能力

### 1.2 文档口径存在边界歧义

现有文档一方面写“Protobuf 只用于 L4 应用负载”，另一方面又把 `Hello / HelloAck / Info` 列为首批适合切换的消息。

如果不把边界说清楚，后续很容易出现两类坏实现：

1. 直接让 Protobuf 侵入 GATT / L2 分帧
2. 一口气把所有 TLV 都替换掉，扩散风险

### 1.3 缺少灰度迁移路径

当前 TLV 已经是主链路事实。任何 Protobuf 接入都必须满足：

- 双端都支持时才启用
- 单端不支持时自动回退 TLV
- 现有波形和 OTA 高吞吐路径不受影响

如果没有灰度协商，接入会直接破坏当前 BLE 联调闭环。

### 1.4 缺少“首批低风险消息”的明确范围

不是所有消息都适合同步切到 Protobuf。

当前项目里：

- 高吞吐波形块不适合首批切换
- OTA 数据块不适合首批切换
- 最适合首批落地的是 **握手元数据与设备信息**

如果不先限定范围，项目会在第一步就承担不必要的复杂度。

---

## 2. 设计原则

### 2.1 坚持混合模式

本次采用：

- **传输层保持自定义**
- **结构化协议负载可选 Protobuf**
- **高吞吐二进制块继续保留紧凑自定义编码**

### 2.2 首批只做低风险灰度

首批落地范围限定为：

- `HELLO_ACK`
- `INFO`
- 对应共享结构：`DeviceInfo`

其中：

- `HELLO` 请求仍保持 TLV
- 原因是 capability 协商本身依赖首个握手请求，不能形成“是否使用 Protobuf”的鸡生蛋问题

### 2.3 保持域模型不变

Protobuf 只改变字节载荷表达，不改变上层域模型。

也就是说：

- `DecodedFrame` 仍然产出 `Command`
- `DeviceRepositoryImpl` 仍然消费 `Command`
- App / Simulator 上层逻辑不需要知道载荷来自 TLV 还是 Protobuf

### 2.4 能力位协商优先于强制切换

通过新增 `PROTOBUF_PAYLOAD` capability 位实现灰度协商：

- App 宣告支持
- Simulator / Device 宣告支持
- 双方都支持时，设备端允许把结构化响应切换为 Protobuf
- 否则继续走 TLV

---

## 3. 首批落地范围

### 3.1 本次实施

- 新建 `proto/` schema 与 README
- 接入 `SwiftProtobuf`
- 增加生成脚本
- 增加 `HRSenseProtocol` 内部 Protobuf 载荷编解码器
- 增加 `FrameType.protobufCommand`
- 为 `HELLO_ACK` / `INFO` 提供 Protobuf 响应分支
- App / Simulator 双端共享同一套解码逻辑
- 保持 TLV 为默认主路径与回退路径

### 3.2 本次明确不做

- 不切波形块
- 不切 OTA 数据块
- 不切 `DeviceSample` 高频实时样本主路径
- 不做 Android / 固件侧真实接入
- 不引入 `buf` 作为硬依赖，仅预留工具链位置

---

## 4. 模块化实施计划

### 模块 1：协议文档与治理口径收敛

- 预计时间：0.5h
- 目标：
  - 修正 L4-only 与 Hello/HelloAck 首批候选之间的口径歧义
  - 明确“首批只切结构化响应负载”
  - 指定 capability 位与 frame type
- 产出：
  - `docs/03-ble-gatt-protocol.md`
  - `docs/gap-closure/protobuf-integration-and-schema-governance.md`
  - 本文档

### 模块 2：Schema 与工具链接入

- 预计时间：1h
- 目标：
  - 建立 `proto/` 目录结构
  - 编写 `.proto`
  - 增加生成脚本
  - 接入 `SwiftProtobuf`
- 产出：
  - `proto/README.md`
  - `proto/hrsense/common/v1/device_info.proto`
  - `proto/hrsense/session/v1/hello.proto`
  - `tools/generate_proto.sh`
  - `Package.swift`

### 模块 3：协议层编解码实现

- 预计时间：1h - 1.5h
- 目标：
  - 在 `HRSenseProtocol` 中增加 Protobuf 载荷映射
  - 增加 `FrameType.protobufCommand`
  - 让解码后仍回到既有 `Command` 域模型
- 产出：
  - `Sources/HRSenseProtocol/Generated/*`
  - `Sources/HRSenseProtocol/Codec/ProtobufCommandCodec.swift`
  - `Sources/HRSenseProtocol/Framing/FrameType.swift`
  - `Sources/HRSenseProtocol/Framing/FrameAssembler.swift`
  - `Sources/HRSenseProtocol/HRSenseProtocol.swift`

### 模块 4：双端灰度接线

- 预计时间：1h
- 目标：
  - App 宣告 `PROTOBUF_PAYLOAD`
  - Simulator 在双方都支持时返回 Protobuf `HELLO_ACK`
  - 否则自动回退 TLV
- 产出：
  - `DeviceRepositoryImpl.swift`
  - `SimulatorConfig.swift`
  - `CommandProcessor.swift`

### 模块 5：测试与验证

- 预计时间：1h
- 目标：
  - 验证 schema 生成与 Swift 编译
  - 验证 Protobuf/TLV 双分支都能解码回同一域模型
  - 验证 capability 协商与回退逻辑
- 产出：
  - `HRSenseProtocolTests`
  - `HRSenseSimulatorKitTests`
  - `swift build`
  - `swift test`
  - workspace 构建验证

---

## 5. 旧设计问题与本方案收益

### 旧设计问题

- 文档写了 Protobuf，但仓库完全不可运行
- 没有 schema 资产与生成流程
- 没有灰度协商能力
- 上层逻辑无法在不破坏主链路的前提下试点

### 本方案收益

- 把 Protobuf 从“讨论能力”变成“工程能力”
- 保持 TLV 主路径稳定
- 用最小真实路径验证 schema、生成器、运行时和回退机制
- 为后续扩展到 `INFO`、事件消息、结构化状态消息建立统一模式

---

## 6. 验收标准

本次实施完成后，至少满足：

1. `proto/` 下存在真实 schema 与 README
2. `Package.swift` 已接入 `SwiftProtobuf`
3. `tools/generate_proto.sh` 可生成 Swift 代码
4. `HRSenseProtocol` 可解码 `protobufCommand` 帧
5. Simulator 在协商成功时可发送 Protobuf `HELLO_ACK`
6. App 可无改动上层业务逻辑地消费该响应
7. 不支持或未协商成功时自动回退 TLV
8. `swift build` / `swift test` / 两个 workspace build 通过

---

## 7. 当前实施决策

本次选择的最优路径不是“全量替换 TLV”，而是：

- **保留 TLV 主链**
- **先打通 HelloAck / DeviceInfo 的 Protobuf 灰度分支**
- **保持上层域模型与业务逻辑不变**
- **用 capability + frame type 进行协商与分流**

这是当前项目在架构正确性、迁移风险和实施成本之间的最优平衡。
