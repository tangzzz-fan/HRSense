# HRSense

HRSense 是一个面向心率与生理信号采集场景的 iOS 项目，采用 **Clean Architecture + Redux** 架构。设备通过 **自定义 BLE GATT 协议栈** 上报心率、RR 间期、波形与 OTA 相关数据，App 负责展示、计算与推理。

当前没有实体硬件，因此仓库同时包含一个运行在 **macOS** 上的 **模拟设备（BLE Peripheral）**，用于协议联调、回归验证、场景脚本测试与 CI。

## 当前状态

- 当前处于 **实现阶段**，仓库中已经包含真实 SwiftPM 代码、`Apps/` 下的两个 App shell，以及根级 `HRSense.xcworkspace`
- 设计文档仍然是架构与协议契约来源，但日常开发、构建与测试应以当前代码仓库为准
- 自定义协议、模拟器、App BLE 连接、Redux 状态流、波形链路、OTA 骨架、可观测性骨架、CoreML/C++ 计算骨架都已落地，里程碑闭环程度以 `docs/11-delivery-plan.md` 为准

## 快速开始

### 开发入口

- 统一从 `HRSense.xcworkspace` 打开工程
- 不要同时单独打开 `Apps/HRSenseApp/HRSenseApp.xcodeproj` 和 `Apps/HRSenseSimulator/HRSenseSimulator.xcodeproj`
- 根目录 `Package.swift` 是共享业务逻辑的主入口；两个 App 工程只承担入口、权限与组合根职责

### 标准验证命令

```bash
swift build
swift test
swift test --filter HRSenseProtocolTests
nocorrect xcodebuild -workspace HRSense.xcworkspace -scheme HRSenseApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
nocorrect xcodebuild -workspace HRSense.xcworkspace -scheme HRSenseSimulator \
  -destination 'platform=macOS' build
```

### 工作规则

- 任何协议变更先更新 `docs/03-ble-gatt-protocol.md`，再更新 `HRSenseProtocol`，最后同步 App 与 Simulator
- 涉及 BLE 契约、场景引擎、headless 模式或故障注入的改动，必须同时验证 Simulator 路径
- 里程碑完成标准不只看编译通过，还要对齐 `docs/11-delivery-plan.md` 中的验收项

## 核心架构

1. **iOS = BLE Central，macOS 模拟器 = BLE Peripheral**，两端均基于 CoreBluetooth。
2. **`HRSenseProtocol` 是共享协议包**，负责 L2-L4 的 framing、命令、数据编解码，App 与 Simulator 共用同一份实现，避免协议漂移。
3. **自定义协议栈运行在 BLE GATT 之上**，使用 128-bit 自定义 UUID，而非标准 Heart Rate Service。
4. **App 架构采用 Clean + 自建 Redux**，基于 [`TGReduxKit`](https://github.com/tangzzz-fan/TGReduxKit)，Reducer 保持纯函数，BLE/计算/CoreML/OTA 统一放入 Middleware。
5. **重计算链路采用 C ABI**，Swift 调用 `HRSenseCompute`，底层桥接到 `HRSenseComputeCxx`。
6. **CoreML 采用 placeholder-model-first 策略**，先打通端到端推理链路，再替换真实模型。
7. **Simulator 是长期回归资产**，而不是一次性桩代码；其职责包括脚本场景、故障注入、headless 执行与 CI 支撑。

## 当前仓库结构

```text
HRSense/
├── Package.swift
├── HRSense.xcworkspace
├── Apps/
│   ├── HRSenseApp/
│   └── HRSenseSimulator/
├── Sources/
│   ├── HRSenseProtocol/
│   ├── HRSenseCore/
│   ├── HRSenseComputeCxx/
│   ├── HRSenseCompute/
│   ├── HRSenseData/
│   ├── HRSenseFeature/
│   ├── HRSenseAppUI/
│   ├── HRSenseSimulatorKit/
│   ├── HRSenseSimulatorUI/
│   └── HRSenseSimulator/
├── Tests/
├── Models/
├── Scenarios/
├── docs/
├── proto/
├── tools/
└── THIRD_PARTY_LICENSES.md
```

## 模块概览

- `HRSenseProtocol`: 共享协议层，负责分帧、重组、CRC、命令与数据编解码
- `HRSenseCore`: 领域实体、仓储协议、用例抽象、错误模型
- `HRSenseComputeCxx` / `HRSenseCompute`: C++ 计算实现与 Swift 桥接
- `HRSenseData`: BLE 数据源、Repository 实现、持久化、Metrics、OTA Repository
- `HRSenseFeature`: Redux 状态、动作、Reducer、Middleware、SwiftUI 表现层
- `HRSenseAppUI`: App shell 组合根与容器视图
- `HRSenseSimulatorKit`: 模拟器核心能力，包括 Peripheral、场景引擎、数据生成器、OTA 状态机、故障注入与 headless runner
- `HRSenseSimulatorUI`: 模拟器 GUI 界面
- `HRSenseSimulator`: Simulator CLI 入口

## 文档索引

| 文档 | 内容 |
| --- | --- |
| [docs/00-overview.md](docs/00-overview.md) | 项目总览、目标、范围、关键决策、术语表 |
| [docs/01-roadmap.md](docs/01-roadmap.md) | 里程碑路线图（概念轨道 / 并行与依赖） |
| [docs/11-delivery-plan.md](docs/11-delivery-plan.md) | 里程碑与验收标准，当前执行口径 |
| [docs/02-architecture.md](docs/02-architecture.md) | 系统整体架构、组件划分、数据流 |
| [docs/03-ble-gatt-protocol.md](docs/03-ble-gatt-protocol.md) | 自定义 BLE 协议契约 |
| [docs/04-app-clean-redux.md](docs/04-app-clean-redux.md) | App 侧 Clean + Redux 设计 |
| [docs/05-simulator-macos.md](docs/05-simulator-macos.md) | macOS 模拟设备设计 |
| [docs/06-coreml-and-compute.md](docs/06-coreml-and-compute.md) | CoreML 与 C++ 计算链路 |
| [docs/07-ota-dfu.md](docs/07-ota-dfu.md) | OTA/DFU 设计 |
| [docs/08-project-structure.md](docs/08-project-structure.md) | 项目结构规划文档，包含早期结构设计背景 |
| [docs/10-observability.md](docs/10-observability.md) | 日志、指标、诊断与监控 |
| [docs/specs/](docs/specs/) | 细化 spec 目录与模板 |
