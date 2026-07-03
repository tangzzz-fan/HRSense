# C++ 计算层桥接（HRSenseComputeCxx）

> Swift 通过 C ABI 调用 C++ 实现的高性能 HRV 计算，本文详解桥接模式、算法实现与内存安全。

---

## 1. 架构分层

```
┌─────────────────────────────────────────────────────────┐
│  ComputeMiddleware (Swift, MainActor 外)                 │
│  ─ 积累 RR 间期到 5 分钟滑动窗口                         │
│  ─ 每 10 秒触发一次计算                                  │
└─────────────────────────┬───────────────────────────────┘
                          │ rrBuffer: [UInt16]
                          ▼
┌─────────────────────────────────────────────────────────┐
│  ComputeRepository (协议) → ComputeRepositoryImpl       │
│  ─ HRSenseCore 层定义的接口                              │
└─────────────────────────┬───────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│  ComputeBridge (Swift struct, Sendable)                  │
│  ─ 唯一导入 HRSenseComputeCxx 的文件                     │
│  ─ withUnsafeBufferPointer → C 函数调用                  │
│  ─ C struct → Swift struct 逐字段映射                    │
└─────────────────────────┬───────────────────────────────┘
                          │ hrs_compute_hrv()
                          ▼
┌─────────────────────────────────────────────────────────┐
│  hrv.cpp (C++, 纯数学计算)                               │
│  ─ 时域: SDNN, RMSSD, pNN50, SD1, SD2                   │
│  ─ 频域: Lomb-Scargle → LF, HF, Total Power             │
│  ─ 非线性: Sample Entropy, DFA α1, Stress Index         │
└─────────────────────────────────────────────────────────┘
```

---

## 2. C ABI 桥接模式

### 2.1 头文件定义（`hrs_compute.h`）

```c
typedef struct {
    double sdnn;              // 0
    double rmssd;             // 1
    double pnn50;             // 2
    double mean_rr;           // 3
    double hr;                // 4
    double lf_power;          // 5
    double hf_power;          // 6
    double lf_hf_ratio;       // 7
    double total_power;       // 8
    double sd1;               // 9
    double sd2;               // 10
    double sample_entropy;    // 11
    double dfa_alpha1;        // 12
    double stress_index;      // 13
} hrs_hrv_metrics_t;

// 4 个公共函数，全部 extern "C"
int hrs_compute_hrv(const uint16_t *rr_ms, size_t count, hrs_hrv_metrics_t *out);
int hrs_extract_features(const hrs_hrv_metrics_t *metrics, float *out_features);
int hrs_compute_hr_trend(const double *hr_values, size_t count, double *out_trend);
int hrs_compute_circadian_variation(const double *hrv_values, size_t count, double *out_variation);
```

**设计要点**：
- `extern "C"` 确保 C ABI 兼容，Swift 可直接调用
- 所有指针参数为 `const`（输入）或 caller-allocated（输出）
- 返回值 `int`：0 = 成功，非零 = 错误
- `hrs_hrv_metrics_t` 是 POD 类型（只有 double），无指针成员

### 2.2 Swift 桥接代码（`ComputeBridge.swift`）

```swift
public struct ComputeBridge: Sendable {

    public func computeHRV(from rrIntervalsMs: [UInt16]) throws -> HRVMetrics {
        guard rrIntervalsMs.count >= 2 else { throw ComputeError.tooFewIntervals }

        var metrics = hrs_hrv_metrics_t()  // ① 调用者分配内存
        let result = rrIntervalsMs.withUnsafeBufferPointer { buf in
            hrs_compute_hrv(buf.baseAddress, buf.count, &metrics)  // ② C 函数填充
        }
        guard result == 0 else { throw ComputeError.computationFailed }

        // ③ C struct → Swift struct 逐字段映射
        return HRVMetrics(
            sdnn: metrics.sdnn, rmssd: metrics.rmssd, pnn50: metrics.pnn50,
            meanRR: metrics.mean_rr, hr: metrics.hr,
            lfPower: metrics.lf_power, hfPower: metrics.hf_power,
            lfHfRatio: metrics.lf_hf_ratio, totalPower: metrics.total_power,
            sd1: metrics.sd1, sd2: metrics.sd2,
            sampleEntropy: metrics.sample_entropy, dfaAlpha1: metrics.dfa_alpha1,
            stressIndex: metrics.stress_index
        )
    }
}
```

**三步安全模型**：
1. **调用者分配**：Swift 侧 `var metrics = hrs_hrv_metrics_t()`，C 侧只写不分配
2. **临时指针**：`withUnsafeBufferPointer` 在闭包内有效，闭包结束指针失效
3. **手动映射**：逐字段拷贝到 Swift struct，不保留任何 C 指针引用

---

## 3. C++ 算法详解

### 3.1 时域指标

| 指标 | 算法 | 复杂度 | 代码位置 |
|------|------|--------|---------|
| **SDNN** | `sqrt(Σ(rr_i - mean)² / (n-1))` | O(n) | `compute_sdnn` |
| **RMSSD** | `sqrt(Σ(diff_i²) / n)` | O(n) | `compute_rmssd` |
| **pNN50** | `count(|diff_i| > 50ms) / n × 100` | O(n) | `compute_pnn50` |
| **SD1/SD2** | SD1=SDSD/√2, SD2=√(2·SDNN²-SD1²) | O(n) | `compute_sd1_sd2` |
| **Stress Index** | AMo / (2 × MxDMn × SDNN) | O(n) | `compute_stress_index` |

### 3.2 频域指标（Lomb-Scargle 周期图）

```cpp
// 为什么不用 FFT？
// RR 间期是非等距采样（心跳间隔不等），FFT 要求等距信号
// Lomb-Scargle 专为非等距时间序列设计

// 实现步骤：
// 1. 构建时间数组 t_secs[]（累积 RR 转秒）
// 2. 计算 256 个频率 bin 的功率
// 3. 对每个频率 f，计算:
//    P(f) = (Σ(rr_i × cos(2πf·t_i))² + Σ(rr_i × sin(2πf·t_i))²) / (2σ²N)
// 4. 累加 LF 频段 [0.04, 0.15] Hz 和 HF 频段 [0.15, 0.40] Hz

// 复杂度: O(256 × n)
```

### 3.3 非线性指标

| 指标 | 算法 | 复杂度 | 说明 |
|------|------|--------|------|
| **Sample Entropy** | 嵌入维度 m=2, 容限 r=0.2×SDNN，统计匹配模板 | O(n²) | 值越低越规律（压力/疲劳） |
| **DFA α1** | 短期尺度 4-16 拍的分形指数 | O(n·log n) | 正常 ≈ 1.0，偏离提示异常 |

---

## 4. ComputeMiddleware 触发逻辑

```swift
public func makeComputeMiddleware(
    computeRepo: any ComputeRepository,
    windowDuration: TimeInterval = 300,  // 5 分钟窗口
    stepInterval: TimeInterval = 10      // 10 秒步进
) -> Middleware<AppState, Action> {
    var rrBuffer: [(date: Date, rr: Int)] = []
    var lastComputeTime: Date = Date.distantPast

    return { store, action, next in
        next(action)

        switch action {
        case .heartRateReceived(let samples):
            // ① 积累 RR 间期
            for sample in samples {
                for rr in sample.rrIntervals {
                    rrBuffer.append((sample.timestamp, rr))
                }
            }
            // ② 裁剪 5 分钟窗口
            let windowStart = Date().addingTimeInterval(-windowDuration)
            rrBuffer = rrBuffer.filter { $0.date >= windowStart }

            // ③ 10 秒步进触发
            let now = Date()
            if now.timeIntervalSince(lastComputeTime) >= stepInterval,
               rrBuffer.count >= 2 {
                lastComputeTime = now
                store.dispatch(.computeStarted)

                let rrValues = rrBuffer.map { UInt16($0.rr) }
                Task {
                    let metrics = try computeRepo.computeHRV(from: rrValues.map(Int.init))
                    await MainActor.run { store.dispatch(.hrvComputed(metrics)) }

                    let features = FeatureVector(metrics: metrics)
                    await MainActor.run { store.dispatch(.featuresExtracted(features)) }
                }
            }

        case .clearSamples:
            rrBuffer.removeAll()

        default:
            break
        }
    }
}
```

**关键设计**：
- **滑动窗口**：始终保持最近 5 分钟的 RR 数据
- **步进触发**：不是每次收到数据就计算，而是每 10 秒触发一次
- **级联 dispatch**：`computeStarted` → `hrvComputed` → `featuresExtracted`

---

## 5. 特征顺序一致性（关键契约）

```
索引  │ C++ hrs_extract_features │ Swift HRVMetrics  │ CoreML 输入
──────┼──────────────────────────┼───────────────────┼──────────────
  0   │ sdnn                     │ metrics.sdnn       │ features[0]
  1   │ rmssd                    │ metrics.rmssd      │ features[1]
  2   │ pnn50                    │ metrics.pnn50      │ features[2]
  3   │ mean_rr                  │ metrics.meanRR     │ features[3]
  4   │ hr                       │ metrics.hr         │ features[4]
  5   │ lf_power                 │ metrics.lfPower    │ features[5]
  6   │ hf_power                 │ metrics.hfPower    │ features[6]
  7   │ lf_hf_ratio              │ metrics.lfHfRatio  │ features[7]
  8   │ total_power              │ metrics.totalPower │ features[8]
  9   │ sd1                      │ metrics.sd1        │ features[9]
  10  │ sd2                      │ metrics.sd2        │ features[10]
  11  │ sample_entropy           │ metrics.sampleEntropy │ features[11]
  12  │ dfa_alpha1               │ metrics.dfaAlpha1  │ features[12]
  13  │ stress_index             │ metrics.stressIndex│ features[13]
```

**任何错位都会导致 ML 推理结果错误**。C++ 头文件通过注释标注索引号作为契约。

---

## 6. 重点难点

### 6.1 内存安全边界
- `withUnsafeBufferPointer` 暴露的指针**仅在闭包内有效**
- C 函数**禁止存储指针引用**（只读 + 填充输出）
- `hrs_hrv_metrics_t` 是 POD 类型，跨语言传递安全

### 6.2 Sample Entropy 的 O(n²) 复杂度
- 5 分钟窗口（70 bpm）≈ 350 个 RR 间期 → 350² = 122,500 次比较
- 10 分钟窗口 ≈ 700 个 RR → 490,000 次比较，可能感知延迟
- **优化方向**：限制窗口大小 / KD-Tree 加速匹配 / 降采样

### 6.3 Lomb-Scargle 的精度与性能权衡
- 256 个频率 bin，每个 O(n) → 总 O(256n)
- 频段边界硬编码 [0.04-0.15] 和 [0.15-0.40] Hz
- **已知限制**：n < 4 时返回 0（无法计算频谱）

### 6.4 SD2 的二次修正
```cpp
// 第一次在 compute_sd1_sd2() 中用近似值
sd2 = sd1 * 1.8;  // placeholder

// 然后在 hrs_compute_hrv() 中用精确公式修正
out->sd2 = std::sqrt(std::max(0.0, 2.0 * sdnn * sdnn - sd1 * sd1));
```
