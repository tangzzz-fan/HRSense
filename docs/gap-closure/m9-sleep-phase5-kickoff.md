# M9 睡眠分期阶段 5 启动说明

## 为什么现在开始阶段 5

`M9` 阶段 5 依赖的两条基础输入已经具备：

- `M8` 已经有 `RR -> HRV -> FeatureVector` 的计算主链路
- `M9` 阶段 1~4 已经有 `SleepSession`、持久化边界与保留/归档基础设施

这意味着睡眠分期当前真正缺的，不再是“底层数据没有”，而是：

- 缺少一个独立的 `SleepInferenceRepository` 抽象
- 缺少一个可替换的 `SleepStageService`
- 缺少一条先可运行、后可替换为真实 CoreML 模型的启动实现

## 本轮补齐了什么

### 1. 先把阶段 5 的接口落下来

本轮先增加：

- `Sources/HRSenseCore/Repositories/SleepInferenceRepository.swift`
- `Sources/HRSenseCore/Entities/SleepStagePrediction.swift`

目的不是马上把整夜睡眠链路全部接完，而是先固定：

- 上层拿到的睡眠分期结果长什么样
- Data 层如何对外暴露睡眠推理能力
- 后续从规则回退切换到真实模型时，Feature/Middleware 不需要一起改接口

### 1.1 睡眠窗口输入契约已开始固化

这轮进一步补了阶段 5 最关键的一层：

- `Sources/HRSenseCore/Entities/SleepWindowInput.swift`

当前睡眠输入不再只理解成“给一份 `HRVMetrics`”，而是明确拆成：

1. `HRVMetrics`
2. `SleepTimeContext`
3. `SleepCXXFeatures`

这样做的原因是睡眠分期天然依赖：

- 当前窗口的 HRV 指标
- 这个窗口处在整夜中的什么位置
- 更长时窗趋势特征（如 `hrTrend`、`circadianVariation`）

如果现在不先把输入契约固化，后面一旦补：

- C++ 新特征
- 真正的 CoreML 睡眠模型
- `SleepMiddleware`

接口会在多个层之间来回漂移。

### 2. 先提供可运行的 Bootstrap Service

本轮新增：

- `Sources/HRSenseData/ML/SleepStageService.swift`
- `Sources/HRSenseData/Repositories/SleepInferenceRepositoryImpl.swift`

当前实现策略是：

- **先用规则回退**完成 `Wake / Light / Deep / REM` 四分类输出
- 输入改为消费 `SleepWindowInput`
- 保留 `modelVersion`
- 让测试、Redux 接线、持久化流水线都可以先跑通

这一步的核心目的是**先固定 pipeline 形状，而不是假装真实模型已经就位**。

## 为什么不直接硬上真实模型

阶段 5 当前还有两个明显缺口：

1. `SleepStageClassifier_v1.mlpackage` 还没有进入工程资产与加载链路
2. plans 里提到的 C++ 特征扩展：
   - `hrs_compute_hr_trend()`
   - `hrs_compute_circadian_variation()`
   还没有落到 `HRSenseComputeCxx`

如果现在强行写“完整 CoreML 睡眠服务”，会立即遇到三个问题：

- 输入特征契约不稳定
- 模型资产未就绪，运行路径只能半真半假
- Feature/Middleware 层会被迫围绕临时实现反复改接口

因此本轮采用更稳妥的启动顺序：

1. **先固化仓储接口**
2. **先给出可测试的回退实现**
3. **再补模型资产与特征扩展**
4. **最后接入 SleepMiddleware / SleepState / Hypnogram**

## 当前实现边界

在本轮继续推进后，阶段 5 已经不再只是“启动态”，而是具备了**最小可运行编排链路**。当前已经具备：

- `SleepInferenceRepository`
- `SleepStageService`
- `SleepWindowInput`
- `SleepMiddleware`
- `SleepState`
- `SleepAction`
- `SleepSession` 自动持久化接线

但这仍然不等于阶段 5 已经完成，当前仍未完成：

- 还没有真实 `CoreML` 睡眠模型加载
- 还没有真正的 Hypnogram 展示链路
- 还没有 `hrs_compute_hr_trend()` / `hrs_compute_circadian_variation()` 的 C++ 实现
- 还没有把当前 Swift 占位特征替换成真实 C++ 睡眠特征

但已经具备下面这些可以继续推进的前置条件：

- 睡眠分期输出类型稳定
- 睡眠推理仓储边界稳定
- 可先用假模型/规则回退驱动上层联调

## 下一步实施建议

当前阶段之后，建议严格按下面顺序继续，而不是直接跳去做最终 UI：

1. **补 C++ 特征扩展**
   - `hr trend`
   - `circadian variation`

2. **补睡眠模型资产加载**
   - 增加 `SleepStageClassifier_v1.mlpackage`
   - 明确输入输出 feature 名称、类别标签与 `modelVersion`

3. **把 `SleepWindowInput` 切到真实 C++ 输出**
   - 用真实 `hrTrend`
   - 用真实 `circadianVariation`
   - 去掉当前 Swift 占位推导逻辑

4. **接图表层**
   - `SleepHypnogramView` 数据源
   - 历史睡眠查询

## 验证建议

当前阶段建议最少覆盖：

- 高压力窗口回退到 `Wake`
- 高副交感窗口回退到 `Deep`
- `modelVersion` 能透出到上层
- 后续真实模型接入时，沿用同一组 repository 测试外壳
