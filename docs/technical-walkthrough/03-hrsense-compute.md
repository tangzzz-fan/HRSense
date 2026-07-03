# 03 · HRSenseCompute — C++ 计算 + CoreML 推理

> **路径**: `Sources/HRSenseComputeCxx/` + `Sources/HRSenseCompute/`  
> **依赖**: `HRSenseCore`, `HRSenseComputeCxx`  
> **被依赖**: `HRSenseData`

## 1. 模块定位

计算层分为两个 SPM target：
- `HRSenseComputeCxx`：纯 C/C++ 实现，通过 C ABI 暴露函数
- `HRSenseCompute`：Swift 桥接层 + CoreML 服务

这种分层让重计算（HRV、FFT、特征提取）在 C++ 中高效执行，同时上层只看到纯 Swift 类型。

## 2. C ABI 接口（hrs_compute.h）

```c
// 14 维 HRV 指标结构体
typedef struct {
    double sdnn, rmssd, pnn50, mean_rr, hr;
    double lf_power, hf_power, lf_hf_ratio, total_power;
    double sd1, sd2, sample_entropy, dfa_alpha1, stress_index;
} hrs_hrv_metrics_t;

// 核心函数
int hrs_compute_hrv(const uint16_t *rr_ms, size_t count, hrs_hrv_metrics_t *out);
int hrs_extract_features(const hrs_hrv_metrics_t *metrics, float *out_features);
int hrs_compute_hr_trend(const double *hr_values, size_t count, double *out_trend);
int hrs_compute_circadian_variation(const double *hrv_values, size_t count, double *out_variation);
```

**内存模型**：调用者分配缓冲区，C 函数填充。无 C++ 类型泄漏到接口层。

**module.modulemap** 声明 `HRSenseComputeCxx` 为 C 模块，Swift 可直接 import。

## 3. C++ 实现（hrv.cpp，~361 行）

核心算法：
- **时域 HRV**：SDNN、RMSSD、pNN50、meanRR 直接从 RR 间期计算
- **频域 HRV**：通过 FFT 计算 LF(0.04–0.15Hz)、HF(0.15–0.4Hz) 功率谱
- **非线性**：Poincaré 图（SD1/SD2）、样本熵、DFA α1
- **压力指数**：基于 HRV 综合评分
- **睡眠特征**：心率趋势斜率（线性回归）、昼夜变异代理指标

## 4. Swift 桥接（ComputeBridge）

`ComputeBridge` 是唯一导入 `HRSenseComputeCxx` 的文件：

```swift
struct ComputeBridge: Sendable {
    func computeHRV(from rrIntervalsMs: [UInt16]) throws -> HRVMetrics
    func extractFeatures(from metrics: HRVMetrics) -> [Float]
    func computeAndExtract(from rrIntervalsMs: [UInt16]) throws -> FeatureVector
    func computeSleepFeatures(heartRates: [Double], hrvWindowValues: [Double]) throws -> SleepCXXFeatures
}
```

桥接模式：
1. Swift `[UInt16]` → `withUnsafeBufferPointer` → C `const uint16_t*`
2. C 函数填充 `hrs_hrv_metrics_t`
3. Swift 从 C 结构体逐字段拷贝到 `HRVMetrics`（值类型）

## 5. CoreML 服务（CoreMLService）

### 5.1 模型加载策略

采用**占位模型优先**策略：先用 placeholder model 跑通全管线，后续替换为真实训练模型。

```swift
final class CoreMLService {
    struct Configuration {
        let expectedFeatureCount: Int        // 14（压力）/ 18（睡眠）
        let fallbackModelVersion: String
        let fallbackPredictor: (([Float]) -> PredictionResult?)?
    }
}
```

加载流程：
1. 通过 `CoreMLModelCatalog`（BundleCoreMLModelCatalog）扫描 App Bundle 中的 `.mlpackage`
2. `ModelSelectionStrategy` 按 `ModelSelectionRequest`（task + featureContractVersion）选择最佳匹配
3. 加载失败时降级到 `fallbackPredictor`（规则引擎）

### 5.2 推理流程

```swift
func predict(features: [Float]) -> PredictionResult? {
    // 1. 校验特征维度
    // 2. 构建 MLMultiArray (float32, shape=[14])
    // 3. MLDictionaryFeatureProvider → model.prediction()
    // 4. 解析 classLabel + classProbability
    // 5. 失败时降级到 fallbackPredictor
}
```

### 5.3 预置模型配置

| 配置 | 特征数 | 分类目标 | Fallback |
|------|--------|---------|----------|
| `stressClassifier` | 14 | Baseline / Stress | 规则引擎（HR>90 或 RMSSD<30 → Stress） |
| `sleepStageClassifier` | 18 | Wake / Light / Deep / REM | 无 fallback |

### 5.4 模型选择架构

```
ModelSelectionRequest(task, featureContractVersion)
    ↓
CoreMLModelCatalog.discoverModels() → [ModelDescriptor]
    ↓
ModelSelectionStrategy.selectModel() → ModelDescriptor?
    ↓
CoreMLModelInspector.inspectModel() → 验证 metadata
```

`ModelDescriptor` 包含：modelName, modelVersion, task, featureContractVersion, url。版本信息从 MLModel metadata 中提取。

## 6. 计算管线数据流

```
BLE → RR intervals → ComputeBridge.computeHRV() → HRVMetrics
                                                        ↓
                                    ComputeBridge.extractFeatures() → [Float](14)
                                                        ↓
                                    CoreMLService.predict() → InferenceResult
                                                        ↓
                                    dispatch(.inferenceCompleted) → Redux Store
```

**触发条件**：由 `ComputeMiddleware` 在 RR 间期窗口填满（~5min / 300 个 RR）时触发。
