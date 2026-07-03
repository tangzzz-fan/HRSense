# M9 用 Python 创建 Sleep Model 的流程说明

## 结论

**可以**像当前 stress 模型一样，在 `tools` 目录下放一份 Python 脚本来生成 sleep model，方便：

- 先产出占位 `mlpackage`
- 固化模型 I/O 契约
- 验证工程加载链路
- 给后续真实训练模型提供同名替换入口

当前已经有两份相关脚本：

- [create_placeholder_model.py](file:///Users/bigapple/Developments/HRSense/tools/create_placeholder_model.py)
- [create_sleep_placeholder_model.py](file:///Users/bigapple/Developments/HRSense/tools/create_sleep_placeholder_model.py)

其中：

- `create_placeholder_model.py` 对应 **stress** 占位模型
- `create_sleep_placeholder_model.py` 对应 **sleep-stage** 占位模型

## 现有 stress 脚本是否可复用

答案是：**可以复用思路，不能原样直接复用**。

原因：

- stress 模型当前是：
  - `14` 维输入
  - `2` 分类输出：`Baseline / Stress`
  - `task = stress-classification`
- sleep 模型当前需要的是：
  - `18` 维输入
  - `4` 分类输出：`Wake / Light / Deep / REM`
  - `task = sleep-stage`

所以可复用的是：

- Python + `coremltools` 导出 `.mlpackage`
- `NeuralNetworkBuilder` 的构建方式
- metadata 写入方式
- 导出后本地一致性校验流程

不能直接复用的是：

- 输入维度
- 类别标签
- metadata 的 `task`
- 特征名称与顺序

## 当前 sleep model 的工程契约

睡眠模型输入必须对齐：

- [SleepModelFeatureSpec.swift](file:///Users/bigapple/Developments/HRSense/Sources/HRSenseCore/Entities/SleepModelFeatureSpec.swift)

当前固定为：

- `contractVersion = 1`
- `featureCount = 18`

### 18 维特征顺序

1. `sdnn`
2. `rmssd`
3. `pnn50`
4. `mean_rr`
5. `heart_rate`
6. `lf_power`
7. `hf_power`
8. `lf_hf_ratio`
9. `total_power`
10. `sd1`
11. `sd2`
12. `sample_entropy`
13. `dfa_alpha1`
14. `stress_index`
15. `minutes_since_session_start`
16. `local_clock_minutes`
17. `hr_trend`
18. `circadian_variation`

## Python 创建 sleep model 的标准流程

### 1. 准备 Python 环境

建议环境：

- Python `3.10+`
- `coremltools >= 8.0`
- `numpy`

安装方式：

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install coremltools numpy
```

如果后续使用真实训练框架，还可能需要：

- `scikit-learn`
- `torch`
- `tensorflow`
- `pandas`

### 2. 明确训练输入 schema

训练前必须先锁死三件事：

1. feature 名称
2. feature 顺序
3. `contractVersion`

这里必须直接以：

- [SleepModelFeatureSpec.swift](file:///Users/bigapple/Developments/HRSense/Sources/HRSenseCore/Entities/SleepModelFeatureSpec.swift)

为准，而不是在 Python 里另起一套口径。

### 3. 准备训练数据

真实训练数据建议至少包含：

- `session_id`
- `window_start`
- `window_end`
- `18` 维特征
- `label`

其中 `label` 需要明确映射到：

- `Wake`
- `Light`
- `Deep`
- `REM`

如果当前还没有真实训练数据，可以先像 stress 脚本一样：

- 生成 synthetic data
- 训练一个 placeholder 线性分类器
- 只用于验证工程链路，不宣称模型有效性

### 4. 训练模型

当前最务实的选择有三类：

- **占位模型**
  - 线性分类器 / 逻辑回归
  - 优点：实现快，容易导出和调试
  - 缺点：没有真实睡眠分期价值
- **sklearn 模型**
  - 如 logistic regression / random forest / xgboost
  - 优点：训练和调参简单
  - 缺点：时序能力有限
- **PyTorch / TensorFlow 模型**
  - 如 MLP / small temporal model
  - 优点：更适合真实睡眠分期建模
  - 缺点：训练、导出、版本兼容复杂度更高

当前工程阶段最推荐：

- 先用 **placeholder 线性分类器** 固化导出流程
- 真实模型后续再替换

### 5. 导出为 CoreML `.mlpackage`

当前 `tools/create_sleep_placeholder_model.py` 使用的是：

- `coremltools.models.neural_network.NeuralNetworkBuilder`

原因是它可以完全控制：

- 输入名
- 输出名
- 类别标签
- metadata

当前约定的 I/O 是：

- 输入：`features`
- 输出概率：`classProbability`
- 输出标签：`classLabel`

### 6. 写入 metadata

sleep model 必须至少写入：

- `featureContractVersion = 1`
- `task = sleep-stage`
- `modelVersion = ...`

这是后续运行时模型选择和校验的关键。

如果缺这些 metadata，会出现：

- 模型无法被正确识别为 sleep-stage 任务
- contract version 无法比对
- 上层无法准确区分 fallback 与真实模型

### 7. 导出路径

约定导出到：

- `Models/SleepStageClassifier_v1.mlpackage`

这样后续真实模型替换时：

- 文件名不变
- 运行时选择请求不变
- 上层服务只需要切换加载逻辑

### 8. 做本地一致性校验

导出后至少要做两层校验：

#### A. Python 侧参考输出校验

用原始 Python 模型和导出的 CoreML 模型对同一批样本推理，检查：

- `classLabel` 是否一致
- `classProbability` 是否在允许误差内

#### B. 工程侧契约校验

在仓库里至少补：

- 模型选择测试
- feature contract 测试
- sleep inference service 测试

## 当前脚本做了什么

新脚本：

- [create_sleep_placeholder_model.py](file:///Users/bigapple/Developments/HRSense/tools/create_sleep_placeholder_model.py)

当前实现内容：

- 合成 18 维 sleep 特征样本
- 训练 4 分类占位线性分类器
- 导出 `SleepStageClassifier_v1.mlpackage`
- 写入 `task=sleep-stage`
- 写入 `featureContractVersion=1`
- 写入 `modelVersion=1.0.0-placeholder`
- 做导出后的一致性验证

## 推荐使用方式

### 先生成占位模型

```bash
python3 tools/create_sleep_placeholder_model.py
```

执行成功后，预期输出：

- `Models/SleepStageClassifier_v1.mlpackage`

当前本地工作区已经按这个流程成功生成过一次该文件。

### 然后做工程接入

1. 把生成出的 `mlpackage` 纳入 Xcode target
2. 后续在 Swift 侧接 `sleep-stage` 模型选择
3. 保留 fallback 作为兜底

当前 Swift 侧已经推进到：

- `SleepStageService` 优先加载 sleep-stage CoreML 模型
- 当模型不可用时，自动回退到规则推理

## 当前风险点

### 1. 这仍然只是占位模型

它的价值主要是：

- 固化工程接口
- 跑通 CoreML 加载路径
- 让 UI 和推理链路可以联调

不是：

- 可用于真实睡眠分期的产品模型

### 2. synthetic data 不代表真实分布

合成数据只能用来验证流程，不应用来判断模型效果。

### 3. metadata 必须严格对齐

真实模型替换时，最容易出问题的是：

- `task` 写错
- `featureContractVersion` 漏写
- 输入维度不一致
- feature 顺序与 Swift 侧不一致

## 后续建议

最合理的推进顺序是：

1. 用 `create_sleep_placeholder_model.py` 先生成占位 sleep model
2. 在 Swift 侧把 `SleepStageService` 改成“模型优先、fallback 兜底”
3. 跑通真实 `sleep-stage` 模型加载路径
4. 等真实训练模型准备好后，直接替换同名 `mlpackage`
5. 用真实夜间回放数据做端到端验证
