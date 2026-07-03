# M8 推理链可见性与 Golden 回归补强

## 背景

`M8` 当前的主链路已经具备：

- RR -> HRV -> `FeatureVector`
- `FeatureVector` -> CoreML / fallback 推理
- `InferenceResult` -> Store -> UI

但从验收角度看，仍存在两个明显缺口：

- iOS App 内虽然已经能跑推理，但对“当前到底用了什么模型、推了什么特征”缺少足够可见性
- 回归测试对 `M8` 的覆盖仍偏“链路能跑”，缺少更明确的固定输入回归

## 原缺失点

### 1. M8 中间产物可见性不足

虽然 `FeatureVector` 和 `InferenceResult.modelVersion` 已进入状态树，但：

- 主界面没有明确显示 `modelVersion`
- 诊断面板导出中没有带上最新特征与最新推理结果

这会导致：

- 联调时难以回答“这次到底推了哪个模型”
- 诊断包难以解释“输入特征是什么、输出结果是什么”

### 2. M8 回归测试缺少更明确的固定输入断言

此前测试更多覆盖：

- 服务能加载
- fallback 能工作
- middleware 能把链路串起来

但对以下问题的约束还不够强：

- fallback 规则推理是否对固定输入保持稳定
- `InferenceRepositoryImpl` 是否稳定回传 `modelVersion`
- 诊断导出是否真的把 `FeatureVector / InferenceResult` 带出去

## 本次更新

### iOS App 展示补齐

- 主界面的推理结果区域现在会直接显示 `modelVersion`
- 诊断面板新增 `M8 Inference` 区块，展示：
  - 最新特征维度
  - 特征契约版本
  - 特征预览
  - 最新标签
  - 模型版本
  - 推理耗时

### 诊断包内容补齐

`DiagnosticPackage` 新增：

- `latestFeatureVector`
- `latestInference`

这样导出出来的 JSON 不再只有日志和指标，也能带上 `M8` 的关键上下文。

### 回归测试补强

新增 / 更新测试：

- `CoreMLServiceTests`
  - 固定 stress / baseline 输入在 fallback 规则下输出稳定标签与概率
  - 补充 fallback 阈值黄金样本，锁定 `rmssd < 30 || hr > 90` 的判定边界
  - 占位模型加载时，额外锁定 `modelVersion == 1.0.0-placeholder` 与概率分布合法性
- `ComputeBridgeTests`
  - 新增两组 RR reference case，对 `HRVMetrics` 14 个字段逐项对拍
  - 同时对 `extractFeatures()` 的 14 维输出顺序和值做逐项 golden 校验
  - 明确覆盖 `sampleEntropy` 的极端值场景，避免 C++ 计算细节漂移
- `InferenceRepositoryImplTests`
  - 缺失模型时稳定回传 `fallback-rule-engine`
  - 加载 placeholder 模型时稳定回传真实 `modelVersion`
- `DiagnosticPanelModelTests`
  - 导出 JSON 时包含最新 `FeatureVector` 与最新 `InferenceResult`

## 新增实现原理

### 1. 为什么这轮优先补“可见性”

`M8` 和 `M6/M7` 不同，它的问题不是“完全没有链路”，而是：

- 链路已经能跑
- 但运行时很难观察
- 出问题时诊断证据不足

如果继续只补底层推理逻辑，而不把 `FeatureVector / modelVersion / inference result` 暴露出来，会出现两个典型问题：

- UI 上只能看到一个标签，看不到背后是哪个模型得出的
- 导出的诊断包无法回答“输入是什么、输出是什么、是否走了 fallback”

因此这轮先补的是**可观察性闭环**，让 `M8` 在 iOS App 内部变成可联调、可排障的状态。

### 2. 为什么把 `FeatureVector` 和 `InferenceResult` 放进诊断包

此前 `DiagnosticPackage` 更偏系统观测：

- 日志
- 状态迁移
- 指标快照
- 系统信息

但对 `M8` 来说，这些信息还不够，因为推理问题通常要回答四个问题：

1. 当时提取了什么特征
2. 特征契约版本是什么
3. 推理输出是什么
4. 用的是哪个模型版本

这次把：

- `latestFeatureVector`
- `latestInference`

加入诊断包，目的就是让一次导出就能把 `M8` 的关键上下文带走，而不是联调时还要额外开日志或手工截图。

### 3. 为什么主界面也显示 `modelVersion`

仅把 `modelVersion` 放进调试面板还不够，因为日常联调时开发者最先看到的是主界面推理结果卡片。

因此这次顺手把 `modelVersion` 直接展示在主界面推理结果区域，带来的价值是：

- 一眼区分当前是否仍在 fallback
- 发现模型替换后是否真的生效
- 便于录屏、截图时直接保留证据

这属于低成本但高收益的可观察性增强。

### 4. 为什么新增的是“固定输入回归”，而不是立刻补全量黄金集

严格来说，`M8` 最终应该有两类 golden：

- C++ 14 维特征 golden
- CoreML 固定输入 -> 固定概率 golden

但在当前阶段，先补最有价值的第一批固定输入回归更务实：

- 对 fallback 路径，用固定 stress / baseline 输入锁定标签与概率
- 对 `InferenceRepositoryImpl`，锁定 `modelVersion` 回传行为
- 对诊断导出，锁定 `FeatureVector / InferenceResult` 进入 JSON 的行为

这样可以先防住最容易退化的运行时行为，再在下一轮继续扩大 golden set。

### 5. 为什么这轮先收紧 `ComputeBridge` 和 fallback 契约

`M8` 里真正长期稳定、且最容易被后续重构误伤的，不是某个临时占位模型的输出概率，而是两层更底的契约：

- RR 序列进入 C++ 后，14 维特征到底算成什么
- 没有模型或模型加载失败时，fallback 规则到底怎么判

这两层有几个特点：

- 它们贯穿整个推理链路，UI、Store、Repository 都依赖它们
- 后面即使替换正式 CoreML 模型，这两层仍然继续存在
- 一旦漂移，联调阶段最难发现，因为表面上“还能出结果”

所以这轮更严格 golden set 的落点是：

- 先把 `ComputeBridge` 的 14 维数学输出锁成 reference case
- 再把 fallback 的阈值行为锁成判定契约
- 最后保留 placeholder / 正式模型概率 golden，等模型工件冻结后再继续收紧

这样分层推进，比一开始就把所有压力都堆在 placeholder 概率上更稳妥。

### 6. 更严格 golden set 的拆分思路

这轮实际采用的是三层 golden 思路：

1. **特征层 golden**
   - 输入固定 RR 序列
   - 输出固定 `HRVMetrics` 和 14 维 `FeatureVector`
   - 目的：防止 C++ 公式、字段顺序、Float 映射被改坏

2. **推理策略层 golden**
   - 输入固定 14 维特征
   - 输出固定 fallback 标签和概率
   - 目的：防止无模型场景下的行为契约漂移

3. **模型工件层 golden**
   - 输入固定 14 维特征
   - 输出固定 CoreML 标签和概率
   - 目的：防止模型替换、导出、metadata 变更造成行为回退

当前这轮主要把前两层收紧，因为它们对运行时稳定性收益最高，也最不依赖外部训练资产。

### 7. 这轮 golden set 的限定范围

为了避免 golden set 一上来就膨胀成难维护的“大而全快照库”，这轮先做了明确限定：

- **先锁底层契约，不先锁所有表现层结果**
  - 优先锁 `ComputeBridge` 的 14 维特征输出
  - 优先锁 fallback 策略的阈值边界
  - 暂时不把所有 UI 文案、时间戳、导出文件名纳入 golden

- **先锁稳定输入，不先锁高噪声输入**
  - 选固定 RR reference case
  - 选固定 14 维特征样本
  - 暂不把真机实时采样流直接作为 golden 主体

- **先锁契约性字段，不先锁偶发性字段**
  - 锁 label、probabilities、modelVersion、14 维特征顺序
  - 不锁 `timestamp`、导出路径、分享面板行为

- **先锁占位策略，不假装锁正式模型**
  - fallback 规则和 placeholder metadata 现在可以稳定保护
  - 正式 CoreML 概率 golden 需要等训练工件冻结后再继续扩大

这组限定的核心目的，是让 golden set 先承担“防漂移”的职责，而不是过早变成“什么都快照一下”的维护负担。

### 8. 设计思路：如何防止偏移现象

这里说的“偏移”，主要不是指测试直接挂掉，而是指**链路还能跑，但结果已经悄悄变了**。在 `M8` 里最常见的偏移来源有四类：

1. **公式偏移**
   - C++ 侧改了 SDNN / RMSSD / sample entropy / stress index 的实现
   - 表面上编译通过，但 14 维值已经变了

2. **字段顺序偏移**
   - `HRVMetrics -> FeatureVector` 的映射顺序被改动
   - CoreML 仍然能跑，但输入语义已经错位

3. **策略偏移**
   - fallback 阈值被改成别的数值
   - 无模型场景下标签和概率发生静默变化

4. **工件偏移**
   - placeholder / 正式模型被替换
   - metadata、`modelVersion`、类别分布变化，但联调时没有明确证据

针对这四类偏移，这轮 golden set 的设计原则是：

- **分层防漂移**
  - 特征层防公式偏移和字段顺序偏移
  - 策略层防 fallback 规则偏移
  - 模型工件层防 modelVersion 和模型替换偏移

- **最小但高价值**
  - 不追求一次覆盖所有输入
  - 先选最能代表契约边界的样本

- **以 reference case 为主，不以随机样本为主**
  - reference case 可以复算、可解释、能长期维护
  - 随机样本虽然多，但难以解释失败原因

- **把“边界点”单独锁住**
  - 例如 fallback 的 `rmssd = 30`、`hr = 90`
  - 这类样本比普通样本更能防止阈值滑动

### 9. 设计流程：更严格 golden set 怎么落地

这轮采用的落地流程是固定的，后面继续扩样本也建议沿用：

1. **先找契约面**
   - 明确这一层到底要保护什么
   - 例如 `ComputeBridge` 保护的是数学输出与字段顺序，不是 UI

2. **再挑 reference input**
   - 选择可复算、可解释、波动小的 RR 序列或特征向量
   - 尽量覆盖正常值、边界值、极端值

3. **再确定 golden 输出**
   - 用当前实现和公式计算出参考值
   - 把每个字段的精度、公差、是否允许 `infinity` 写清楚

4. **最后才写断言**
   - 对 14 维特征逐项断言，而不是只断言最终 label
   - 对阈值边界单独断言，而不是只测“明显 Stress / 明显 Baseline”

5. **文档同步补原理**
   - 每次扩大 golden set，都要在 gap 文档说明：
   - 为什么选这批样本
   - 这批样本防的是什么漂移
   - 哪些部分仍然刻意没有锁死

### 10. 防漂移的具体约束策略

为了让 golden set 真正起到“防偏移”作用，而不是只变成一组脆弱快照，这轮采用了几条具体约束：

- **固定 reference corpus**
  - RR 样本序列直接写死在测试里
  - 不依赖网络、不依赖外部文件、不依赖运行时状态

- **逐字段断言，不只看最终类别**
  - 如果只看 `Baseline/Stress`，很多中间偏移根本发现不了
  - 逐字段断言能更快定位是公式变了、顺序变了，还是阈值变了

- **边界样本单独测试**
  - `rmssd = 30` 和 `hr = 90` 这种临界值必须单独锁
  - 否则阈值从 `>` 变成 `>=` 时很容易静默漂移

- **对高波动字段单独定义策略**
  - 例如 `sampleEntropy` 在某些 reference case 下可能是 `infinity`
  - 这类字段不能简单用普通浮点比较，需要单独定义断言方式

- **把 placeholder 与正式模型解耦**
  - 当前 placeholder 只保护 metadata 和基本输出合法性
  - 等正式模型冻结后，再把固定概率 golden 作为下一层保护

### 11. 后续继续扩展时的建议流程

下一轮如果继续扩大 `M8` golden set，建议按下面顺序推进，避免一次性把测试体系做得过重：

1. 新增更多 RR 节律形态 reference case
   - 稳态
   - 高变异
   - 低变异
   - 临界异常

2. 为每组样本补“为什么存在”的说明
   - 防哪个公式漂移
   - 防哪个字段顺序漂移
   - 防哪个边界条件漂移

3. 在模型工件冻结后，再补 CoreML 概率 golden
   - 同时记录模型文件 hash / modelVersion / featureContractVersion

4. 如有必要，再把真机联调 case 转成验收样本
   - 但应作为补充层，而不是最底层契约的唯一来源

## 代码落点

- `Sources/HRSenseProtocol/Logging/DiagnosticPackage.swift`
- `Sources/HRSenseFeature/Observability/DiagnosticPanelModel.swift`
- `Sources/HRSenseFeature/Views/DiagnosticPanelView.swift`
- `Sources/HRSenseFeature/Views/RootView.swift`
- `Sources/HRSenseAppUI/AppComposition.swift`
- `Tests/HRSenseComputeTests/CoreMLServiceTests.swift`
- `Tests/HRSenseDataTests/InferenceRepositoryImplTests.swift`
- `Tests/HRSenseFeatureTests/DiagnosticPanelModelTests.swift`

## 对 M8 验收的直接收益

本轮更新后，`M8` 在 iOS App 侧更接近“可联调、可诊断、可回归”：

- 主界面能直接看到当前模型版本
- 诊断面板和导出包能看到 `FeatureVector / InferenceResult`
- fallback 路径已有更明确的固定输入回归
- C++ 14 维特征已经有 reference case 逐项 golden 校验
- fallback 阈值边界已经被测试锁定
- `InferenceRepositoryImpl` 的版本回传行为已有测试保护

## 仍未完全闭合的部分

以下内容建议作为下一轮 `M8` 继续补齐：

- 扩大 RR reference corpus，补更多窗口长度、节律形态、异常输入的特征 golden
- placeholder / 正式 CoreML 模型的固定输入 -> 固定概率 golden set
- 真实设备输入 -> App -> CoreML -> UI 的联调记录
- 诊断包中补充更多推理上下文，例如窗口时间范围和 RR 样本数
