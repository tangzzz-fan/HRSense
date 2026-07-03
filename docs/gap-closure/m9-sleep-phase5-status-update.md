# M9 阶段 5 当前完成度、C++ 特征与 UI 状态说明

## 结论先说

`M9` 阶段 5 **还没有完成**。

当前最准确的状态是：

- **已完成**：睡眠分期的输入契约、仓储边界、Redux 编排最小闭环、C++ 睡眠特征基础接线、Hypnogram/历史展示基础 UI
- **未完成**：真实 CoreML 睡眠模型、完整展示产品化、C++ 特征与模型口径联调

也就是说，阶段 5 现在已经从“只有规划”推进到了“**可以运行的工程骨架 + 最小编排链路**”，但还没有到 plans 里“睡眠分期模型”真正完成的状态。

## 已完成部分

### 1. 输入契约

当前已经有稳定的睡眠窗口输入模型：

- `Sources/HRSenseCore/Entities/SleepWindowInput.swift`

其中明确固化了三类输入：

1. `HRVMetrics`
2. `SleepTimeContext`
3. `SleepCXXFeatures`

这一步的价值是先固定训练/推理的输入形状，避免后面真实模型接入时接口漂移。

### 2. 睡眠推理边界

当前已经有：

- `Sources/HRSenseCore/Repositories/SleepInferenceRepository.swift`
- `Sources/HRSenseCore/Entities/SleepStagePrediction.swift`
- `Sources/HRSenseData/ML/SleepStageService.swift`
- `Sources/HRSenseData/Repositories/SleepInferenceRepositoryImpl.swift`

这意味着：

- Feature 层已经可以通过协议驱动睡眠推理
- 当前先用 fallback 规则服务跑通 pipeline
- 以后替换为真实 CoreML 模型时，不需要推倒 Redux 和持久化接线

### 3. Redux 编排链路

当前已经有：

- `Sources/HRSenseFeature/Actions/SleepAction.swift`
- `Sources/HRSenseFeature/State/SleepState.swift`
- `Sources/HRSenseFeature/Middleware/SleepMiddleware.swift`

并且已经接入：

- 根 `Action`
- 根 `AppState`
- 根 `AppReducer`
- `AppComposition`

当前可运行链路是：

`HR/RR -> HRVMetrics -> SleepWindowInput -> SleepInference -> SleepSession -> Persistence`

### 4. 自动持久化

当前 `SleepMiddleware` 已经能在推理完成后：

- 合并 `SleepStageSegment`
- 更新 `SleepSession`
- 调 `PersistenceStore.saveSleepSession`

这意味着阶段 5 后端链路已经具备最小落库能力。

### 5. C++ 睡眠特征接口已落地

当前已新增并接通：

- `Sources/HRSenseComputeCxx/include/hrs_compute.h`
- `Sources/HRSenseComputeCxx/hrv.cpp`
- `Sources/HRSenseCompute/ComputeBridge.swift`
- `Sources/HRSenseCore/Repositories/ComputeRepository.swift`
- `Sources/HRSenseData/Repositories/ComputeRepositoryImpl.swift`

目前已存在的 C++ 接口：

- `hrs_compute_hr_trend()`
- `hrs_compute_circadian_variation()`

当前 `SleepMiddleware` 已不再使用 Swift 本地占位算法，而是改为：

- 窗口内 `heartRate` 序列 -> `hrs_compute_hr_trend()`
- 近期 `RMSSD` 历史序列 -> `hrs_compute_circadian_variation()`

### 6. 睡眠模型输入契约已冻结

当前已新增：

- `Sources/HRSenseCore/Entities/SleepModelFeatureSpec.swift`

这份定义明确冻结了：

- feature 名称
- feature 顺序
- `contractVersion = 1`

当前睡眠模型输入共 `18` 维，已经从“隐式约定”升级为“显式 schema”。

### 7. 睡眠 UI 已进入可展示阶段

当前已新增：

- `Sources/HRSenseFeature/Views/SleepHypnogramView.swift`

并在 `RootView` 中接入：

- 当前睡眠监测区
- Hypnogram 展示
- 最近睡眠历史展示

同时 `SleepMiddleware` 已支持通过 `PersistenceStore.querySleepSessions(...)` 拉取最近睡眠会话并回填到 `SleepState.recentSessions`。

### 8. Python 模型生成脚本已提供

当前 `tools` 目录下已具备：

- `tools/create_placeholder_model.py`
- `tools/create_sleep_placeholder_model.py`

含义分别是：

- stress 占位模型生成脚本
- sleep-stage 占位模型生成脚本

这意味着工程侧已经具备“先生成占位 `mlpackage` 跑通链路，再替换为真实训练模型”的工具基础。

### 9. 本地 sleep placeholder model 已生成

当前本地已经实际生成：

- `Models/SleepStageClassifier_v1.mlpackage`

这份模型当前是：

- Python 生成的 placeholder 模型
- 输入 `18` 维
- 输出 `Wake / Light / Deep / REM`
- metadata:
  - `task = sleep-stage`
  - `featureContractVersion = 1`
  - `modelVersion = 1.0.0-placeholder`

需要注意：

- 它说明工程链路已经可以真实加载 sleep `mlpackage`
- 但它仍然不是最终训练好的产品模型

## 未完成部分

### 1. 真实睡眠模型还没接入

plans 里要求的：

- `Models/SleepStageClassifier_v1.mlpackage`

目前**还没有真实进入工程运行链路**。

当前 `SleepStageService` 仍然是：

- 基于 `SleepWindowInput`
- 用规则回退输出 `Wake / Light / Deep / REM`

所以现在它更像：

- **可运行占位推理服务**

而不是：

- **真实睡眠 CoreML 推理服务**

### 2. 真实 C++ 特征语义仍需继续收敛

plans 里明确提到两个 C++ 函数：

- `hrs_compute_hr_trend()`
- `hrs_compute_circadian_variation()`

这两个函数现在**已经添加并接线完成**，但当前实现仍然属于第一版工程实现，而不是最终建模口径：

- `hrs_compute_hr_trend()`
  - 当前实现：对窗口内 `heartRate` 序列做最小二乘线性回归，返回 slope
- `hrs_compute_circadian_variation()`
  - 当前实现：对近期 `RMSSD` 历史序列计算归一化振幅 `(max - min) / mean`

这意味着：

- **接口层已经完成**
- **工程链路已经完成**
- **建模语义仍可能继续迭代**

## 这两个 C++ 函数应该做什么

### 1. `hrs_compute_hr_trend()`

目标：

- 计算一个睡眠窗口内心率变化趋势

当前实现语义：

- 输入：窗口内的 `heartRate` 序列
- 输出：线性回归斜率

解释：

- 斜率为负：心率整体在下降，更接近入睡/深睡阶段
- 斜率接近 0：心率较稳定
- 斜率为正：心率抬升，可能更接近觉醒或 REM 波动

当前实现形式：

- 对 `(timeIndex, heartRate)` 做最小二乘线性回归
- 返回 slope

### 2. `hrs_compute_circadian_variation()`

目标：

- 计算更长时间尺度上的 HRV/HR 振幅变化

当前实现语义：

- 输入：多个相邻时间窗的 `RMSSD` 序列
- 输出：归一化振幅 `(max - min) / mean`

解释：

- 睡眠分期不是只看当前 5 分钟窗口
- 还需要知道“这一段在整夜中的相对位置与长期变化”
- 这个特征能帮助模型区分：
  - 入睡早期
  - 稳定深睡
  - 后半夜 REM 增多
  - 觉醒回升

当前风险点：

- 这个函数天然比 `hrs_compute_hr_trend()` 更依赖**多窗口历史上下文**
- 当前只保留了 `SleepMiddleware` 内部的近期 `RMSSD` 历史，暂时还不是跨整夜的完整 circadian 建模
- 后续如果模型训练要求变化，最可能继续调整的是：
  - 输入窗口数量
  - 输入摘要字段
  - 时间跨度
  - 归一化方式

## 当前阶段 5 是否已形成最小闭环

### 1. 后端编排最小闭环

**是，已经成立。**

现在已经可以做到：

- 连接后进入 sleep monitoring
- 收到 `HRVMetrics` 后构造 `SleepWindowInput`
- 调睡眠推理仓储
- 生成 `SleepStagePrediction`
- 合并 `SleepSession`
- 写入持久化层

### 2. 产品展示最小闭环

**还没有。**

因为还缺：

- `SleepHypnogramView`
- 睡眠历史查询展示
- 真实模型
- C++ 特征与模型口径联调
- 完整的 UI 产品化打磨

## 下一步应做什么

因为 C++ 两个函数已经接好，当前下一步应当继续推进：

1. **把 `SleepStageClassifier_v1.mlpackage` 放到 `Models` 目录**
2. **为 `sleep-stage` 任务接真实 CoreML 加载**
3. **按 `SleepModelFeatureSpec` 校验 feature contract**
4. **用真实 CoreML 输出替换 fallback 睡眠推理**
5. **继续 UI 产品化和历史交互**

## 对 plans 的更新理解

如果对照 `docs/plans/09-m9-storage-visualization-sleep.md`，当前阶段 5 的完成度更适合表述为：

- `SleepStageService.swift`：**已落 bootstrap 版**
- `SleepInferenceRepositoryImpl.swift`：**已落**
- `SleepWindowInput`：**已补，属于 plans 的必要前置契约**
- `SleepModelFeatureSpec`：**已补，contract 已冻结**
- `SleepMiddleware / SleepState / SleepAction`：**已落，可运行**
- `hrs_compute_hr_trend()`：**已完成第一版**
- `hrs_compute_circadian_variation()`：**已完成第一版**
- `SleepHypnogramView`：**已落基础版**
- 睡眠历史查询展示：**已落基础版**
- `tools/create_sleep_placeholder_model.py`：**已落**
- `Models/SleepStageClassifier_v1.mlpackage`：**已在本地生成 placeholder 版**
- 真实训练版 `SleepStageClassifier_v1.mlpackage`：**未完成**
