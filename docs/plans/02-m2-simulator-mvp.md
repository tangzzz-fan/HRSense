# M2 · macOS 模拟器 MVP 实施计划

## 摘要

M2 构建 macOS BLE 外设，使其可被发现、连接、握手并按 `HRSenseProtocol` 推送心率数据。该模拟器提供带 UI 的 SwiftUI 应用，以及用于 CI 的无界面模式。

**先决条件（硬依赖）**：M1 必须在 `Sources/HRSenseProtocol/` 下存在一个可工作的 `HRSenseProtocol` 包，提供 `encodeCommand`、`encodeData`、`FrameAssembler`、`DecodedFrame` 以及所有模型类型（`Command`、`DeviceSample`、`Capabilities`、UUID 常量）。

---

## 第一步：项目脚手架（Package.swift 与 Target 结构）

在开始编写模拟器代码之前，仓库必须能够编译一个最小的 `HRSenseSimulatorKit` target。

**1a. 添加 `HRSenseSimulatorKit` target 到根 Package.swift**

在 `Package.swift` 的 `targets` 数组中新增条目：

```swift
.target(
    name: "HRSenseSimulatorKit",
    dependencies: ["HRSenseProtocol"]
),
.testTarget(
    name: "HRSenseSimulatorKitTests",
    dependencies: ["HRSenseSimulatorKit"]
),
```

同时更新 `products` 数组，添加 `.library(name: "HRSenseSimulatorKit", targets: ["HRSenseSimulatorKit"])`。

**1b. 创建 Sources 与 Tests 目录**

- `Sources/HRSenseSimulatorKit/` —— 一个占位文件 `SimulatorKit.swift`（仅需 `import HRSenseProtocol`），用于验证编译。
- `Tests/HRSenseSimulatorKitTests/` —— 一个空测试文件，用于验证 `swift test` 能找到该 target。

**1c. 运行 `swift build` and `swift test` —— 必须通过**

---

## 第二步：HRSenseSimulatorKit 核心类型与状态机

编写不依赖 CoreBluetooth 的纯逻辑组件。这样可以在无蓝牙依赖的情况下进行单元测试。

**2a. `Sources/HRSenseSimulatorKit/DeviceStateMachine.swift`**

实现文档 05 第 2.2 节中定义的外部设备状态机：

```
Advertising → Connected（Central 已连接 + 已订阅通知）
Connected → HandshakeDone（收到 HELLO，回复 HELLO_ACK）
HandshakeDone → Streaming（收到 START_STREAM）
Streaming → HandshakeDone（收到 STOP_STREAM）
任何状态 → Advertising（断连）
```

定义为 `DeviceState` 枚举：`advertising`、`connected`、`handshakeDone`、`streaming`。提供 `transition(on:)` 方法，接受事件并返回新的 `DeviceState`。必须为纯函数。

**2b. `Sources/HRSenseSimulatorKit/Models/SimulatorConfig.swift`**

```swift
struct SimulatorConfig {
    var model: String             // "HRSense-Sim"
    var firmwareVersion: String   // "1.0.0-sim"
    var protocolVersion: UInt8    // 0x01
    var capabilities: UInt32      // 能力位图
    var advertisingLocalName: String // "HRSense-Sim"
    var mtu: Int                  // 默认 185
}
```

**2c. `Sources/HRSenseSimulatorKit/Models/ScenarioModels.swift`**

用于表示场景脚本的数据类型（JSON 可解码）：`Scenario`、`ScenarioStep`、`ScenarioStepAction` 枚举。

---

## 第三步：数据生成器

实现可插拔的生成器，提供可测的数据流。

**3a. `Sources/HRSenseSimulatorKit/Generators/DataGeneratorProtocol.swift`**

```swift
protocol DataGeneratorProtocol: AnyObject {
    var mode: GeneratorMode { get }
    func start()
    func stop()
    func nextSample(timestampMs: UInt32) -> DeviceSample
}
```

**3b–3f. 具体生成器**

- `RestingHRGenerator.swift`：60–75 bpm 范围内以小振幅正弦波变化
- `ExerciseHRGenerator.swift`：根据强度曲线生成
- `ManualHRGenerator.swift`：支持外部滑杆控制
- `AnomalyHRGenerator.swift`：产生异常值
- `ReplayHRGenerator.swift`：从 CSV 文件读取并回放
- `CSVParser.swift`：CSV 行解析器

---

## 第四步：命令处理器

**4a. `Sources/HRSenseSimulatorKit/CommandProcessor.swift`**

```swift
final class CommandProcessor {
    func process(command: Command, seq: UInt8, mtu: Int) -> [Data]
}
```

**4b. 命令路由**

- `HELLO (0x01)` → 返回 `HELLO_ACK`，切换到 `handshakeDone`
- `GET_INFO (0x02)` → 返回 `INFO`
- `START_STREAM (0x03)` → 启动生成器，切换到 `streaming`
- `STOP_STREAM (0x04)` → 停止生成器，切换到 `handshakeDone`
- `SET_CONFIG (0x05)` → 更新配置
- 未知 opcode → 返回 ERROR

---

## 第五步：PeripheralManager 封装（CoreBluetooth 集成）

**5a. `Sources/HRSenseSimulatorKit/Peripheral/BluetoothPermission.swift`**

封装 `CBPeripheralManager.authorization` 与权限状态。

**5b. `Sources/HRSenseSimulatorKit/Peripheral/SimulatedPeripheral.swift`**

核心类，遵循 `CBPeripheralManagerDelegate`。引用 `HRSenseProtocol` 编码器、`CommandProcessor`、当前 `DataGeneratorProtocol`、`FaultInjector`。

委托队列使用 `DispatchQueue(label: "com.hrsense.simulator.ble")`。

**5c. 生成器计时器逻辑**

使用 `DispatchSourceTimer` 按 1 Hz 触发数据推送。

---

## 第六步：场景引擎（用于 CI/headless）

**6a. `Sources/HRSenseSimulatorKit/Scenario/ScenarioEngine.swift`**

驱动操作之间的定时状态变更与延迟。

**6b. `Sources/HRSenseSimulatorKit/Scenario/ScenarioParser.swift`**

从文件路径加载并解码 `Scenario` JSON。

**6c. `Scenarios/example-resting.json`**

示例场景文件。

---

## 第七步：故障注入（M2 最小骨架）

**7a. `Sources/HRSenseSimulatorKit/Faults/FaultInjector.swift`**

```swift
final class FaultInjector {
    var dropProbability: Double = 0.0
    var corruptCRCProbability: Double = 0.0
    var latencyMilliseconds: Range<Int>?
}
```

---

## 第八步：macOS App 外壳

**8a–8g. App 外壳文件**

- `Apps/HRSenseSimulator/HRSenseSimulator.xcodeproj`
- `SimulatorApp.swift`：`@main` 入口，支持 `--headless --scenario <path>`
- `SimulatorViewModel.swift`：`@MainActor ObservableObject`
- `ContentView.swift`：控制面板 UI
- `Info.plist`：`NSBluetoothAlwaysUsageDescription`
- `HRSenseSimulator.entitlements`：App Sandbox + Bluetooth

---

## 第九步：工作区与链接

- 创建/更新 `HRSense.xcworkspace`
- 将 `HRSenseSimulatorKit` 链接到 App target

---

## 第十步：测试与验收

**10a. 单元测试**

覆盖：`DeviceStateMachine`、数据生成器、`CommandProcessor`、场景解析器、故障注入。

**10b. 手动验收（M2 检查清单）**

1. 用 LightBlue/nRF Connect 发现、读 Info、订阅 Notify、收到 HR 帧
2. HELLO→HELLO_ACK 正确；START_STREAM/STOP_STREAM 生效
3. `--headless --scenario <file>` 无 UI 启动并按脚本产数

---

## 需要创建的文件完整列表

**Sources/HRSenseSimulatorKit/**

```
Sources/HRSenseSimulatorKit/
├── SimulatorKit.swift
├── DeviceStateMachine.swift
├── CommandProcessor.swift
├── Models/
│   ├── SimulatorConfig.swift
│   └── ScenarioModels.swift
├── Peripheral/
│   ├── BluetoothPermission.swift
│   └── SimulatedPeripheral.swift
├── Scenario/
│   ├── ScenarioEngine.swift
│   └── ScenarioParser.swift
├── Generators/
│   ├── DataGeneratorProtocol.swift
│   ├── RestingHRGenerator.swift
│   ├── ExerciseHRGenerator.swift
│   ├── ManualHRGenerator.swift
│   ├── AnomalyHRGenerator.swift
│   ├── ReplayHRGenerator.swift
│   └── CSVParser.swift
├── Faults/
│   └── FaultInjector.swift
└── OTA/
    └── .gitkeep
```

**Tests/HRSenseSimulatorKitTests/**

```
Tests/HRSenseSimulatorKitTests/
├── DeviceStateMachineTests.swift
├── CommandProcessorTests.swift
├── DataGeneratorTests.swift
├── CSVParserTests.swift
├── FaultInjectorTests.swift
├── ScenarioParserTests.swift
└── SimulatedPeripheralTests.swift
```

**Apps/HRSenseSimulator/**

```
Apps/HRSenseSimulator/
├── HRSenseSimulator.xcodeproj/
└── HRSenseSimulator/
    ├── SimulatorApp.swift
    ├── SimulatorViewModel.swift
    ├── ContentView.swift
    ├── Info.plist
    ├── HRSenseSimulator.entitlements
    └── Assets.xcassets/
```

**Scenarios/**（仓库根目录下）

```
Scenarios/
├── example-resting.json
├── example-exercise.json
└── example-faults.json
```

---

## 关键文件依赖与排序

```
M1 (HRSenseProtocol) → 第二步（类型与状态机）
第一步（脚手架）→ 第二步 → 第三步（生成器）→ 第四步（命令处理器）
                                    ↓
                    第五步（CBPeripheralManager 封装）
                                    ↓
                    第六步（场景引擎）→ 第八步（macOS App）
                    第七步（故障注入）  第九步（工作区）
                                    ↓
                    第十步（测试与验收）
```
