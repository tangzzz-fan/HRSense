# M11 · 场景编写指南

## 1. 目标

M11 的核心资产之一不是测试代码，而是 **场景脚本库**。

如果场景写法不统一，后续会很快出现这些问题：

- 同类场景命名混乱
- timeline 粒度不一致
- 故障注入参数不可比较
- CI 里很难挑选 smoke / fault / soak
- 回归失败后难以定位是哪类场景退化

因此在 M11 里，场景 JSON 必须像代码一样被设计，而不是随手堆文件。

---

## 2. 当前建议的场景分类

推荐按目录管理：

```text
Scenarios/
├── smoke/
├── faults/
├── ota/
├── stability/
├── regression/
└── schema/
```

### `smoke/`

用途：

- 验证关键主路径是否还通
- 用于 PR 级门控

建议场景：

- `basic-connect.json`
- `hr-reconnect.json`
- `command-roundtrip.json`

### `faults/`

用途：

- 验证丢包、延迟、CRC 错误、异常帧等抗扰能力

建议场景：

- `packet-loss-5pct.json`
- `crc-burst.json`
- `disconnect-spam.json`

### `ota/`

用途：

- 验证 OTA happy path、重试、续传、窗口 ACK

建议场景：

- `ota-happy-path.json`
- `ota-resume.json`
- `ota-window-retransmit.json`

### `stability/`

用途：

- 长时间运行
- soak / overnight replay

建议场景：

- `soak-1h.json`
- `overnight-replay.json`

### `regression/`

用途：

- 固化已修复 bug
- 防止历史问题回归

建议场景：

- `regression-smoke.json`
- `regression-full.json`

---

## 3. 命名规范

### 文件名规范

统一使用：

```text
<domain>-<behavior>.json
```

例如：

- `basic-connect.json`
- `packet-loss-5pct.json`
- `ota-resume.json`

不要使用：

- `test1.json`
- `new_scenario.json`
- `最终版.json`

### metadata.id 规范

建议：

```text
<group>.<name>
```

例如：

- `smoke.basic-connect`
- `faults.packet-loss-5pct`
- `ota.ota-resume`

### metadata.tags 规范

建议标签只使用少量稳定词汇：

- `smoke`
- `fault`
- `ota`
- `stability`
- `regression`
- `sleep`
- `waveform`
- `background`

不要随意创造大量新 tag，否则后续筛选价值会变差。

---

## 4. 场景设计原则

### 原则 1：一个场景只验证一个主目标

好例子：

- `packet-loss-5pct.json` 主要验证 5% 丢包下 HR 连续性
- `ota-resume.json` 主要验证 OTA 中断后续传

坏例子：

- 一个场景同时测 reconnect、waveform、OTA、sleep、background

这类“大杂烩场景”一旦失败，定位成本极高。

### 原则 2：timeline 要尽量业务化，不要纯技术动作堆砌

好例子：

1. 开始广告
2. 建立连接
3. 启动数据流
4. 注入 5% 丢包
5. 断言连接仍然可恢复

坏例子：

1. wait 10s
2. wait 5s
3. wait 8s
4. 再 random inject fault

如果 timeline 自己都不表达清楚业务意图，后续别人就无法维护。

### 原则 3：先定义成功标准，再写场景

每个场景在编写前都应该先回答：

- 这个场景的 PASS 条件是什么？
- 失败时最应该看哪一类指标？
- 它应该属于 PR gate 还是 nightly？

---

## 5. 最小场景结构建议

第一版建议至少包含：

```json
{
  "scenarioVersion": "1.0",
  "metadata": {
    "id": "smoke.basic-connect",
    "name": "基础连接冒烟",
    "tags": ["smoke"]
  },
  "timeline": [
    { "atMs": 0, "action": "start_stream" },
    { "atMs": 5000, "action": "assert", "type": "state", "field": "connection", "op": "eq", "value": "connected" }
  ]
}
```

即使当前代码还没完全支持这些字段，也建议文档和场景资产先按这个方向收敛。

---

## 6. 故障场景写法建议

### 丢包场景

推荐：

- 故障强度写进文件名
- duration 明确
- 断言只围绕“是否保持可用”

例如：

```json
{
  "metadata": { "id": "faults.packet-loss-5pct", "tags": ["fault"] },
  "timeline": [
    { "atMs": 0, "action": "start_stream" },
    { "atMs": 30000, "action": "fault", "type": "packet_loss", "probability": 0.05, "durationMs": 30000 }
  ]
}
```

### 断连场景

关注点：

- 是否重连
- 重连时间是否在阈值内
- 重连后数据流是否继续

### CRC/非法帧场景

关注点：

- 不崩溃
- 不进入永久坏状态
- 后续正常帧仍可消费

---

## 7. OTA 场景写法建议

OTA 场景不要只看“最后是否成功”，还要关注中间阶段：

- `preparing`
- `transferring`
- `validating`
- `applying`
- `completed`

建议每个 OTA 场景至少回答：

1. 是否注入故障
2. 注入点是在窗口、校验还是应用阶段
3. 是否期待 resume / retry
4. 最终版本号是否变更

---

## 8. Soak / Stability 场景写法建议

长时间场景和 smoke 最大的不同是：

- 不能太依赖密集断言
- 更依赖周期性指标摘要

建议：

- timeline 只保留关键切换点
- 指标由 JSONL / analyzer 汇总
- 结果重点看：
  - 内存峰值
  - 内存趋势
  - crash 数
  - reconnect 成功率

---

## 9. 回归场景来源建议

`regression/` 目录的内容不要拍脑袋添加。

推荐来源：

1. 真实线上/联调 bug
2. M5-M10 期间曾修复的协议/并发/恢复问题
3. 曾经导致编译通过但运行错误的链路问题

一个好回归场景的标准是：

- 它能稳定复现曾经的问题
- 修复后可稳定通过
- 它的存在价值大于维护成本

---

## 10. PR Gate 与 Nightly 的场景选择

### PR Gate

要求：

- 运行快
- 失败信号明确
- 覆盖关键主路径

建议只放：

- 3~5 个 smoke/fault/ota 代表场景

### Nightly

要求：

- 允许运行更久
- 允许更重的指标分析

建议放：

- soak
- overnight replay
- 更大故障矩阵

不要把所有场景都塞进 PR gate，否则开发体验会很差。

---

## 11. 编写时的常见错误

### 错误 1：场景时间线过密

问题：

- 维护困难
- 失败后难以看懂

建议：

- 只有关键事件才入 timeline

### 错误 2：把随机性写得过强

问题：

- 场景结果不稳定
- CI 容易出现 flaky

建议：

- 尽量使用可重复参数
- 必要时固定随机种子

### 错误 3：没有清晰断言

问题：

- 场景能跑，但不知道到底验证了什么

建议：

- 每个场景至少写一句“这个场景的通过条件是什么”

---

## 12. 当前建议的第一批场景

如果 M11 下一轮开始做场景资产化，建议第一批就落这 5 个：

1. `smoke/basic-connect.json`
2. `smoke/hr-reconnect.json`
3. `faults/packet-loss-5pct.json`
4. `ota/ota-happy-path.json`
5. `regression/m10-background-restore-smoke.json`

这 5 个覆盖：

- 基础连接
- 重连
- 故障容忍
- OTA 主路径
- M10 新增后台恢复路径

---

## 13. 当前结论

M11 场景库的建设重点不是“多”，而是“规范、稳定、可被 CI 消费”。

因此场景编写要坚持三点：

1. **一场景一目标**
2. **文件名与 metadata 稳定**
3. **先定义通过条件，再写 timeline**

只要这三点守住，M11 的场景资产就会越积越有价值，而不是越积越乱。
