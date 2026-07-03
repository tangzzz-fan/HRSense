# HRSense 技术讲解 — 模块全貌

本文件夹按模块对项目的**实际实现**进行技术讲解。每份文档聚焦一个 SPM target，包含核心类型、关键流程、线程模型与设计取舍。

## 模块依赖关系

```
HRSenseProtocol  ←── 双端共享的协议栈（帧、编解码、TLV、CRC）
       │
       ├── HRSenseCore  ←── 领域层（实体、Repository 接口、UseCase）
       │       │
       │       ├── HRSenseComputeCxx  ←── C++ 计算层（HRV / 特征提取）
       │       │       │
       │       │       └── HRSenseCompute  ←── Swift 桥接 + CoreML 推理
       │       │
       │       ├── HRSenseData  ←── 数据层（BLE、持久化、OTA、Repository 实现）
       │       │
       │       └── HRSenseFeature  ←── 展示层（Redux Store、Middleware、SwiftUI）
       │               │
       │               └── HRSenseAppUI  ←── App 壳（组合根、入口视图）
       │
       ├── HRSenseSimulatorKit  ←── 模拟器核心（BLE 外设、生成器、场景引擎）
       │       │
       │       └── HRSenseSimulatorUI  ←── 模拟器 UI
       │
       └── HRSenseSimulator  ←── CLI 可执行入口
```

## 文档索引

| 文档 | 模块 | 内容概要 |
|------|------|---------|
| [01-hrsense-protocol](./01-hrsense-protocol.md) | `HRSenseProtocol` | 帧编解码、分片重组、TLV、CRC、命令/数据模型 |
| [02-hrsense-core](./02-hrsense-core.md) | `HRSenseCore` | 领域实体、Repository 协议、UseCase |
| [03-hrsense-compute](./03-hrsense-compute.md) | `HRSenseComputeCxx` + `HRSenseCompute` | C ABI 桥接、HRV 计算、CoreML 推理管线 |
| [04-hrsense-data](./04-hrsense-data.md) | `HRSenseData` | BLE Central、持久化、OTA、Repository 实现 |
| [05-hrsense-feature](./05-hrsense-feature.md) | `HRSenseFeature` | Redux Store、Reducer、Middleware、SwiftUI |
| [06-hrsense-simulator](./06-hrsense-simulator.md) | `HRSenseSimulatorKit` | 模拟外设、数据生成器、场景引擎、故障注入 |
| [07-app-composition](./07-app-composition.md) | `HRSenseAppUI` | 组合根、依赖注入、端到端数据流 |
| [08-ble-cccd-flow](./08-ble-cccd-flow.md) | 跨模块流程 | BLE 连接建立、CCCD 订阅、握手、重连、State Restoration |
| [09-tgreduxkit-usage](./09-tgreduxkit-usage.md) | 跨模块分析 | TGReduxKit 使用模式、7 种异步流处理场景、线程模型 |
| [10-glossary-and-custom-ble](./10-glossary-and-custom-ble.md) | 参考 | 名词解释表（HR/HRV/RR/CCCD 等 40+）+ 标准 BLE vs 自定义 GATT 分析 |
| [11-pipeline-overview](./11-pipeline-overview.md) | 跨模块管线 | 端到端数据流全景、5 条链路索引、线程模型、Middleware 编排顺序 |
| [12-cpp-compute-bridge](./12-cpp-compute-bridge.md) | `HRSenseComputeCxx` | C ABI 桥接模式、8 种 HRV 算法、特征顺序契约 |
| [13-coreml-inference](./13-coreml-inference.md) | `HRSenseCompute` | 模型选择策略、评分系统、三级降级链 |
| [14-waveform-pipeline](./14-waveform-pipeline.md) | 波形管线 | 高吞吐 BLE 波形、Ring Buffer、丢块检测、轮询策略 |
| [15-sleep-pipeline](./15-sleep-pipeline.md) | 睡眠管线 | 18 维特征、Sleep Session 合并、规则引擎降级 |
| [16-best-practices](./16-best-practices.md) | 跨模块分析 | 闭环设计、可观测性、后台策略、错误处理、依赖注入、持久化 |
| [17-improvement-suggestions](./17-improvement-suggestions.md) | 改进建议 | 线程安全、性能优化、架构改进、工程化提升、优先级矩阵 |
| [18-protobuf-integration](./18-protobuf-integration.md) | 跨端集成 | Protobuf schema 设计、代码生成、iOS/Android/FW 集成、版本管理、异常处理 |
| [19-incident-response](./19-incident-response.md) | 运维体系 | 事故分级、信息收集、分层排查方法论、典型场景排查路径、复盘模板 |
| [20-interview-questions](./20-interview-questions.md) | 面试参考 | JD 痛点分析、14 道面试题（高级 + 资深）、评估矩阵 |
| [21-interview-answers](./21-interview-answers.md) | 面试参考答案 | Q1-Q14 完整参考答案，含项目代码对照和排查路径 |
| [22-key-flow-diagrams](./22-key-flow-diagrams.md) | 流程图解 | 7 条关键流程 Mermaid 图 + 32 个坑点标注 |
