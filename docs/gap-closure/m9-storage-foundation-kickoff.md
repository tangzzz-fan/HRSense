# M9 存储基础设施启动与边界收敛

## 为什么现在可以开始 M9

`M9` 的规划依赖是 `M5 + M8`：

- `M5` 已经具备波形采集、环形缓冲与波形展示基础
- `M8` 已经具备 RR -> HRV -> 特征 -> 推理 的主链路

这意味着 `M9` 的两个前置输入已经存在：

1. 有持续产生的原始数据与波形数据
2. 有需要长期保存和回看的计算结果与推理结果

所以从依赖关系上，`M9` 已经具备启动条件。

## 启动时的真实缺口

虽然依赖已满足，但代码里在本轮开始前仍然没有任何真正的存储边界：

- `HRSenseCore` 没有 `PersistenceStore`
- 没有 `Session / HRVMetricRecord / InferenceRecord / SleepSession / WaveformBlobRef` 等领域实体
- `HRSenseData` 没有 `SwiftDataStore`
- 也没有任何可用于验证查询、聚合、清理语义的存储实现

这意味着如果直接开始写 `SwiftData` 查询或 UI 图表，会马上出现两个问题：

- 上层被 `SwiftData` 的 `@Model / ModelContext / Predicate` 细节反向污染
- 后面改成 `GRDB/SQLite` 时，业务层和图表层要一起重写

## 本轮启动策略

本轮没有直接跳到 `SwiftDataStore`，而是先落 `M9` 的**存储边界基础层**：

1. 在 `HRSenseCore` 定义持久化领域实体
2. 在 `HRSenseCore` 定义 `PersistenceStore` 抽象协议
3. 在 `HRSenseData` 提供 `InMemoryPersistenceStore` 作为启动实现
4. 用单元测试先锁定：
   - 查询语义
   - 聚合语义
   - 保留/清理语义

这样做的目的不是“以后就用内存存储”，而是先把**接口、查询口径、聚合结果、清理行为**固定下来，再让 `SwiftDataStore` 去实现同一份契约。

## 新增实现原理

### 1. 为什么先定义领域实体，而不是先写 `SwiftData @Model`

`M9` 最容易走偏的一点，是把持久化模型直接当成领域模型来用。

如果一开始就直接写：

- `@Model SessionModel`
- `@Model HeartRateSampleModel`
- `ModelContext.fetch(...)`

那么后面会产生三种偏移：

- **存储实现偏移**：一旦替换为 `GRDB/SQLite`，上层接口全部跟着改
- **查询语义偏移**：UI 和 Middleware 直接依赖底层查询细节，后面难统一口径
- **领域模型偏移**：业务层开始围绕 DB 结构写逻辑，而不是围绕领域概念写逻辑

所以本轮先在 `HRSenseCore` 固定的是：

- `Session`
- `HeartRateSampleRecord`
- `RRSampleRecord`
- `HRVMetricRecord`
- `InferenceRecord`
- `SleepSession`
- `WaveformBlobRef`
- `EventRecord`

先把“业务上保存什么”定清楚，再决定“底层怎么存”。

### 2. 为什么要先有 `PersistenceStore`

`PersistenceStore` 是 `M9` 最关键的替换边界。

它现在收敛了三类能力：

- **写入**
  - `saveSession`
  - `saveHeartRateSamples`
  - `saveHRVMetrics`
  - `saveInferenceRecords`
  - `saveSleepSession`
  - `saveWaveformBlobRefs`

- **查询/聚合**
  - `querySessions`
  - `queryHeartRate`
  - `queryHRVMetrics`
  - `querySleepSessions`
  - `aggregateHeartRate`

- **保留/清理**
  - `purgeExpiredData`

这样后面的 `SwiftDataStore`、未来可能的 `GRDBStore`，都必须对齐这一组查询语义，而不是各自长出一套风格不同的接口。

### 3. 为什么启动实现选择 `InMemoryPersistenceStore`

这里使用内存实现，不是为了替代 `SwiftData`，而是为了先解决一个更根本的问题：

**如何在不绑定真实数据库的前提下，先把存储契约测试起来。**

它的价值主要有三点：

- 可以先验证 query / aggregate / purge 的行为是否符合 `M9` 设计
- 可以为后续 Middleware / ViewModel / 图表层开发提供稳定 fake/store
- 可以让 `SwiftDataStore` 之后以“同一套测试口径”对齐，而不是边写边猜

这属于典型的“先锁接口语义，再换真实后端实现”策略。

## 这轮如何防止后续实现偏移

### 1. 防止 `SwiftData` 泄漏到上层

现在上层只会看到：

- `PersistenceStore`
- `SessionQuery / HeartRateQuery / HRVMetricQuery / SleepSessionQuery`
- `HeartRateAggregationBucket`
- `RetentionPolicy / StoragePurgeResult`

不会直接看到：

- `@Model`
- `ModelContext`
- `FetchDescriptor`
- `Predicate`

这能保证后续 `SwiftDataStore` 只是一个实现细节，而不是上层的默认世界观。

### 2. 防止查询口径漂移

本轮先用 `InMemoryPersistenceStoreTests` 锁定了几类最容易漂移的行为：

- session 查询按最新时间倒序返回
- heart-rate 查询支持时间范围与 limit
- trend 聚合按 bucket 输出 min/avg/max
- purge 按 retention cutoff 清理过期原始数据与波形引用
- sleep session 查询按最新日期倒序返回

这些测试后面会成为 `SwiftDataStore` 的对齐基线。

### 3. 防止保留策略在实现阶段失真

很多项目在设计文档里写了 retention policy，但真正落库后：

- cutoff 规则被写散
- 清理统计口径不一致
- reclaim 结果无法量化

所以本轮已经把以下概念提前落成显式类型：

- `RetentionPolicy`
- `StoragePurgeResult`

这样后面做 `RetentionCleanupTask` 时，不会把清理逻辑继续写成一堆隐式常量和分散判断。

## 本轮代码落点

- `Sources/HRSenseCore/Entities/PersistenceModels.swift`
- `Sources/HRSenseCore/Repositories/PersistenceStore.swift`
- `Sources/HRSenseData/Persistence/InMemoryPersistenceStore.swift`
- `Tests/HRSenseDataTests/InMemoryPersistenceStoreTests.swift`

## 第二层已按计划开始实施

在 `plans/09-m9-storage-visualization-sleep.md` 里，阶段 2 的目标非常明确：

- `*Model.swift`
- `SwiftDataStore.swift`
- `BackgroundWriteBuffer.swift`
- `DataAggregation.swift`

本轮继续推进 `M9` 时，严格沿这个顺序开始落地，而不是跳过阶段 2 直接去写：

- 图表查询
- UI 视图
- 睡眠 hypnogram
- Redux 持久化接线

原因很简单：如果阶段 2 没落稳，后面的图表、睡眠和 Middleware 都会直接建立在不稳定的存储细节之上。

### 1. 这轮新增的 Phase 2 代码

- `Sources/HRSenseData/Persistence/SwiftDataModels.swift`
  - 新增 `SessionModel / HeartRateSampleModel / RRSampleModel / HRVMetricRecordModel / InferenceRecordModel / SleepSessionModel / WaveformBlobRefModel / EventRecordModel`
  - 每个模型都提供 `domain -> model` 与 `model -> domain` 映射

- `Sources/HRSenseData/Persistence/SwiftDataStore.swift`
  - 使用 `ModelActor` 形式实现 `PersistenceStore`
  - 查询与聚合出口仍然只暴露 `PersistenceStore` 定义好的抽象接口

- `Sources/HRSenseData/Persistence/BackgroundWriteBuffer.swift`
  - 提供阈值触发和定时 flush 的后台批量写缓冲器
  - 为后续 `PersistenceMiddleware` 做写入削峰准备

- `Sources/HRSenseData/Persistence/DataAggregation.swift`
  - 提取心率趋势聚合逻辑
  - 让 `InMemoryPersistenceStore` 与 `SwiftDataStore` 共享同一份 bucket 口径

- `Tests/HRSenseDataTests/SwiftDataStoreTests.swift`
  - 验证 `SwiftDataStore` 的 save/query/aggregate/purge 行为与基础层契约一致

- `Tests/HRSenseDataTests/BackgroundWriteBufferTests.swift`
  - 验证阈值 flush、定时 flush 与手动 flush

### 2. 为什么这叫“按 plans 开始实施”

这里不是简单地“用上了 SwiftData”，而是按计划把阶段 2 拆成了对应的四层职责：

1. **模型映射层**
   - `@Model` 只负责持久化表示
   - 领域实体仍然留在 `HRSenseCore`

2. **存储实现层**
   - `SwiftDataStore` 只实现 `PersistenceStore`
   - 不把 `ModelContext` 暴露给上层

3. **批量写入层**
   - `BackgroundWriteBuffer` 先独立落地
   - 后面再接入 `PersistenceMiddleware`

4. **聚合层**
   - `DataAggregation` 独立于 `SwiftDataStore`
   - 后续迁到 `GRDBStore` 时可以继续复用同一套聚合口径

这和 `plans` 里“模型映射层与查询层分离、查询/聚合先收敛到 `PersistenceStore` 抽象接口”的要求是一致的。

### 3. 这轮如何继续防止偏移

进入阶段 2 后，新的偏移风险主要来自三处：

- `SwiftData` 模型字段和领域模型字段开始失配
- `SwiftDataStore` 的查询口径和 `InMemoryPersistenceStore` 不一致
- 批量写入在后续接入时改变写入顺序或 flush 行为

这轮对应的防偏移策略是：

- **模型映射显式化**
  - 每个 `@Model` 都写 `toDomain()/init(domain:)/apply(_:)`
  - 避免靠隐式字段名约定同步

- **同契约双实现对拍**
  - 先有 `InMemoryPersistenceStore`
  - 再让 `SwiftDataStoreTests` 对齐同一套 save/query/aggregate/purge 语义

- **聚合逻辑抽离**
  - 不把 minute/hour/day bucket 逻辑塞进 `SwiftData` 查询细节
  - 先由 `DataAggregation` 明确趋势桶口径

- **写入缓冲单独测试**
  - `BackgroundWriteBuffer` 独立测试阈值和定时行为
  - 避免以后在 `PersistenceMiddleware` 里边写边猜 flush 规则

### 4. 对 M9 下一步的直接意义

到这里，`M9` 已经不只是“有存储边界”，而是开始具备真正的阶段 2 能力：

- 结构化数据已经能通过 `SwiftDataStore` 落库和查询
- 聚合逻辑已经抽离为独立层
- 后台批量写的基础组件已经具备
- 后续可以按计划继续接：
  - `WaveformFileStore`
  - `PersistenceMiddleware`
  - 趋势图/HRV 图的数据源
  - 睡眠分期结果落库

## 对 M9 下一步的直接意义

这轮完成后，`M9` 已经从“只有规划文档、没有代码边界”推进到“有明确的领域模型和可验证的存储契约”。

下一步可以顺着这个边界继续推进：

1. `SwiftDataStore` 的 `@Model` 映射层
2. `WaveformFileStore`
3. `PersistenceMiddleware` 批量写入
4. 日/周/月图表查询与聚合接线
5. 睡眠分期结果落库与 hypnogram 数据源
