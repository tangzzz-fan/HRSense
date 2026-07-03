# M10 · 后台 BLE + 状态恢复实现设计说明

## 1. 目标

M10 的目标不是单纯“App 进入后台还能连着蓝牙”，而是建立一条完整的 iOS 后台 BLE 恢复链路：

1. App 声明 `bluetooth-central` 后台能力
2. `CBCentralManager` 开启 State Preservation & Restoration
3. 系统在进程被回收后，如有 BLE 事件，可重新唤醒 App
4. App 在 `willRestoreState` 中拿回已恢复的 `CBPeripheral`
5. 恢复后重新发现服务与特征，重新订阅 notify
6. 基于缓存设备信息做最小身份校验
7. 必要时重跑握手，恢复到可继续收流的状态

这条链路是 **Apple 原生 CoreBluetooth 后台恢复机制** 的标准实现方向，不依赖第三方 BLE 框架。

---

## 2. 为什么不能只靠“系统帮我们恢复连接”

`willRestoreState` 只能说明系统把中心管理器和外设对象恢复回来了，但这并不等价于业务会话已经恢复完成。

原因包括：

- 恢复出来的 `CBPeripheral.delegate` 需要重新设置
- 已缓存的 service / characteristic 视图不一定可靠，通常要重新发现
- notify 订阅状态需要重新确认
- 应用层握手状态并不会随 CoreBluetooth 自动恢复
- 本地缓存设备与当前恢复外设之间仍需要做身份校验

因此，M10 必须拆成两层：

- **系统层恢复**：CoreBluetooth 帮我们找回外设对象
- **业务层恢复**：App 重新建立“可安全继续收流”的协议会话

---

## 3. 当前实现分层

### 3.1 App 外壳层

文件：

- `Apps/HRSenseApp/HRSenseApp/Info.plist`
- `Sources/HRSenseAppUI/HRSenseAppContainerView.swift`

职责：

- 在 `Info.plist` 中声明 `UIBackgroundModes = bluetooth-central`
- 通过 SwiftUI `scenePhase` 把前后台切换映射为根 action：
  - `didEnterBackground`
  - `willEnterForeground`

这样 App 生命周期就进入了 Redux 状态树，而不是散落在 UI 回调里。

### 3.2 根状态层

文件：

- `Sources/HRSenseCore/Entities/AppLifecycleState.swift`
- `Sources/HRSenseCore/Entities/ConnectionState.swift`
- `Sources/HRSenseFeature/Actions/Action.swift`
- `Sources/HRSenseFeature/State/AppState.swift`
- `Sources/HRSenseFeature/Reducer/AppReducer.swift`

新增的核心状态：

- `AppLifecycleState`
  - `active`
  - `background`
  - `restoring`

- `ConnectionState`
  - `restored`
  - `restoredValidating`
  - `restoredConnected`

这里的设计原则是：**M10 直接扩展既有根状态，不再平行创建一套“后台恢复专用状态树”**。这样可以保证 UI、日志、测试和中间件都共享同一套真实状态。

### 3.3 BLE 数据源层

文件：

- `Sources/HRSenseData/BLE/BLECentralDataSource.swift`

职责：

1. 初始化 `CBCentralManager` 时传入：

```swift
let options: [String: Any] = [
    CBCentralManagerOptionRestoreIdentifierKey: restoreIdentifier
]
```

2. 在 `willRestoreState` 中：
  - 取回 `CBPeripheral`
  - 重新设置 `peripheral.delegate`
  - 发出恢复的 peripheral IDs
  - 将连接状态推进到 `.restored`

3. 在恢复编排开始时：
  - 重置握手 readiness gate
  - 重新发现服务
  - 将状态推进到 `.restoredValidating`

4. 在恢复成功后：
  - 更新缓存的 `DeviceInfo`
  - 将状态推进到 `.restoredConnected`

这层只负责 **CoreBluetooth 对象生命周期与 GATT 重新发现**，不直接承担业务决策。

### 3.4 Repository 层

文件：

- `Sources/HRSenseCore/Repositories/DeviceRepository.swift`
- `Sources/HRSenseData/Repositories/DeviceRepositoryImpl.swift`

`DeviceRepository` 新增：

```swift
func restoreConnection(cachedDevice: DeviceInfo?) async throws -> DeviceInfo
```

恢复主链路放在 repository 的原因：

- 它需要同时使用 BLE 数据源能力和业务握手能力
- 它比 middleware 更接近设备协议细节
- 它更适合做单元测试与失败分支验证

当前 `restoreConnection` 的实际流程：

1. 确认当前存在系统恢复出的 `connectedPeripheral`
2. 调用 `beginRestoredConnectionValidation()`
3. 重新发现 service / characteristics / notify
4. 读取 `0004 Info` 特征返回的 JSON 信息
5. 与缓存 `DeviceInfo` 做最小身份校验
6. 再次执行 `performHandshake()`
7. 成功后调用 `completeRestoration(with:)`

这里采用 **“恢复后重握手”** 的保守策略，而不是假设协议会话仍然完全有效。这样实现更稳，也更符合后续真机排障习惯。

### 3.5 Middleware 层

文件：

- `Sources/HRSenseFeature/Middleware/ConnectionMiddleware.swift`

职责：

- 订阅 `restoredPeripheralIDsStream`
- 收到恢复事件后派发 `restoreInitiated(peripheralIDs:)`
- 调用 `deviceRepo.restoreConnection(cachedDevice:)`
- 成功时派发 `restoreConnectionRestored(peripheralIDs:)`
- 失败时派发 `restoreFailed(reason:)`

因此 Redux 里的恢复状态流现在是：

```text
didEnterBackground
 -> lifecycle = background

willRestoreState
 -> restoreInitiated
 -> lifecycle = restoring
 -> connection = restored

beginRestoredConnectionValidation
 -> connectionStateChanged(.restoredValidating)

restoreConnection success
 -> connectionStateChanged(.restoredConnected)
 -> restoreConnectionRestored
 -> lifecycle = active
```

---

## 4. 身份校验策略

当前实现的校验是“最小可运行版本”，重点防止恢复到了错误设备：

- `peripheralIdentifier` 必须一致
- `model` 在双方都非空时必须一致
- `protocolVersion` 在双方都有效时必须一致
- `capabilities` 在双方都非零时必须一致

这是一套 **务实的恢复期保护机制**：

- 既避免完全不校验的风险
- 又不把规则写得过死，影响第一阶段落地

后续如果硬件侧补充更稳定的设备唯一标识，可再升级为基于设备序列号或签名信息的更强校验。

---

## 5. 为什么恢复阶段还要重新握手

这是 M10 的关键设计点。

重新握手的价值：

- 重建应用层时序锚点 `t0`
- 重新确认协议版本与 capabilities
- 重新发送 `START_STREAM`
- 保证后续收到的样本和波形可以继续进入既有 M5/M8/M9 链路

如果不做这一步，可能出现：

- notify 已恢复但协议状态不同步
- 本地仍认为已进入 streaming，设备端其实没有
- 心率/波形时间锚点失真
- 恢复后的数据直接进入计算链路，导致异常结果

因此当前版本采用 **“恢复后重新发现 + 重新握手”** 的稳健路线。

---

## 6. 当前范围与未完成部分

### 已完成

- 后台模式接线
- 生命周期状态入树
- CoreBluetooth restoration identifier
- `willRestoreState` 基础恢复入口
- Redux 恢复 action / reducer / UI 状态映射
- 恢复主链路的 repository 编排骨架
- 最小身份校验
- 恢复成功后的 `restoredConnected` 状态
- 最小版 `BackgroundMiddleware` 后台降级策略

---

## 6.1 最小版 BackgroundMiddleware 设计

文件：

- `Sources/HRSenseFeature/Middleware/BackgroundMiddleware.swift`

### 设计目标

这一版不是“完整后台治理系统”，而是一个 **最小可落地、能马上带来收益** 的后台策略层。

它优先解决三件事：

1. 后台时不要继续做不必要的 UI 渲染
2. 后台时不要继续跑通用 stress 推理链路
3. 后台时如果没有显式睡眠监测，不要继续做 HRV 计算

### 当前策略

最小版 `BackgroundExecutionPolicy.minimal` 包含四条规则：

1. `pauseWaveformRenderingInBackground = true`
2. `pauseStressInferenceInBackground = true`
3. `pauseComputeInBackgroundUnlessSleepMonitoring = true`
4. `stopUserScanningOnBackground = true`

### 实际拦截的 action

后台时直接丢弃：

- `waveformSamplesReceived`
- `waveformMetricsUpdated`
- `featuresExtracted`
- `inferenceStarted`
- `inferenceCompleted`

后台且 **未开启睡眠监测** 时额外丢弃：

- `computeStarted`
- `hrvComputed`

进入后台时如果用户还停留在扫描页，则自动发出：

- `stopScanning`

### 为什么这样设计

这是一个明显偏保守、偏务实的版本。

原因是：

- BLE 恢复链路本身必须继续保留
- 睡眠监测是当前项目里最有业务价值的后台计算场景，因此不能一刀切停掉全部 compute
- stress inference 在后台没有直接用户可见价值，优先停掉更合理
- 波形渲染属于典型前台展示能力，后台继续刷新只会消耗 CPU 和内存

### 当前没有做的事

最小版 **故意没有** 直接做这些能力：

- 不做完整任务优先级调度
- 不做后台写盘批处理控制
- 不做 OTA 专项后台策略
- 不做可配置的用户模式切换（例如“后台继续睡眠分析”开关）
- 不做全局日志级别动态切换器

这些能力后续仍可继续演进，但不影响本阶段先把后台 BLE 的资源使用收敛住。

### 与其他 middleware 的协作

为了让最小版策略真的带来性能收益，当前还配合了两处补强：

1. `WaveformMiddleware`
   - 前台约 10Hz 轮询
   - 后台切到更低频率轮询
   - 避免仅仅“丢 action”但 CPU 仍持续空转

2. `LoggingMiddleware`
   - 后台只保留关键状态日志
   - 普通 action 不再持续写 info 日志

这意味着最小版后台策略并不是只有一个文件，而是：

- `BackgroundMiddleware` 负责统一决策入口
- 高频模块各自做最少量的配合降级

### 恢复链路兼容性

M10 新增 `restoredConnected` 后，以下中间件都已补齐恢复态入口：

- `BLEStreamMiddleware`
- `WaveformMiddleware`
- `SleepMiddleware`

否则会出现“恢复状态成功了，但数据流和监测链路没有继续运行”的假恢复现象。

### 仍待继续

- 更细的“是否需要重握手”判定
- `sampleSeq` 连续性校验
- 基于历史 `t0` 的恢复窗口判断
- 后台降级策略 `BackgroundMiddleware`
- 真机后台唤醒与耗电表现验收

---

## 7. 性能与兼容性考量

### 性能

- 当前恢复路径只在系统实际触发恢复时运行，不影响前台常规连接吞吐
- `0004 Info` 采用轻量 JSON 读回，额外成本较低
- 恢复成功后仍复用既有波形、计算、推理和持久化链路，不额外引入复制层

### 兼容性

- `State Preservation & Restoration` 依赖 iOS 原生 CoreBluetooth 行为，真机是必须验证场景
- `UIBackgroundModes = bluetooth-central` 符合苹果官方后台 BLE 使用方式
- 当前实现对 macOS / 非 iOS 编译路径保持兼容，因为后台恢复能力仅在 iOS App 壳层实际生效

---

## 8. 开发注意事项

- `willRestoreState` 可能早于 `centralManagerDidUpdateState`，恢复编排不要假定蓝牙状态流一定先后固定
- 恢复得到的 `CBPeripheral` 一定要重新设置 delegate
- 增加新的 `ConnectionState` 后，UI / reducer / 测试中的 `switch` 都要同步补全，否则会直接编译失败
- Simulator 只能验证编译和状态流，**不能代替真机后台 BLE 恢复验收**

---

## 9. 当前结论

M10 现在已经从“文档计划”进入“可运行骨架 + 恢复编排主链路”的阶段。

当前最核心的成果是：

- 后台 BLE 恢复不再只是 `willRestoreState` 的回调占位
- 已经形成一条真实的业务恢复路径：
  - 系统恢复
  - 状态入树
  - 重新发现
  - 最小身份校验
  - 重新握手
  - 恢复完成

下一步最合理的增量是：

1. 补 `BackgroundMiddleware` 降级策略
2. 补更严格的重握手判定
3. 做真机后台恢复验收记录
