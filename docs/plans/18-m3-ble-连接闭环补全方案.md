# 18 · M3 BLE 连接闭环补全方案

> 状态：draft
> 范围：iOS App 与 `HRSenseSimulator` 的扫描、发现、连接、握手、状态推进
> 目的：把“能扫描到 simulator，但 app 不会真正连上设备”的断点固化，并给出一版最短可运行闭环实现。

## 1. 背景

当前仓库已经具备如下能力：

- iOS 端可以启动扫描，并能发现符合自定义 GATT Service UUID 的外设。
- macOS `HRSenseSimulator` 已能广播、接受 `HELLO/START_STREAM` 并回响应。
- Redux 主链、中间件和 UI 骨架已经存在。

但真实联调时，App 仍停在“发现设备”阶段，没有进入稳定的数据接收状态。

## 2. 旧实现的问题

### 2.1 发现设备后没有连接入口

- `RootView` 只会在 `onAppear` 时触发 `.startScanning`。
- `deviceDiscovered(DeviceInfo)` 在 reducer 中被直接忽略。
- `AppState` 没有保存 discovered device 列表，UI 无法展示、选择或连接设备。

结果：

- 日志里能看到 `deviceDiscovered(Unknown)`。
- 但没有任何路径会继续 dispatch `.connect(deviceID:)`。

### 2.2 握手成功后没有推进到 `.connected`

- `BLECentralDataSource` 在 characteristic discovery 完成后只会发 `.handshaking`。
- `DeviceRepositoryImpl.performHandshake()` 完成 `HELLO_ACK + START_STREAM` 后没有通知 data source 切到 `.connected`。
- `BLEStreamMiddleware` 和 `WaveformMiddleware` 都依赖 `.connectionStateChanged(.connected)` 才开始工作。

结果：

- 即使 BLE 连接与握手命令本身成功，数据流中间件也不会启动。

### 2.3 设备身份传播错误

- `performHandshake()` 之前用 `UUID()` 临时生成 `DeviceInfo.peripheralIdentifier`。
- 这会让 UI 上看到的设备和真实 peripheral 身份脱节。

结果：

- 后续重连、调试留痕、设备列表更新都会失真。

## 3. 这次修改的原理

### 3.1 把“发现设备”变成显式状态

- `AppState` 新增 `discoveredDevices: [DeviceInfo]`
- reducer 在 `.deviceDiscovered` 时去重写入
- `RootView` 显示 discovered device 列表，并提供显式 `Connect` 按钮

原理：

- 发现结果必须进入 Store，才能被 UI、日志和测试共同观察。
- 如果发现设备只存在于 middleware 或 data source 的局部变量里，就无法确认“到底是没扫到、没显示，还是没连接”。

### 3.2 把“握手完成”变成显式状态推进

- `BLECentralDataSource` 新增 `completeHandshake(with:)`
- `DeviceRepositoryImpl.performHandshake()` 在 `START_STREAM` 成功后调用它
- `completeHandshake(with:)` 同步两件事：
  - 回写当前 connected peripheral 对应的 `DeviceInfo`
  - 发出 `.connected`

原理：

- `.handshaking` 只是“BLE characteristic 已就绪”，不是“业务连接已完成”。
- 对当前架构来说，真正的业务完成点是：
  - `HELLO_ACK` 收到
  - `START_STREAM` 成功
- 所以 `.connected` 必须在这一步显式触发。

### 3.3 用真实 peripheral ID 回填 DeviceInfo

- `DeviceRepositoryImpl` 从 `BLECentralDataSource` 读取当前 connected peripheral 的真实 identifier
- 同时复用 discovered device 的 name

原理：

- `DeviceInfo` 不是临时 DTO，而是 Store、UI、日志、重连策略共享的设备身份实体。
- 它必须与真实 BLE peripheral 一致。

## 4. 设计流程

```mermaid
flowchart TD
    A[RootView onAppear] --> B[dispatch startScanning]
    B --> C[ConnectionMiddleware 调用 DeviceRepository.startScanning]
    C --> D[BLECentralDataSource 扫描并发现 simulator]
    D --> E[dispatch deviceDiscovered]
    E --> F[Reducer 写入 discoveredDevices]
    F --> G[RootView 展示设备列表]
    G --> H[用户点击 Connect]
    H --> I[dispatch connect(deviceID)]
    I --> J[ConnectionMiddleware 调用 connect + performHandshake]
    J --> K[HELLO -> HELLO_ACK -> START_STREAM]
    K --> L[BLECentralDataSource.completeHandshake]
    L --> M[connectionStateChanged(.connected)]
    M --> N[BLEStreamMiddleware / WaveformMiddleware 启动]

    style A fill:#bbdefb,color:#0d47a1
    style D fill:#bbdefb,color:#0d47a1
    style G fill:#fff3e0,color:#e65100
    style K fill:#fff3e0,color:#e65100
    style N fill:#c8e6c9,color:#1a5e20
```

## 5. 模块拆分与时间

| 模块 | 修改点 | 目标 | 预计时间 |
| --- | --- | --- | --- |
| M3-A | `AppState` / `AppReducer` | 保存 discovered devices 并去重 | 20 min |
| M3-B | `RootView` | 展示设备列表并提供连接入口 | 25 min |
| M3-C | `ConnectionMiddleware` | 修正 discovered stream 订阅模型，避免重复订阅 | 15 min |
| M3-D | `BLECentralDataSource` / `DeviceRepositoryImpl` | 握手成功后推进 `.connected`，并传播真实设备 ID | 25 min |
| M3-E | `HRSenseFeatureTests` / `HRSenseDataTests` | 补 reducer / middleware / data 层回归测试 | 40 min |
| M3-F | 文档对齐 | 更新 `15` 号文档中的 M3/M4 口径 | 15 min |

## 6. 已实现项

- [x] `AppState` 新增 `discoveredDevices`
- [x] reducer 处理 `.deviceDiscovered` / `.deviceInfoUpdated` 去重更新
- [x] `RootView` 显示 discovered device 列表与 `Connect` 按钮
- [x] `ConnectionMiddleware` 将 discovered device stream 改成一次性订阅
- [x] `BLECentralDataSource.completeHandshake(with:)`
- [x] `DeviceRepositoryImpl.performHandshake()` 使用真实 peripheral ID，并在 `START_STREAM` 后推进 `.connected`
- [x] feature/data 层补充回归测试

## 7. 剩余边界

- 当前仍需要真机 iPhone 与 `HRSenseSimulator` 做手工联调，验证真实 BLE 运行时行为。
- 当前连接入口是显式按钮，不是自动连接策略；这是为了优先保证调试可观察性。
- 重连退避已经有骨架和测试，但仍缺真实设备断链后的运行时验证。
