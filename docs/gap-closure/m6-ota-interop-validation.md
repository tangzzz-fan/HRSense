# M6 OTA 联调验收脚本与记录模板

## 目标

本模板用于补齐 `M6 OTA / DFU` 的联调验收证据，重点覆盖以下问题：

- App 侧是否按 `OTA_START_ACK` 协商值执行窗口发送
- `OTA_WINDOW_ACK` 是否真正参与流控，而不是本地假成功
- 断点续传、失败重试、OTA APPLY 后版本更新是否在联调中可见
- iOS App 与 macOS 模拟器之间的 OTA 行为是否与 `docs/07-ota-dfu.md` 对齐

本模板既可以作为联调操作脚本使用，也可以直接复制后填写为验收记录。

## 适用范围

- App 端：`Apps/HRSenseApp`
- 模拟器端：`Apps/HRSenseSimulator`
- 协议路径：
  - `0003` OTA 控制命令
  - `0005` OTA 数据写入
  - `0002` OTA notify ACK

## 前置条件

开始联调前，请先确认：

- iOS App 与 macOS Simulator 均使用最新本地代码
- `swift test` 已通过
- 模拟器端可正常广播，App 可正常完成 BLE 握手
- 待升级固件镜像已准备好，并记录：
  - `imageSize`
  - `imageCRC32`
  - `newVersion`
- 如需保留证据，请提前准备：
  - App 端日志导出目录
  - Simulator 端控制台日志
  - 屏幕录制或关键截图

## 建议联调步骤

### 场景 1：基础 OTA 成功路径

目的：验证 `start -> transfer -> validate -> apply -> reboot -> 新版本可见` 的主链路。

操作步骤：

1. 启动 macOS 模拟器并开始广播
2. 启动 iOS App，连接到模拟器外设
3. 记录连接成功时的旧版本号
4. 触发 OTA 升级
5. 观察 App 端是否收到 `OTA_START_ACK`
6. 记录协商参数：
   - `resumeOffset`
   - `maxChunkSize`
   - `maxWindow`
7. 观察每个窗口是否遵循：
   - 发送 `OTA_WINDOW_BEGIN`
   - 写入 `0005`
   - 等待 `OTA_WINDOW_ACK`
8. 传输完成后，观察 `OTA_VALIDATE_RESULT`
9. 观察 `OTA_APPLY` 成功返回
10. 等待设备“重启”并重新广播
11. App 重新连接并再次握手
12. 确认新版本号已经更新

通过标准：

- App 不依赖固定延时推进窗口
- `OTA_WINDOW_ACK` 中 `recvOffset` 与窗口推进一致
- OTA 完成后再次握手返回 `newVersion`

### 场景 2：断点续传路径

目的：验证 `resumeOffset` 是否真正生效。

操作步骤：

1. 启动 OTA 升级
2. 在至少完成 1 个窗口后，主动断开连接
3. 重新连接同一设备
4. 再次触发相同镜像的 OTA_START
5. 记录 `OTA_START_ACK.resumeOffset`
6. 检查 App 是否仅发送剩余字节，而不是从 0 重传

通过标准：

- `resumeOffset > 0`
- App 首个重传窗口的 offset 与 `resumeOffset` 一致
- 剩余镜像传输成功，最终 OTA 完成

### 场景 3：失败与重试路径

目的：验证窗口级错误不会被误判为成功。

建议至少覆盖以下子场景：

- `OTA_WINDOW_ACK` 超时
- `windowCRC32` 不匹配
- 低电量拒绝 OTA_START
- 降级升级请求被拒绝

通过标准：

- App 能正确提示 OTA 失败阶段
- 失败日志中能区分 `start / transfer / validate / apply`
- 不会出现 OTA 失败但 UI 仍显示完成

## 推荐观察点

### App 端

- `ota` 分类日志
- 连接状态变化
- `resumeOffset / maxChunkSize / maxWindow`
- `recvOffset / windowCRC32`
- OTA 进度与错误提示

### Simulator 端

- `OTA_START` 收到的 `imageSize / imageCRC32 / newVersion`
- `OTA_WINDOW_BEGIN` 的 `offset / size`
- `0005` 实际写入的 `offset + payload`
- `OTA_VALIDATE` 的 expected/actual CRC
- OTA APPLY 后的当前版本号

## 验收记录模板

建议每次联调新建一份副本，按以下格式填写。

```md
# M6 OTA 联调记录

## 基本信息

- 日期：
- 执行人：
- App 提交：
- Simulator 提交：
- 镜像版本：
- 镜像大小：
- 镜像 CRC32：

## 场景 1：基础成功路径

- 旧版本：
- OTA_START_ACK：
- 协商 maxChunkSize：
- 协商 maxWindow：
- OTA_WINDOW_ACK 观察结果：
- OTA_VALIDATE_RESULT：
- OTA_APPLY：
- 重连后新版本：
- 结论：通过 / 失败

## 场景 2：断点续传

- 中断时 offset：
- 续传 resumeOffset：
- 是否只发送剩余字节：
- 最终是否成功：
- 结论：通过 / 失败

## 场景 3：失败路径

- 超时重试结果：
- CRC 不匹配结果：
- 低电量拒绝结果：
- 降级拒绝结果：
- 结论：通过 / 失败

## 附件

- App 日志：
- Simulator 日志：
- 截图 / 录屏：

## 问题列表

- 问题 1：
- 问题 2：

## 结论

- 本轮是否满足 M6 联调验收：
- 下一步建议：
```

## 推荐命名

联调记录文件建议命名为：

- `docs/gap-closure/records/m6-ota-interop-YYYYMMDD.md`

如果 `records/` 目录尚未创建，可在第一次正式联调时补建。

## 当前已自动化覆盖，联调仍需关注的部分

虽然当前代码已经通过自动化测试，但以下内容仍必须通过人工联调确认：

- 真正的 BLE 写入节奏与 notify 时序
- App 前后台切换对 OTA 的影响
- OTA 后再次扫描、重连、握手的真实体验
- 真机上系统层连接中断、蓝牙权限、功耗与 UI 提示的一致性

## 与本轮 gap closure 的关系

本模板对应的代码补齐见：

- `docs/gap-closure/m6-ota-window-ack-flow.md`

联调时请将自动化测试结论与人工记录结合使用，不建议只凭 `swift test` 视为 M6 完整验收。
