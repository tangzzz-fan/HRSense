# 改进建议与提升方向

> 以资深 iOS 架构师视角，指出项目中可优化的技术债务、设计改进点和工程化提升方向。知无不言。

---

## 1. 线程安全与并发

### 1.1 `@unchecked Sendable` 的广泛使用

**现状**：多个类标记为 `@unchecked Sendable`（`BLECentralDataSource`、`MetricsCollector`、`WaveformRingBuffer`、`ComputeBridge` 等），手动用 `NSLock` 保护。

**风险**：
- 编译器无法验证线程安全，完全依赖开发者自觉
- 新增属性时容易忘记加锁
- `NSLock` 不可重入，嵌套调用可能死锁

**建议**：
```swift
// 方案 A：迁移到 Actor（Swift 6 原生）
public actor WaveformRingBuffer {
    private var buffer: [WaveformSample] = []
    // 无需 NSLock，Actor 自动串行
}

// 方案 B：对高频读/低频写的场景，使用 os_unfair_lock 替代 NSLock
// os_unfair_lock 更轻量，但不可重入

// 方案 C：对 MetricsCollector 等只增计数器，使用 Atomics
import Atomics
private let _totalSamplesReceived = ManagedAtomic<Int>(0)
```

**优先级**：高 — Swift 6 严格并发检查下，`@unchecked Sendable` 会产生大量警告。

### 1.2 Middleware 闭包内的可变状态

**现状**：Middleware 工厂函数内部使用 `var` 闭包捕获：
```swift
public func makeComputeMiddleware(...) -> Middleware<AppState, Action> {
    var rrBuffer: [(date: Date, rr: Int)] = []      // 可变闭包捕获
    var lastComputeTime: Date = Date.distantPast    // 可变闭包捕获

    return { store, action, next in
        // rrBuffer 和 lastComputeTime 在闭包内修改
    }
}
```

**风险**：
- Middleware 在 MainActor 上执行，目前安全
- 但如果未来 TGReduxKit 支持并发 dispatch，这些 `var` 会产生 data race

**建议**：
- 将闭包可变状态封装为 class + NSLock，或迁移到 actor
- 或使用 `@MainActor` 标注 Middleware 闭包，明确线程约束

---

## 2. 错误处理

### 2.1 强制类型转换

**现状**：
```swift
// ConnectionMiddleware.swift
await MainActor.run {
    store.dispatch(.errorOccurred(error is AppError ? (error as! AppError) : .connectionTimeout))
}
```

**问题**：`error as! AppError` 是强制转换，如果 error 不是 AppError 但 `is` 判断出错（理论上不会，但风格不安全）。

**建议**：
```swift
let appError = (error as? AppError) ?? .connectionTimeout
await MainActor.run { store.dispatch(.errorOccurred(appError)) }
```

### 2.2 try? 的静默失败

**现状**：
```swift
let cxxFeatures = (try? computeRepository.computeSleepFeatures(...)) ?? SleepCXXFeatures()
```

**问题**：`try?` 静默吞掉错误，无法区分"计算返回零值"和"计算失败"。

**建议**：
```swift
do {
    cxxFeatures = try computeRepository.computeSleepFeatures(...)
} catch {
    HRSenseLogging.error(.computeInfer, "Sleep C++ features failed: \(error)")
    cxxFeatures = SleepCXXFeatures()
}
```

---

## 3. 测试覆盖

### 3.1 缺少集成测试

**现状**：测试文件集中在 Protocol、Data、SimulatorKit 层，但缺少：
- Middleware 之间的链式集成测试（如 heartRateReceived → hrvComputed → inferenceCompleted）
- 完整管线端到端测试（BLE 原始字节 → 最终 AppState）

**建议**：
```swift
// 管线集成测试示例
func testFullPipelineFromRRToInference() async {
    let store = TestStore(initialState: AppState())
    let mockCompute = MockComputeRepository(metrics: expectedMetrics)
    let mockInference = MockInferenceRepository(result: expectedResult)

    let middleware = [
        makeComputeMiddleware(computeRepo: mockCompute),
        makeInferenceMiddleware(inferenceRepo: mockInference)
    ]
    store.middlewares = middleware

    store.dispatch(.heartRateReceived([sampleWithRR]))

    // 等待异步完成
    await store.waitForAction(.inferenceCompleted, timeout: 2.0)

    XCTAssertEqual(store.state.inference.latestResult?.label, "Baseline")
}
```

### 3.2 C++ 计算层缺少边界测试

**现状**：`hrs_compute_hrv` 的 `count < 2` 测试覆盖不足。

**建议**：补充以下边界用例：
- n = 2（最小有效输入）
- 所有 RR 相同（方差 = 0，频域应返回 0）
- RR 中有极端异常值（如 2000ms）
- 极短窗口（< 30s，频域无法计算）

---

## 4. 性能优化

### 4.1 Sample Entropy O(n²) 优化

**现状**：双重循环遍历所有模板对，5 分钟窗口约 350 个 RR → 122,500 次比较。

**建议**：
```cpp
// 方案 A：限制搜索窗口
static double compute_sample_entropy(const std::vector<double> &x, int m, double r) {
    size_t N = std::min(x.size(), (size_t)300);  // 最多取 300 个点
    // ... 后续计算
}

// 方案 B：KD-Tree 或 Ball-Tree 加速近邻搜索
// 将 O(n²) 降到 O(n·log n)

// 方案 C：近似 Sample Entropy（ApEn 变体）
```

### 4.2 Reducer 中的数组截断

**现状**：
```swift
case .heartRateReceived(let samples):
    state.live.recentSamples.append(contentsOf: samples)
    if state.live.recentSamples.count > 600 {
        state.live.recentSamples = Array(state.live.recentSamples.suffix(600))
        // 每次超过 600 都创建新数组
    }
```

**问题**：每次截断都创建新数组，高频触发时有 GC 压力。

**建议**：
```swift
// 使用 Deque（swift-collections）或自定义 Ring Buffer
import DequeModule
var recentSamples: Deque<HeartRateSample> = []

case .heartRateReceived(let samples):
    state.live.recentSamples.append(contentsOf: samples)
    while state.live.recentSamples.count > 600 {
        state.live.recentSamples.removeFirst()
    }
```

### 4.3 Lomb-Scargle 频率 bin 数量

**现状**：固定 256 个频率 bin。

**建议**：根据数据长度自适应：
```cpp
// 数据短（n < 64）时减少 bin 数量
int bins = std::min(256, std::max(32, (int)(total_time * 2)));
```

---

## 5. 架构改进

### 5.1 Middleware 闭包可变状态的类型化

**现状**：每个 Middleware 函数内部用 `var` 维护私有状态，外部无法观察或重置。

**建议**：将 Middleware 状态显式建模：
```swift
// 方案：Middleware 状态提升为 class
final class ComputeMiddlewareState {
    var rrBuffer: [(date: Date, rr: Int)] = []
    var lastComputeTime: Date = .distantPast
}

public func makeComputeMiddleware(
    computeRepo: any ComputeRepository,
    state: ComputeMiddlewareState = ComputeMiddlewareState()
) -> Middleware<AppState, Action> {
    // 使用 state.rrBuffer 代替 var rrBuffer
}
```

**好处**：
- 可在测试中注入和检查内部状态
- 可在 Debug 面板中展示 Middleware 内部状态
- 支持状态重置（如 disconnect 后清理）

### 5.2 Action 枚举膨胀

**现状**：`Action` 枚举包含约 40+ 个 case，且持续增长。

**建议**：按领域分组为嵌套枚举：
```swift
public enum Action {
    // 连接域
    case connection(ConnectionAction)
    // 数据域
    case live(LiveAction)
    // 计算域
    case compute(ComputeAction)
    // 推理域
    case inference(InferenceAction)
    // 睡眠域（已实现）
    case sleep(SleepAction)
    // OTA 域
    case ota(OTAAction)
    // 波形域
    case waveform(WaveformAction)
}

public enum ConnectionAction {
    case startScanning
    case stopScanning
    case connect(UUID)
    case disconnect
    case connectionStateChanged(ConnectionState)
    // ...
}
```

**好处**：
- Reducer 可以按领域分发，减少巨型 switch
- 新增 action 不影响其他领域的 case 列表

### 5.3 AppState 的 recentSamples 不应放在 Redux State

**现状**：`AppState.live.recentSamples` 最多 600 个 `HeartRateSample`，每次更新触发 SwiftUI diff。

**问题**：
- 600 个 struct 的 `Equatable` 比较开销
- SwiftUI 无法高效 diff 大数组变化
- 波形数据已经在 `WaveformRingBuffer` 中独立管理，心率数据应该一致

**建议**：
```swift
// 方案：将 recentSamples 提取到独立的 Ring Buffer
public final class HeartRateSampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [HeartRateSample] = []
    private let capacity: Int = 600

    public func push(_ samples: [HeartRateSample]) { ... }
    public func readRecent(count: Int) -> [HeartRateSample] { ... }
}

// AppState 只保留摘要
public struct LiveState {
    public var currentHeartRate: Int?
    public var lastUpdated: Date?
    // 移除 recentSamples: [HeartRateSample]
}
```

---

## 6. 可观测性提升

### 6.1 缺少 Performance Metrics 的持久化

**现状**：`MetricsCollector` 的 KPI 只在内存中，App 重启后丢失。

**建议**：
```swift
// 定期快照到 UserDefaults 或文件
extension MetricsCollector {
    func persistSnapshot() {
        let data = try? JSONEncoder().encode(kpiSnapshot())
        UserDefaults.standard.set(data, forKey: "latestKPI")
    }
}
```

### 6.2 缺少 Middleware 执行耗时追踪

**现状**：无法知道每个 Middleware 处理一个 action 花了多长时间。

**建议**：
```swift
public func makeTimingMiddleware() -> Middleware<AppState, Action> {
    { store, action, next in
        let start = CFAbsoluteTimeGetCurrent()
        next(action)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        if elapsed > 1.0 {  // 超过 1ms 记录
            HRSenseLogging.info(.perf, "Middleware took \(String(format: "%.2f", elapsed))ms for \(action)")
        }
    }
}
```

### 6.3 DiagnosticPanelView 限制在 DEBUG

**现状**：`#if DEBUG` 包裹整个 DiagnosticPanelView，Release 包无法使用。

**建议**：
- 通过 feature flag 或隐藏手势（如长按 Logo 5 次）在 Release 中启用
- 或至少将 JSON 导出功能保留在 Release 中（用户可发送给开发者）

---

## 7. 工程化提升

### 7.1 缺少 CI 中的协议兼容性检查

**建议**：在 CI 中添加一个测试，确保 `HRSenseProtocol` 的编解码结果与已知 golden 字节一致：
```swift
func testProtocolGoldenBytes() {
    let sample = DeviceSample(timestamp: 1000, heartRate: 72, rrIntervals: [830, 835])
    let encoded = encodeData(sample, seq: 42, mtu: 185)
    let expected = loadGoldenBytes("golden_data_sample.bin")
    XCTAssertEqual(encoded, expected, "Protocol encoding changed! Update golden file if intentional.")
}
```

### 7.2 CoreML 模型的 Feature Contract Version 验证

**现状**：`featureContractVersion` 在模型元数据中声明，但推理时不验证特征语义。

**建议**：在 `CoreMLService` 中增加特征名称验证：
```swift
// 检查模型输入是否真的有 "features" 这个名称
if let inputDesc = model.modelDescription.inputDescriptionsByName["features"] {
    let shape = inputDesc.multiArrayConstraint?.shape
    assert(shape == [14], "Feature count mismatch")
}
```

### 7.3 模拟器与真机的能力差异收敛

**现状**：模拟器在 `HELLO_ACK` 中声明 capabilities，App 上层按能力自适应。

**建议**：将能力检查集中在一个 Adapter 中：
```swift
struct DeviceCapabilities {
    let raw: UInt32

    var supportsRR: Bool { raw & (1 << 1) != 0 }
    var supportsWaveform: Bool { raw & (1 << 10) != 0 }
    var supportsOTA: Bool { raw & (1 << 9) != 0 }

    // Middleware 根据 capabilities 决定是否启动对应管线
}
```

---

## 8. 优先级矩阵

| 建议 | 影响 | 工作量 | 优先级 |
|------|------|--------|--------|
| Swift 6 并发安全迁移 | 高（编译警告消除） | 中 | **P0** |
| Middleware 闭包可变状态类型化 | 中（可测试性提升） | 低 | **P1** |
| Sample Entropy 性能优化 | 中（大窗口场景） | 低 | **P1** |
| Reducer 数组截断优化 | 低（当前数据量小） | 低 | P2 |
| Action 枚举分组 | 中（可维护性） | 中 | P2 |
| 管线集成测试 | 高（回归保护） | 高 | P2 |
| 协议 Golden Bytes CI | 中（协议漂移防护） | 低 | P2 |
| recentSamples 提取到独立 Buffer | 中（UI 性能） | 中 | P3 |
| DiagnosticPanel Release 可用 | 低（现场调试） | 低 | P3 |
| Middleware 耗时追踪 | 中（性能调优） | 低 | P3 |
