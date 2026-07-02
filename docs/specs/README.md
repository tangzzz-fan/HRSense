# Specs · 细化设计

本目录存放**可独立评审、可实施**的细化设计（spec）。与 `docs/` 下的规划文档相比，spec 更聚焦、更具体，通常对应一个明确的实现任务。

## 约定
- 命名：`NNNN-slug.spec.md`（4 位递增编号 + 简短英文 slug）。
- 每个 spec 用 [`spec-template.md`](spec-template.md) 起草。
- 状态：`draft`（草案）→ `review`（评审中）→ `accepted`（已接受）→ `implemented`（已实现）。

## 索引

| 编号 | 标题 | 状态 | 说明 |
| --- | --- | --- | --- |
| [0001](0001-cpp-compute-integration.spec.md) | C++ 计算层集成 | draft (决策已固化) | C ABI + SwiftPM 源码 target；内存/线程/错误约定已定；含算法原型移植流程 |
| [0002](0002-coreml-inference-pipeline.spec.md) | CoreML 推理管线（落地路线）| draft (决策已固化) | 管线优先/14维特征契约/I-O schema/占位模型/转换与合规；含睡眠分期扩展任务 |
| [0003](0003-waveform-high-throughput.spec.md) | 实时波形高吞吐 + 高性能可视化 | draft (决策已固化) | 波形通道/吞吐优化/背压降采样/自绘渲染/度量指标 |
| [0004](0004-local-storage.spec.md) | 本地存储与数据保留 | draft (决策已固化) | SwiftData+文件混合/数据模型/保留归档策略 |

> 协议侧 Open Questions（UUID/CRC/能力位图/时间戳/字节序/可靠性）已直接在 [`../03-ble-gatt-protocol.md`](../03-ble-gatt-protocol.md) §8 内联冻结，不再单列 spec。

## 待创建（建议）
- 模拟器脚本化故障注入 / E2E 测试 spec。
- 模型训练/评估流程 spec（独立训练仓库）。
