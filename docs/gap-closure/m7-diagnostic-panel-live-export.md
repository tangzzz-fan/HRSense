# M7 iOS 诊断面板 Live Metrics 与导出闭环

## 背景

`M7` 的原始目标是建立 App 侧可观测性基础设施，包括：

- 诊断面板实时展示关键指标
- MetricKit 诊断可见
- 诊断包可导出，便于联调与问题回放

在本轮补齐前，项目里虽然已经有：

- `MetricsCollector`
- `DiagnosticPackage`
- `MetricKitManager`
- `DiagnosticPanelView`

但这些能力并没有在 iOS App 内真正闭环。

## 原缺失点

### 1. 诊断面板没有接 live metrics

`DiagnosticPanelView.refreshMetrics()` 原来是空实现，面板里展示的 KPI 只是本地占位状态，无法反映真实 BLE / OTA 行为。

这会导致：

- 连接成功率、命令超时率、OTA 成功率长期为默认值
- 面板无法用于联调阶段的真实定位
- `M7` 的“实时指标”验收条目无法成立

### 2. 诊断导出仍是占位 UI

原来“Export Diagnostic Package”按钮只弹一个占位提示，没有真正生成 JSON，也没有进入系统分享链路。

这会导致：

- App 无法输出可提交的问题诊断包
- 日志、状态迁移、指标快照无法一起落地
- `docs/11-delivery-plan.md` 中“可导出诊断包”的验收项未满足

### 3. App 内没有面板入口

虽然有 `DiagnosticPanelView`，但 iOS App 容器里没有可达入口，开发阶段无法直接从 App 内打开。

### 4. 指标采集链路不完整

`MetricsCollector` 虽然定义了：

- `recordConnectionAttempt`
- `recordConnectionSuccess`
- `recordCommandSent`
- `recordCommandTimeout`
- `recordOTAAttempt`
- `recordOTASuccess`

但业务路径里此前并没有完整调用，因此即使接上面板，也会出现很多指标长期为 0。

## 本次更新

### iOS App 侧入口

在 `HRSenseAppContainerView` 中新增了 DEBUG 专用诊断入口：

- App 右上角悬浮按钮可直接打开诊断面板
- 面板通过 `environmentObject` 注入统一的 `DiagnosticPanelModel`

### 诊断面板模型化

新增 `DiagnosticPanelModel`，把原来散落在 View 里的占位状态改为真实数据源驱动。

职责包括：

- 从 live `MetricsCollector` 拉取 KPI
- 读取 `MetricKitManager` 的最近诊断记录
- 读取日志 ring buffer
- 组装 `DiagnosticPackage`
- 生成临时 JSON 文件供分享

### 导出链路闭环

`DiagnosticPanelView` 现已支持：

- 点击按钮生成诊断包 JSON
- 将最近日志、状态迁移、指标快照、系统信息一起打包
- 生成完成后通过 `ShareLink` 进入系统分享链路

### 日志与诊断基础设施补强

为了让导出真正有内容，本轮同时补了两项基础能力：

- `LoggingRegistry` 新增 `LogRingBuffer`
- `HRSenseLogging` 每条日志都会同时写入 ring buffer

这样导出诊断包时就能带上最近日志，而不是只有空壳 JSON。

### MetricKit 历史可读

`MetricKitManager` 新增最近诊断记录缓存，诊断面板现在能稳定显示：

- crash
- hang
- CPU exception
- 调试注入的测试诊断记录

### 指标采集链路补齐

本轮补齐了几条关键计数路径：

- `DeviceRepositoryImpl.connect` 记录连接尝试
- `performHandshake()` 成功后记录连接成功
- `BLECentralDataSource` 的 command / OTA wait 记录命令发送与超时
- `OTARepositoryImpl` 记录 OTA 尝试与 OTA 成功

## 代码落点

- `Sources/HRSenseFeature/Observability/DiagnosticPanelModel.swift`
- `Sources/HRSenseFeature/Views/DiagnosticPanelView.swift`
- `Sources/HRSenseFeature/Observability/MetricKitManager.swift`
- `Sources/HRSenseProtocol/Logging/HRSenseLogging.swift`
- `Sources/HRSenseAppUI/AppComposition.swift`
- `Sources/HRSenseAppUI/HRSenseAppContainerView.swift`
- `Sources/HRSenseData/Repositories/DeviceRepositoryImpl.swift`
- `Sources/HRSenseData/BLE/BLECentralDataSource.swift`
- `Sources/HRSenseData/OTA/OTARepositoryImpl.swift`

## 新增验证

- `Tests/HRSenseFeatureTests/DiagnosticPanelModelTests.swift`
  - 校验 live KPI 与 MetricKit 记录能刷新到面板模型
  - 校验诊断包 JSON 能真实导出并可反序列化

## 对 M7 验收的直接收益

本轮更新后，`M7` 在 iOS App 侧已经从“有壳无链路”推进到“可打开、可观察、可导出”的状态：

- 诊断面板可从 App 内直接进入
- KPI 已来自 live `MetricsCollector`
- 最近诊断记录可见
- 诊断包可生成并分享
- 日志、状态迁移、指标快照可一起进入导出文件

## 仍未完全闭合的部分

以下内容仍建议作为 `M7` 下一轮补齐：

- 真机上 `MetricKit` 实际回传 crash / hang 的联调记录
- 诊断包落地到 `Application Support` 的持久化归档
- 与 Simulator 日志对齐的双端诊断包 diff 说明
- 更细粒度的指标补齐：重连计数、样本丢失率、推理耗时趋势
