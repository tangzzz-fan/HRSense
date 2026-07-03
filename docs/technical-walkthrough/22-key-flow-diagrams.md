# 关键流程 Mermaid 图解与坑点标注

> 用 Mermaid 图可视化 HRSense 的 7 条关键流程，每张图标注 ⚠️ 坑点（常见故障 / 易踩的坑）。

---

## 1. BLE 连接 + CCCD + 握手流程

```mermaid
sequenceDiagram
    participant App as iOS App
    participant BLE as BLECentralDataSource<br/>(bleQueue)
    participant Dev as Peripheral (设备)

    App->>BLE: startScanning()
    BLE->>Dev: scanForPeripherals(serviceUUID)
    Dev-->>BLE: didDiscover(peripheral)
    BLE-->>App: AsyncStream yield DeviceInfo

    App->>BLE: connect(peripheralID)
    BLE->>BLE: handshakeReadinessGate.reset()
    BLE->>BLE: connectionStateMachine.resetBackoff()
    BLE->>Dev: centralManager.connect(peripheral)

    Note over Dev: ⚠️ 坑点1: connect() 是异步的<br/>可能永远不回调(设备关机/超范围)<br/>需要超时保护

    Dev-->>BLE: didConnect(peripheral)
    BLE->>Dev: discoverServices([serviceUUID])

    Dev-->>BLE: didDiscoverServices
    BLE->>Dev: discoverCharacteristics([0002,0003,0004,0005])

    Dev-->>BLE: didDiscoverCharacteristicsFor
    Note over BLE: 0002 → setNotifyValue(true) 写 CCCD<br/>0003 → 记录 writeChar<br/>0004 → readValue(infoChar)<br/>0005 → 记录 otaChar

    Note over BLE: ⚠️ 坑点2: 特征发现是逐个回调<br/>顺序不确定<br/>必须在全部发现后才能握手<br/>→ HandshakeReadinessGate 门控

    Dev-->>BLE: didUpdateNotificationStateFor(0002)
    Note over BLE: isNotifying == true ?<br/>检查 Gate 三条件

    alt Gate 条件全部满足
        BLE-->>App: emitState(.handshaking)
        App->>BLE: performHandshake()
        BLE->>Dev: HELLO (Write 0003)
        Dev-->>BLE: HELLO_ACK (Notify 0002)
        Note over BLE: 解析 DeviceInfo<br/>(model, fwVersion, capabilities)
        BLE->>Dev: START_STREAM (Write 0003)
        Dev-->>BLE: START_STREAM_ACK
        BLE-->>App: emitState(.connected)
    else Gate 条件不满足
        Note over BLE: ⚠️ 坑点3: CCCD 写入失败<br/>(error != nil)<br/>设备不支持 notify<br/>→ 无法进入握手<br/>→ 连接卡住
    end
```

**坑点总结**：

| 坑 | 描述 | 后果 | 缓解 |
|----|------|------|------|
| ⚠️1 | `connect()` 无超时 | App 无限等待 | 添加 10s 超时 → `cancelPeripheralConnection` |
| ⚠️2 | 特征发现回调顺序不确定 | 0003 可能比 0002 先发现 | `HandshakeReadinessGate` 三条件门控 |
| ⚠️3 | CCCD 写入可能失败 | 握手永远不触发 | 监听 `didUpdateNotificationStateFor` 的 error 参数 |

---

## 2. 数据管线：notify 字节 → AppState

```mermaid
sequenceDiagram
    participant Dev as Peripheral
    participant BLE as BLECentralDataSource<br/>(bleQueue)
    participant FA as FrameAssembler<br/>(bleQueue)
    participant Parser as BLEDataParser<br/>(MainActor)
    participant MW as Middleware Chain<br/>(MainActor)
    participant Redux as Store + Reducer<br/>(MainActor)
    participant UI as SwiftUI View

    Dev-->>BLE: didUpdateValueFor(0002) → Data
    Note over BLE: metricsCollector.recordBytesReceived()

    BLE->>FA: feed(data)
    Note over FA: 分片重组:<br/>检查 seq, type, body<br/>CRC-16 校验

    Note over FA: ⚠️ 坑点4: BLE 丢包<br/>notify 是 best-effort<br/>分片可能不完整<br/>→ FrameAssembler 等待超时<br/>→ 丢弃当前帧

    FA-->>BLE: [DecodedFrame]
    
    alt DecodedFrame.data(DeviceSample)
        BLE->>Parser: parseSample(sample)
        Note over Parser: t0 时间戳映射<br/>RR 间期转换<br/>→ HeartRateSample
        BLE-->>MW: heartRateStream.yield(sample)
    else DecodedFrame.waveform(block)
        BLE->>Parser: parseWaveformBlock(block)
        Note over Parser: 归一化 (raw/32768)<br/>时间戳映射<br/>→ [WaveformSample]
        BLE->>BLE: ringBuffer.push(samples)
    end

    Note over MW: ⚠️ 坑点5: 线程切换<br/>bleQueue → MainActor<br/>必须 await MainActor.run { }<br/>否则 Reducer 在非主线程执行<br/>→ SwiftUI 崩溃

    MW->>Redux: dispatch(.heartRateReceived)
    Note over MW: 经过 Middleware 链:<br/>BackgroundMW → ConnectionMW<br/>→ BLEStreamMW → ComputeMW<br/>→ InferenceMW → SleepMW

    Note over MW: ⚠️ 坑点6: Middleware 拦截<br/>BackgroundMiddleware 可能<br/>在后台丢弃 action<br/>→ 数据不更新不是 bug

    Redux->>Redux: Reducer 更新 AppState
    Redux-->>UI: @ObservableObject 通知
    UI->>UI: body 重算

    Note over UI: ⚠️ 坑点7: UI 刷新风暴<br/>128Hz 数据 → 每秒 128 次 dispatch<br/>→ SwiftUI body 疯狂重算<br/>→ 卡顿<br/>解法: 10Hz 轮询 + throttle
```

**坑点总结**：

| 坑 | 描述 | 后果 | 缓解 |
|----|------|------|------|
| ⚠️4 | BLE notify 丢包 | 帧重组不完整 | FrameAssembler 超时丢弃 + blockSeq 检测丢包率 |
| ⚠️5 | bleQueue → MainActor 线程切换 | Reducer 在非主线程执行 | 所有 dispatch 用 `await MainActor.run { }` |
| ⚠️6 | BackgroundMiddleware 拦截 | 后台数据不更新 | 设计意图——检查 `state.lifecycle` |
| ⚠️7 | 高频 dispatch 导致 UI 卡顿 | 128Hz action → 128Hz body 重算 | 波形用 10Hz 轮询，心率用 0.5s throttle |

---

## 3. OTA 固件传输流程

```mermaid
sequenceDiagram
    participant App as App (OTA Middleware)
    participant BLE as BLECentralDataSource
    participant Dev as Peripheral (设备)

    Note over App: Phase 0: 准备
    App->>App: 检查固件文件 (SHA-256)
    App->>App: 检查电量 > 20%

    Note over App: ⚠️ 坑点8: 电量不足时开始 OTA<br/>传输到一半设备断电<br/>→ 可能变砖

    App->>BLE: sendOTAControlAndWait(OTA_START)
    BLE->>Dev: OTA_START (Write 0003)
    Dev-->>BLE: OTA_START_ACK (Notify 0002)
    Note over Dev: 返回 resumeOffset<br/>(断点续传偏移量)

    Note over Dev: ⚠️ 坑点9: 上次 OTA 中断<br/>resumeOffset > 0<br/>App 必须从偏移量续传<br/>不能从头开始

    Note over App: Phase 1: 传输
    App->>BLE: sendOTAControl(OTA_WINDOW_BEGIN)
    BLE->>Dev: OTA_WINDOW_BEGIN (Write 0003)

    loop 每个窗口 (N=16 chunks)
        App->>BLE: sendOTAChunk(chunk_1)
        BLE->>Dev: chunk_1 (Write Without Response 0005)
        App->>BLE: sendOTAChunk(chunk_2)
        BLE->>Dev: chunk_2 (Write Without Response 0005)
        Note over App: ... chunk_N
        App->>BLE: sendOTAChunk(chunk_N)
        BLE->>Dev: chunk_N (Write Without Response 0005)
        
        App->>BLE: waitForOTAWindowAck()
        Dev-->>BLE: OTA_WINDOW_ACK (Notify 0002)

        Note over Dev: ⚠️ 坑点10: WINDOW_ACK 超时<br/>BLE 丢包导致设备没收到全部 chunk<br/>→ App 超时重试当前窗口<br/>→ 不能跳过
    end

    alt BLE 断连
        Note over App,BLE: ⚠️ 坑点11: 传输中断连断开
        Note over App: 不清除 OTA 进度<br/>触发自动重连<br/>重连后发 OTA_START<br/>→ 设备返回 resumeOffset<br/>→ 从断点续传
    end

    Note over App: Phase 2: 校验
    App->>BLE: sendOTAControlAndWait(OTA_VALIDATE)
    BLE->>Dev: OTA_VALIDATE (Write 0003)
    Dev-->>BLE: OTA_VALIDATE_RESULT (CRC-32)
    App->>App: 对比本地 CRC-32

    Note over App: ⚠️ 坑点12: CRC 不匹配<br/>→ 传输有丢块但没检测到<br/>→ 必须重新 OTA（不能续传）

    Note over App: Phase 3: 应用
    App->>BLE: sendOTAControl(OTA_APPLY)
    BLE->>Dev: OTA_APPLY (Write 0003)
    Note over Dev: 刷写固件 + 重启
    Dev--xApp: BLE 连接断开 (设备重启)
    Note over App: 等待设备重新广播<br/>→ 重新连接<br/>→ 验证新固件版本号
```

**坑点总结**：

| 坑 | 描述 | 后果 | 缓解 |
|----|------|------|------|
| ⚠️8 | 低电量 OTA | 传输中设备断电 → 变砖 | App + 设备双重电量检查 |
| ⚠️9 | resumeOffset 处理 | 从头传 → 浪费带宽 | 读取 ACK 中的 resumeOffset 续传 |
| ⚠️10 | WINDOW_ACK 超时 | 传输卡住 | 超时重试当前窗口（指数退避） |
| ⚠️11 | 传输中 BLE 断连 | 进度丢失 | 设备记住 offset，重连后续传 |
| ⚠️12 | CRC-32 不匹配 | 固件损坏 | 丢弃已传数据，从头重新 OTA |

---

## 4. C++ HRV 计算 + CoreML 推理管线

```mermaid
sequenceDiagram
    participant MW as ComputeMiddleware
    participant Bridge as ComputeBridge
    participant Cxx as hrv.cpp (C++)
    participant ML as CoreMLService
    participant Model as .mlmodelc
    participant Redux as Store

    Note over MW: 触发条件:<br/>收到 .heartRateReceived<br/>且 rrBuffer 窗口 ≥ 5 分钟<br/>且距上次计算 ≥ 10 秒

    MW->>MW: rrBuffer.append(rrIntervals)

    Note over MW: ⚠️ 坑点13: rrBuffer 是闭包可变状态<br/>var rrBuffer: [(date, rr)]<br/>非 Actor 保护<br/>如果 Middleware 被并发调用<br/>→ 数据竞争

    MW->>Bridge: computeHRV(from: rrIntervalsMs)
    Bridge->>Bridge: var metrics = hrs_hrv_metrics_t()
    Bridge->>Cxx: hrs_compute_hrv(ptr, count, &metrics)

    Note over Cxx: ⚠️ 坑点14: 输入数据要求<br/>至少 2 个 RR 间期<br/>→ guard count >= 2<br/>否则返回错误码

    Note over Cxx: 8 种算法执行:<br/>SDNN, RMSSD, pNN50 (O(n))<br/>Poincaré SD1/SD2 (O(n))<br/>Lomb-Scargle (O(256n))<br/>Sample Entropy (O(n²))<br/>DFA α1 (O(n·log n))

    Note over Cxx: ⚠️ 坑点15: Sample Entropy O(n²)<br/>5 分钟 ≈ 300 个 RR<br/>300² = 90,000 次比较<br/>如果窗口增大到 30 分钟<br/>→ 1800² = 3,240,000 → 卡顿

    Cxx-->>Bridge: metrics (POD struct)
    Bridge->>Bridge: 手动映射 C → Swift struct
    Bridge-->>MW: HRVMetrics (14 字段)

    MW->>Redux: dispatch(.hrvComputed(metrics))

    Note over MW: InferenceMiddleware 接收<br/>.hrvComputed 触发推理

    MW->>Bridge: extractFeatures(from: metrics)
    Bridge->>Cxx: hrs_extract_features(&cMetrics, &cFeatures)
    Cxx-->>Bridge: Float[14]
    Bridge-->>MW: FeatureVector

    MW->>ML: predict(features: FeatureVector)
    ML->>ML: ModelSelectionRequest(task: .stress)
    Note over ML: 评分选择模型:<br/>task +100, contract +50<br/>name +25, version +25

    alt 模型加载成功
        ML->>Model: model.prediction(input: MLMultiArray)
        Note over ML: ⚠️ 坑点16: MLMultiArray 形状<br/>必须 [1, 14] 不是 [14]<br/>形状不匹配 → 推理崩溃
        Model-->>ML: prediction output
        ML-->>MW: InferenceResult
    else 模型加载失败
        Note over ML: ⚠️ 坑点17: 模型文件缺失<br/>.mlmodelc 不在 Bundle 中<br/>→ fallbackPredictor 接管<br/>→ 规则引擎 (hr > 90 → Stress)
        ML-->>MW: FallbackResult
    end

    MW->>Redux: dispatch(.inferenceCompleted(result))
```

**坑点总结**：

| 坑 | 描述 | 后果 | 缓解 |
|----|------|------|------|
| ⚠️13 | 闭包可变状态无锁 | 数据竞争 | 迁移到 typed state 对象或 Swift 6 检查 |
| ⚠️14 | RR 间期不足 | C++ 返回错误码 | Swift 端 guard count >= 2 提前拦截 |
| ⚠️15 | Sample Entropy O(n²) | 大窗口计算慢 | 限制窗口大小或优化算法 |
| ⚠️16 | MLMultiArray 形状 | 推理崩溃 | 构造时确保 shape = [1, 14] |
| ⚠️17 | 模型文件缺失 | 无 ML 推理 | 三级降级: CoreML → 规则引擎 → 硬编码默认值 |

---

## 5. 睡眠分期管线

```mermaid
sequenceDiagram
    participant CM as ComputeMiddleware
    participant SM as SleepMiddleware
    participant Bridge as ComputeBridge
    participant Cxx as hrv.cpp
    participant SIS as SleepStageService
    participant ML as CoreML (sleep model)
    participant Redux as Store
    participant PS as PersistenceStore

    CM->>Redux: dispatch(.hrvComputed(metrics))
    Redux-->>SM: .hrvComputed 到达

    Note over SM: 前置检查:
    SM->>SM: guard state.sleep.isMonitoring
    SM->>SM: guard recentSamples.last != nil

    Note over SM: ⚠️ 坑点18: 睡眠监测未启动<br/>isMonitoring == false<br/>→ 所有 HRV 数据被忽略<br/>→ 用户忘记点"开始睡眠"

    SM->>SM: metricsHistory.append(SleepMetricSnapshot)
    SM->>SM: 裁剪到最近 4 小时

    Note over SM: ⚠️ 坑点19: 4 小时 RMSSD 历史<br/>需要持续接收数据 4 小时<br/>如果中途 BLE 断连 > 5 分钟<br/>→ 历史不连续<br/>→ circadianVariation 不准

    SM->>Bridge: computeSleepFeatures(heartRates, hrvValues)
    Bridge->>Cxx: hrs_compute_hr_trend(ptr, count, &out)
    Cxx-->>Bridge: hrTrend
    Bridge->>Cxx: hrs_compute_circadian_variation(ptr, count, &out)
    Cxx-->>Bridge: circadianVariation

    Note over Bridge: ⚠️ 坑点20: C++ 特征计算失败<br/>返回非 0 → throw<br/>→ 整个睡眠窗口被跳过<br/>→ 该时间段无睡眠分期

    Bridge-->>SM: SleepCXXFeatures

    SM->>SM: 组装 18 维特征向量
    Note over SM: [0-13] HRV from C++<br/>[14] hrTrend<br/>[15] circadianVariation<br/>[16] minutesSinceSessionStart<br/>[17] localClockMinutes

    SM->>Redux: dispatch(.sleep(.inferenceStarted))
    SM->>SIS: inferSleepStage(input)
    SIS->>ML: predict(18 features)

    alt ML 推理成功
        ML-->>SIS: SleepStage (Wake/Light/Deep/REM)
    else ML 推理失败
        Note over SIS: ⚠️ 坑点21: 降级到规则引擎<br/>4 条规则:<br/>HR > 82 → Wake<br/>RMSSD < 65 → Light<br/>SE < 1.25 → Light<br/>默认 → Light: 0.64
        SIS->>SIS: makeFallbackProbabilities()
    end

    SIS-->>SM: SleepStagePrediction

    SM->>SM: mergeSleepPrediction()
    Note over SM: 同 stage → 延长 segment<br/>不同 stage → 新建 segment

    Note over SM: ⚠️ 坑点22: 频繁 stage 切换<br/>Light→Deep→Light→REM<br/>每 30 秒切一次<br/>→ session 出现大量碎片 segment<br/>→ 睡眠质量分析不准

    SM->>Redux: dispatch(.sleep(.sessionUpdated))
    SM->>PS: saveSleepSession(session)
    PS-->>SM: success
    SM->>Redux: dispatch(.sleep(.sessionPersisted))

    Note over SM: ⚠️ 坑点23: 持久化连锁<br/>sessionPersisted → historyLoadRequested<br/>→ 重新从数据库加载历史<br/>→ 如果 SwiftData 有缓存问题<br/>→ 可能读到旧数据
```

**坑点总结**：

| 坑 | 描述 | 后果 | 缓解 |
|----|------|------|------|
| ⚠️18 | 睡眠监测未启动 | HRV 数据全部丢弃 | UI 明确提示"请开始睡眠监测" |
| ⚠️19 | 4 小时历史不连续 | circadianVariation 不准 | BLE 断连后标记数据间隙 |
| ⚠️20 | C++ 特征计算失败 | 整个窗口跳过 | 重试或降级到上一次有效值 |
| ⚠️21 | ML 推理失败 | 降级到简单规则 | 4 条 fallback 规则 + 日志告警 |
| ⚠️22 | stage 频繁切换 | 碎片化 segment | 后处理平滑（最短持续时间过滤） |
| ⚠️23 | 持久化连锁 | 读到旧数据 | 持久化后不立即 reload，用内存中的 session |

---

## 6. 后台/前台切换流程

```mermaid
sequenceDiagram
    participant Sys as iOS System
    participant BM as BackgroundMiddleware
    participant CM as ConnectionMiddleware
    participant BLE as BLECentralDataSource
    participant Redux as Store

    Note over Sys: 用户按 Home 键 / 锁屏
    Sys-->>Redux: dispatch(.didEnterBackground)
    Redux-->>BM: .didEnterBackground

    BM->>Redux: state.lifecycle = .background

    Note over BM: 后台策略生效:
    BM->>BM: shouldDrop() 开始拦截

    Note over BM: ⚠️ 坑点24: 拦截发生在 next(action) 之前<br/>被拦截的 action 不经过 Reducer<br/>→ AppState 不更新<br/>→ 但 Ring Buffer 仍在后台接收数据<br/>（Ring Buffer 不受 Middleware 控制）

    Note over BM: 以下 action 被拦截:<br/>.waveformSamplesReceived ✗<br/>.waveformMetricsUpdated ✗<br/>.featuresExtracted ✗<br/>.inferenceStarted ✗<br/>.computeStarted ✗ (除非 sleep)

    Note over BM: 以下 action 正常通过:<br/>.heartRateReceived ✓<br/>.hrvComputed ✓ (if sleep)<br/>.connectionStateChanged ✓<br/>.sleep.* ✓

    Note over Sys: --- 后台运行中 ---

    Note over BLE: ⚠️ 坑点25: BLE 后台 CPU 预算<br/>~30 秒 CPU 时间<br/>如果 ComputeMiddleware 在后台<br/>执行 C++ 计算太频繁<br/>→ 超出预算 → 系统杀进程

    Note over Sys: 用户回到前台
    Sys-->>Redux: dispatch(.didEnterForeground)
    Redux-->>BM: .didEnterForeground
    BM->>Redux: state.lifecycle = .foreground

    Note over BM: 策略解除:
    Note over BM: ⚠️ 坑点26: 回到前台后<br/>Ring Buffer 里有 30 秒的波形数据<br/>但 AppState.waveform 是空的<br/>(后台没 dispatch waveform action)<br/>→ 第一次轮询会一次性推送大量数据<br/>→ UI 可能出现"跳变"

    Note over CM: 检查 BLE 连接状态
    CM->>BLE: connectionState?

    alt 仍连接
        Note over BLE: 连接保活成功<br/>数据正常流动
    else 已断连
        Note over CM: ⚠️ 坑点27: 后台超时断连<br/>Supervision Timeout 过期<br/>系统回收了 BLE 连接<br/>→ 触发自动重连（指数退避）
        CM->>BLE: startScanning()
    end
```

**坑点总结**：

| 坑 | 描述 | 后果 | 缓解 |
|----|------|------|------|
| ⚠️24 | 后台拦截 vs Ring Buffer | Ring Buffer 有数据但 UI 空 | 设计意图——回到前台后轮询立即填充 |
| ⚠️25 | 后台 CPU 预算超限 | 系统杀进程 | 后台暂停非核心计算 |
| ⚠️26 | 前台恢复数据跳变 | UI 突然出现 30 秒数据 | 轮询用 `readRecent(5s)` 限制窗口 |
| ⚠️27 | 后台超时断连 | 数据中断 | 自动重连 + 指数退避 |

---

## 7. State Restoration 恢复流程

```mermaid
sequenceDiagram
    participant Sys as iOS System
    participant BLE as BLECentralDataSource
    participant CM as ConnectionMiddleware
    participant Redux as Store
    participant Dev as Peripheral

    Note over Sys: App 被系统杀掉<br/>(内存压力/后台超时)
    Note over Dev: BLE 连接由蓝牙芯片保持<br/>(不依赖 App 进程)

    Note over Sys: 新的 BLE 事件到达<br/>(notify 数据/连接状态变化)
    Sys->>Sys: 重启 App 进程

    Note over Sys: ⚠️ 坑点28: 重启条件<br/>只有系统杀 App 才触发<br/>用户手动杀掉 → 不恢复<br/>BLE 连接被彻底断开

    Sys->>BLE: CBCentralManager init<br/>(restoreIdentifier 相同)
    BLE-->>Sys: 系统识别到 restoreIdentifier

    Sys->>BLE: willRestoreState(dict)
    Note over BLE: dict[PeripheralsKey] → [CBPeripheral]

    Note over BLE: ⚠️ 坑点29: peripheral.delegate 不恢复<br/>必须手动设置<br/>peripheral.delegate = self<br/>否则所有回调不触发

    BLE->>BLE: _connectedPeripheral = peripheral
    BLE-->>CM: restoredPeripheralIDsStream.yield([UUID])

    CM->>Redux: dispatch(.restoreInitiated)
    CM->>BLE: beginRestoredConnectionValidation()
    BLE->>Dev: discoverServices([serviceUUID])

    Note over Dev: ⚠️ 坑点30: services 可能为空<br/>恢复后的 peripheral 不保证<br/>缓存 GATT 数据库<br/>→ 必须重新 discoverServices

    Dev-->>BLE: didDiscoverServices
    BLE->>Dev: discoverCharacteristics([...])
    Dev-->>BLE: didDiscoverCharacteristicsFor

    Note over BLE: ⚠️ 坑点31: CCCD 可能已重置<br/>isNotifying 可能为 false<br/>→ 必须重新 setNotifyValue(true)<br/>否则收不到数据

    BLE->>Dev: setNotifyValue(true) for 0002
    Dev-->>BLE: didUpdateNotificationStateFor

    Note over BLE: HandshakeReadinessGate 检查
    BLE-->>CM: emitState(.restoredValidating)

    CM->>BLE: performHandshake()
    BLE->>Dev: HELLO (Write 0003)

    alt 握手成功
        Dev-->>BLE: HELLO_ACK
        Note over BLE: 解析 DeviceInfo<br/>验证协议版本兼容
        BLE-->>CM: emitState(.restoredConnected)
        CM->>Redux: dispatch(.restoreConnectionRestored)
    else 握手失败
        Note over CM: ⚠️ 坑点32: 协议版本不兼容<br/>固件升级后协议变了<br/>HELLO_ACK 中 protocolVersion 不匹配<br/>→ dispatch(.restoreFailed)
        CM->>Redux: dispatch(.restoreFailed)
        Note over CM: 回退到正常连接流程<br/>断开 → 重新扫描 → 完整连接
    end
```

**坑点总结**：

| 坑 | 描述 | 后果 | 缓解 |
|----|------|------|------|
| ⚠️28 | 用户手动杀 App | BLE 连接丢失，不恢复 | 文档告知用户不要手动杀 App |
| ⚠️29 | delegate 不自动恢复 | 所有回调不触发 | `willRestoreState` 中设置 delegate |
| ⚠️30 | services 缓存不可靠 | discoverServices 返回空 | 始终重新 discoverServices |
| ⚠️31 | CCCD 可能重置 | 收不到 notify 数据 | 始终重新 setNotifyValue(true) |
| ⚠️32 | 协议版本不兼容 | 握手失败 | 版本检查 + 降级到完整连接流程 |

---

## 坑点总索引

| 编号 | 流程 | 坑点 | 严重度 |
|------|------|------|--------|
| 1 | BLE 连接 | connect() 无超时 | 高 |
| 2 | BLE 连接 | 特征发现顺序不确定 | 中 |
| 3 | BLE 连接 | CCCD 写入失败 | 高 |
| 4 | 数据管线 | BLE notify 丢包 | 中 |
| 5 | 数据管线 | bleQueue → MainActor 线程切换 | 高 |
| 6 | 数据管线 | BackgroundMiddleware 拦截 | 低（设计意图） |
| 7 | 数据管线 | 高频 dispatch UI 卡顿 | 高 |
| 8 | OTA | 低电量 OTA | 严重 |
| 9 | OTA | resumeOffset 断点续传 | 高 |
| 10 | OTA | WINDOW_ACK 超时 | 中 |
| 11 | OTA | 传输中 BLE 断连 | 高 |
| 12 | OTA | CRC-32 不匹配 | 高 |
| 13 | 计算推理 | 闭包可变状态数据竞争 | 高 |
| 14 | 计算推理 | RR 间期不足 | 低 |
| 15 | 计算推理 | Sample Entropy O(n²) | 中 |
| 16 | 计算推理 | MLMultiArray 形状错误 | 高 |
| 17 | 计算推理 | 模型文件缺失 | 低（有降级） |
| 18 | 睡眠 | 监测未启动 | 低 |
| 19 | 睡眠 | 4 小时历史不连续 | 中 |
| 20 | 睡眠 | C++ 特征计算失败 | 中 |
| 21 | 睡眠 | ML 推理失败降级 | 低（有降级） |
| 22 | 睡眠 | stage 频繁切换碎片化 | 中 |
| 23 | 睡眠 | 持久化连锁读旧数据 | 中 |
| 24 | 后台 | 拦截 vs Ring Buffer 不一致 | 低（设计意图） |
| 25 | 后台 | CPU 预算超限被杀 | 严重 |
| 26 | 后台 | 前台恢复数据跳变 | 低 |
| 27 | 后台 | 超时断连 | 中 |
| 28 | 恢复 | 用户手动杀 App | 低 |
| 29 | 恢复 | delegate 不恢复 | 严重 |
| 30 | 恢复 | services 缓存不可靠 | 高 |
| 31 | 恢复 | CCCD 可能重置 | 高 |
| 32 | 恢复 | 协议版本不兼容 | 中 |
