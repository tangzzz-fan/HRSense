# CoreML 推理管线

> 模型发现、选择、加载、推理、降级——从 14 维特征到分类标签的完整链路。

---

## 1. 推理触发路径

```
ComputeMiddleware:
    heartRateReceived → 积累 RR → hrs_compute_hrv()
        → dispatch(.hrvComputed(metrics))
        → dispatch(.featuresExtracted(features))

InferenceMiddleware:
    featuresExtracted → inferenceRepo.runInference()
        → dispatch(.inferenceCompleted(result))
```

### InferenceMiddleware 核心代码

```swift
public func makeInferenceMiddleware(
    inferenceRepo: any InferenceRepository
) -> Middleware<AppState, Action> {
    { store, action, next in
        next(action)

        switch action {
        case .featuresExtracted(let features):
            store.dispatch(.inferenceStarted)
            Task {
                do {
                    let result = try await inferenceRepo.runInference(features: features.values)
                    await MainActor.run {
                        store.dispatch(.inferenceCompleted(result))
                    }
                } catch {
                    await MainActor.run {
                        store.dispatch(.errorOccurred(.inferenceFailed))
                    }
                }
            }

        default:
            break
        }
    }
}
```

---

## 2. 模型选择架构

```
┌────────────────────────────────────────────────────────────┐
│  ModelSelectionRequest                                      │
│  ─ task: stressClassification / sleepStage                  │
│  ─ featureContractVersion: 1                                │
│  ─ preferredModelName: "StressClassifier_v1"               │
└──────────────────────────────┬─────────────────────────────┘
                               │
                               ▼
┌────────────────────────────────────────────────────────────┐
│  CoreMLModelCatalog (BundleCoreMLModelCatalog)              │
│  ─ 扫描 Bundle 中的 .mlmodelc / .mlpackage / .mlmodel       │
│  ─ 解析元数据 → [ModelDescriptor]                           │
└──────────────────────────────┬─────────────────────────────┘
                               │
                               ▼
┌────────────────────────────────────────────────────────────┐
│  ModelSelectionStrategy (DefaultModelSelectionStrategy)     │
│  ─ 评分系统: task(+100) + contract(+50) + name(+25) + ver  │
│  ─ 选最高分的 ModelDescriptor                               │
└──────────────────────────────┬─────────────────────────────┘
                               │
                               ▼
┌────────────────────────────────────────────────────────────┐
│  CoreMLService                                              │
│  ─ 加载 MLModel                                             │
│  ─ 创建 MLMultiArray(float32)                               │
│  ─ model.prediction(from:) → label + probabilities          │
│  ─ 失败时 → fallbackPredictor                               │
└────────────────────────────────────────────────────────────┘
```

---

## 3. 模型评分选择策略

```swift
// DefaultModelSelectionStrategy.swift
private func selectionScore(for descriptor: ModelDescriptor, request: ModelSelectionRequest) -> Int {
    var score = 0

    // 硬性条件（不匹配直接排除）
    if let task = descriptor.task {
        guard task == request.task.rawValue else { return Int.min }
        score += 100
    }
    if let contractVersion = descriptor.featureContractVersion {
        guard contractVersion == request.featureContractVersion else { return Int.min }
        score += 50
    }

    // 软性偏好
    if descriptor.modelName == request.preferredModelName { score += 25 }
    if descriptor.modelVersion == request.preferredModelVersion { score += 25 }

    // 格式偏好
    switch descriptor.url.pathExtension {
    case "mlmodelc": score += 5   // 已编译，加载最快
    case "mlpackage": score += 3  // 需编译
    default: break
    }

    return score
}
```

**评分结果**：
- 最高分 = 100(task) + 50(contract) + 25(name) + 25(version) + 5(format) = **205**
- 硬性条件不匹配 = `Int.min`（直接排除）

---

## 4. 三级降级链

```
优先级 1: CoreML 模型推理
    ↓ 模型文件不存在 / 加载失败 / 推理异常
优先级 2: Fallback Predictor（规则引擎）
    ↓ 规则引擎返回 nil
优先级 3: 默认硬编码结果
```

### 压力分类器 Fallback

```swift
// CoreMLService.Configuration.stressClassifier
fallbackPredictor: { features in
    let rmssd = features[1]
    let hr = features[4]
    let isStress = hr > 90 || rmssd < 30
    return PredictionResult(
        label: isStress ? "Stress" : "Baseline",
        probabilities: isStress
            ? ["Baseline": 0.3, "Stress": 0.7]
            : ["Baseline": 0.7, "Stress": 0.3]
    )
}
```

### 推理容错代码

```swift
// CoreMLService.predict()
public func predict(features: [Float]) -> PredictionResult? {
    guard features.count == configuration.expectedFeatureCount else { return nil }

    guard let model = model else {
        return configuration.fallbackPredictor?(features)  // 模型未加载
    }

    do {
        // ... 正常推理 ...
    } catch {
        return configuration.fallbackPredictor?(features)  // 推理异常
    }
}
```

---

## 5. 两个推理任务对比

| 维度 | 压力分类器 | 睡眠分期器 |
|------|-----------|-----------|
| **ModelSelectionRequest** | `.stressClassifierV1` | `.sleepStageClassifierV1` |
| **特征维度** | 14 (HRV 指标) | 18 (HRV + 睡眠上下文) |
| **输出类别** | Baseline / Stress | Wake / Light / Deep / REM |
| **Fallback** | 规则引擎 (hr > 90 \|\| rmssd < 30) | 多规则系统 (见 15-sleep-pipeline.md) |
| **触发时机** | featuresExtracted | hrvComputed (经 sleep middleware) |

---

## 6. 特征维度契约

### 压力分类器（14 维）
完全等同于 C++ HRV 指标，见 [12-cpp-compute-bridge](./12-cpp-compute-bridge.md#5-特征顺序一致性关键契约)。

### 睡眠分期器（18 维）
| 索引 0-13 | 14 个 HRV 指标 | C++ `hrs_compute_hrv` |
|-----------|---------------|----------------------|
| 索引 14 | hrTrend | C++ `hrs_compute_hr_trend` |
| 索引 15 | circadianVariation | C++ `hrs_compute_circadian_variation` |
| 索引 16 | minutesSinceSessionStart | 时间上下文 |
| 索引 17 | localClockMinutes | 本地时钟 |

**硬检查**：`features.count != expectedFeatureCount` → 直接返回 nil，不执行推理。

---

## 7. 重点难点

### 7.1 模型加载时机
- `CoreMLService.init()` 同步加载模型（可能耗时 100ms+）
- `mlpackage` 需编译为 `mlmodelc`，首次更慢
- **当前策略**：在 `AppComposition.makeAppShell()` 启动时创建，避免推理时延迟

### 7.2 元数据解析兼容性
```swift
// 模型元数据中的 creatorDefined 可能是 [String: String] 或 [String: Any]
if let creatorDefined = metadata[.creatorDefinedKey] as? [String: String],
   let modelVersion = creatorDefined["modelVersion"] { ... }

if let creatorDefined = metadata[.creatorDefinedKey] as? [String: Any],
   let modelVersion = creatorDefined["modelVersion"] as? String { ... }
```

### 7.3 Bundle 扫描安全
```swift
// BundleCoreMLModelCatalog.defaultDiscoveryBundles()
// 限制扫描范围为 app 自身的 bundle，避免扫描系统 framework
let mainBundleURL = Bundle.main.bundleURL.standardizedFileURL
let appScopedBundles = ([Bundle.main] + Bundle.allBundles + Bundle.allFrameworks)
    .filter { bundle in
        bundle.bundleURL.path.hasPrefix(mainBundleURL.path + "/")
    }
```

### 7.4 推理时间追踪
```swift
let start = CFAbsoluteTimeGetCurrent()
// ... model.prediction() ...
let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
return PredictionResult(label: label, probabilities: probs, inferenceTimeMs: elapsed)
```
DiagnosticPanel 展示此数值，便于性能调优。
