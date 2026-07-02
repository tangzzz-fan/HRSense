# M6 · OTA/DFU 全流程实施计划

## 概述

M6 实现端到端固件升级全流程。建立在 M3（BLE 集成）之上。

**核心设计文档**：`docs/07-ota-dfu.md` —— 定义了完整的 OTA 协议、命令表、设备状态机、传输时序、安全约束以及 App 状态模型。

**硬依赖**：M3 必须完成。M6 需要 `HRSenseProtocol` 包、`BLECentralDataSource`、`DeviceRepository` 及连接状态机。

---

## 步骤 0：前置条件检查

在编写 M6 代码之前验证 M3 边界：

1. `HRSenseProtocol` `FrameAssembler` 能否解码任意帧，单元测试覆盖率 ≥80%？
2. `BLECentralDataSource` 能否发现 OTA 服务（`0005`），执行 `.withoutResponse` 写入？
3. `DeviceRepository` 是否暴露 `writeCommand`、`writeData` 和通知订阅流？
4. 连接中间件和状态机是否支持设备重启后重连？

---

## 步骤 1：`HRSenseProtocol/OTA/` —— OTA 命令编解码器

**原则**：编解码器必须双向对称。App 侧编码 = 模拟器侧解码，反之亦然。所有多字节字段小端序。

| 文件 | 职责 |
|---|---|
| `Sources/HRSenseProtocol/OTA/OTAOpCode.swift` | 枚举：`OTA_START=0x20`、`OTA_START_ACK=0xA0`、`OTA_WINDOW_BEGIN=0x21`、`OTA_WINDOW_ACK=0xA1`、`OTA_VALIDATE=0x23`、`OTA_VALIDATE_RESULT=0xA3`、`OTA_APPLY=0x24`、`OTA_ABORT=0x25` |
| `Sources/HRSenseProtocol/OTA/OTACommand.swift` | 带关联值载荷的枚举 |
| `Sources/HRSenseProtocol/OTA/OTAStatusCode.swift` | 设备状态码枚举 |
| `Sources/HRSenseProtocol/OTA/OTACodec.swift` | TLV 编码/解码静态方法 |
| `Sources/HRSenseProtocol/OTA/OTAChunkEncoder.swift` | 紧凑二进制格式 `offset(u32 LE) + payload` |
| `Sources/HRSenseProtocol/CRC32.swift` | CRC-32 (IEEE 802.3) 工具 + 已知向量测试 |

**测试**：往返测试 `decode(encode(x))==x`、黄金字节、边界情况（零大小、最大偏移、截断 TLV）、CRC32 已知值。

---

## 步骤 2：`HRSenseSimulatorKit/OTA/` —— 设备端 OTA 状态机

状态机：`Idle → Preparing → Transferring → Validating → Applying → Rebooting`

| 文件 | 职责 |
|---|---|
| `Sources/HRSenseSimulatorKit/OTA/OTAStateMachine.swift` | 核心状态机，处理所有 OTA 命令转换 |
| `Sources/HRSenseSimulatorKit/OTA/OTAImageBuffer.swift` | 内存镜像存储，增量 CRC32，断点续传 |
| `Sources/HRSenseSimulatorKit/OTA/OTAEventHandler.swift` | didReceiveWrite 回调路由 OTA 命令 |
| `Sources/HRSenseSimulatorKit/OTA/OTARebootSimulator.swift` | 模拟重启：断连→延迟→新版本重广播 |
| `Sources/HRSenseSimulatorKit/OTA/OTAPreconditionChecker.swift` | 电池 ≥30%、禁止降级、空间检查 |

**故障注入**：
- 中途断连 / CRC 错误窗口 / 篡改镜像 / 拒绝启动 / 重启后不返回 / 超时

---

## 步骤 3：`HRSenseCore/` —— 领域实体、UseCase、Repository 协议

| 文件 | 职责 |
|---|---|
| `Sources/HRSenseCore/Entities/OTAUpdateError.swift` | 领域错误枚举 |
| `Sources/HRSenseCore/Entities/OTAProgress.swift` | 阶段枚举 + 进度 (0.0...1.0) |
| `Sources/HRSenseCore/Entities/OTAFirmwareImage.swift` | 固件镜像值类型 |
| `Sources/HRSenseCore/Repositories/OTARepository.swift` | 协议：`startOTA`、`abortOTA`、`cancelOTA` |
| `Sources/HRSenseCore/UseCases/OTAUpdateUseCase.swift` | 编排整个 OTA 流程 |

---

## 步骤 4：`HRSenseData/` —— Repository 实现与 BLE OTA I/O

| 文件 | 职责 |
|---|---|
| `Sources/HRSenseData/OTA/OTARepositoryImpl.swift` | 实现 `OTARepository`，编排 BLE OTA 流程 |
| `Sources/HRSenseData/OTA/OTACommandSender.swift` | 通过 Control/Write (0003) 发送命令帧，超时重试 |
| `Sources/HRSenseData/OTA/OTAWindowTransfer.swift` | 通过 OTA Data (0005) 传输窗口，背压控制 |
| `Sources/HRSenseData/OTA/OTAProgressTracker.swift` | 原始 BLE 事件 → `OTAProgress` 流 |

**窗口重传**：CRC 不匹配 → 自动重传该窗口，最多 3 次。

---

## 步骤 5：`HRSenseFeature/` —— Redux 状态/Action/Reducer/Middleware

| 文件 | 职责 |
|---|---|
| `Sources/HRSenseFeature/State/OTAState.swift` | Redux 状态片段 |
| `Sources/HRSenseFeature/Actions/OTAActions.swift` | OTA 操作枚举 |
| `Sources/HRSenseFeature/Reducer/OTAReducer.swift` | 纯函数状态转换 |
| `Sources/HRSenseFeature/Middleware/OTAMiddleware.swift` | 编排 OTA 流，进度 → Actions |

**OTAState 设计**：
```swift
enum OTAPhase: Equatable {
    case idle, preparing, transferring(progress: Double)
    case validating, applying, rebootingAndReconnecting
    case completed(newVersion: String), failed(error: OTAUpdateError)
}
```

---

## 步骤 6：SwiftUI 进度界面

| 文件 | 职责 |
|---|---|
| `OTAUpgradeView.swift` | 整体升级流程视图 |
| `OTAProgressBar.swift` | 确定性进度条（单调递增） |
| `OTAPhaseIndicator.swift` | 当前阶段指示器 |
| `OTAErrorView.swift` | 错误状态 + 操作按钮 |
| `OTASuccessView.swift` | 成功动画 + 版本确认 |
| `OTAVersionCompareView.swift` | 版本对比 |

**UI 规则**：进度条必须单调递增、升级期间禁止退出导航、后台继续传输、VoiceOver 无障碍。

---

## 步骤 7：App 外壳集成

更新 `AppComposition.swift` 连线 OTA 依赖。在 `makeStore()` 中注册 `OTAMiddleware`。

---

## 步骤 8：端到端验收

| 验收类别 | 验证 |
|---|---|
| A. 正常升级 | 连续 10 次 100% 成功率，进度单调递增，新版本确认 |
| B. 断点续传 | 中断后从 resumeOffset 续传成功 |
| C. 完整性 | 篡改镜像 → 设备拒绝并回滚 |
| D. 窗口重传 | CRC 错 → 自动重传 → 成功 |
| E. 前置检查 | 电量 <30% 拒绝、禁止降级 |
| F. 错误路径 | 全部错误路径无崩溃、无冻结 |

---

## 关键架构注意事项

1. OTA Data `0005` 使用 Write Without Response —— App 端需基于 `OTA_WINDOW_ACK` 自行实现流控
2. OTA 状态机单向 —— 一旦进入 `applying` 无法返回
3. `resumeOffset` 依赖相同 `imageCRC32` 定位传输
4. 镜像数据不经过正常命令编解码路径，走专用高吞吐通道
5. 使用 `ota` 日志分类埋点关键路径（为 M7 做准备）
