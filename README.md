# HRSense

一款连接蓝牙心率设备的 iOS App，采用 **Clean Architecture + Redux** 架构。设备通过 **自定义协议栈（承载于 BLE GATT 之上）** 上报心率等生理数据，App 负责实时展示、指标计算（集成 C++ 计算库）以及基于 **CoreML** 的推理。

由于当前没有实体硬件，配套一个运行在 **macOS** 上的 **模拟设备（BLE Peripheral）**，用于在没有硬件的情况下完成端到端开发、联调与自动化测试。

> 当前阶段：**规划 / 文档阶段**。本仓库暂不落地实现代码，仅沉淀架构与协议规划文档，作为后续开发的依据。

---

## 文档索引

| 文档 | 内容 |
| --- | --- |
| [docs/00-overview.md](docs/00-overview.md) | 项目总览、目标、范围、关键决策、术语表 |
| [docs/01-roadmap.md](docs/01-roadmap.md) | 里程碑路线图（概念轨道 / 并行与依赖） |
| [docs/11-delivery-plan.md](docs/11-delivery-plan.md) | **落地计划（Milestone + 验收标准）· 执行标杆** |
| [docs/02-architecture.md](docs/02-architecture.md) | 系统整体架构、组件划分、数据流 |
| [docs/03-ble-gatt-protocol.md](docs/03-ble-gatt-protocol.md) | 自定义协议栈分层、GATT Profile、分帧/可靠传输/命令定义 |
| [docs/04-app-clean-redux.md](docs/04-app-clean-redux.md) | App 侧 Clean Architecture 分层与 Redux 单向数据流 |
| [docs/05-simulator-macos.md](docs/05-simulator-macos.md) | macOS 模拟设备设计（Peripheral、场景引擎、故障注入） |
| [docs/06-coreml-and-compute.md](docs/06-coreml-and-compute.md) | CoreML 推理管线与 C++ 计算层集成方式 |
| [docs/07-ota-dfu.md](docs/07-ota-dfu.md) | OTA / DFU 固件升级协议与流程设计（仅模拟用途）|
| [docs/08-project-structure.md](docs/08-project-structure.md) | 项目结构与文件组织（Package.swift + 各 SPM 包 + 两个 App 外壳骨架）|
| [docs/09-jd-coverage-analysis.md](docs/09-jd-coverage-analysis.md) | 对照目标 JD 的覆盖度/差距分析与补充建议 |
| [docs/10-observability.md](docs/10-observability.md) | 可观测性：日志体系 / 崩溃分析 / 监控指标 |
| [docs/specs/](docs/specs/) | 细化设计 spec 目录（0001–0004，含模板）|

## 核心架构决策（摘要）

1. **iOS = BLE Central，macOS 模拟器 = BLE Peripheral**，均基于 CoreBluetooth。
2. **协议编解码下沉为独立 Swift Package（`HRSenseProtocol`）**，App 与模拟器共享同一份实现，保证两端一致、避免协议漂移。
3. **自定义协议栈分 4 层**：GATT 传输层 → 分帧/可靠传输层 → 会话/命令层 → 应用数据层。使用 128-bit 自定义 UUID，而非标准 Heart Rate Service。
4. **App 架构 = 自建轻量 Redux**，基于开源库 [`TGReduxKit`](https://github.com/tangzzz-fan/TGReduxKit)（MIT，SwiftUI/iOS 17+，基于 Swift Observation）。BLE / 计算 / 推理等副作用统一在 Middleware（Effects）中触发，View 只消费 State。
5. **重计算（HRV/滤波/特征提取）交给 C++ 计算库**，采用 **C ABI 方案**（C++ 暴露纯 C 接口，Swift 桥接调用，SwiftPM 打包；详见 spec 0001）。
6. **面向"未来对接真实硬件"设计**：协议版本协商 + 能力发现，把模拟器与真实设备的差异收敛在协议层。
7. **CoreML 端上推理**：框架本身为 Apple 私有随 SDK 提供、无开源义务；转换工具 `coremltools` 为 BSD-3-Clause；许可风险主要在"模型来源"（外部权重/数据集），需登记核对（详见 `docs/06`）。

## 构建方式：SwiftPM 优先

项目**默认使用 Swift Package Manager (SwiftPM)** 组织所有可复用逻辑：协议、领域、数据、计算层均为**本地 SwiftPM 包**（可独立编译与单测）。第三方依赖（如 `TGReduxKit`）也通过 SwiftPM 引入。

> 现实约束：iOS App 与 macOS 模拟器这两个**可执行程序**需要 `Info.plist` / entitlements / 蓝牙权限 / App 打包，因此各自保留一个**轻量 Xcode app target 作为"外壳"**，仅负责入口、权限与组装，业务逻辑全部来自 SwiftPM 包。这样既享受 SwiftPM 的模块化与可测性，又满足 App 的打包与权限需求。

## 目录规划（SwiftPM-first，概览）

```
HRSense/
├── Package.swift               # 核心库：一个包多产品(多 target)
├── Sources/                    # SPM 库 target：Protocol / Core / Compute(+Cxx) / Data / Feature / SimulatorKit
├── Tests/                      # 各 target 单测
├── Apps/                       # 两个薄外壳
│   ├── HRSenseApp/             #   iOS App(Central)：入口 + 权限 + 组装
│   └── HRSenseSimulator/       #   macOS 模拟设备(Peripheral)
├── Models/                     # CoreML 模型(.mlpackage，Git LFS)
├── Scenarios/                  # 模拟器场景脚本/录制数据集
├── docs/                       # 本仓库文档
└── THIRD_PARTY_LICENSES.md     # 第三方依赖 / 模型来源与许可登记
```

> 完整结构、`Package.swift` 示例、C ABI target/modulemap、App 外壳与依赖关系图详见 **[docs/08-project-structure.md](docs/08-project-structure.md)**。
> 注：以上为规划，尚未创建。
