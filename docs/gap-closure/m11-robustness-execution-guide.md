# M11 · 健壮性最终验收落地指南

## 1. 文档目的

`docs/plans/11-m11-robustness.md` 给出了 M11 的完整蓝图，但按当前仓库状态来看，M11 还不能直接按“大满贯形态”一次性展开。

这份文档的目的，是把 M11 从“总体计划”拆成一条 **当前可落地、可迭代、可验收** 的实施路径，回答三个问题：

1. **现在已经具备哪些 M11 基础能力**
2. **接下来 M11 最应该先做什么**
3. **哪些内容应该先轻量落地，再逐步演进**

---

## 2. 当前基础能力盘点

### 2.1 已具备的部分

当前代码库已经具备 M11 的几个关键前置能力。

#### A. 场景与 headless 运行基础已经存在

相关文件：

- `Sources/HRSenseSimulatorKit/Scenario/ScenarioParser.swift`
- `Sources/HRSenseSimulatorKit/Scenario/ScenarioEngine.swift`
- `Sources/HRSenseSimulatorKit/SimulatorHeadlessRunner.swift`
- `Sources/HRSenseSimulatorKit/Faults/FaultInjector.swift`
- `Sources/HRSenseSimulatorKit/Models/ScenarioModels.swift`

现状：

- 已有 JSON 场景解析能力
- 已有基础 `ScenarioEngine`
- 已有 `SimulatorHeadlessRunner`
- 已有基础故障注入器
- 已有 `Scenarios/example-*.json`

这意味着 M11 **不是从 0 开始**，而是已经有一条最小 headless 路径，只是表达能力和验证能力都还比较初级。

#### B. CI 已存在，但还很轻

相关文件：

- `.github/workflows/ci.yml`

现状：

- 当前 CI 只做 `swift build` + `swift test`
- 还没有场景回放
- 还没有故障场景矩阵
- 还没有 nightly soak / long-run job

这说明 M11 的 CI 入口已经有了，但还没有变成“健壮性门控”。

#### C. 可观测性基础已经具备

相关文件：

- `Sources/HRSenseFeature/Observability/MetricKitManager.swift`
- `Sources/HRSenseFeature/Observability/DiagnosticPanelModel.swift`
- `Sources/HRSenseFeature/Views/DiagnosticPanelView.swift`
- `docs/gap-closure/m7-diagnostic-panel-live-export.md`

现状：

- 已能记录最近 MetricKit diagnostics
- 已有状态迁移 ring buffer
- 已能导出诊断包

这部分对于 M11 很重要，因为 M11 不只是“跑场景”，还需要 **解释失败原因**。

#### D. 模块级测试覆盖已经较好

现状：

- `Tests/` 下已覆盖协议、BLE、波形、OTA、Compute、CoreML、Sleep、Persistence 等模块
- M8 / M9 / M10 的关键路径已经有较多 targeted tests

这意味着 M11 可以优先补 **回归测试体系和端到端验证层**，而不必回头重建模块单测基础。

---

## 3. 当前缺口判断

如果严格对照 `11-m11-robustness.md`，当前主要缺口有 6 类。

### 3.1 场景模型表达能力不足

当前 `Scenario` 模型只支持：

- `setHR`
- `startStream`
- `stopStream`
- `disconnect`
- `reconnect`
- `injectFault`
- `wait`

但 M11 计划里的目标还包括：

- 时间线断言
- 设备信息断言
- 数据模式切换
- OTA 流程控制
- 长时间 soak 脚本
- regression / smoke / faults / ota / stability 分类场景

结论：

- **场景系统可用，但还不是 M11 所需的“验收脚本系统”**

### 3.2 FaultInjector 还不够强

当前 `FaultInjector` 主要支持：

- 丢包
- CRC 破坏
- 固定延迟

而计划中的 M11 故障集还包括：

- `disconnect`
- `withhold_response`
- `block_reorder`
- `block_truncation`
- `illegal_frame`
- `battery_drop`

结论：

- **当前故障注入只够做最小 smoke/fault，离协议鲁棒性验收还差一层**

### 3.3 Headless 输出还不具备“断言消费”价值

当前 headless runner 更像调试日志输出器，还不是稳定的机器可消费指标流。

还缺：

- JSONL 结构化输出
- 固定字段 schema
- 场景结果摘要
- 失败原因和断言映射

结论：

- **M11 不能先上 AssertionRunner，再补 headless 格式；顺序必须反过来**

### 3.4 CI 还没有 M11 门控能力

当前 CI 没有：

- PR 级 smoke / fault / OTA 冒烟矩阵
- nightly soak
- 日志 artifact
- 失败报告聚合

结论：

- **M11 的第一步不是“加更多单测”，而是把现有 CI 升级为执行 M11 资产的平台**

### 3.5 场景库目录结构还没成型

当前 `Scenarios/` 只有 3 个示例 JSON。

计划中的结构：

- `schema/`
- `smoke/`
- `faults/`
- `ota/`
- `stability/`
- `regression/`
- `datasets/`

结论：

- **场景库还处于 demo 状态，不适合作为回归资产仓库使用**

### 3.6 缺少“失败即证据”的工具链

M11 的难点不是跑，而是 **失败之后是否知道为什么失败**。

当前还没有：

- 统一断言 runner
- JUnit/JSON 报告
- soak 分析器
- 指标阈值审计工具

结论：

- **M11 当前最大的缺口不是执行器，而是结果解释层**

---

## 4. M11 最合理的实施顺序

结合当前代码基线，建议把 M11 拆成 4 个阶段，而不是直接按总计划一次性推进。

### 阶段 A：把现有场景系统升级到“可回放、可对比”

优先级：**最高**

先做：

1. 扩展 `Scenario` 数据模型，引入：
   - `scenarioVersion`
   - `metadata`
   - `timeline`
   - `assertions`
2. 保持向下兼容现有 example 场景
3. 为 ScenarioParser 增加基础 schema 校验
4. 给 ScenarioEngine 增加按 `atMs` 执行 timeline 的能力

这一阶段的目标不是复杂，而是要让“场景”从 demo step list 变成 **可被 M11 资产化的脚本格式**。

### 阶段 B：把 headless 输出升级到“结构化证据流”

优先级：**最高**

先做：

1. `SimulatorHeadlessRunner` 增加 JSONL 输出
2. 定义最小事件集：
   - `scenario_started`
   - `scenario_completed`
   - `stream_started`
   - `fault_applied`
   - `disconnect`
   - `reconnect`
   - `ota_progress`
   - `metric_snapshot`
   - `assertion_context`
3. 支持 `--log-format json`
4. 支持 `--log-file`

没有这一层，后面的 AssertionRunner 和 SoakAnalyzer 都很难落地。

### 阶段 C：最小 M11 执行器与 PR 门控

优先级：**高**

先做：

1. 不必一上来建独立 `Tools/M11AssertionRunner`
2. 可以先在 `Sources/HRSenseSimulator/` 或 `tools/` 下做一个轻量版结果分析脚本
3. 先支持 3 类最小断言：
   - 无 crash
   - 场景完成
   - 关键状态命中
4. 在 CI 先加：
   - `smoke/basic-connect`
   - `faults/packet-loss-5pct`
   - `ota/ota-happy-path`

这一阶段的目标是：

- **让 PR 开始被“场景回放”约束**
- 而不是等所有工具都完美后再接 CI

### 阶段 D：nightly soak / regression / dashboard

优先级：**中高**

这一阶段再逐步补：

1. nightly 1h soak
2. overnight replay
3. `*RegressionTests.swift`
4. DEBUG 面板 M11 tab
5. 真机辅助验收清单

这些都重要，但不应该压过 A/B/C 阶段。

---

## 5. 当前就能落地的 M11 最小范围

如果从“本周就开始做”的角度看，M11 最小范围建议是：

### 5.1 场景格式 v1

先支持：

- metadata
- timeline
- fault
- 最小 assertions

暂时不要一开始就做过重 schema。

### 5.2 结构化 JSONL 输出

先把 headless 输出改成：

```json
{"event":"scenario_started","scenario":"basic-connect","ts":"..."}
{"event":"fault_applied","type":"packet_loss","value":0.05,"ts":"..."}
{"event":"scenario_completed","scenario":"basic-connect","ts":"..."}
```

核心要求：

- 字段稳定
- 便于 grep / parser / CI artifact 消费
- 避免后续工具链反复适配格式漂移

### 5.3 三类 smoke 场景

建议第一批先做：

1. `smoke/basic-connect.json`
2. `faults/packet-loss-5pct.json`
3. `ota/ota-happy-path.json`

理由：

- 分别对应 M3 / M5-M8 / M6 的关键主路径
- 这 3 个场景对系统回归价值最高
- 实现成本远小于 overnight soak

### 5.4 最小断言能力

建议先只做：

- 场景完成
- 无异常退出
- 指定状态事件出现

不要第一阶段就做：

- 内存趋势审计
- 所有指标阈值
- 真机 FPS 自动化

这些可以放在下一轮。

---

## 6. 推荐的 M11 文档资产

M11 不是只靠代码推进，文档必须一起建立，否则回归资产会迅速失控。

建议至少补齐这 4 份文档：

### 6.1 M11 落地指南

就是当前这份文档。

作用：

- 定义顺序
- 约束范围
- 说明先做什么、后做什么

### 6.2 场景编写指南

建议新增：

- `docs/gap-closure/m11-scenario-authoring-guide.md`

内容建议：

- 场景 JSON 字段说明
- 推荐命名规范
- 时间线设计原则
- fault 场景写法
- assertion 写法
- 不推荐写法

### 6.3 CI 门控指南

建议新增：

- `docs/gap-closure/m11-ci-gating-guide.md`

内容建议：

- PR gate 跑哪些
- nightly 跑哪些
- 如何选择 smoke vs soak
- artifact 如何保留

### 6.4 M11 指标口径文档

建议新增：

- `docs/gap-closure/m11-metrics-and-thresholds.md`

内容建议：

- memory peak
- reconnect time
- packet loss tolerance
- OTA success rate
- HRV golden accuracy

重点是把“口径”写死，避免后续不同脚本各算各的。

---

## 7. 风险与取舍

### 风险 1：M11 一开始做得过重

常见错误：

- 一上来做完整 schema
- 一上来做 overnight soak
- 一上来做复杂 assertion DSL

后果：

- 工具链迟迟无法形成第一版闭环
- 团队会觉得 M11 “太大，先放一放”

规避建议：

- **先做最小场景回放 + 最小 JSONL + 最小 CI smoke**

### 风险 2：只堆场景，不做结果解释

如果只有场景，没有结果结构化和断言工具，最终只会积累很多“能跑的脚本”，但回归价值很低。

规避建议：

- M11 每做一步场景能力，都要同步补一层机器可消费结果

### 风险 3：把真机验证自动化幻想得过头

像后台 BLE 恢复、真机 FPS、系统回收行为，自动化程度天然有限。

规避建议：

- 这类场景保留“自动化预筛 + 真机辅助验收”双轨

---

## 8. 建议的实施清单

如果按最稳妥方式推进，M11 下一轮建议直接做：

1. 扩展 `Scenario` 模型到 v1
2. 给 `ScenarioEngine` 增加 timeline 能力
3. 给 `SimulatorHeadlessRunner` 增加 JSONL 输出
4. 建立 `Scenarios/smoke`、`faults`、`ota` 目录
5. 先补 3 个 PR gate 场景
6. 升级 GitHub Actions，让 PR 至少跑这 3 个场景

做到这里，M11 就已经不是“计划”，而是开始真正承担回归门控职责了。

---

## 9. 当前结论

M11 **现在完全可以开始做**，但不应该按“大一统验收系统”方式直接启动。

更合理的路径是：

- 先把现有 simulator / scenario / CI 升级成 **最小可执行回归平台**
- 再逐步叠加断言、nightly、soak、dashboard、真机验收

换句话说：

- **M10 解决的是后台 BLE 是否能恢复**
- **M11 要解决的是：这些能力以后怎么持续不退化**

因此，M11 的真正起点不是“再写更多测试”，而是：

- 让场景成为资产
- 让日志成为证据
- 让 CI 成为门控
