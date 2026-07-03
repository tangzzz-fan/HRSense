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
- 仅在 ACK `status == success`、`recvOffset == expectedOffset` 且 `windowCRC32 == expectedWindowCRC32` 时推进进度
- 超时或 NAK 时进入窗口级重试
- `OTA_START_ACK` 现会解析 `maxChunkSize / maxWindow`，并按设备协商值裁剪窗口大小

同时修复了一个已有问题：

- `OTA_START_ACK.resumeOffset` 原解析偏移错误，现已按当前 payload 结构修正
- 续传判断改为以设备返回的 `resumeOffset` 为准，而不是依赖 App 进程内的临时状态

### 模拟器侧

#### `OTAEventHandler`

窗口语义从“收到 `OTA_WINDOW_BEGIN` 就直接写数据”改为：

1. `OTA_WINDOW_BEGIN` 先登记 `pendingWindow`
2. `0005` 收到 `offset + payload`
3. 校验窗口 offset/size
4. 写入 `OTAImageBuffer`
5. 计算该窗口 `windowCRC32`
6. 返回 `OTA_WINDOW_ACK`

`OTA_START_ACK` 也已补齐为：

- `status`
- `resumeOffset`
- `maxChunkSize`
- `maxWindow`

同时补充了设备侧前置校验：

- 低电量时拒绝 OTA
- 降级升级请求拒绝 OTA
- `OTA_ABORT` 会清理窗口状态与缓存上下文

#### `SimulatedPeripheral`

新增：

- `0003` 对原始 OTA 控制命令的路由
- `0005` 对 OTA chunk 的真实处理
- OTA 响应通过 notify 回传 App
- OTA `APPLY` 完成后会更新运行时 `firmwareVersion`
- 设备“重启”后会清理连接态并重新进入 advertising，下一次握手可读到新版本

## 代码落点

- `Sources/HRSenseData/BLE/BLECentralDataSource.swift`
- `Sources/HRSenseData/OTA/OTARepositoryImpl.swift`
- `Sources/HRSenseSimulatorKit/OTA/OTAEventHandler.swift`
- `Sources/HRSenseSimulatorKit/Peripheral/SimulatedPeripheral.swift`
- `Sources/HRSenseAppUI/AppComposition.swift`

## 新增验证

新增单元测试：

- `Tests/HRSenseSimulatorKitTests/OTAEventHandlerTests.swift`
  - 校验 `OTA_START_ACK` 会携带 `resumeOffset / maxChunkSize / maxWindow`
  - 校验窗口 begin + `0005` chunk 后能生成携带 `windowCRC32` 的 `OTA_WINDOW_ACK`
  - 校验无 pending window 时返回 out-of-order ack
  - 校验窗口乱序 begin 的失败路径
  - 校验同一镜像重启/重连后设备返回 `resumeOffset`
  - 校验低电量拒绝 OTA
  - 校验降级请求被拒绝
  - 校验 `OTA_ABORT` 后窗口状态被清空
- `Tests/HRSenseDataTests/OTARepositoryImplTests.swift`
  - 校验仓储层会等待窗口 ACK
  - 校验 `0005` 发包格式已变为 `offset + payload`
  - 校验会遵循 `maxChunkSize` 协商结果拆分窗口
  - 校验 `OTA_WINDOW_ACK` 超时重试失败
  - 校验 `windowCRC32` 不匹配时拒绝推进窗口
  - 校验 `OTA_START` 被低电量拒绝时直接失败
  - 校验整包 validate 失败路径
  - 校验 `resumeOffset` 续传时仅发送剩余字节
- `Tests/HRSenseSimulatorKitTests/SimulatedPeripheralOTATests.swift`
  - 校验 OTA `APPLY` 触发“重启”后，下一次 `HELLO` 已经返回新 `firmwareVersion`

## 对 M6 验收的直接收益

本次更新后，M6 从“sleep 驱动的半实现”推进到“窗口级 ACK 驱动的真实流控路径”，并补上了关键失败/续传测试，直接改善以下验收项：

- 窗口重传具备真实触发基础
- `0005` 数据通路已能进入设备端缓存
- OTA 进度推进不再依赖固定延时
- `windowCRC32` 已进入协议与校验链路
- `OTA_START_ACK` 已进入协商参数链路
- 续传逻辑已有设备侧与 App 侧回归测试
- 低电量 / 降级 / abort 等关键失败路径已有自动化测试
- 设备 OTA 后的新版本已能在下一次握手中被读取

## 仍未完全闭合的部分

以下内容仍建议作为下一轮 M6 补齐：

- 需要补齐真机 + macOS 模拟器联调验收记录
- App 自动回连并自动再次执行握手的端到端联调仍需补实机/模拟器验收记录
- 需要继续补充 OTA 失败路径测试：设备重启后不回来、`APPLY` 失败、低电量在升级中途下降
