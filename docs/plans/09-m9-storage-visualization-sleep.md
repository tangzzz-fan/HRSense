# M9 · 本地存储 + 可视化 + 睡眠结构 — 实施计划

## 摘要

持久化 + 高性能图表 + 睡眠 hypnogram。采用 SwiftData（结构化）+ 文件系统（波形大块）混合存储方案。包含数据保留/归档策略。

**依赖**：M5（波形）、M8（计算/CoreML）。

---

## 阶段 1：领域实体与存储协议（HRSenseCore）

| 实体 | 关键字段 |
|---|---|
| `Session` | id, deviceId, startAt, endAt, fwVersion |
| `HeartRateSample` | sessionId, ts, bpm |
| `RRSample` | sessionId, ts, rrMs |
| `HRVMetricRecord` | sessionId, windowStart, sdnn, rmssd, pnn50, lfHf, ... |
| `InferenceRecord` | sessionId, ts, label, confidence, modelVersion |
| `SleepSession` | id, date, stages: [SleepStage] |
| `WaveformBlobRef` | sessionId, type, sampleRate, startTs, fileURL, checksum |
| `EventRecord` | sessionId, ts, kind, payload |

**`PersistenceStore` 协议**：
```
saveSession / saveSamples / saveHRVMetrics / saveInference / saveSleepSession / saveWaveformBlobRef
querySessions / queryHeartRate / queryHRVMetrics / querySleepSessions
aggregateHeartRate / purgeExpiredData
```

---

## 阶段 2：SwiftDataStore 实现（HRSenseData）

| 文件 | 职责 |
|---|---|
| `*Model.swift`（8 个） | `@Model` 持久化类 + `toDomain()/fromDomain()` 映射 |
| `SwiftDataStore.swift` | 实现 `PersistenceStore`，专用 `ModelActor` 后台写入 |
| `BackgroundWriteBuffer.swift` | 内存批量累积（阈值 100/5s 定时），后台写入不阻塞 UI/BLE |
| `DataAggregation.swift` | min/avg/max 桶聚合，原始点降采样归档 |

---

## 阶段 3：WaveformFileStore 实现

| 文件 | 职责 |
|---|---|
| `WaveformFileStore.swift` | 二进制文件读写：`writeChunks`、`readChunks`、`deleteChunks`、`verifyChecksum` |
| 文件格式 | 头（Magic `0x48525357` + 版本 + sampleRate + sampleBits）+ 块数组 `[blockSeq:u32][timestampOffset:u32][sampleCount:u16][samples:i16[]]` |
| 校验 | SHA-256 整文件校验和 |

**存储布局**：`Application Support/HRSense/waveforms/<sessionId>/<type>_<startTs>.bin`

---

## 阶段 4：保留与归档后台任务

| 文件 | 职责 |
|---|---|
| `RetentionPolicy.swift` | 配置：waveformRetentionDays（7）、rawSampleRetentionDays（30）、maxTotalStorageBytes（500MB） |
| `RetentionCleanupTask.swift` | 波形过期清理、原始点降采样归档、存储上限裁剪 |
| `BackgroundTaskScheduler.swift` | `BGTaskScheduler` 注册 + 应用启动时触发 + 后台触发 |

---

## 阶段 5：睡眠分期模型（HRSenseData/ML/）

| 文件 | 职责 |
|---|---|
| `SleepStageService.swift` | 包装睡眠模型加载与预测（Wake/Light/Deep/REM） |
| `SleepInferenceRepositoryImpl.swift` | 实现 `SleepInferenceRepository` 协议 |
| `Models/SleepStageClassifier_v1.mlpackage` | Git LFS 跟踪的占位模型 |

### C++ 特征扩展
- `hrs_compute_hr_trend()` — 窗口内心率线性回归斜率
- `hrs_compute_circadian_variation()` — 多小时间窗 HRV 幅度

---

## 阶段 6：图表组件（HRSenseFeature/Views/Charts/）

| 文件 | 职责 |
|---|---|
| `HeartRateTrendChart.swift` | Swift Charts：`LineMark`+`AreaMark`，日/周/月聚合切换 |
| `HRVChart.swift` | 多系列：SDNN/RMSSD/LFHF 折线 |
| `SleepHypnogramView.swift` | **自定义 Canvas**：阶段色块（Wake 浅灰、REM 紫、Light 蓝、Deep 深蓝），时间轴+手势 |

---

## 阶段 7：Redux 状态

| 文件 | 内容 |
|---|---|
| `SleepState.swift` | `currentSession`、`stageHistory`、`isMonitoring`、`lastInference` |
| `StorageState.swift` | `lastPurgeResult`、`totalStorageBytes`、`isRetentionTaskRunning` |
| `SleepAction.swift` / `StorageAction.swift` | 对应 Action 枚举 |
| `SleepMiddleware.swift` | 编排睡眠监测：窗口积累 → 特征提取 → 分期推理 → 持久化 |
| `PersistenceMiddleware.swift` | 监听所有数据 Action → 缓冲写入 → 批量落库 |

---

## 验收标准
- [ ] 会话数据落库；重启后可查询/聚合（日视图）
- [ ] 波形大块存文件 + 校验往返一致
- [ ] 保留策略生效：过期波形清理、原始点降采样归档
- [ ] 整夜 replay → 睡眠阶段带状图显示
- [ ] 存储写入不阻塞 UI/BLE（后台批量写）

## 预估文件数：~45 个新文件

## 实施顺序依赖

```
阶段 1（实体+协议）→ 阶段 2（SwiftDataStore）→ 阶段 3（WaveformFileStore）
                                                    ↓
阶段 1 → 阶段 5（睡眠模型+ pipeline）                阶段 4（保留任务）
                                                    ↓
                  阶段 6（图表+Hypnogram）← 阶段 2 + 阶段 5
                  阶段 7（Redux 集成）→ 全部
```
