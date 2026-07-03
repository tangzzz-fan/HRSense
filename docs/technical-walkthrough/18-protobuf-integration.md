# Protobuf 跨端集成方案

> 本文档说明如何在 HRSense 项目中引入 Protocol Buffers，实现 iOS / Android / 固件 / 算法四端共享数据协议。包含定义规范、代码生成、版本管理、异常处理与迁移策略。

---

## 1. 为什么引入 Protobuf

### 1.1 现状：自定义 TLV

当前 L4 应用数据层使用自定义 TLV（Tag-Length-Value）编码：

```
[DataKind(1B)] [Tag(1B) Len(1B) Value(Len)] ...
```

**优点**：字节紧凑、无依赖、MCU 友好
**缺点**：
- 字段增删需手动维护 Tag 字典，容易冲突
- iOS 和 Android 需各自实现解析器，容易协议漂移
- 无自动代码生成，新增字段需改 3 处（Swift / Kotlin / C）

### 1.2 Protobuf 带来的价值

| 特性 | TLV | Protobuf |
|------|-----|----------|
| 向前/向后兼容 | 手动（未知 Tag 跳过） | 自动（unknown fields 保留） |
| 代码生成 | 无 | `protoc` → Swift/Kotlin/C |
| Schema 即文档 | Tag 字典表 | `.proto` 文件 |
| 类型安全 | 手动校验 | 编译期检查 |
| 工具生态 | 无 | `buf lint`, `buf breaking`, gRPC |
| 跨端一致性 | 依赖人工对齐 | Schema 强制一致 |

### 1.3 与现有协议栈的关系

```
┌─────────────────────────────────────────────┐
│ L4 应用数据层                                 │
│  v1: 自定义 TLV（当前）                       │
│  v2: Protobuf 序列化（可选，共存）            │  ← 只换 L4 载荷编码
├─────────────────────────────────────────────┤
│ L3 会话/命令层（保持不变）                     │
├─────────────────────────────────────────────┤
│ L2 分帧/可靠传输（保持不变）                   │  ← 分片/seq/CRC 不受影响
├─────────────────────────────────────────────┤
│ L1 GATT 传输层（保持不变）                     │
└─────────────────────────────────────────────┘
```

**核心原则**：Protobuf 只替换 L4 的载荷编码，L1-L3 完全不变。

---

## 2. Schema 定义规范

### 2.1 目录结构

```
proto/
├── hrsense/
│   ├── v1/
│   │   ├── device_sample.proto      # 心率/RR 样本
│   │   ├── waveform.proto           # 波形数据块
│   │   ├── command.proto            # 命令/响应
│   │   ├── device_info.proto        # 设备信息
│   │   └── sleep.proto              # 睡眠分期数据
│   └── v2/                          # 未来大版本
├── buf.yaml                         # Buf 配置
├── buf.gen.yaml                     # 代码生成配置
└── README.md                        # Schema 使用说明
```

### 2.2 示例 Schema：DeviceSample

```protobuf
// proto/hrsense/v1/device_sample.proto
syntax = "proto3";

package hrsense.v1;

option swift_prefix = "HRS";  // 避免 Swift 命名冲突

// 心率/RR 样本 — 设备 → App 的核心数据
message DeviceSample {
    // 相对 START_STREAM 的毫秒偏移 (uint32 回绕 ≈ 49.7 天)
    uint32 timestamp_ms = 1;

    // 心率 (bpm)，0 表示无效
    uint32 heart_rate = 2;

    // RR 间期数组 (毫秒)
    repeated uint32 rr_intervals_ms = 3;

    // 电池电量 (0-100%)，255 表示未知
    uint32 battery_percent = 4;

    // 传感器状态位图
    SensorStatus sensor_status = 5;

    // 样本序号 (用于丢包检测)
    uint32 sample_seq = 6;
}

// 传感器状态
message SensorStatus {
    bool contact_detected = 1;       // 佩戴/接触状态
    uint32 signal_quality = 2;       // 信号质量 (0-255)
    bool motion_detected = 3;        // 体动检测
}
```

### 2.3 Schema 设计规则

| 规则 | 说明 | 理由 |
|------|------|------|
| **字段号 1-15 用 1 字节编码** | 高频字段用小字段号 | 节省 BLE 带宽 |
| **repeated 而非 bytes** | `repeated uint32 rr_intervals_ms` 而非 `bytes rr_raw` | 跨端类型安全 |
| **枚举而非 uint** | 状态类字段用 enum | 语义清晰 + 编译期约束 |
| **reserved 保留已删字段号** | `reserved 7, 8;` | 防止字段号复用导致兼容性问题 |
| **oneof 表达互斥** | 命令载荷互斥时用 oneof | 节省空间 + 语义明确 |
| **不使用 map** | MCU 端 nanopb 不支持 | 嵌入式兼容性 |

### 2.4 示例 Schema：WaveformBlock

```protobuf
// proto/hrsense/v1/waveform.proto
syntax = "proto3";

package hrsense.v1;

message WaveformBlock {
    WaveformType waveform_type = 1;   // ECG / PPG
    uint32 sample_rate_hz = 2;        // 采样率
    uint32 block_seq = 3;             // 块序号 (丢块检测)
    uint32 start_timestamp_ms = 4;    // 块起始时间戳
    uint32 sample_bits = 5;           // 采样精度 (12/16)
    repeated sint32 samples = 6;      // 有符号采样值 (sint32 负数更紧凑)
}

enum WaveformType {
    WAVEFORM_TYPE_UNSPECIFIED = 0;
    WAVEFORM_TYPE_ECG = 1;
    WAVEFORM_TYPE_PPG = 2;
}
```

### 2.5 示例 Schema：Command

```protobuf
// proto/hrsense/v1/command.proto
syntax = "proto3";

package hrsense.v1;

// 统一命令消息 — 用 oneof 表达互斥载荷
message Command {
    uint32 request_id = 1;

    oneof payload {
        HelloRequest hello = 10;
        StartStreamRequest start_stream = 11;
        StopStreamRequest stop_stream = 12;
        SetConfigRequest set_config = 13;
        GetInfoRequest get_info = 14;
    }
}

message HelloRequest {
    repeated uint32 supported_versions = 1;
    uint32 capabilities = 2;  // 能力位图
}

message StartStreamRequest {
    uint32 sample_rate_hz = 1;
    repeated DataType data_types = 2;
}

enum DataType {
    DATA_TYPE_UNSPECIFIED = 0;
    DATA_TYPE_HEART_RATE = 1;
    DATA_TYPE_WAVEFORM = 2;
    DATA_TYPE_BATTERY = 3;
}
```

---

## 3. 代码生成与集成

### 3.1 工具链选择

| 端 | 工具 | 生成命令 |
|----|------|---------|
| **iOS** | `swift-protobuf` | `protoc --swift_out=. *.proto` |
| **Android** | `protoc` + `kotlin` | `protoc --kotlin_out=. *.proto` |
| **固件 (MCU)** | `nanopb` | `nanopb_generator.py *.proto` |
| **Python (算法)** | `grpcio-tools` | `python -m grpc_tools.protoc --python_out=. *.proto` |

### 3.2 iOS 集成步骤

**Step 1: 添加依赖**

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.27.0"),
]

targets: [
    .target(
        name: "HRSenseProtocol",
        dependencies: [
            .product(name: "SwiftProtobuf", package: "swift-protobuf"),
        ]
    ),
]
```

**Step 2: 生成 Swift 代码**

```bash
# tools/generate_proto.sh
#!/bin/bash
protoc \
    --swift_out=Sources/HRSenseProtocol/Generated \
    --swift_opt=Visibility=Public \
    proto/hrsense/v1/*.proto
```

**Step 3: 替换 L4 编解码**

```swift
// HRSenseProtocol/Codec/ProtobufDataCodec.swift
import SwiftProtobuf

public struct ProtobufDataCodec: DataCodec {
    public func encode(_ sample: DeviceSample) throws -> Data {
        var proto = HRS_V1_DeviceSample()
        proto.timestampMs = UInt32(sample.timestamp)
        proto.heartRate = UInt32(sample.heartRate ?? 0)
        proto.rrIntervalsMs = sample.rrIntervals.map { UInt32($0) }
        proto.sampleSeq = sample.sampleSeq
        return try proto.serializedData()
    }

    public func decode(_ data: Data) throws -> DeviceSample {
        let proto = try HRS_V1_DeviceSample(serializedData: data)
        return DeviceSample(
            timestamp: proto.timestampMs,
            heartRate: proto.heartRate == 0 ? nil : UInt8(proto.heartRate),
            rrIntervals: proto.rrIntervalsMs.map { UInt16($0) },
            sampleSeq: proto.sampleSeq
        )
    }
}
```

### 3.3 固件端（nanopb）

```c
// nanopb 生成的 C 代码
typedef struct {
    uint32_t timestamp_ms;
    uint32_t heart_rate;
    size_t rr_intervals_ms_count;
    uint32_t rr_intervals_ms[16];  // 固定数组（nanopb 不支持动态）
    uint32_t battery_percent;
    uint32_t sample_seq;
} hrsense_v1_DeviceSample;

// 编码
uint8_t buffer[128];
pb_ostream_t stream = pb_ostream_from_buffer(buffer, sizeof(buffer));
pb_encode(&stream, hrsense_v1_DeviceSample_fields, &sample);
```

**MCU 约束**：
- `nanopb` 要求 `repeated` 字段指定最大数量（`.options` 文件）
- 生成代码体积极小（< 10KB）
- 无动态内存分配

### 3.4 能力协商：TLV 与 Protobuf 共存

```
App → Dev: HELLO { capabilities: ... | PROTOBUF_PAYLOAD (bit 12) }
Dev → App: HELLO_ACK { capabilities: ... | PROTOBUF_PAYLOAD (bit 12) }

if (双方都声明 PROTOBUF_PAYLOAD):
    L4 载荷使用 Protobuf 编码
else:
    L4 载荷使用 TLV 编码（v1 默认）
```

**Frame Type 扩展**：
```
Type=0x05: Protobuf 数据帧（与 Type=0x02 TLV 数据帧并存）
Type=0x06: Protobuf 命令帧（与 Type=0x01 TLV 命令帧并存）
```

---

## 4. 版本管理与维护

### 4.1 兼容性规则（Protobuf 黄金法则）

| 操作 | 兼容性 | 说明 |
|------|--------|------|
| 新增字段（新字段号） | ✅ 兼容 | 旧代码忽略 unknown fields |
| 删除字段 | ⚠️ 需 reserved | 必须 `reserved 7;` 防止字段号复用 |
| 修改字段号 | ❌ 破坏兼容 | 等同于删除 + 新增 |
| 修改字段类型 | ❌ 破坏兼容 | 除 uint32 ↔ int32 等少数安全转换 |
| 修改字段名 | ✅ 兼容 | 字段号不变即可 |
| 修改包名 | ❌ 破坏兼容 | 影响生成代码命名空间 |

### 4.2 版本演进策略

```
proto/hrsense/v1/  ← 当前版本（向后兼容修改）
proto/hrsense/v2/  ← 未来大版本（不兼容变更，如重构字段号）
```

**CI 检查**（使用 Buf）：
```yaml
# buf.yaml
version: v2
modules:
  - path: proto
lint:
  use:
    - STANDARD           # 命名规范
    - COMMENTS           # 字段必须有注释
breaking:
  use:
    - FILE               # 不允许破坏性变更
```

```bash
# CI 脚本
buf lint proto/
buf breaking proto/ --against .git#branch=main
```

### 4.3 Schema 变更流程

```
1. 修改 .proto 文件
2. 运行 buf lint（格式检查）
3. 运行 buf breaking（兼容性检查）
4. Code Review（至少 1 个 FW + 1 个 App 工程师）
5. 合并后重新生成所有端代码
6. 更新 golden bytes 测试
```

---

## 5. 异常处理

### 5.1 序列化/反序列化异常

```swift
public struct ProtobufDataCodec: DataCodec {
    public func decode(_ data: Data) throws -> DeviceSample {
        do {
            let proto = try HRS_V1_DeviceSample(serializedData: data)
            return mapToDomain(proto)
        } catch let error as SwiftProtobuf.BinaryDecodingError {
            switch error {
            case .truncated:
                throw ProtocolError.protobufTruncated  // 数据不完整（BLE 丢包）
            case .invalidFieldNumber:
                throw ProtocolError.protobufInvalidField
            case .malformedVarint:
                throw ProtocolError.protobufMalformedVarint
            default:
                throw ProtocolError.decodeError
            }
        } catch {
            throw ProtocolError.decodeError
        }
    }
}
```

### 5.2 字段校验

```swift
private func mapToDomain(_ proto: HRS_V1_DeviceSample) throws -> DeviceSample {
    // 校验必填字段的业务有效性
    guard proto.heartRate <= 255 else {
        throw ProtocolError.invalidHeartRate(value: proto.heartRate)
    }
    guard proto.rrIntervalsMs.allSatisfy({ $0 >= 200 && $0 <= 2000 }) else {
        throw ProtocolError.invalidRRInterval  // 生理上不可能的 RR 值
    }

    return DeviceSample(
        timestamp: proto.timestampMs,
        heartRate: proto.heartRate == 0 ? nil : UInt8(proto.heartRate),
        rrIntervals: proto.rrIntervalsMs.map { UInt16($0) },
        sampleSeq: proto.sampleSeq
    )
}
```

### 5.3 大小限制

```swift
// BLE 帧最大载荷受 MTU 限制（~185 bytes）
// Protobuf 序列化后可能比 TLV 更大（varint 编码 + 字段号开销）
// 需要检查序列化后大小是否超过帧容量

let serialized = try proto.serializedData()
guard serialized.count <= maxPayloadSize else {
    // 拆分为多个帧或使用 bytes 原始编码
    throw ProtocolError.payloadTooLarge(size: serialized.count)
}
```

### 5.4 降级策略

```swift
// 编解码器选择 — 运行时根据协商结果切换
public enum DataCodecSelector {
    case tlv       // v1 默认
    case protobuf  // v2 可选

    public static func select(capabilities: UInt32) -> DataCodecSelector {
        let supportsProtobuf = capabilities & (1 << 12) != 0
        return supportsProtobuf ? .protobuf : .tlv
    }
}
```

---

## 6. 与现有 TLV 的迁移路径

### Phase 1: Schema 定义 + 代码生成（无运行时变化）

- 创建 `proto/` 目录和 `.proto` 文件
- 配置 CI 代码生成
- 生成 Swift / Kotlin / C 代码但不使用
- 添加 Protobuf 编解码的单元测试

### Phase 2: 双模式编解码（运行时共存）

- 实现 `ProtobufDataCodec` 和 `TLVDataCodec`
- 通过 `HELLO` 能力位协商选择
- 模拟器默认使用 TLV，真机可选 Protobuf

### Phase 3: 全面切换（可选）

- 如果 Protobuf 在实际使用中证明更优
- 废弃 TLV 编解码器
- 移除 `PROTOBUF_PAYLOAD` 能力位（默认使用 Protobuf）

---

## 7. 性能考量

| 指标 | TLV (v1) | Protobuf | 差异 |
|------|---------|----------|------|
| 编码速度 | 极快（手动 memcpy） | 快（生成代码优化） | TLV 快 ~2x |
| 解码速度 | 极快 | 快 | TLV 快 ~2x |
| 代码体积 | 0 依赖 | ~200KB (swift-protobuf) | Protobuf 有运行时开销 |
| 单帧大小 | ~12 bytes (HR+2RR) | ~15-20 bytes | Protobuf 大 ~30-60% |
| 波形块 | 手动打包 | repeated sint32 | 相近 |
| MCU 端 | 手写解析器 | nanopb (~10KB) | nanopb 有少量开销 |

**结论**：
- 心率/RR 样本（小数据）：TLV 更紧凑，保持 TLV
- 复杂命令/设备信息（多字段）：Protobuf 更安全，优先 Protobuf
- 波形块（大数组）：两者相近，按需选择
