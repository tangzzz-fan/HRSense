# M10 · 后台 BLE + 状态恢复 — 实施计划

## 摘要

实现 iOS 后台 BLE 运行与 CoreBluetooth 状态恢复（State Preservation & Restoration）。当 App 被系统杀死后，蓝牙事件可唤醒 App 并恢复连接/订阅。

**回溯修改说明**：M10 会扩展 M3 定义的 `ConnectionState` 与 M4 定义的 `Action` / `AppState`。这些类型的所有权仍保留在原文件中，本里程碑以增量方式回写，不另起平行状态体系。

**依赖**：M4（Redux 展示层）。

---

## 阶段 1：Info.plist 后台模式

`Apps/HRSenseApp/HRSenseApp/Info.plist`：
```xml
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
</array>
```

---

## 阶段 2：BLECentralDataSource 添加恢复标识符

```swift
private let restoreIdentifier = "com.hrsense.ble-central-restore"

// 初始化 CBCentralManager 时
let options: [String: Any] = [
    CBCentralManagerOptionRestoreIdentifierKey: restoreIdentifier
]
centralManager = CBCentralManager(delegate: self, queue: queue, options: options)
```

---

## 阶段 3：实现 willRestoreState

```swift
func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
    guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] else { return }
    for peripheral in peripherals {
        peripheral.delegate = self
        if peripheral.state == .connected {
            restoredConnectedPeripherals.append(peripheral)
        } else if peripheral.state == .connecting {
            restoredConnectingPeripherals.append(peripheral)
        }
    }
    onRestoreState?(peripherals)
}
```

**关键细节**：
- `willRestoreState` 回调**先于 `centralManagerDidUpdateState`** 触发
- 恢复的外设代理为 nil，需重新设置 `peripheral.delegate = self`
- `.connected` 的外设需重新发现服务（缓存可能过期）
- `.connecting` 的外设等待常规 `didConnect` 回调

---

## 阶段 4：添加 AppLifecycleState 到 Redux

`Sources/HRSenseCore/Entities/AppLifecycleState.swift`：
```swift
enum AppLifecycleState: Equatable {
    case active       // 前台
    case background   // 后台
    case restoring    // 系统 kill 后唤醒恢复中
}
```

`AppState` 新增 `var lifecycle: AppLifecycleState`。

---

## 阶段 5：生命周期 Action + Reducer

本阶段直接修改 M3 / M4 既有基础类型，而不是创建新的旁路状态。

| Action | State 变更 |
|---|---|
| `didEnterBackground` | `lifecycle = .background` |
| `willEnterForeground` | `lifecycle = .active` |
| `restoreInitiated` | `lifecycle = .restoring`，`connection = .restored` |
| `restoreConnectionRestored` | 连接恢复成功 |
| `restoreFailed` | `connection = .disconnected(reason:)` |

---

## 阶段 6：ConnectionMiddleware 恢复流程

当 `onRestoreState` 触发时：

1. dispatch `restoreInitiated(peripheralIDs)`
2. 等待 `centralManagerDidUpdateState(.poweredOn)`
3. 对每个已恢复的外设：重新发现服务 → 重新订阅
4. 会话验证：读 Info 特征 → 对比已缓存 DeviceInfo → 确认同一设备
5. **重握手判定**（需重握手的情况）：
   - 无缓存的 DeviceInfo
   - 设备身份不匹配
   - 本地 t0 > 30 秒
   - 首帧 sampleSeq 不连续
6. 重握手：写 HELLO → 等 HELLO_ACK → 写 START_STREAM
7. dispatch `restoreConnectionRestored`

**重连状态机扩展**（新增状态）：
```
case restored              // 连接恢复，验证中
case restoredValidating    // 重握手中
case restoredConnected     // 完全恢复
```

这些状态追加到 `Sources/HRSenseCore/Entities/ConnectionState.swift`，保持 M3 与 M10 共用同一个连接状态枚举。

---

## 阶段 7：BackgroundMiddleware 降级策略

`Sources/HRSenseFeature/Middleware/BackgroundMiddleware.swift`：

| 组件 | 后台行为 |
|---|---|
| UI 刷新计时器 | 停止 |
| ComputeMiddleware | 暂停（除非用户启用录制） |
| InferenceMiddleware | 暂停 |
| BLE Notify 接收 | 继续（CoreBluetooth 系统级，无需 App 操作） |
| BLE 扫描 | 必须带 `withServices` 过滤（后台强制） |
| 日志刷新 | 降级为仅 error |

通过 `BackgroundTaskProviding` 协议抽象 `UIApplication` 依赖。

---

## 阶段 8：App 外壳集成

`HRSenseAppApp.swift`：
```swift
@Environment(\.scenePhase) private var scenePhase
.onChange(of: scenePhase) { oldPhase, newPhase in
    switch newPhase {
    case .background: store.dispatch(.appLifecycle(.didEnterBackground))
    case .active: store.dispatch(.appLifecycle(.willEnterForeground))
    default: break
    }
}
```

---

## 验收标准（真机）
- [ ] App 进后台后仍能接收 notify（短时场景）
- [ ] 进程被系统回收后，蓝牙事件唤醒 App 并恢复连接/订阅（`willRestoreState` 路径命中，日志可见）
- [ ] 记录后台唤醒/耗电表现

## 预估文件数：~8 个新文件 + 多处修改
