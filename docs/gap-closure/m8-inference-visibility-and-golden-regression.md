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
- `InferenceRepositoryImpl` 的版本回传行为已有测试保护

## 仍未完全闭合的部分

以下内容建议作为下一轮 `M8` 继续补齐：

- 更严格的 C++ 特征 golden set，对 14 维特征逐项对拍
- placeholder / 正式 CoreML 模型的固定输入 -> 固定概率 golden set
- 真实设备输入 -> App -> CoreML -> UI 的联调记录
- 诊断包中补充更多推理上下文，例如窗口时间范围和 RR 样本数
