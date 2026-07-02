# M7 · 可观测性（日志/崩溃/监控）— 实施计划

## 摘要

建立诊断基础设施：分层日志门面、Redux Logging Middleware、MetricKit 崩溃采集、MetricsCollector 指标聚合、DEBUG 诊断面板。

**依赖**：M4（Redux 展示层）。

---

## 阶段 1：HRSenseLogging 门面（新 SPM target）

| 文件 | 职责 |
|---|---|
| `LogCategory.swift` | 8 个分类枚举：`bleRaw`/`bleFrame`/`bleConn`/`protoCmd`/`state`/`ota`/`computeInfer`/`perf` + `LogFilter` 开关 |
| `HRSenseLog.swift` | 门面结构体：`debug()`/`info()`/`notice()`/`error()`/`fault()`，每分类独立 `Logger` 实例 |
| `LogPrivacy.swift` | `public`/`private` 枚举 |
| `DiagnosticPackage.swift` | 诊断包数据模型（日志条目 + 指标快照 JSON 可导出） |
| `HexFormat.swift` | 规范 hex dump：`canonicalHexDump(_:)`，两端格式一致，可并排 diff |

---

## 阶段 2：日志插桩（HRSenseData + HRSenseFeature）

在关键路径添加 `HRSenseLog` 调用：

| 位置 | Category | 内容 |
|---|---|---|
| `BLECentralDataSource.didUpdateValue` | `ble.raw` | 原始字节 hex dump |
| `FrameAssembler.feed` 返回帧 | `ble.frame` | seq/分片数/CRC 结果 |
| `BLECentralDataSource` 连接事件 | `ble.conn` | 扫描/连接/断连/MTU/重连 |
| 命令处理代码 | `proto.cmd` | 发送/响应操作码+耗时 |
| OTA Repository | `ota` | 阶段转换/进度/CRC |
| `MetricsCollector` | `perf` | 每 10s 聚合快照 |

---

## 阶段 3：Redux Logging Middleware

`Sources/HRSenseFeature/Middleware/LoggingMiddleware.swift`：
- 观察每个 `Action → State` 转换
- 维护最近 N=50 次状态转换的环形缓冲区
- 崩溃时序列化为 JSON 附加至诊断报告

---

## 阶段 4：MetricKit 集成

`Sources/HRSenseData/Observability/MetricKitManager.swift`：
- `MXMetricManagerSubscriber` 协议
- 接收 `MXCrashDiagnostic`/`MXHangDiagnostic`/`MXCPUExceptionDiagnostic`
- 崩溃-日志关联：检测到崩溃 → 附加 `LoggingMiddleware.recentTransitions`
- 持久化至 `Application Support/HRSense/crashes/`

---

## 阶段 5：MetricsCollector

Actor 模式聚合所有实时指标：

| 指标 | 来源 |
|---|---|
| `connectionSuccessRate` | `connectionSuccesses / connectionAttempts` |
| `reconnectCount` | 重连状态机 |
| `commandTimeoutRate` | `commandTimeouts / commandsSent` |
| `sampleLossRate` | 1.0 - `samplesReceived / samplesExpected` |
| `throughputBytesPerSec` | `totalBytesReceived / elapsed` |
| `otaSuccessRate` | `otaSuccesses / otaAttempts` |

---

## 阶段 6：DEBUG 诊断面板

`Sources/HRSenseFeature/Views/DiagnosticPanelView.swift`（`#if DEBUG` 包裹）：

- **Section 1**：实时指标（6 个 KPI，每 1s 刷新）
- **Section 2**：日志分类开关（8 个 Toggle + "全部开启/关闭"+ 级别选择器）
- **Section 3**：MetricKit 诊断（崩溃/挂起/CPU 异常 + 最近状态转换）
- **Section 4**：诊断导出（`DiagnosticPackage` JSON → 分享表单）

测试崩溃按钮（`fatalError` 触发）、测试挂起按钮（`Thread.sleep` 5s）。

---

## 验收标准
- [ ] 日志可按 category 开关
- [ ] 可导出诊断包
- [ ] App 与模拟器 hex 格式一致可并排 diff
- [ ] MetricKit 捕获注入的崩溃/挂起诊断
- [ ] 崩溃报告附最近状态迁移
- [ ] 面板实时显示 6 个关键指标

## 预估文件数：~12 个新文件 + 多处日志插桩修改
