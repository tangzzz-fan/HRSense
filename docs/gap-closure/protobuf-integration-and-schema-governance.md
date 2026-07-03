# Protobuf 集成与 Schema 治理说明

## 1. 文档目的

`JD.md` 和 [09-jd-coverage-analysis.md](file:///Users/bigapple/Developments/HRSense/docs/09-jd-coverage-analysis.md) 都提到了 **Protobuf** 这一类跨端协议协作能力。

当前项目已经在协议文档中明确：

- 默认协议仍然是 **自定义 GATT + L2 分帧/可靠传输 + L4 TLV**
- 如果引入 Protobuf，**只能落在 L4 应用负载编码边界**

相关已有口径见：

- [03-ble-gatt-protocol.md](file:///Users/bigapple/Developments/HRSense/docs/03-ble-gatt-protocol.md)
- [08-project-structure.md](file:///Users/bigapple/Developments/HRSense/docs/08-project-structure.md)
- `CLAUDE.md` 中的 `Protobuf Boundary (Optional, L4 Only)`

这份文档的目标是把这些已有结论进一步落地为一套 **当前项目可执行的 Protobuf 集成方案**，重点回答：

1. 当前项目里 **Protobuf 应该放在哪一层**
2. **哪些消息适合用 Protobuf，哪些不建议**
3. **如何设计 `.proto` schema**
4. **如何做版本兼容、维护和升级**
5. **iOS / Android / 固件团队如何共享和治理这一层契约**

---

## 2. 当前项目里 Protobuf 的正确边界

### 2.1 正确落点

在当前项目中，Protobuf 的推荐落点是：

- **只用于 L4 应用数据负载编码**

即：

- **L0** BLE 物理链路：不变
- **L1** GATT Service / Characteristic：不变
- **L2** 分片、重组、seq、CRC、ACK：不变
- **L3** 会话/命令语义、握手、能力协商：原则上不变
- **L4** 业务消息体：可由 TLV 切换为 Protobuf 或与 TLV 共存

### 2.2 明确不应该放的位置

当前项目里 **不建议** 把 Protobuf 放在这些位置：

- 不放到 GATT 层
- 不替代 L2 分帧/重传/CRC
- 不直接进入 UI 层 ViewModel
- 不直接作为持久化数据库结构
- 不直接替代 OTA 二进制镜像块协议

原因很明确：

- **GATT 与 L2 是传输与可靠性边界**
- **Protobuf 是应用消息表达边界**

如果把两者混在一起，会直接破坏当前项目已经冻结的协议分层设计。

---

## 3. 当前项目最推荐的集成方式

### 3.1 推荐方案：混合模式，而不是全量替换

对当前项目最务实的选择不是“一刀切把 TLV 全部替换成 Protobuf”，而是采用 **混合模式**：

#### 保持自定义二进制 / TLV 的部分

- 高吞吐波形块
- OTA 数据块
- L2 分片帧
- ACK / seq / CRC

#### 优先考虑 Protobuf 的部分

- `HELLO` / `HELLO_ACK` 里的能力与元信息
- `INFO` 响应
- 设备状态 / 电量 / 传感器状态
- 结构化事件消息
- 将来跨 iOS / Android / 固件共同维护的业务扩展字段

### 3.2 为什么不建议一上来全量替换

如果当前项目全量切换到 Protobuf，会有几个现实问题：

1. **固件侧成本上升**
   - MCU 需要接入 `nanopb` 或类似轻量实现
   - 内存和代码体积压力会上来

2. **高吞吐路径收益不一定高**
   - 波形块本身更适合紧凑 packed binary
   - Protobuf 在高频原始采样块上的收益不如在结构化消息上明显

3. **当前项目已有 TLV 契约已冻结**
   - 全量替换会引入较大迁移面
   - 风险不必要地扩散到 M1/M3/M5/M6 的稳定路径

因此，**当前项目最佳策略是“结构化控制/状态消息优先 Protobuf，吞吐敏感数据仍保留自定义紧凑编码”**。

---

## 4. 哪些消息最适合优先切 Protobuf

建议按下面优先级排序。

### P0：设备信息与协商元数据

例如：

- `HELLO`
- `HELLO_ACK`
- `INFO`
- `ERROR`

适合原因：

- 字段结构清晰
- 扩展需求强
- 跨端协作多
- 吞吐敏感度低

### P1：结构化状态与事件

例如：

- 电量状态
- 传感器状态
- 设备事件
- 睡眠或算法辅助状态消息

适合原因：

- 事件类型会逐步增多
- TLV 手写 tag 容易散乱
- Protobuf 更适合长期演进

### P2：普通心率样本批量消息

可选，但要谨慎。

如果做：

- 更推荐对“批量样本容器”使用 Protobuf
- 而不是对每个极小样本单独套一层 Protobuf message

### 不建议优先切换：波形与 OTA 原始块

原因：

- 波形和 OTA 对体积、吞吐、解析成本都更敏感
- 当前项目已有高吞吐 spec 与二进制块模型
- 用 Protobuf 只会增加复杂度，不一定提升价值

---

## 5. 推荐的目录与文件组织

### 5.1 仓库目录

当前项目已经预留：

- `proto/`

建议把它组织成：

```text
proto/
├── hrsense/
│   ├── common/
│   │   ├── device_info.proto
│   │   ├── capabilities.proto
│   │   └── error.proto
│   ├── session/
│   │   ├── hello.proto
│   │   ├── info.proto
│   │   └── event.proto
│   ├── data/
│   │   ├── heart_rate.proto
│   │   └── device_status.proto
│   └── README.md
```

### 5.2 包名建议

建议统一使用稳定 package：

```proto
package hrsense.session.v1;
```

或：

```proto
package hrsense.common.v1;
```

不要把版本号写进 message 名本身，例如：

- 不推荐 `HelloV1`
- 更推荐 `package hrsense.session.v1; message Hello`

这样升级时目录和 package 更清晰。

---

## 6. Schema 怎么定

这是 Protobuf 成败的关键。

### 6.1 先定“跨端共享消息”，不要先定“本端内部模型”

定义 `.proto` 时，应该问的是：

- 哪些字段必须由 iOS / Android / 固件共同理解？

而不是：

- iOS 当前 ViewModel 里有哪些属性？

`.proto` 是 **跨端通信契约**，不是 UI DTO。

### 6.2 先定边界，再定字段

建议按下面顺序：

1. 明确消息用途
   - 握手
   - 信息读取
   - 设备事件
   - 样本上传

2. 明确方向
   - App -> Device
   - Device -> App
   - 双向

3. 明确生命周期
   - 连接期一次性消息
   - 周期性状态消息
   - 高频流消息

4. 再定义字段

如果顺序反过来，容易出现字段越加越乱。

### 6.3 字段粒度要稳定

好做法：

- 一个字段表达一个稳定语义
- 同类字段聚合到嵌套 message

例如：

```proto
message DeviceInfo {
  string model = 1;
  string firmware_version = 2;
  uint32 protocol_version = 3;
  uint32 capabilities = 4;
}
```

不要把“临时调试字段”直接长期放进核心 message。

### 6.4 统一字段命名风格

建议：

- `snake_case`

例如：

- `firmware_version`
- `protocol_version`
- `heart_rate_bpm`

这样对固件/C/Android/Swift 侧都更中性。

### 6.5 尽量避免过度嵌套

在嵌入式和调试场景里，过深嵌套会降低可读性和维护性。

建议：

- 一层主 message
- 一层必要嵌套
- 避免三层以上嵌套结构

---

## 7. 字段编号怎么分配

### 7.1 基本规则

一旦字段号发布，就要视为长期契约：

- **字段号不可复用**
- 字段名可以废弃
- 字段号不能随意回收

### 7.2 分段建议

可以为不同性质字段预留区间：

- `1-15`：核心稳定字段
- `16-31`：常规扩展字段
- `32-63`：预留给未来功能

这样有利于长期演进。

### 7.3 删除字段时必须 `reserved`

例如：

```proto
message DeviceInfo {
  reserved 5;
  reserved "legacy_hw_revision";

  string model = 1;
  string firmware_version = 2;
  uint32 protocol_version = 3;
  uint32 capabilities = 4;
}
```

这是 Protobuf 升级治理的硬约束之一。

---

## 8. 推荐的消息设计模式

### 8.1 用 message 表达结构，不用裸 bytes 逃避设计

如果引入了 Protobuf，但 payload 里又大面积回退成：

```proto
bytes raw_payload = 8;
```

那等于并没有真正建立可维护 schema。

只有在这些场景下才推荐 `bytes`：

- 波形原始块
- OTA 原始块
- 未来需要保留紧凑 packed binary 的特殊高吞吐数据

### 8.2 `oneof` 用于互斥事件

例如：

```proto
message DeviceEvent {
  uint64 timestamp_ms = 1;

  oneof kind {
    BatteryLow battery_low = 10;
    SensorDetached sensor_detached = 11;
    OtaStateChanged ota_state_changed = 12;
  }
}
```

这类事件型消息很适合 `oneof`。

### 8.3 枚举要保留未知值容忍

枚举要考虑未来扩展：

```proto
enum SensorStatus {
  SENSOR_STATUS_UNSPECIFIED = 0;
  SENSOR_STATUS_READY = 1;
  SENSOR_STATUS_DETACHED = 2;
}
```

不要从 `1` 开始，也不要没有 `UNSPECIFIED = 0`。

---

## 9. 版本与升级策略

### 9.1 推荐双层版本观

当前项目里建议区分：

1. **协议版本**
   - 仍由现有 `protocolVersion` / `HELLO` 协商承担

2. **Schema 版本**
   - 表示当前 Protobuf message 契约代次

这两者不要混淆。

### 9.2 推荐做法：能力位 + schema 版本并存

如果未来正式接入 Protobuf，建议：

- 在 `capabilities` 中增加 `PROTOBUF_PAYLOAD`
- 在握手里增加 `schema_version`

这样双方可以协商：

- 是否支持 protobuf payload
- 支持哪个 schema 代次

### 9.3 升级策略建议

推荐采用：

- **向后兼容新增字段**
- **旧字段废弃但保留编号**
- **重大不兼容变更才升 package/version 代次**

不要轻易因为字段增减就改成 `v2`。

### 9.4 什么时候应该升 `v2`

只有在这些场景下才建议升级 schema 主版本：

- 字段语义发生根本变化
- 老消息不能通过兼容方式解释
- 编码规则整体调整
- 同一 message 的业务边界重构

---

## 10. iOS / Android / 固件如何共同维护

### 10.1 `.proto` 是仓库级契约，不是某一端私有资产

建议明确治理原则：

- `proto/` 目录属于 **协议契约资产**
- 不归 iOS 单方独占
- 变更必须同步考虑 iOS / Android / 固件

### 10.2 推荐变更流程

当前项目建议使用下面这条流程：

1. 先更新协议文档
   - [03-ble-gatt-protocol.md](file:///Users/bigapple/Developments/HRSense/docs/03-ble-gatt-protocol.md)

2. 再更新 `.proto`

3. 再更新 `HRSenseProtocol`

4. 再更新 iOS / Android / firmware 各自生成与适配代码

5. 最后补 golden tests / integration tests

这个顺序和当前项目的协议治理原则保持一致。

### 10.3 推荐代码生成职责

建议各端各自生成：

- iOS：`SwiftProtobuf`
- Android：官方 Protobuf / Kotlin 绑定
- 固件：`nanopb`

不要把生成后的所有平台代码都提交进当前仓库主目录。

更合理的是：

- 当前仓库持有 `.proto`
- 各平台在自己的构建流程里生成代码

如果当前仓库未来只作为 iOS 主仓，也至少应保留：

- `.proto`
- 生成脚本
- README 说明

---

## 11. 当前项目里的推荐落地步骤

如果未来真的要在当前项目里集成 Protobuf，建议按下面顺序推进。

### 第一步：只选 1-2 类低风险消息

建议优先：

- `DeviceInfo`
- `Hello` / `HelloAck`

不要第一步就碰：

- 波形块
- OTA 数据块

### 第二步：在 `proto/` 建 schema 与 README

先做：

- 目录结构
- 命名规范
- package/version 规范

### 第三步：在 `HRSenseProtocol` 增加可选 Protobuf payload 分支

保持：

- L2 不变
- L3 不变
- 仅 L4 payload 可切换

### 第四步：能力协商灰度启用

通过能力位或 schema 版本协商决定：

- 双方都支持才走 protobuf
- 否则回退 TLV

### 第五步：补 golden 与 cross-end 测试

至少补：

- `.proto` 编码/解码 golden
- TLV / Protobuf 双实现一致性测试
- 兼容回退测试

---

## 12. 当前项目里不建议做的事

### 12.1 不建议把 Protobuf 直接拿来替代本地存储模型

原因：

- 通信契约不等于持久化模型
- 本地查询、聚合、迁移有不同需求

### 12.2 不建议把所有消息都强行统一成 Protobuf

原因：

- 高吞吐二进制块不一定适合
- 固件侧代价并不低

### 12.3 不建议在没有协商能力位前就单边切换

原因：

- 极易造成真机/模拟器/固件互通失败
- 调试成本会急剧上升

---

## 13. 推荐的最小 schema 示例

下面是一个更接近当前项目的最小示例：

```proto
syntax = "proto3";

package hrsense.session.v1;

message Hello {
  repeated uint32 supported_protocol_versions = 1;
  uint32 app_capabilities = 2;
  uint32 schema_version = 3;
}

message HelloAck {
  uint32 negotiated_protocol_version = 1;
  uint32 device_capabilities = 2;
  DeviceInfo device_info = 3;
}

message DeviceInfo {
  string model = 1;
  string firmware_version = 2;
  uint32 protocol_version = 3;
  uint32 capabilities = 4;
}
```

这个示例的重点不在代码本身，而在几个治理原则：

- message 边界清晰
- 字段号简洁稳定
- schema_version 明确
- 不把 UI / 持久化字段混进协议 message

---

## 14. 验收标准建议

如果未来把 Protobuf 真正接进当前项目，建议至少满足下面这些验收条件：

1. `proto/` 有稳定目录结构和 README
2. 至少有一类消息完成 `.proto -> Swift/firmware` 打通
3. `docs/03-ble-gatt-protocol.md` 明确记录协商方式与边界
4. `HRSenseProtocol` 仍是统一编解码入口
5. 有 golden tests 验证 byte-level 行为
6. 有 TLV fallback 或兼容迁移路径

---

## 15. 当前结论

对当前项目而言，Protobuf **可以集成**，但推荐的方式不是大规模替换，而是：

- **坚持 L4 边界**
- **优先结构化消息**
- **保留高吞吐二进制块的自定义编码**
- **把 `.proto` 当成跨端契约治理资产**

最重要的结论只有一句：

- **当前项目最合适的方案，是“自定义传输层 + 可选 Protobuf 业务负载”的混合架构。**

这既保留了 BLE/OTA/波形吞吐上的工程控制力，也能满足 JD 中强调的跨端协议协作与 schema 治理能力。
