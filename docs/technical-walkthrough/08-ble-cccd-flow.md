# BLE 连接与 CCCD 订阅流程

> 本文档基于 HRSense 项目实际实现，讲解 BLE GATT 连接建立、CCCD 订阅、握手的完整流程。

## 1. CCCD 是什么

CCCD（Client Characteristic Configuration Descriptor，UUID `0x2902`）是 BLE GATT 标准描述符，用于：

| 写入值 | 含义 | 效果 |
|--------|------|------|
| `0x0100` | 启用 Notification | Peripheral 通过 notify 发送数据（无需 ACK） |
| `0x0200` | 启用 Indication | Peripheral 通过 indicate 发送数据（需要 ACK） |
| `0x0000` | 关闭订阅 | Peripheral 停止发送 |

在 CoreBluetooth 中，调用 `peripheral.setNotifyValue(true, for: characteristic)` 时，系统会自动写入 CCCD，开发者不需要手动操作描述符。

## 2. HRSense 的 GATT 特征布局

| UUID Short | 名称 | 方向 | 属性 | CCCD |
|-----------|------|------|------|------|
| 0002 | Data/Notify | 设备→App | Notify | **需要订阅** |
| 0003 | Control/Write | App→设备 | Write With Response | 不需要 |
| 0004 | Info | 设备→App | Read | 不需要 |
| 0005 | OTA Data | App→设备 | Write Without Response | 不需要 |

只有 0002（Data/Notify）需要写入 CCCD 来启用通知。

## 3. 完整连接流程

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        iOS App（Central）                               │
│                                                                         │
│  1. startScanning()                                                     │
│     └─► CBCentralManager.scanForPeripherals(withServices: [serviceUUID])│
│                                                                         │
│  2. didDiscover(peripheral)                                             │
│     └─► 记录到 discoveredDevicesStream                                  │
│                                                                         │
│  3. connect(to: peripheralID)                                           │
│     └─► CBCentralManager.connect(peripheral)                            │
│                                                                         │
│  4. didConnect(peripheral)                                              │
│     └─► peripheral.discoverServices([serviceUUID])                      │
│                                                                         │
│  5. didDiscoverServices                                                 │
│     └─► peripheral.discoverCharacteristics([0002,0003,0004,0005])       │
│                                                                         │
│  6. didDiscoverCharacteristicsFor                                       │
│     ├─► 0002: setNotifyValue(true)  ← 自动写 CCCD                       │
│     ├─► 0003: 记录 writeCharacteristic                                  │
│     ├─► 0004: readValue(for: infoChar)                                  │
│     └─► 0005: 记录 otaDataCharacteristic                                │
│                                                                         │
│  7. didUpdateNotificationStateFor (0002)                                │
│     └─► isNotifying == true → HandshakeReadinessGate 检查               │
│         └─► 三个条件全部满足 → emitState(.handshaking)                  │
│                                                                         │
│  8. performHandshake()                                                  │
│     ├─► 写 HELLO 命令 (0003)                                            │
│     ├─► 等待 HELLO_ACK (0002 notify)                                    │
│     ├─► 解析 DeviceInfo（model, firmwareVersion, capabilities）         │
│     └─► 写 START_STREAM (0003)                                          │
│         └─► emitState(.connected)                                       │
└─────────────────────────────────────────────────────────────────────────┘
```

## 4. HandshakeReadinessGate：CCCD 就绪门控

`HandshakeReadinessGate` 是一个状态结构体，追踪三个条件是否全部满足：

```swift
struct HandshakeReadinessGate {
    var hasNotifyCharacteristic = false        // 0002 特征已发现
    var hasWriteCharacteristic = false         // 0003 特征已发现
    var isNotifySubscriptionActive = false     // CCCD 写入成功（isNotifying == true）
    var hasEmittedHandshaking = false          // 是否已发射 handshaking 状态
}
```

只有当**三个条件全部为 true** 时，才会发射 `.handshaking` 状态，触发握手流程：

```swift
// BLECentralDataSource.swift
func peripheral(_ peripheral: CBPeripheral, 
                didUpdateNotificationStateFor characteristic: CBCharacteristic, 
                error: Error?) {
    guard characteristic.uuid == notifyCharUUID else { return }
    
    // isNotifying == true 说明 CCCD 已成功写入
    if _handshakeReadinessGate.updateNotifySubscription(isActive: characteristic.isNotifying) {
        emitState(.handshaking)  // 进入握手阶段
    }
}
```

**设计意图**：防止在特征发现未完成或 CCCD 未生效时就尝试握手，避免命令写入失败或 notify 丢失。

## 5. 模拟器侧的 CCCD 处理

在模拟器端（`SimulatedPeripheral`），当 Central 写入 CCCD 时，系统自动触发回调：

```swift
// SimulatedPeripheral.swift
func peripheralManager(_ peripheral: CBPeripheralManager, 
                       central: CBCentral, 
                       didSubscribeTo characteristic: CBCharacteristic) {
    _centralSubscribed = true
    // 开始通过 notify 推送数据
}

func peripheralManager(_ peripheral: CBPeripheralManager, 
                       central: CBCentral, 
                       didUnsubscribeFrom characteristic: CBCharacteristic) {
    _centralSubscribed = false
}
```

模拟器只在 `_centralSubscribed == true` 时才调用 `updateValue(_:for:)` 推送数据。

## 6. 断连与重连

断连时，CCCD 订阅自动失效，需要完整重建：

```swift
// BLECentralDataSource.swift
func centralManager(_ central: CBCentralManager, 
                    didDisconnectPeripheral peripheral: CBPeripheral, 
                    error: Error?) {
    _notifyCharacteristic = nil     // 特征引用清空
    _writeCharacteristic = nil
    _otaDataCharacteristic = nil
    _handshakeReadinessGate.reset() // 就绪门控重置
    frameAssembler.reset()          // 帧重组器重置
    emitState(.disconnected)        // → 触发指数退避重连
}
```

**重连机制**（由 `ConnectionMiddleware` 编排）：
1. 收到 `.disconnected` → 从 `BLEConnectionStateMachine` 获取退避延迟
2. `Task.sleep(delay)` 等待
3. 重新调用 `startScanning()` → 完整连接流程重走

退避策略：指数增长（1s → 2s → 4s → ... → 60s 封顶），连接成功后重置。

## 7. State Preservation / Restoration

iOS 系统在 App 被终止后可以恢复 BLE 连接：

```swift
// willRestoreState 中恢复 peripheral
func centralManager(_ central: CBCentralManager, 
                    willRestoreState dict: [String: Any]) {
    guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral]
    else { return }
    
    // 恢复已连接的 peripheral 引用
    if let connected = peripherals.first(where: { $0.state == .connected }) {
        _connectedPeripheral = connected
    }
    
    // 通知上层触发恢复验证
    restoredPeripheralIDsContinuation?.yield(peripherals.map(\.identifier))
    emitState(.restored)
}
```

恢复后需要重新发现服务、重新订阅 CCCD、重新握手，由 `ConnectionMiddleware` 中的 `restoreConnection()` 编排。

## 8. 数据通道可靠性

| 通道 | 机制 | 说明 |
|------|------|------|
| 0002 Notify | Best-effort | 不保证到达，通过 `sampleSeq` / `blockSeq` 检测丢包 |
| 0003 Write | ATT ACK | Write With Response 有 ATT 层确认 |
| 0005 OTA Write | 应用层 ACK | Write Without Response，但通过 `OTA_WINDOW_ACK` 确认 |

CCCD 订阅的 0002 通道采用 best-effort 设计，高频数据（心率 1Hz、波形 128Hz）不需要逐包 ACK，通过序号检测丢包率即可。
