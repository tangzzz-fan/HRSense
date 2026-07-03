# M6 OTA Window ACK Flow Closure

## 背景

本次补齐对应 `docs/11-delivery-plan.md` 中 **M6 OTA / DFU 全流程** 的关键验收缺口：

- `OTA Data(0005)` 发送后，App 端必须基于 `OTA_WINDOW_ACK` 做真实流控
- 模拟器侧必须真正接收 `0005` 镜像数据并在写入窗口后回 ACK
- OTA 传输不应继续依赖固定 `sleep` 作为伪同步机制

## 原缺失点

### 1. App 侧窗口流控是假实现

`Sources/HRSenseData/OTA/OTARepositoryImpl.swift` 原实现中：

- `OTA_WINDOW_BEGIN` 发出后，直接把 chunk 写到 `0005`
- 然后只做一次 `Task.sleep(50ms)`
- 默认认为窗口成功，没有真正等待 notify 返回的 `OTA_WINDOW_ACK`

这意味着：

- 无法区分“设备已接收”与“只是本地写出”
- 无法对窗口级失败/超时做可控重试
- 不满足 `docs/07-ota-dfu.md` 定义的 OTA 流控语义

### 2. App 侧 BLE 数据源没有 OTA notify 桥接

`Sources/HRSenseData/BLE/BLECentralDataSource.swift` 原先只处理：

- 协议帧重组后的 `DecodedFrame`
- 普通命令/ACK/数据/波形

但并没有把 OTA 的原始 notify 消息单独桥接出来，因此仓储层无从等待 `OTA_WINDOW_ACK`。

### 3. 模拟器侧没有真正消费 `0005` 数据

`Sources/HRSenseSimulatorKit/Peripheral/SimulatedPeripheral.swift` 中：

- `0005` 写入只是打日志并立即返回 success
- 没有写入 `OTAImageBuffer`
- 也没有在窗口写入完成后通过 notify 返回 `OTA_WINDOW_ACK`

这导致 OTA 控制路径和镜像数据路径没有真正闭环。

## 本次更新

### App 侧

#### `BLECentralDataSource`

新增：

- 原始 OTA notify 识别逻辑
- `sendOTAControl(_:)`
- `sendOTAControlAndWait(_:timeout:)`
- `waitForOTAWindowAck(timeout:)`

实现方式：

- `0003` 上发送原始 OTA 控制命令
- `0002` 上识别原始 OTA 响应
- 通过 continuation 等待 `OTA_START_ACK` / `OTA_WINDOW_ACK` / `OTA_VALIDATE_RESULT` / `OTA_APPLY`

#### `OTARepositoryImpl`

更新为真实窗口流控：

- `OTA_WINDOW_BEGIN` 只负责声明窗口
- `0005` 发送的数据包改为 `offset(u32 LE) + payload`
- 每个窗口发送后调用 `waitForOTAWindowAck`
- 仅在 ACK `status == success` 且 `recvOffset == expectedOffset` 时推进进度
- 超时或 NAK 时进入窗口级重试

同时修复了一个已有问题：

- `OTA_START_ACK.resumeOffset` 原解析偏移错误，现已按当前 payload 结构修正

### 模拟器侧

#### `OTAEventHandler`

窗口语义从“收到 `OTA_WINDOW_BEGIN` 就直接写数据”改为：

1. `OTA_WINDOW_BEGIN` 先登记 `pendingWindow`
2. `0005` 收到 `offset + payload`
3. 校验窗口 offset/size
4. 写入 `OTAImageBuffer`
5. 返回 `OTA_WINDOW_ACK`

#### `SimulatedPeripheral`

新增：

- `0003` 对原始 OTA 控制命令的路由
- `0005` 对 OTA chunk 的真实处理
- OTA 响应通过 notify 回传 App

## 代码落点

- `Sources/HRSenseData/BLE/BLECentralDataSource.swift`
- `Sources/HRSenseData/OTA/OTARepositoryImpl.swift`
- `Sources/HRSenseSimulatorKit/OTA/OTAEventHandler.swift`
- `Sources/HRSenseSimulatorKit/Peripheral/SimulatedPeripheral.swift`
- `Sources/HRSenseAppUI/AppComposition.swift`

## 新增验证

新增单元测试：

- `Tests/HRSenseSimulatorKitTests/OTAEventHandlerTests.swift`
  - 校验窗口 begin + `0005` chunk 后能生成 `OTA_WINDOW_ACK`
  - 校验无 pending window 时返回 out-of-order ack
- `Tests/HRSenseDataTests/OTARepositoryImplTests.swift`
  - 校验仓储层会等待窗口 ACK
  - 校验 `0005` 发包格式已变为 `offset + payload`

## 对 M6 验收的直接收益

本次更新后，M6 从“sleep 驱动的半实现”推进到“窗口级 ACK 驱动的真实流控路径”，直接改善以下验收项：

- 窗口重传具备真实触发基础
- `0005` 数据通路已能进入设备端缓存
- OTA 进度推进不再依赖固定延时

## 仍未完全闭合的部分

以下内容仍建议作为下一轮 M6 补齐：

- `OTA_WINDOW_ACK` payload 还未完全扩展到 `docs/07-ota-dfu.md` 中的 `windowCRC32`
- 模拟器重启/重连后的 OTA 续传路径仍需端到端打通
- 需要补齐真机 + macOS 模拟器联调验收记录
- 需要补充 OTA 失败路径测试：CRC mismatch / timeout / retry exhausted / abort
