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

## 阶段 5：Swift ComputeBridge（关键适配层）

`Sources/HRSenseCompute/ComputeBridge.swift`：
```swift
public struct ComputeBridge: Sendable {
    public func computeHRV(from rrIntervalsMs: [UInt16]) -> Result<HRVComputeResult, ComputeError>
    public func extractFeatures(from metrics: HRVComputeResult) -> Result<[Float], ComputeError>
}
```

**ComputeBridge 是整个系统中唯一直接依赖 C ABI 的文件。** 这是故意的——把 C 互操作的边界压缩到一个薄适配层（~50 行），上层代码全部通过 `ComputeRepository` 协议消费。

边界测试：空输入、单 RR、恰好 2 个、大数组。

### 设计理由与 Swift/C++ 直接互操作迁移路径

**当前选择 C ABI（`extern "C"` + module map）而非 Swift 5.9+ C++ 直接互操作的原因**：
- Swift 5.9 的 C++ 互操作是首次引入，工具链成熟度/编译速度/跨版本兼容性仍需观察
- C ABI 边界由调用方分配内存、值类型进出，不泄露 C++ 类型——这个原则无论用哪种方案都成立
- 项目当前基线 iOS 17，Swift 5.9 刚好够；但团队经验、CI 工具链、SwiftPM 对 C++ 互操作的支持都需额外验证

**到 Swift/C++ 直接互操作的最小迁移面（只改 2 个文件）**：

```
HRSenseCore (Domain)
    ↑ ComputeRepository 协议（不变）
HRSenseData
    ↑ ComputeRepositoryImpl（不变——调的是 ComputeBridge 的 Swift 接口）
HRSenseCompute ← 唯一需要改的模块
    ├── ComputeBridge.swift        ← 【改】重写实现，import HRSenseComputeCxx 改为直接 import C++ 类型
    └── HRSenseComputeCxx/
        ├── include/hrs_compute.h  ← 【改】去掉 extern "C"，暴露 C++ 函数签名（或直接 import C++ header）
        ├── include/module.modulemap ← 【删】不再需要 module map
        ├── hrv.cpp                ← 不变
        └── dsp.cpp                ← 不变
```

**迁移步骤（预估 <2 小时）**：

1. **删除 `module.modulemap`**，Swift 5.9+ 通过 `-cxx-interoperability-mode` 直接 import C++ header
2. **改写 `hrs_compute.h`**：去掉 `extern "C"`，函数签名不变，C++ 类型（如 `std::vector` / `std::span`）可作为可选增强
3. **改写 `ComputeBridge.swift`**：把 `hrs_compute_hrv(rr_ms, count, &out)` 替换为直接调用 C++ 函数，Swift 自动桥接 `[UInt16]` → `std::span<const uint16_t>`
4. **更新 `Package.swift`**：`cxxSettings` 添加 `-cxx-interoperability-mode=default`，swiftSettings 添加 `-cxx-interoperability-mode=default`

**不做任何改动的文件**（全部受保护）：
- `HRSenseCore/Entities/HRVMetrics.swift`、`FeatureVector.swift`
- `HRSenseCore/Repositories/ComputeRepository.swift`（协议不变）
- `HRSenseData/Repositories/ComputeRepositoryImpl.swift`（调 ComputeBridge，接口不变）
- `HRSenseFeature/Middleware/ComputeMiddleware.swift`（通过协议消费，无感知）
- 所有单元测试（`ComputeBridge` 的公开 API 签名不变，黄金值测试直接复用）
- `hrv.cpp`、`dsp.cpp`（C++ 内部实现不受互操作方式影响）

**关键设计原则**：C++ 实现不感知互操作方式。`hrs_compute_*` 函数签名的语义（输入 POD 类型数组指针 + 输出 caller-allocated 结构体指针 + 返回 int 状态码）在两种方案下完全一致。迁移只是把 `extern "C"` 关键字去掉、把 Swift 侧的调用语法从 C 函数改为 C++ 函数——中间的计算逻辑不动一行。

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
