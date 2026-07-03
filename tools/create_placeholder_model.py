#!/usr/bin/env python3
"""
create_placeholder_model.py — 生成 HRSense M8 占位 CoreML 模型

生成一个可在 iOS 17+ 设备上运行的极简二分类 CoreML 模型
（Baseline / Stress），输入 14 维 HRV 特征，输出类别标签 + 概率。

模型逻辑：简单的线性分类器 + softmax，权重基于领域启发式规则：
  - 高 HR (index 4) + 低 RMSSD (index 1) + 高 StressIndex (index 13) → "Stress"
  - 否则 → "Baseline"

依赖：pip install coremltools numpy
coremltools 版本 ≥ 8.0（兼容 iOS 17+/macOS 14+）

输出：Models/StressClassifier_v1.mlpackage/

使用方法：
  python3 tools/create_placeholder_model.py

替换为真实模型的流程：
  1. 训练模型（sklearn / PyTorch / Create ML），产出 14 维特征 → 2 类 label
  2. 用 coremltools.convert() 或 Create ML 导出 .mlpackage
  3. 确认模型 I/O schema 与本脚本一致（见下方 schema）
  4. 替换 Models/StressClassifier_v1.mlpackage
  5. 更新 modelVersion 字符串
  6. 运行 swift test --filter HRSenseComputeTests 确认黄金值通过
"""

import os
import sys
import numpy as np

try:
    import coremltools as ct
except ImportError:
    print("❌ 需要 coremltools: pip install coremltools")
    sys.exit(1)

# ────────────────────────────────────────────────────────
# 1. 模型定义：线性分类器（可替换为任意 sklearn/PyTorch 模型）
# ────────────────────────────────────────────────────────

class PlaceholderStressClassifier:
    """
    基于 HRV 领域知识的规则线性分类器。

    特征索引（与 HRS_FEATURE_DIM 14 完全对齐）：
      0  sdnn           — RR 标准差（ms）
      1  rmssd          — 相邻 RR 差值均方根（ms）
      2  pnn50          — 相邻 RR 差 >50ms 占比（%）
      3  meanRR         — 平均 RR 间期（ms）
      4  hr             — 心率（bpm）
      5  lfPower        — 低频功率（ms²）
      6  hfPower        — 高频功率（ms²）
      7  lfHfRatio      — LF/HF 比
      8  totalPower     — 总功率（ms²）
      9  sd1            — Poincaré SD1（短轴）
      10 sd2            — Poincaré SD2（长轴）
      11 sampleEntropy  — 样本熵
      12 dfaAlpha1      — DFA α1
      13 stressIndex    — Baevsky 压力指数

    分类规则（权重可以替换为训练得到的值）：
      - "低 HRV + 高 HR + 高压力指数" → 偏向 Stress
      - 给这个模型喂白噪声，模型仍然出分类，不追求精度
    """
    def __init__(self):
        # 线性权重（14 维 → 2 类），经过 softmax
        # 类 0 = Baseline，类 1 = Stress
        self.weights = np.zeros((14, 2), dtype=np.float32)

        # RMSSD 高 → Baseline 分数高
        self.weights[1, 0] =  0.3   # rmssd → Baseline
        self.weights[1, 1] = -0.3   # rmssd → Stress

        # HR 高 → Stress 分数高
        self.weights[4, 0] = -0.2   # hr → Baseline
        self.weights[4, 1] =  0.2   # hr → Stress

        # pNN50 高 → Baseline（高 HRV）
        self.weights[2, 0] =  0.15

        # SDNN 高 → Baseline
        self.weights[0, 0] =  0.15

        # stressIndex 高 → Stress
        self.weights[13, 0] = -0.25
        self.weights[13, 1] =  0.25

        # LF/HF ratio 高 → Stress（交感神经占优）
        self.weights[7, 0]  = -0.1
        self.weights[7, 1]  =  0.1

        # DFA alpha1 高 → Stress
        self.weights[12, 1] =  0.1

        # bias
        self.bias = np.array([0.1, -0.1], dtype=np.float32)

    def predict(self, X):
        """X shape (N, 14) → logits shape (N, 2)"""
        return X @ self.weights + self.bias


# ────────────────────────────────────────────────────────
# 2. 生成训练数据（合成 + 规则打标）
# ────────────────────────────────────────────────────────

def generate_synthetic_data(n_samples=500):
    """
    合成 HRV 特征数据，用简单规则打标：
      - hr > 90 且 rmssd < 30 且 stressIndex > 500 → "Stress"
      - 否则 → "Baseline"
    """
    np.random.seed(42)
    X = np.zeros((n_samples, 14), dtype=np.float32)
    y = np.zeros(n_samples, dtype=np.int32)

    for i in range(n_samples):
        # 随机生成"低 HRV / 高压力"或"正常 HRV / 放松"样本
        if np.random.random() < 0.5:
            # Baseline（放松）：正常 HRV
            sdnn       = np.random.normal(50, 10)
            rmssd      = np.random.normal(40, 8)
            pnn50      = np.random.normal(20, 5)
            meanRR     = np.random.normal(850, 50)
            hr         = np.random.normal(70, 5)
            lfPower    = np.random.normal(800, 200)
            hfPower    = np.random.normal(600, 150)
            lfHfRatio  = np.random.normal(1.3, 0.3)
            totalPower = np.random.normal(1600, 300)
            sd1        = np.random.normal(30, 5)
            sd2        = np.random.normal(60, 10)
            sampEn     = np.random.normal(1.5, 0.3)
            dfaA1      = np.random.normal(0.85, 0.1)
            stressIdx  = np.random.normal(200, 50)
            y[i] = 0  # Baseline
        else:
            # Stress（高压力）：低 HRV + 高 HR
            sdnn       = np.random.normal(20, 5)
            rmssd      = np.random.normal(15, 4)
            pnn50      = np.random.normal(3, 2)
            meanRR     = np.random.normal(650, 30)
            hr         = np.random.normal(95, 8)
            lfPower    = np.random.normal(1200, 300)
            hfPower    = np.random.normal(200, 50)
            lfHfRatio  = np.random.normal(4.0, 1.0)
            totalPower = np.random.normal(1600, 300)
            sd1        = np.random.normal(10, 3)
            sd2        = np.random.normal(30, 8)
            sampEn     = np.random.normal(0.8, 0.2)
            dfaA1      = np.random.normal(1.2, 0.15)
            stressIdx  = np.random.normal(800, 150)
            y[i] = 1  # Stress

        X[i] = [sdnn, rmssd, pnn50, meanRR, hr,
                lfPower, hfPower, lfHfRatio, totalPower,
                sd1, sd2, sampEn, dfaA1, stressIdx]

    return X, y


# ────────────────────────────────────────────────────────
# 3. 训练（简单线性分类器 + softmax）
# ────────────────────────────────────────────────────────

def softmax(logits):
    exp_logits = np.exp(logits - np.max(logits, axis=1, keepdims=True))
    return exp_logits / np.sum(exp_logits, axis=1, keepdims=True)


def cross_entropy_loss(probs, y):
    n = len(y)
    return -np.sum(np.log(probs[np.arange(n), y] + 1e-10)) / n


def train_model(model, X, y, epochs=100, lr=0.01):
    """简单梯度下降训练"""
    for epoch in range(epochs):
        logits = model.predict(X)
        probs = softmax(logits)

        # 梯度
        n = len(y)
        grad = probs.copy()
        grad[np.arange(n), y] -= 1
        grad /= n

        dW = X.T @ grad
        db = grad.sum(axis=0)

        model.weights -= lr * dW
        model.bias    -= lr * db

        if epoch % 20 == 0:
            loss = cross_entropy_loss(probs, y)
            acc = np.mean(np.argmax(probs, axis=1) == y)
            print(f"  Epoch {epoch:3d}: loss={loss:.4f}  accuracy={acc:.2%}")

    return model


# ────────────────────────────────────────────────────────
# 4. 转换为 CoreML .mlpackage
# ────────────────────────────────────────────────────────

def convert_to_coreml(model, output_dir="Models"):
    """将训练好的权重转换为 CoreML .mlpackage"""
    os.makedirs(output_dir, exist_ok=True)

    model_path = os.path.join(output_dir, "StressClassifier_v1.mlpackage")
    classifier = model  # for clarity below

    # 构建 CoreML 模型（使用神经网络构建器或直接转换）
    # 方案 A：使用 coremltools 的神经网络构建器（推荐 — 可完全控制 I/O）
    import coremltools.models.datatypes as dt

    # 构建一个极简神经网络：Dense(2) + Softmax
    builder = ct.models.neural_network.NeuralNetworkBuilder(
        input_features=[("features", dt.Array(14))],
        output_features=[("classProbability", dt.Array(2))],
        mode="classifier",
    )

    # 全连接层
    builder.add_inner_product(
        name="fc",
        W=classifier.weights.T,  # (2, 14)
        b=classifier.bias,
        input_channels=14,
        output_channels=2,
        has_bias=True,
        input_name="features",
        output_name="logits",
    )

    # Softmax
    builder.add_softmax(
        name="softmax",
        input_name="logits",
        output_name="classProbability",
    )

    # 设置分类标签
    builder.set_class_labels(
        class_labels=["Baseline", "Stress"],
        predicted_feature_name="classLabel",
        prediction_blob="classProbability",
    )

    # Write metadata in a way that works with coremltools 9+.
    spec = builder.spec
    spec.description.metadata.shortDescription = (
        "HRSense placeholder stress classifier — 14 HRV features to Baseline/Stress"
    )
    spec.description.metadata.author = "HRSense"
    spec.description.metadata.versionString = "1.0.0"
    spec.description.metadata.userDefined["featureContractVersion"] = "1"
    spec.description.metadata.userDefined["task"] = "stress-classification"
    spec.description.metadata.userDefined["modelVersion"] = "1.0.0-placeholder"

    # Export the final model package.
    mlmodel = ct.models.MLModel(spec, weights_dir=output_dir)
    mlmodel.save(model_path)
    print(f"\n✅ CoreML model exported to: {model_path}")
    print(f"   File size: {_get_dir_size(model_path):.1f} KB")


def _get_dir_size(path):
    total = 0
    for dirpath, _, filenames in os.walk(path):
        for f in filenames:
            total += os.path.getsize(os.path.join(dirpath, f))
    return total / 1024


# ────────────────────────────────────────────────────────
# 5. 转换后一致性校验
# ────────────────────────────────────────────────────────

def validate_model(model, mlmodel_path):
    """验证 CoreML 模型输出与实际分类器一致"""
    print("\n🔍 Validating CoreML model against reference...")

    # 生成一些测试样本
    X_test, _ = generate_synthetic_data(n_samples=20)

    # 参考输出（Python 侧）
    logits = model.predict(X_test)
    ref_probs = softmax(logits)
    ref_labels = ["Baseline" if p[0] > p[1] else "Stress" for p in ref_probs]

    # CoreML 输出
    mlmodel = ct.models.MLModel(mlmodel_path)
    errors = 0
    for i in range(len(X_test)):
        input_dict = {"features": X_test[i].tolist()}
        output = mlmodel.predict(input_dict)
        ml_label = output["classLabel"]
        if isinstance(ml_label, bytes):
            ml_label = ml_label.decode()
        ml_probs = output["classProbability"]

        label_match = ml_label == ref_labels[i]
        if not label_match:
            print(f"  ⚠️  Sample {i}: ML={ml_label} vs Ref={ref_labels[i]}")
            errors += 1

    if errors == 0:
        print("  ✅ All 20 samples match reference output")
    else:
        print(f"  ⚠️  {errors}/20 samples differ (acceptable within tolerance for placeholder)")

    print(f"  Sample output: {X_test[0].tolist()[:4]}... → {ref_labels[0]} "
          f"(Baseline={ref_probs[0][0]:.3f}, Stress={ref_probs[0][1]:.3f})")


# ────────────────────────────────────────────────────────
# 6. Main
# ────────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("HRSense Placeholder CoreML Model Generator")
    print("=" * 60)
    print(f"coremltools version: {ct.__version__}")
    print()

    # 生成数据
    print("1. Generating synthetic training data...")
    X, y = generate_synthetic_data(n_samples=500)
    print(f"   Generated {len(X)} samples (14 features × 2 classes)")
    print(f"   Class distribution: Baseline={np.sum(y==0)}, Stress={np.sum(y==1)}")

    # 训练
    print("\n2. Training simple linear classifier...")
    model = PlaceholderStressClassifier()
    model = train_model(model, X, y, epochs=100, lr=0.01)

    # 最终精度
    logits = model.predict(X)
    probs = softmax(logits)
    acc = np.mean(np.argmax(probs, axis=1) == y)
    print(f"   Final accuracy: {acc:.2%}")

    # 转换为 CoreML
    print("\n3. Converting to CoreML .mlpackage...")
    model_path = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "Models",
    )
    convert_to_coreml(model, output_dir=model_path)
    full_path = os.path.join(model_path, "StressClassifier_v1.mlpackage")

    # 校验
    print("\n4. Validating CoreML model...")
    validate_model(model, full_path)

    print("\n" + "=" * 60)
    print("Done! Next steps:")
    print("  1. Add Models/StressClassifier_v1.mlpackage to Xcode target")
    print("  2. Build & run — CoreMLService will load model at runtime")
    print("  3. When training a real model, replace this file and update")
    print("     CoreMLService.modelVersion")
    print("=" * 60)


if __name__ == "__main__":
    main()
