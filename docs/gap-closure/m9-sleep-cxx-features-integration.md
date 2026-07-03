# M9 睡眠 C++ 特征接入说明

## 本轮做了什么

本轮按既定顺序把阶段 5 的 C++ 特征链路补上了：

1. 在 C++ 层新增：
   - `hrs_compute_hr_trend()`
   - `hrs_compute_circadian_variation()`
2. 在 Swift bridge 层新增：
   - `ComputeBridge.computeSleepFeatures(...)`
3. 在仓储层新增：
   - `ComputeRepository.computeSleepFeatures(...)`
   - `ComputeRepositoryImpl.computeSleepFeatures(...)`
4. 在 Feature 层替换：
   - `SleepMiddleware` 不再使用 Swift 本地占位推导
   - 改为真实调用 C++ 睡眠特征

## 全链路位置

当前睡眠特征链路是：

```text
HeartRateSample / HRVMetrics
    -> SleepMiddleware
    -> ComputeRepository.computeSleepFeatures(...)
    -> ComputeBridge.computeSleepFeatures(...)
    -> hrs_compute_hr_trend()
    -> hrs_compute_circadian_variation()
    -> SleepCXXFeatures
    -> SleepWindowInput
    -> SleepInferenceRepository
    -> SleepStageService
```

## 两个函数当前的实现语义

### 1. `hrs_compute_hr_trend()`

输入：

- 当前睡眠窗口内的 `heartRate` 序列

输出：

- 线性回归斜率 `slope`

当前解释：

- `< 0`：窗口内心率总体下降
- `≈ 0`：窗口内心率相对平稳
- `> 0`：窗口内心率总体上升

当前实现方法：

- 用样本下标作为 `x`
- 用 `heartRate` 作为 `y`
- 做最小二乘线性回归
- 返回 slope

### 2. `hrs_compute_circadian_variation()`

输入：

- 最近一段时间的 `RMSSD` 历史序列

输出：

- 归一化振幅 `(max - min) / mean`

当前解释：

- 数值越大，表示近期 HRV 波动幅度越明显
- 数值越小，表示近期 HRV 更平稳

当前实现方法：

- 取输入序列的 `max/min/mean`
- 计算归一化振幅
- 当样本过少或均值过小，返回 `0`

## 为什么这样接

### `hrTrend`

这是一个**短时窗特征**，最自然的输入就是当前窗口内的心率变化。

### `circadianVariation`

这是一个**长时窗特征**，只看当前一个窗口是不够的，所以当前在 `SleepMiddleware` 内维护了一段 `RMSSD` 历史，再送到 C++ 计算。

## 当前实现的边界

这轮已经完成的是：

- **接口落地**
- **Swift/C++ 接线落地**
- **阶段 5 编排链路已真正消费 C++ 输出**

这轮还没有完成的是：

- 与真实睡眠模型训练口径完全对齐
- 基于更长时间跨度的整夜 circadian 建模
- 用真实 `SleepStageClassifier_v1.mlpackage` 验证这两个特征的最终价值

## 风险与后续建议

### 风险点

- `hrs_compute_circadian_variation()` 当前使用的是 `RMSSD` 历史，而不是更复杂的多特征序列
- 历史窗口现在保存在 `SleepMiddleware` 内存中，应用重启后不会延续
- 当前实现适合阶段 5 工程接线，不一定就是最终训练版特征定义

### 后续建议

1. 固化模型输入字段顺序与名称
2. 接入真实 `SleepStageClassifier_v1.mlpackage`
3. 用真实夜间数据回放验证 `hrTrend / circadianVariation`
4. 再决定是否要把 `circadianVariation` 扩展为更长跨度、更复杂的统计特征
