# M11 · 健壮性最终验收（故障注入 + 端到端自动化）— 实施计划

## 摘要

M11 是系统性验证里程碑：利用场景脚本库、CI 管道和长时间稳定性测试，验证系统在所有异常和正常路径下均保持稳健。M11 依赖于 M5-M10 全部完成。

---

## 步骤 1：场景 JSON Schema 与解析器

在 `Sources/HRSenseSimulatorKit/Scenario/` 中创建 `ScenarioScript` Codable 模型：

```jsonc
{
  "scenarioVersion": "1.0",
  "metadata": { "id": "e2e-ota-resume", "name": "OTA中断后续传", "tags": ["ota", "fault", "smoke"] },
  "device": { "model": "HRSense-Sim", "fwVersion": "2.0.0", "capabilities": ["HEART_RATE","OTA_DFU"], "initialBattery": 85 },
  "timeline": [
    { "atMs": 0, "action": "set_data_mode", "mode": "resting", "params": { "hrBpm": 70 } },
    { "atMs": 120000, "action": "fault", "type": "packet_loss", "probability": 0.05, "durationMs": 30000 },
    { "atMs": 180000, "action": "assert", "id": "check_ota_version", "type": "device_info", "field": "fwVersion", "op": "eq", "value": "2.1.0" }
  ],
  "assertions": { "invariants": [
    { "id": "no_crash", "type": "crash", "op": "eq", "value": 0 },
    { "id": "memory_lt_200mb", "type": "memory", "op": "lt", "field": "peakBytes", "value": 209715200 }
  ]}
}
```

故障类型：`packet_loss`、`latency`、`disconnect`、`crc_corruption`、`illegal_frame`、`battery_drop`、`block_reorder`、`block_truncation`、`withhold_response`。

---

## 步骤 2：增强 ScenarioEngine 以执行时间线

扩展 `ScenarioEngine.swift`，按 `atMs` 顺序处理时间线事件，连接所有现有组件（DataGenerator、FaultInjector、OTA 状态机、电池系统）。

---

## 步骤 3：Headless 模式增强

新增命令行参数：
- `--log-format json` — JSONL 指标流输出
- `--log-file <path>` — 写入文件
- `--metrics-port <port>` — HTTP 控制端点（`/status`、`/metrics`、`/fault/activate`、`/scenario/pause`、`/shutdown`）

---

## 步骤 4：M11AssertionRunner CLI 工具

新增 `Tools/M11AssertionRunner/` 可执行 target，解析模拟器 JSONL 输出并与场景中的 `assert` 条目对比，生成 JSON/JUnit 报告。

---

## 步骤 5：场景库填充

```
Scenarios/
├── schema/scenario-v1.schema.json
├── datasets/night-sleep-8h.csv, exercise-30min.csv, resting-1h.csv
├── smoke/basic-connect.json, hr-reconnect.json, command-roundtrip.json
├── faults/packet-loss-5pct.json, disconnect-spam.json, crc-burst.json, ...
├── ota/ota-happy-path.json, ota-resume.json, ota-window-retransmit.json, ...
├── stability/soak-1h.json, overnight-replay.json
└── regression/regression-smoke.json, regression-full.json
```

---

## 步骤 6：CI 管道（GitHub Actions）

- `ci-pull-request.yml`：PR 门控 — 构建 + 单元测试 + 冒烟/故障/OTA 场景
- `ci-nightly.yml`：每日 — 1h 浸泡测试 + 8h 整夜重放

---

## 步骤 7：SoakAnalyzer 工具

新增 `Tools/SoakAnalyzer/`，分析 JSONL 日志文件：
- 内存峰值 < 200 MB
- 零崩溃
- 内存趋势 < 5 KB/min
- 重连成功率

---

## 步骤 8：回归单元测试增强

在每个模块的 `Tests/` 下新增 `*RegressionTests.swift`，重点关注 M5-M10 期间实际发现的 bug。

---

## 步骤 9：指标摘要仪表板

在 DEBUG 面板中新增「M11 指标」选项卡，展示所有来源的实时指标及 PASS/FAIL 状态。

---

## 步骤 10：真机辅助验收

在真机 + 模拟器环境下手动验证完整 `regression-smoke.json`，确认波形渲染 fps、后台 BLE 恢复路径。

---

## 综合指标阈值

| 指标 | 阈值 | 来源 |
|---|---|---|
| 连续无崩溃 | ≥ 60 min | M11 |
| 内存峰值 | < 200 MB | M11 |
| 内存趋势 | < 5 KB/min | M11 |
| 重连时间 | < 30s | M3 |
| 丢包容忍 | 5% 丢包下 HR 连续 | M3 |
| 波形吞吐 | ≥ 128 Hz × 2B/sample | M5 |
| 丢块率（无注入） | ≈ 0% | M5 |
| 渲染帧率 | ≥ 55 fps（真机） | M5 |
| OTA 成功率 | 连续 10 次 100% | M6 |
| HRV 黄金值匹配 | 误差 < 阈值 | M8 |
| 推理完整度 | 窗口满时推理触发 | M8 |

## 预估工作量：21-29 天
