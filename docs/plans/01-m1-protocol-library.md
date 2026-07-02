# M1 · HRSenseProtocol 库（L2–L4 编解码 + 日志基线）— 实施计划

## 摘要

实现可脱离蓝牙独立工作的 L2–L4 协议编解码库。分片/重组（FrameAssembler）、CRC-16/CCITT-FALSE、命令/数据/ACK/事件/OTA/波形编解码。App 与模拟器共享同一份实现。

**硬依赖**：M0（基础设施 + 契约冻结）。

---

## 实施顺序（自底向上）

### 阶段 1：基础组件（无内部依赖）

| 文件 | 职责 |
|---|---|
| `Sources/HRSenseProtocol/CRC16.swift` | CRC-16/CCITT-FALSE，黄金值 `CRC16("123456789")==0x29B1` |
| `Sources/HRSenseProtocol/Framing/FragmentHeader.swift` | 分片头 bitfield（START/END/FRAG_IDX） |
| `Sources/HRSenseProtocol/Framing/FrameType.swift` | 帧类型枚举（command=0x01/data=0x02/ack=0x03/event=0x04） |
| `Sources/HRSenseProtocol/Model/Capabilities.swift` | 能力位图，12 位定义 |
| `Sources/HRSenseProtocol/Model/ProtocolVersion.swift` | 协议版本常量 |
| `Sources/HRSenseProtocol/TLV/TLVTag.swift` | TLV 标签常量（0x01–0x15） |

### 阶段 2：TLV 编解码

| 文件 | 职责 |
|---|---|
| `Sources/HRSenseProtocol/TLV/TLVEncoder.swift` | `[TLVRecord]` → 确定性字节序列（标签升序） |
| `Sources/HRSenseProtocol/TLV/TLVDecoder.swift` | 字节 → `[TLVRecord]`（未知标签保留，截断抛出） |

### 阶段 3：模型类型

| 文件 | 职责 |
|---|---|
| `Sources/HRSenseProtocol/Model/Command.swift` | L3 命令模型 + 工厂方法 |
| `Sources/HRSenseProtocol/Model/DeviceSample.swift` | L4 数据样本（DataKind + 类型字段） |
| `Sources/HRSenseProtocol/Model/ACKPayload.swift` | ACK 帧体（seq + opcode + status） |
| `Sources/HRSenseProtocol/Model/DeviceEvent.swift` | 设备事件模型 |
| `Sources/HRSenseProtocol/Model/DecodedFrame.swift` | 枚举：`.command`/`.data`/`.ack`/`.event` |
| `Sources/HRSenseProtocol/Model/OTACommand.swift` | OTA 命令/响应模型 |
| `Sources/HRSenseProtocol/Model/WaveformBlock.swift` | 波形块模型（DataKind=0x02） |

### 阶段 4：L2 分帧

| 文件 | 职责 |
|---|---|
| `Sources/HRSenseProtocol/Framing/FrameEncoder.swift` | 帧 → 分片序列（按 MTU 分割，CRC） |
| `Sources/HRSenseProtocol/Framing/FrameAssembler.swift` | 分片 → 帧重组（去重、CRC 校验、seq 跟踪） |

### 阶段 5：L3/L4 编解码器

| 文件 | 职责 |
|---|---|
| `Sources/HRSenseProtocol/Codec/CommandCodec.swift` | 命令帧编码/解码 |
| `Sources/HRSenseProtocol/Codec/DataCodec.swift` | 数据帧（TLV 映射）编码/解码 |
| `Sources/HRSenseProtocol/Codec/ACKCodec.swift` | ACK 帧编码/解码 |
| `Sources/HRSenseProtocol/Codec/EventCodec.swift` | 事件帧编码/解码 |
| `Sources/HRSenseProtocol/Codec/OTACodec.swift` | OTA 命令编解码 |
| `Sources/HRSenseProtocol/Codec/WaveformCodec.swift` | 波形块编解码 |

### 阶段 6：公共 API 门面 + 日志

| 文件 | 职责 |
|---|---|
| `Sources/HRSenseProtocol/HRSenseProtocol.swift` | 顶层 API 重新导出 + 便捷入口 |
| `Sources/HRSenseProtocol/Logging/` | `HRSenseLogCategory`、`HRSenseLogLevel`、`HRSenseLogger` |

---

## 关键测试清单

| 测试文件 | 覆盖内容 |
|---|---|
| `CRC16Tests.swift` | 黄金值 0x29B1、已知向量、空数据 |
| `FragmentHeaderTests.swift` | bitfield 编解码、单分片检测、边界 |
| `TLVTests.swift` | 往返、多标签、空记录、确定性排序、截断 |
| `FrameAssemblerTests.swift` | **最关键**：单/多分片、乱序、CRC 错误、重复 seq、孤儿分片、交织多帧 |
| `FrameEncoderTests.swift` | 单/多分片输出、CRC、MTU 边界 |
| `CommandCodecTests.swift` | HELLO/HELLO_ACK/START_STREAM 等所有操作码往返 |
| `DataCodecTests.swift` | DeviceSample 所有字段组合往返 |
| `IntegrationTests.swift` | 端到端 Command→encode→分片→feed→DecodedFrame |
| `PropertyTests.swift` | `decode(encode(x))==x` 随机属性 |

---

## 覆盖目标：核心编解码 ≥80% 行覆盖

## 预估文件数：~22 个源文件 + ~15 个测试文件
