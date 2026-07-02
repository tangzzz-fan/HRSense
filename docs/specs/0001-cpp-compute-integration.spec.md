# 0001 · C++ 计算层集成

- **状态**: draft（占位，暂不详细设计）
- **作者**: TBD
- **创建日期**: TBD
- **关联文档**: [../06-coreml-and-compute.md](../06-coreml-and-compute.md)、[../02-architecture.md](../02-architecture.md)

> 说明：当前阶段**不做详细设计**。本 spec 仅记录问题边界与待决项，作为占位，后续再细化。

## 1. 背景与问题

App 需要对心率 / RR 数据做重计算（预处理、HRV 指标、特征提取），并把特征喂给 CoreML。计算密集且未来可能跨平台复用，计划用 **C++** 实现，需确定其与 Swift 的集成方式与接口边界。

## 2. 目标 / 非目标

### 目标
- 确定 C++ 计算库与 Swift App 的集成方案与接口边界。
- 保证"训练/推理特征提取共用同一实现"，避免 train/serve skew。
- 计算库可独立单元测试。

### 非目标（本 spec 暂不覆盖）
- 具体 HRV 算法与数值细节。
- CoreML 模型结构。
- 性能调优的具体手段。

## 3. 方案（已定：C ABI）

集成方式已确定为 **C ABI 方案**（详见 `06` 第 2.3 节）：
- C++ 实现内部逻辑，**对外只暴露一层 `extern "C"` 纯 C 接口**（POD/值类型进出）。
- Swift 经桥接头 / module map 调用该 C 接口。
- C++ 源码以 **SwiftPM target** 打包（`Compute/`）。

**仍需在本 spec 细化**：具体 C 接口签名、内存所有权/生命周期、错误返回约定、线程安全约定。

窄接口示意（待定稿）：
```c
// 纯 C 接口，Swift 侧只见这一层
typedef struct { double sdnn; double rmssd; /* ... */ } hrs_hrv_metrics_t;

// 返回 0 表示成功；out 由调用方分配
int hrs_compute_hrv(const uint16_t* rr_ms, size_t count, hrs_hrv_metrics_t* out);
int hrs_extract_features(const double* window, size_t count,
                         float* out_features, size_t out_capacity, size_t* out_len);
```

## 4. 备选方案与取舍
- **Swift/C++ 互操作（未采用）**：能减少桥接样板，但工具链成熟度/边界坑较多，暂不用。
- **Objective-C++ 包装（可作补充）**：如需传递复杂对象，可在 C 接口之上再加薄 Obj-C++ 层，但优先保持纯 C 边界以稳定 ABI。
- 选 **C ABI** 的核心理由：边界清晰、ABI 稳定、易单测、C++ 细节不外泄、便于未来替换实现。

## 5. 影响面
- App：新增计算桥模块 + `ComputeRepositoryImpl`。
- 构建：SwiftPM / Xcode 对 C++ 目标的配置。
- 测试：计算库独立单测 + 与 Swift 边界的集成测试。

## 6. 测试策略
- 对 C++ 计算给定输入的黄金值（golden）测试。
- Swift 侧边界的往返测试（值进值出）。

## 7. 决策与开放问题（已固化）
- [x] 集成方案：**C ABI**。
- [x] **构建/依赖管理**：以 **SwiftPM 源码 target** 集成（`HRSenseCompute` 包内含 C++ target + 纯 C 接口 target + Swift 封装）；保留后续切换 **预编译 xcframework** 的可能。
- [x] **特征契约单一真相**：14 维 HRV 特征（spec 0002 §3.2）**只在 C++ 实现一次**，训练导出工具与端侧运行共用同一实现，杜绝 train/serve skew。
- [x] **内存/线程模型**：**调用方分配输出缓冲**（不跨边界 malloc/free）；计算函数**无状态、可重入、线程安全**，可在后台队列调用；如需持久状态，用 **opaque handle**（`create/destroy` 由调用方管理）。
- [x] **错误约定**：函数返回 `int` 状态码（0 成功，非 0 错误码），不抛异常跨边界。

## 8. 里程碑 / 任务拆分
- [x] 选定集成方案：C ABI。
- [ ] 定义窄 C 接口签名与数据类型（本 spec 定稿）。
- [ ] 搭建可编译 + 可单测的最小骨架（`Compute/` SwiftPM target）。
- [ ] 接入 Redux Compute Middleware。

## 9. 算法原型移植流程（Python / MATLAB → C++ / CoreML）

> 对应 JD 加分项"能阅读 Python/MATLAB，理解算法工程师原型"。定义一条把原型稳定落到端上的流程。

```mermaid
graph LR
    P[算法原型 Python/MATLAB] --> C[对齐 I/O 与数值口径]
    C --> M{类型}
    M -- 计算/DSP/特征 --> CPP[移植为 C++ (本包)]
    M -- 模型 --> ML[转 CoreML (coremltools, spec 0002)]
    CPP --> G[黄金值对拍]
    ML --> G
    G --> R[接入 Redux / 端上]
```

- **对齐口径**：明确输入采样率/单位/窗口、输出定义、边界与数值精度（float/double）。
- **黄金值对拍（关键）**：用原型对一组固定输入产出**参考输出**，C++/CoreML 移植后对同一输入比对，误差在阈值内才算通过（防止移植走样）。
- **计算类**（HRV/滤波/特征）→ 移植到本包 C++；**模型类** → 走 coremltools 转换（spec 0002）。
- **回归**：把黄金样例纳入单测，原型更新时重新对拍。
- 参考文件组织：原型与对拍脚本放 `tools/`（构建期，不进 App）。
