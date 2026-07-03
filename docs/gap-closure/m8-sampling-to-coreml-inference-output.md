# M8 采样数据到 CoreML 推理与输出说明

## 先辨析一个前提

如果把当前项目的推理链简单理解成：

- `采样数据 -> CoreML -> 输出`

这个说法方向是对的，但还不够准确。

当前项目实际上有**两条不同的模型使用链路**：

1. **Stress / Baseline 推理链**
   - 采样输入是 `HeartRateSample` 中的 HR / RR
   - CoreML 消费的是 **14 维 HRV 特征**
   - 输出是 `InferenceResult`

2. **Sleep Stage 推理链**
   - 采样输入同样来自实时 HR / RR
   - 先构造成 `SleepWindowInput`
   - CoreML 消费的是 **18 维睡眠窗口特征**
   - 输出是 `SleepStagePrediction`

而高频 waveform 当前主要用于：

- 实时展示
- 统计指标
- 后续存储

**不是当前 CoreML 的直接输入。**

## 当前项目中的真实输入源

## 1. BLE 进入 App 的原始数据

设备通过 BLE 把两类关键数据送进 App：

- **低频结构化数据**
  - 心率
  - RR intervals
  - battery / sensorStatus / sampleSeq

- **高频波形数据**
  - ECG waveform block
  - PPG waveform block

当前 CoreML 真正用到的是第一类，也就是：

- `HeartRateSample`

对应解析入口在：

- `BLECentralDataSource.consume(frame:)`
- `BLEDataParser.parseSample(...)`

在这里，协议层 `DeviceSample` 会被转换成领域层：

- `HeartRateSample`

## 2. 为什么当前模型不直接吃 waveform

当前工程设计里，waveform 和推理是拆开的：

- waveform 用于实时显示和链路观察
- 模型当前吃的是更轻量、稳定、低频的特征向量

这样做的原因是：

1. 端上实时波形吞吐高，不适合作为当前最小版推理输入
2. stress / sleep 第一版模型更适合基于 HRV/时间上下文特征
3. 特征向量更容易冻结 contract、调试、回归和替换模型

所以，当前不是：

- `ECG/PPG 原始波形 -> CoreML`

而是：

- `HR/RR -> 特征工程 -> CoreML`

## 一、Stress / Baseline 推理链

## 1. 输入采样是什么

stress 推理链的上游采样来自：

- `HeartRateSample.heartRate`
- `HeartRateSample.rrIntervals`

也就是说，模型不是直接用 BPM 数字本身去推，而是主要依赖：

- RR 间期序列

因为 RR 才是 HRV 特征计算的核心输入。

## 2. 采样如何被累积

在：

- `ComputeMiddleware`

中，系统会持续监听：

- `heartRateReceived(samples)`

然后把每个 sample 里的 RR interval 逐个追加到滑动窗口中。

当前策略是：

- 窗口长度：5 分钟
- 计算步长：10 秒

这意味着：

- 不是每来一个 sample 就立即推理
- 而是先累积 RR 数据
- 满足条件后再触发一次 HRV 计算

## 3. 特征是如何生成的

在 `ComputeMiddleware` 中，窗口满足触发条件后会调用：

- `computeRepo.computeHRV(from:)`

实际实现落在：

- `ComputeRepositoryImpl`
- `ComputeBridge`

这里会调用 C++ 计算层，产出：

- `HRVMetrics`

当前 `HRVMetrics` 一共 14 维：

1. `sdnn`
2. `rmssd`
3. `pnn50`
4. `meanRR`
5. `hr`
6. `lfPower`
7. `hfPower`
8. `lfHfRatio`
9. `totalPower`
10. `sd1`
11. `sd2`
12. `sampleEntropy`
13. `dfaAlpha1`
14. `stressIndex`

随后这些指标会被封装成：

- `FeatureVector`

其 contract 当前为：

- 维度：14
- `contractVersion = 1`

## 4. CoreML 如何被调用

当 `ComputeMiddleware` 派发：

- `featuresExtracted(features)`

后，`InferenceMiddleware` 会调用：

- `InferenceRepository.runInference(features:)`

实际实现是：

- `InferenceRepositoryImpl`

内部再调用：

- `CoreMLService.predict(features:)`

## 5. CoreML 输入长什么样

stress 模型当前约定为：

- 输入特征名：`features`
- 输入类型：`MLMultiArray`
- 特征维度：14

`CoreMLService` 会把 `[Float]` 写入：

- `MLMultiArray(shape: [14], dataType: .float32)`

然后构造：

- `MLDictionaryFeatureProvider`

送进模型。

## 6. 模型选择与 fallback

stress 链默认使用：

- `ModelSelectionRequest.stressClassifierV1`

优先选择：

- `StressClassifier_v1`

如果本地没有找到可用模型，则 `CoreMLService` 会回落到：

- `fallback-rule-engine`

当前 fallback 逻辑基于：

- `rmssd`
- `hr`

简单区分：

- `Stress`
- `Baseline`

## 7. 输出是什么

stress 推理最终输出为：

- `InferenceResult`

字段包括：

- `label`
  - 例如 `Baseline` / `Stress`
- `probabilities`
  - 各类别概率
- `inferenceTimeMs`
  - 推理时延
- `timestamp`
  - 推理完成时间
- `modelVersion`
  - 实际使用的模型版本或 fallback 版本

随后它会被写入 Redux：

- `state.inference.latestResult`

并在 App 中展示。

## 8. 这条链的完整文字图

可以把 stress 链描述为：

1. BLE 收到 `DeviceSample`
2. 解析成 `HeartRateSample`
3. 进入 `heartRateReceived`
4. `ComputeMiddleware` 收集 RR 窗口
5. C++ 计算 `HRVMetrics`
6. 组装成 14 维 `FeatureVector`
7. `InferenceMiddleware` 调用 `InferenceRepository`
8. `CoreMLService` 执行 stress model 或 fallback
9. 产出 `InferenceResult`
10. Redux 更新
11. UI 展示推理标签与概率

## 二、Sleep Stage 推理链

## 1. 输入采样是什么

sleep 推理链上游同样来自：

- 实时 `HeartRateSample`
- 上游已计算出的 `HRVMetrics`

不同点在于，sleep 不是直接拿 14 维 stress 特征去推，而是构造成：

- `SleepWindowInput`

## 2. SleepWindowInput 是怎么形成的

在：

- `SleepMiddleware`

中，当收到：

- `hrvComputed(metrics)`

会进一步拼一个睡眠窗口输入。

这个输入由三部分组成：

1. `metrics: HRVMetrics`
2. `timeContext: SleepTimeContext`
3. `cxxFeatures: SleepCXXFeatures`

其中：

- `SleepTimeContext` 包含
  - `windowStart`
  - `windowEnd`
  - `minutesSinceSessionStart`
  - `localClockMinutes`

- `SleepCXXFeatures` 当前包含
  - `hrTrend`
  - `circadianVariation`

后两项来自：

- `computeRepository.computeSleepFeatures(...)`

如果暂时算不出来，则回退为默认值。

## 3. Sleep 模型吃的特征维度

sleep 模型当前 contract 固定为：

- `contractVersion = 1`
- 特征数：18

由 `SleepModelFeatureSpec` 统一定义顺序。

18 维分别是：

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

## 4. CoreML 如何被调用

sleep 链通过：

- `SleepInferenceRepository`

解耦上层 middleware 和底层模型服务。

其实现为：

- `SleepInferenceRepositoryImpl`

内部调用：

- `SleepStageService.predict(input:)`

`SleepStageService` 再调用：

- `CoreMLService.predict(features: input.toFeatureVector())`

## 5. 模型选择与加载

sleep 链默认使用：

- `ModelSelectionRequest.sleepStageClassifierV1`

优先模型名：

- `SleepStageClassifier_v1`

模型查找顺序大致是：

1. 显式传入的 `modelURL`
2. app bundle 内模型
3. 工程根目录下 `Models/SleepStageClassifier_v1.mlpackage`

## 6. 输出是什么

sleep 推理最终输出为：

- `SleepStagePrediction`

字段包括：

- `stage`
  - `wake / light / deep / rem`
- `confidence`
  - 当前最佳阶段置信度
- `probabilities`
  - 各睡眠阶段概率
- `modelVersion`
  - 实际使用模型或 fallback 版本
- `timestamp`
  - 推理时间

随后 `SleepMiddleware` 会继续把它并入：

- `SleepSession`

用于：

- 历史展示
- hypnogram 视图
- 持久化

## 7. fallback 是什么

如果 sleep CoreML 模型不可用，`SleepStageService` 会回退到：

- `sleep-stage-fallback-v1`

其规则会综合：

- `metrics.hr`
- `metrics.stressIndex`
- `metrics.rmssd`
- `metrics.sampleEntropy`
- `lf/hf`
- `hrTrend`
- `circadianVariation`
- `minutesSinceSessionStart`
- `localClockMinutes`

输出一个近似的：

- `Wake / Light / Deep / REM`

概率分布。

## 三、当前项目中“采样数据到 CoreML”的准确表述

如果要给当前项目做一句准确描述，应该这样说：

> **当前项目并不是把原始 waveform 直接输入 CoreML，而是先从 BLE 采样中提取 HR/RR，再通过 C++ 与时间上下文构造成定长特征向量，最后送入 stress 或 sleep 的 CoreML 模型进行推理。**

## 四、当前 CoreML 输出最终在 App 里表现为什么

### 1. Stress 链输出

App 中最终能看到：

- `Baseline` / `Stress`
- 对应概率
- `modelVersion`
- 推理时间等诊断信息

### 2. Sleep 链输出

当前工程里最终会沉淀为：

- `SleepStagePrediction`
- `SleepSession`
- `SleepStageSegment`

并用于：

- 睡眠历史
- hypnogram
- 阶段统计

## 五、这条链路当前的边界

为了避免误解，最后再明确一次边界：

### 当前已经成立

- BLE 采样进入 App
- HR/RR 驱动 stress 推理
- 睡眠窗口输入可驱动 sleep 推理
- CoreMLService 可以选模型、执行推理、输出版本号

### 当前尚未做成“波形直接推理”

- ECG / PPG 原始高频波形当前没有直接喂给模型
- 当前 waveform 更多是展示链和存储链的一部分

如果未来要走“原始波形直接进模型”的路径，需要新增：

- 波形窗口切片
- 波形预处理
- 波形模型输入 contract
- 更高等级的吞吐与背压治理

## 六、总结

当前项目的 CoreML 使用方式可以总结成两句话：

1. **stress 推理：`HeartRateSample -> RR窗口 -> HRVMetrics -> 14维特征 -> CoreML -> InferenceResult`**
2. **sleep 推理：`HeartRateSample/HRVMetrics -> SleepWindowInput(18维) -> CoreML -> SleepStagePrediction`**

所以，当前“采样数据如何被 CoreML 使用”的核心答案不是：

- 波形直接进模型

而是：

- **采样先被加工成稳定的、定长的、可冻结 contract 的特征向量，再进入 CoreML。**
