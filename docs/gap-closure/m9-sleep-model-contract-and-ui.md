# M9 睡眠模型输入契约与 UI 推进说明

## 结论

这一轮完成了两件关键事：

1. **冻结睡眠模型输入契约**
2. **把睡眠 UI 从“只有编排链路”推进到“已有 Hypnogram 和历史展示”**

当前还没有完成的是：

- `Models/SleepStageClassifier_v1.mlpackage`
- 真实睡眠 CoreML 推理替换

## 已冻结的输入契约

当前统一使用：

- `Sources/HRSenseCore/Entities/SleepModelFeatureSpec.swift`
- `Sources/HRSenseCore/Entities/SleepWindowInput.swift`

### contract version

- `SleepModelFeatureSpec.contractVersion = 1`

### feature 顺序

共 `18` 维，顺序固定如下：

1. `sdnn`
2. `rmssd`
3. `pnn50`
4. `mean_rr`
5. `heart_rate`
6. `lf_power`
7. `hf_power`
8. `lf_hf_ratio`
9. `total_power`
10. `sd1`
11. `sd2`
12. `sample_entropy`
13. `dfa_alpha1`
14. `stress_index`
15. `minutes_since_session_start`
16. `local_clock_minutes`
17. `hr_trend`
18. `circadian_variation`

### feature 来源

- `0...13`：`HRVMetrics`
- `14...15`：`SleepTimeContext`
- `16...17`：`SleepCXXFeatures`

### 当前工程约束

后续训练、导出和 CoreML 接入都必须遵守这份 schema：

- 名称不能漂移
- 顺序不能漂移
- `contractVersion` 不能隐式变化

如果模型训练口径发生变化，必须：

1. 新增 `contractVersion`
2. 明确文档更新
3. 明确运行时兼容策略

## UI 推进了什么

当前新增：

- `Sources/HRSenseFeature/Views/SleepHypnogramView.swift`

并在：

- `Sources/HRSenseFeature/Views/RootView.swift`

增加了：

- 当前睡眠监测区
- Hypnogram 展示
- 最近睡眠历史展示
- 当前契约版本和 feature 名称可视化

## 睡眠历史怎么来的

当前没有单独新建一层 UI 专用 ViewModel，而是继续沿用 Redux：

- `SleepAction.historyLoadRequested(limit:)`
- `SleepAction.historyLoaded([SleepSession])`
- `SleepState.recentSessions`

由：

- `Sources/HRSenseFeature/Middleware/SleepMiddleware.swift`

直接调用 `PersistenceStore.querySleepSessions(...)` 把最近睡眠会话拉回状态树。

这意味着：

- 当前 session 更新后能刷新历史
- App 冷启动时也能主动查询历史

## 与真实睡眠模型的关系

这轮**没有**把真实睡眠模型接入，因为当前仓库里还没有：

- `Models/SleepStageClassifier_v1.mlpackage`

当前 `Models` 里仍然只有：

- `Models/StressClassifier_v1.mlpackage`

它属于 M8 的压力/基线分类模型，不是睡眠分期模型。

更新：

- 当前本地已经生成了 `Models/SleepStageClassifier_v1.mlpackage`
- 但这份文件是 placeholder 版，不是最终训练模型
- `SleepStageService` 当前已调整为：
  - **优先加载 sleep-stage CoreML 模型**
  - **加载失败或模型不可用时回退到规则推理**

## 下一步

等真实模型到位后，建议按下面顺序替换：

1. 把 `SleepStageClassifier_v1.mlpackage` 放到 `Models` 目录
2. 为 `sleep-stage` 任务加载模型
3. 校验模型 metadata：
   - `task = sleep-stage`
   - `featureContractVersion = 1`
   - `modelVersion`
4. 用 `SleepModelFeatureSpec` 生成输入
5. 用真实 CoreML 输出替换当前 `SleepStageService` 的 fallback 规则

## 当前边界

虽然 UI 已经能显示 hypnogram 和最近睡眠历史，但现在展示的睡眠阶段仍然来自：

- `SleepMiddleware` + `SleepStageService` fallback 规则

不是来自真实睡眠 CoreML 模型。
