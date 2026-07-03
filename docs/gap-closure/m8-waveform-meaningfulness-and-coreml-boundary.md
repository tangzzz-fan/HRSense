# M8 波形数据是否有意义，以及如何判断是否经过 CoreML 推理

## 先给结论

在当前项目里，**“App 里能看到波形”** 和 **“这份数据已经经过 CoreML 推理”** 是两件不同的事情。

更准确地说：

- **波形展示链**：主要回答“设备来的高频数据有没有正确进入 App 并被正确展示”
- **CoreML 推理链**：主要回答“低频生理特征有没有被正确提取并送入模型，最终输出了可解释的推理结果”

所以，如果现在你在波形图中看到了图示数据，只能说明：

- waveform display pipeline 基本通了

但这**不能自动证明**：

- 数据已经进入 CoreML
- 模型输出一定有业务意义

## 一、什么叫“有意义的数据”

在当前阶段，“有意义”至少要拆成三层理解。

### 1. 工程意义

这是最低层，也是最先要满足的一层。

它回答的是：

- 这是不是一条真实、连续、时间对齐的波形流
- 不是随机 UI 占位图
- 不是只更新 metrics、没有样本

在工程意义上，一条“有意义的波形”至少要满足：

- `waveformSamplesReceived(...)` 持续出现
- 波形图能随时间滚动，而不是固定静态图
- `ECG / PPG` 切换后，展示数据集确实发生变化
- throughput / samplesPerSec / blockLossRate 不异常

### 2. 生理意义

这层回答的是：

- 这条曲线是否像 ECG / PPG 应有的形态
- 它是不是“看起来像真实信号”，而不是纯噪声或错误缩放

在当前 simulator 环境中，可做的最直接判断是：

- **ECG**
  - 具有周期性峰值
  - 峰间距与当前心率大致一致
  - 不是纯平线，也不是完全随机噪声
- **PPG**
  - 曲线更平滑
  - 也具有和心率相匹配的周期起伏
  - 相比 ECG，不应呈现同样的尖锐 QRS 风格

### 3. 业务意义

这层回答的是：

- 当前这份数据是否真的参与了你关心的模型推理
- 推理结果是否能被产品或算法逻辑解释

在当前项目中，业务意义的判断不能只看波形视图，必须看：

- `FeatureVector`
- `InferenceResult`
- `modelVersion`
- 当前使用的是哪条推理链

## 二、当前项目里，波形和 CoreML 到底是什么关系

### 当前主事实

当前项目里 CoreML 的主推理链并**不是直接吃实时 waveform**。

当前更接近真实情况的描述是：

1. 设备发来 `heartRate / RR / waveform`
2. App 里有两条相关但分开的链路

#### A. 波形展示链

```text
WaveformBlock -> BLEDataParser -> WaveformRingBuffer -> WaveformMiddleware -> WaveformState -> UI
```

这条链路的目标是：

- 实时展示
- 吞吐和丢块观测
- 为后续存储或诊断提供基础

#### B. 推理链

```text
HeartRate / RR -> ComputeMiddleware -> HRVMetrics / FeatureVector -> InferenceMiddleware -> CoreMLService -> InferenceResult -> UI
```

这条链路的目标是：

- 压力/状态推理
- 睡眠分期推理

所以，当前必须明确区分：

- **波形可见**：说明展示链路通了
- **推理可见**：说明 CoreML 链路通了

二者相关，但不是一回事。

## 三、怎么判断“这条波形不是假的”

### 1. 看 action 级证据

如果只看到：

- `waveformMetricsUpdated`

这还不够。

更可靠的证据是：

- `waveformSamplesReceived(...)`

因为它说明样本真的进了 Redux。

### 2. 看时间连续性

一条“有意义的实时波形”应该表现为：

- 图形持续滚动
- 窗口切换后仍有连续数据
- 停止 stream 后图形停止刷新

### 3. 看 ECG / PPG 是否形态不同

如果 ECG 和 PPG 切换后完全一样，通常说明至少有一项存在问题：

- 两路样本没有正确分流
- 实际只发了一路波形
- UI 始终读取同一个 sample 集合

### 4. 看 metrics 是否自洽

可以结合：

- `samplesPerSec`
- `effectiveThroughputBytesPerSec`
- `blockLossRate`

判断数据是否像真实流：

- `samplesPerSec` 应接近设定的采样率量级
- `blockLossRate` 不应长期过高
- throughput 应随 stream 打开而上升，停止后回落

## 四、怎么判断“已经经过 CoreML”

这部分一定不能只看波形图，而要看推理链自己的证据。

### 当前最直接的判断方式

在当前项目里，至少应满足下面几个条件中的大部分：

1. `featuresExtracted(...)` 已发生
2. `inferenceStarted` 已发生
3. `inferenceCompleted(...)` 已发生
4. UI 出现推理标签和概率
5. `modelVersion` 可见

也就是说，**判断是否经过 CoreML，最可靠的不是波形图，而是推理状态和推理元数据。**

### 具体看哪些信息

建议重点看：

- 最新 `FeatureVector`
- 推理结果 `label`
- `probabilities`
- `modelVersion`
- 当前是否走了 fallback

如果这些都没有，只是波形图动了，那么它仍然只是展示链，不足以证明模型在工作。

## 五、当前项目中，哪些结果已经可以认为“有一定意义”

### 1. 波形本身

当前 simulator 环境下，波形有以下意义：

- 说明高吞吐 waveform pipeline 可工作
- 说明 BLE notify、解码、ring buffer、UI 基本打通
- 可用于验证：
  - sampling continuity
  - UI render stability
  - block loss / throughput

但它的局限也很明确：

- 当前是 simulator 生成波形，不是真机真实传感器
- 因此它更适合验证**工程链路正确性**
- 不适合作为医学级或算法效果级结论

### 2. CoreML 推理结果

当前推理结果的意义也要分清楚：

- 如果是 stress placeholder / fallback：
  - 更接近工程可运行性验证
  - 不代表最终算法效果
- 如果后续换成真实训练模型：
  - 才能逐步进入业务效果验收

所以当前阶段更准确的说法是：

- **波形现在已经适合做工程链路验收**
- **CoreML 现在适合做推理链路验收**
- **二者都还不能直接等价为最终算法有效性验收**

## 六、给当前项目的一套实际验收标准

### A. 波形链验收

要判断波形图中的数据是否“工程上有意义”，建议至少验收以下项目：

1. `waveformSamplesReceived(...)` 持续出现
2. `Waveform` 区域进入 `Live`
3. ECG 波形可见，且不是平线
4. PPG 波形可见，且与 ECG 形态不同
5. `samplesPerSec` 与预期量级接近
6. `blockLossRate` 在可接受范围内

### B. 推理链验收

要判断是否已经经过 CoreML，建议至少验收以下项目：

1. `featuresExtracted(...)` 出现
2. `inferenceCompleted(...)` 出现
3. UI 可见推理结果卡片
4. UI 或诊断面板可见 `modelVersion`
5. 能回答“这次推理到底是 placeholder、正式模型，还是 fallback”

### C. 业务可信度验收

要判断是否“业务上有意义”，当前还需要额外条件：

1. 使用真实设备真实数据，而不是只看 simulator
2. 模型输入契约已冻结
3. 模型版本清晰可追踪
4. 有 golden regression / reference case
5. 有实际标签或对照样本做效果验证

## 七、当前最容易误判的地方

### 误判 1：波形动了，就代表模型在工作

不对。

波形动了只能说明展示链有数据，不代表推理链一定在工作。

### 误判 2：出现了 `waveformMetricsUpdated`，就代表收到真实波形

不对。

`waveformMetricsUpdated` 可能只说明 middleware 在轮询。
真正更关键的是 `waveformSamplesReceived(...)`。

### 误判 3：有了 placeholder 模型结果，就代表业务效果可信

不对。

placeholder 或 fallback 更主要是工程闭环，不是算法效果闭环。

## 八、当前阶段最务实的理解

对于当前项目，最务实的说法应该是：

- **波形图可见**：说明 simulator waveform 到 App UI 的链路基本可用
- **看到 FeatureVector / InferenceResult / modelVersion**：说明推理链路在工作
- **要证明“有业务意义”**：还需要真实数据、真实模型、reference case 和回归验证

## 相关代码与文档

代码落点：

- `Sources/HRSenseSimulatorUI/SimulatorViewModel.swift`
- `Sources/HRSenseData/BLE/BLEDataParser.swift`
- `Sources/HRSenseData/WaveformRingBuffer.swift`
- `Sources/HRSenseFeature/Middleware/WaveformMiddleware.swift`
- `Sources/HRSenseFeature/Middleware/ComputeMiddleware.swift`
- `Sources/HRSenseFeature/Middleware/InferenceMiddleware.swift`
- `Sources/HRSenseFeature/Views/RootView.swift`

相关说明文档：

- `docs/gap-closure/m5-waveform-incident-investigation.md`
- `docs/gap-closure/m5-waveform-ble-ringbuffer-ui-chain.md`
- `docs/gap-closure/m9-app-display-and-inference-chain.md`
- `docs/gap-closure/m8-inference-visibility-and-golden-regression.md`
