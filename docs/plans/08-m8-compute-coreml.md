# M8 · C++ 计算 + CoreML 推理 — 实施计划

## 摘要

HRV 特征提取（C ABI）+ 压力二分类推理。创建 `HRSenseComputeCxx`（C++）、`HRSenseCompute`（Swift 桥接）、`CoreMLService`、Inference Middleware。

**依赖**：M4（Redux 展示层）。

---

## 阶段 1：SPM 目标基础设施

- `HRSenseComputeCxx` target（C++，`publicHeadersPath: "include"`）
- `HRSenseCompute` target（Swift，依赖 `HRSenseComputeCxx`）
- 更新 `Package.swift` 依赖图
- `.gitattributes` 添加 `*.mlpackage filter=lfs`

---

## 阶段 2：领域实体与 Repository 协议（HRSenseCore）

| 文件 | 内容 |
|---|---|
| `HRVMetrics.swift` | 14 个字段：`sdnn`、`rmssd`、`pnn50`、`meanRR`、`hr`、`lfPower`、`hfPower`、`lfHfRatio`、`totalPower`、`sd1sd2`、`sampleEntropy`、`dfaAlpha1` 等 |
| `FeatureVector.swift` | `values: [Float]`（count==14）、`contractVersion: Int` |
| `InferenceResult.swift` | `label`、`probabilities`、`inferenceTimeMs`、`timestamp`、`modelVersion` |
| `ComputeRepository.swift` | 协议：`computeHRV(rrIntervalsMs:) throws -> HRVMetrics`、`extractFeatures(from:) throws -> FeatureVector` |
| `InferenceRepository.swift` | 协议：`runInference(features:) async throws -> InferenceResult` |
| `ComputeHRVUseCase.swift` / `RunInferenceUseCase.swift` | 用例封装 |

---

## 阶段 3：C ABI 头与模块映射

**`hrs_compute.h`**：
```c
typedef struct { double sdnn; double rmssd; /* ... 14 fields */ } hrs_hrv_metrics_t;
#define HRS_FEATURE_DIM 14

int hrs_compute_hrv(const uint16_t *rr_ms, size_t count, hrs_hrv_metrics_t *out);
int hrs_extract_features(const hrs_hrv_metrics_t *metrics, float *out_features);
```

**`module.modulemap`**：
```
module HRSenseComputeCxx { header "hrs_compute.h" export * }
```

---

## 阶段 4：C++ HRV 实现 + 黄金值测试

### 时域指标
- SDNN、RMSSD、pNN50、mean_RR、HR

### 频域指标（Lomb-Scargle 或 Welch 周期图）
- LF power、HF power、LF/HF ratio、total power

### 高级指标
- Poincaré SD1/SD2、样本熵（m=2, r=0.2*SDNN）、DFA alpha1

### 特征提取
- 14 维 Float32 有序数组（RMSSD=索引 0，HR=索引 13）

### 黄金值测试
- 已知 RR 序列（PhysioNet 参考数据）→ C++ 输出 vs Python/MATLAB 参考值
- RMSSD/SDNN 误差 <1%；频域指标 <5%

---

## 阶段 5：Swift ComputeBridge

`Sources/HRSenseCompute/ComputeBridge.swift`：
```swift
public struct ComputeBridge: Sendable {
    public func computeHRV(from rrIntervalsMs: [UInt16]) -> Result<HRVComputeResult, ComputeError>
    public func extractFeatures(from metrics: HRVComputeResult) -> Result<[Float], ComputeError>
}
```

边界测试：空输入、单 RR、恰好 2 个、大数组。

---

## 阶段 6：CoreMLService + 占位模型

| 文件 | 职责 |
|---|---|
| `tools/create_placeholder_model.py` | `coremltools` 生成最小 `.mlpackage`（14 特征 → 2 分类：Baseline/Stress） |
| `Models/StressClassifier_v1.mlpackage/` | Git LFS 跟踪 |
| `CoreMLService.swift` | 加载模型、`predict(features:)`、推理耗时测量、版本读取 |

---

## 阶段 7：Redux Middleware

| 文件 | 职责 |
|---|---|
| `ComputeMiddleware.swift` | 5 分钟滑动窗口积累 RR → 触发 `computeHRV` → dispatch `hrvComputed` |
| `InferenceMiddleware.swift` | 收到 `hrvComputed` → 触发 `runInference` → dispatch `inferenceCompleted` |

---

## 验收标准
- [ ] C++ 黄金值对拍：RMSSD/SDNN 误差 <1%，频域 <5%
- [ ] 特征输出 14 维，契约版本匹配
- [ ] 占位模型端到端：特征 → predict → InferenceResult → State → UI
- [ ] 5min 窗 / 30s 步长触发正确
- [ ] 推理耗时记录

## 预估文件数：~20 个新文件 + ~8 个测试文件
