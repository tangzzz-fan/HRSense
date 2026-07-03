# M9 阶段 5 当前完成度与 C++ 特征接线说明

## 结论先说

`M9` 阶段 5 **还没有完成**。

当前最准确的状态是：

- **已完成**：睡眠分期的输入契约、仓储边界、Redux 编排最小闭环、C++ 睡眠特征基础接线
- **未完成**：真实 CoreML 睡眠模型、睡眠图表展示闭环、C++ 特征与模型口径联调

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

## 下一步应做什么

因为这两个 C++ 函数**已经添加并接线完成**，所以下一步应当继续推进：

1. **校准 C++ 特征口径**
2. **接真实 `SleepStageClassifier_v1.mlpackage`**
3. **把模型输入 feature 名称与顺序固定**
4. **继续睡眠 UI / Hypnogram**

## 对 plans 的更新理解

如果对照 `docs/plans/09-m9-storage-visualization-sleep.md`，当前阶段 5 的完成度更适合表述为：

- `SleepStageService.swift`：**已落 bootstrap 版**
- `SleepInferenceRepositoryImpl.swift`：**已落**
- `SleepWindowInput`：**已补，属于 plans 的必要前置契约**
- `SleepMiddleware / SleepState / SleepAction`：**已落，可运行**
- `hrs_compute_hr_trend()`：**已完成第一版**
- `hrs_compute_circadian_variation()`：**已完成第一版**
- `SleepStageClassifier_v1.mlpackage`：**未完成**
- `SleepHypnogramView`：**未完成**
