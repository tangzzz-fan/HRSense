# 01 · HRSenseProtocol — 共享协议栈

> **路径**: `Sources/HRSenseProtocol/`  
> **依赖**: 无（纯 Swift，零平台耦合）  
> **被依赖**: `HRSenseData`, `HRSenseFeature`, `HRSenseSimulatorKit`

## 1. 模块定位

`HRSenseProtocol` 是整个项目最重要的对称点——iOS App 和 macOS 模拟器共享同一份代码，一端编码、另一端解码，杜绝协议漂移。

协议栈分层（L0–L4）：

| 层 | 职责 | 对应实现 |
|---|---|---|
| L0 | BLE GATT 物理层 | CoreBluetooth（不在本模块） |
| L1 | GATT Service/Characteristic | UUID 定义（不在本模块） |
| L2 | 帧编码 / 分片重组 / CRC 校验 | `FrameEncoder`, `FrameAssembler`, `FragmentHeader` |
| L3 | 命令 / 会话控制 | `CommandCodec`, `ACKCodec`, `EventCodec` |
| L4 | 应用数据编码 | `DataCodec`, `WaveformCodec`, `OTACodec` |

## 2. 帧格式

### 2.1 完整帧结构

```
[Ver(1B)] [Type(1B)] [Body(variable)] [CRC16-LE(2B)]
```

- `Ver`: 协议版本，当前仅 `0x01`
- `Type`: 帧类型 — `command(0x01)` / `data(0x02)` / `ack(0x03)` / `event(0x04)`
- `Body`: 由对应 Codec 编码
- `CRC16`: CRC-16/CCITT-FALSE，小端序

### 2.2 分片头（FragmentHeader）

每个 GATT 分片在帧数据前附加 2 字节头：

```
[FragHdr(1B)] [Seq(1B)] [Payload...]
```

`FragmentHeader` 的位域布局：
- `bit7` = isStart（首片）
- `bit6` = isEnd（末片）
- `bit5..0` = fragIndex（片序号，0–63）

单片帧：`isStart=true, isEnd=true`。多片帧按序发送，接收端通过 `seq` 关联。

## 3. 核心组件

### 3.1 FrameEncoder（编码）

```swift
FrameEncoder.encode(type: .command, body: bodyBytes, seq: seq, mtu: mtu)
// → [Data]  // 按 MTU 切片，每片 ≤ mtu 字节
```

流程：构建完整帧（Ver+Type+Body+CRC16）→ 按 `mtu - 2` 切片 → 每片加 `FragmentHeader + seq`。

### 3.2 FrameAssembler（解码/重组）

有状态类，每个 BLE 连接维护一个实例。核心方法：

```swift
func feed(_ fragment: Data) -> [DecodedFrame]
```

关键机制：
- **去重**：`seenSeqs: Set<UInt8>` 记录已处理的 seq，防止单片帧重复
- **多片缓冲**：`partialFrames: [UInt8: PartialFrame]` 按 seq 分组累积
- **槽位上限**：最多 16 个并发部分帧，超出则淘汰最旧
- **帧大小上限**：64 KiB，防止恶意/畸形帧耗尽内存
- **CRC 校验**：完整帧先验 CRC，不匹配直接丢弃
- **路由分发**：按 `FrameType` 路由到 `CommandCodec.decode` / `DataCodec.decode` / `WaveformDecoder.decode` 等

断连时调用 `reset()` 清空所有状态。

### 3.3 CRC16 / CRC32

- `CRC16`：CRC-16/CCITT-FALSE（多项式 `0x1021`，初始值 `0xFFFF`），用于帧完整性
- `CRC32`：标准 CRC-32（多项式 `0xEDB88320`），用于 OTA 固件镜像校验

## 4. 数据模型

### 4.1 Command（L3 命令）

```swift
struct Command {
    let opCode: CommandOpCode  // hello(0x01), helloAck(0x81), startStream(0x03), stopStream(0x04), ...
    let flags: CommandFlags    // isResponse, needsACK
    let params: [TLVRecord]    // TLV 编码的参数
}
```

便捷工厂方法：
- `Command.hello(capabilities:)` — App→Dev 握手
- `Command.helloAck(version:capabilities:model:firmwareVersion:)` — Dev→App 应答
- `Command.startStream(sampleKinds:)` — 开始数据流
- `Command.stopStream()` — 停止数据流

### 4.2 DeviceSample（L4 心率数据）

```swift
struct DeviceSample {
    let timestamp: UInt32       // 设备相对时间（ms），START_STREAM 起算
    let heartRate: UInt16?
    let rrIntervals: [UInt16]   // RR 间期（ms）
    let battery: UInt8?
    let sensorStatus: UInt8?
    let sampleSeq: UInt32?      // 采样序号，用于丢包检测
}
```

### 4.3 WaveformBlock（L4 波形数据）

```swift
struct WaveformBlock {
    let blockSeq: UInt32        // 块序号
    let sampleCount: UInt16     // 块内采样数
    let sampleRate: UInt16      // 采样率 Hz
    let channelType: UInt8      // ECG(0x01) / PPG(0x02)
    let samples: [Int16]        // 原始采样值
}
```

### 4.4 OTACommand（OTA 命令）

定义了完整的 OTA 命令集：`otaStart`, `otaStartAck`, `otaWindowBegin`, `otaWindowAck`, `otaValidate`, `otaValidateResult`, `otaApply`, `otaAbort`。

## 5. TLV 编码

自定义轻量 TLV（Tag-Length-Value）：

```
[Tag(1B)] [Len(1B)] [Value(Len B)] ...
```

`TLVTag` 枚举定义了已知标签（`timestamp`, `heartRate`, `rrIntervals`, `battery`, `sensorStatus`, `sampleSeq`, `capabilities` 等）。解码时遇到未知 tag 会跳过（前向兼容）。

## 6. 日志门面

`HRSenseLogging` 提供分级日志（debug/info/error），按子系统分类（`.bleRaw`, `.protoCmd`, `.ota`, `.state`, `.perf`），可接入 OSLog 或内存环形缓冲区用于诊断面板导出。

## 7. 顶层便捷 API

```swift
encodeCommand(_:seq:mtu:)  // Command → [Data] 分片
encodeData(_:seq:mtu:)     // DeviceSample → [Data] 分片
encodeACK(_:seq:mtu:)      // ACKPayload → [Data] 分片
encodeEvent(_:seq:mtu:)    // DeviceEvent → [Data] 分片
```

这些函数组合了 L3/L4 Codec + L2 FrameEncoder，是两端编码的统一入口。解码则通过 `FrameAssembler.feed()` 统一处理。
