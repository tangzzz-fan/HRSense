#!/usr/bin/env python3
"""
create_sleep_placeholder_model.py — 生成 HRSense M9 睡眠分期占位 CoreML 模型

目标：
  - 为 M9 提供一个可被工程加载的占位 sleep-stage CoreML 模型
  - 输入与 SleepModelFeatureSpec 保持一致：18 维 float 特征
  - 输出 4 类 sleep stage：Wake / Light / Deep / REM

依赖：
  pip install coremltools numpy

输出：
  Models/SleepStageClassifier_v1.mlpackage

说明：
  - 这是工程占位模型，不等于真实训练模型
  - 真实模型到位后，应直接替换同名 mlpackage，并保持 metadata / I-O contract 一致
"""

import os
import sys
import numpy as np

try:
    import coremltools as ct
except ImportError:
    print("❌ 需要 coremltools: pip install coremltools")
    sys.exit(1)


FEATURE_NAMES = [
    "sdnn",
    "rmssd",
    "pnn50",
    "mean_rr",
    "heart_rate",
    "lf_power",
    "hf_power",
    "lf_hf_ratio",
    "total_power",
    "sd1",
    "sd2",
    "sample_entropy",
    "dfa_alpha1",
    "stress_index",
    "minutes_since_session_start",
    "local_clock_minutes",
    "hr_trend",
    "circadian_variation",
]

CLASS_LABELS = ["Wake", "Light", "Deep", "REM"]


class PlaceholderSleepClassifier:
    """18 维输入 → 4 类输出的极简线性分类器。"""

    def __init__(self):
        self.weights = np.zeros((len(FEATURE_NAMES), len(CLASS_LABELS)), dtype=np.float32)
        self.bias = np.zeros(len(CLASS_LABELS), dtype=np.float32)

        # Wake: 高心率、高压力、更晚的局部唤醒趋势
        self.weights[4, 0] = 0.18   # heart_rate
        self.weights[13, 0] = 0.16  # stress_index
        self.weights[16, 0] = 0.12  # hr_trend

        # Light: 默认过渡态
        self.bias[1] = 0.12

        # Deep: 高副交感、低 HR、下降趋势
        self.weights[1, 2] = 0.18   # rmssd
        self.weights[6, 2] = 0.10   # hf_power
        self.weights[4, 2] = -0.12  # heart_rate
        self.weights[16, 2] = -0.08 # hr_trend

        # REM: 中低 HR、较高熵、后半夜更常见
        self.weights[11, 3] = 0.14  # sample_entropy
        self.weights[15, 3] = 0.05  # local_clock_minutes
        self.weights[17, 3] = 0.10  # circadian_variation

    def predict(self, X):
        return X @ self.weights + self.bias


def softmax(logits):
    exp_logits = np.exp(logits - np.max(logits, axis=1, keepdims=True))
    return exp_logits / np.sum(exp_logits, axis=1, keepdims=True)


def generate_synthetic_data(n_samples=800):
    """
    生成合成睡眠特征数据。
    这里只用于占位模型导出，不代表真实临床或训练分布。
    """
    np.random.seed(42)
    X = np.zeros((n_samples, len(FEATURE_NAMES)), dtype=np.float32)
    y = np.zeros(n_samples, dtype=np.int32)

    for i in range(n_samples):
        label = i % 4
        y[i] = label

        if label == 0:  # Wake
            values = [
                np.random.normal(18, 5),     # sdnn
                np.random.normal(15, 4),     # rmssd
                np.random.normal(2, 1),      # pnn50
                np.random.normal(690, 35),   # mean_rr
                np.random.normal(90, 7),     # heart_rate
                np.random.normal(400, 90),   # lf_power
                np.random.normal(120, 30),   # hf_power
                np.random.normal(2.8, 0.6),  # lf_hf_ratio
                np.random.normal(620, 120),  # total_power
                np.random.normal(10, 3),     # sd1
                np.random.normal(24, 6),     # sd2
                np.random.normal(0.7, 0.2),  # sample_entropy
                np.random.normal(1.15, 0.1), # dfa_alpha1
                np.random.normal(620, 120),  # stress_index
                np.random.normal(20, 10),    # minutes_since_session_start
                np.random.normal(60, 30),    # local_clock_minutes
                np.random.normal(0.15, 0.08),# hr_trend
                np.random.normal(0.08, 0.05) # circadian_variation
            ]
        elif label == 1:  # Light
            values = [
                np.random.normal(28, 6),
                np.random.normal(30, 6),
                np.random.normal(8, 3),
                np.random.normal(820, 40),
                np.random.normal(73, 6),
                np.random.normal(520, 120),
                np.random.normal(300, 80),
                np.random.normal(1.7, 0.4),
                np.random.normal(900, 150),
                np.random.normal(18, 4),
                np.random.normal(38, 8),
                np.random.normal(1.0, 0.2),
                np.random.normal(0.95, 0.1),
                np.random.normal(280, 70),
                np.random.normal(45, 20),
                np.random.normal(120, 60),
                np.random.normal(-0.03, 0.05),
                np.random.normal(0.16, 0.06)
            ]
        elif label == 2:  # Deep
            values = [
                np.random.normal(55, 10),
                np.random.normal(70, 10),
                np.random.normal(22, 6),
                np.random.normal(980, 40),
                np.random.normal(57, 4),
                np.random.normal(360, 90),
                np.random.normal(520, 120),
                np.random.normal(0.8, 0.2),
                np.random.normal(980, 160),
                np.random.normal(30, 5),
                np.random.normal(60, 10),
                np.random.normal(1.1, 0.15),
                np.random.normal(0.82, 0.08),
                np.random.normal(130, 40),
                np.random.normal(80, 30),
                np.random.normal(150, 60),
                np.random.normal(-0.12, 0.06),
                np.random.normal(0.12, 0.05)
            ]
        else:  # REM
            values = [
                np.random.normal(34, 8),
                np.random.normal(42, 8),
                np.random.normal(12, 4),
                np.random.normal(860, 35),
                np.random.normal(68, 5),
                np.random.normal(430, 100),
                np.random.normal(360, 90),
                np.random.normal(1.2, 0.3),
                np.random.normal(860, 150),
                np.random.normal(22, 5),
                np.random.normal(44, 8),
                np.random.normal(1.35, 0.2),
                np.random.normal(0.92, 0.08),
                np.random.normal(200, 60),
                np.random.normal(240, 50),
                np.random.normal(270, 60),
                np.random.normal(0.02, 0.05),
                np.random.normal(0.28, 0.08)
            ]

        X[i] = values

    return X, y


def train_model(model, X, y, epochs=120, lr=0.005):
    for epoch in range(epochs):
        logits = model.predict(X)
        probs = softmax(logits)

        grad = probs.copy()
        grad[np.arange(len(y)), y] -= 1
        grad /= len(y)

        model.weights -= lr * (X.T @ grad)
        model.bias -= lr * grad.sum(axis=0)

        if epoch % 20 == 0:
            loss = -np.mean(np.log(probs[np.arange(len(y)), y] + 1e-10))
            acc = np.mean(np.argmax(probs, axis=1) == y)
            print(f"  Epoch {epoch:3d}: loss={loss:.4f} accuracy={acc:.2%}")

    return model


def convert_to_coreml(model, output_dir="Models"):
    os.makedirs(output_dir, exist_ok=True)
    model_path = os.path.join(output_dir, "SleepStageClassifier_v1.mlpackage")

    import coremltools.models.datatypes as dt

    builder = ct.models.neural_network.NeuralNetworkBuilder(
        input_features=[("features", dt.Array(len(FEATURE_NAMES)))],
        output_features=[("classProbability", dt.Array(len(CLASS_LABELS)))],
        mode="classifier",
    )

    builder.add_inner_product(
        name="fc",
        W=model.weights.T,
        b=model.bias,
        input_channels=len(FEATURE_NAMES),
        output_channels=len(CLASS_LABELS),
        has_bias=True,
        input_name="features",
        output_name="logits",
    )

    builder.add_softmax(
        name="softmax",
        input_name="logits",
        output_name="classProbability",
    )

    builder.set_class_labels(
        class_labels=CLASS_LABELS,
        predicted_feature_name="classLabel",
        prediction_blob="classProbability",
    )

    spec = builder.spec
    spec.description.metadata.shortDescription = (
        "HRSense placeholder sleep-stage classifier — 18 features to Wake/Light/Deep/REM"
    )
    spec.description.metadata.author = "HRSense"
    spec.description.metadata.versionString = "1.0.0"
    spec.description.metadata.userDefined["featureContractVersion"] = "1"
    spec.description.metadata.userDefined["task"] = "sleep-stage"
    spec.description.metadata.userDefined["modelVersion"] = "1.0.0-placeholder"
    spec.description.input[0].shortDescription = ",".join(FEATURE_NAMES)

    mlmodel = ct.models.MLModel(spec, weights_dir=output_dir)
    mlmodel.save(model_path)
    print(f"\n✅ CoreML model exported to: {model_path}")


def validate_model(model, mlmodel_path):
    print("\n🔍 Validating CoreML model against reference...")
    X_test, _ = generate_synthetic_data(n_samples=20)
    ref_probs = softmax(model.predict(X_test))
    ref_labels = [CLASS_LABELS[int(np.argmax(p))] for p in ref_probs]

    mlmodel = ct.models.MLModel(mlmodel_path)
    errors = 0
    for i in range(len(X_test)):
        output = mlmodel.predict({"features": X_test[i].tolist()})
        label = output["classLabel"]
        if isinstance(label, bytes):
            label = label.decode()
        if label != ref_labels[i]:
            errors += 1

    if errors == 0:
        print("  ✅ All 20 samples match reference output")
    else:
        print(f"  ⚠️  {errors}/20 samples differ from reference output")


def main():
    print("=" * 60)
    print("HRSense Placeholder Sleep CoreML Model Generator")
    print("=" * 60)
    print(f"coremltools version: {ct.__version__}")

    print("\n1. Generating synthetic training data...")
    X, y = generate_synthetic_data()
    print(f"   Generated {len(X)} samples ({len(FEATURE_NAMES)} features × {len(CLASS_LABELS)} classes)")

    print("\n2. Training simple linear classifier...")
    model = train_model(PlaceholderSleepClassifier(), X, y)

    print("\n3. Converting to CoreML .mlpackage...")
    models_dir = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "Models",
    )
    convert_to_coreml(model, output_dir=models_dir)
    full_path = os.path.join(models_dir, "SleepStageClassifier_v1.mlpackage")

    print("\n4. Validating CoreML model...")
    validate_model(model, full_path)

    print("\nDone! Next steps:")
    print("  1. Add Models/SleepStageClassifier_v1.mlpackage to Xcode target")
    print("  2. Keep metadata task=sleep-stage and featureContractVersion=1")
    print("  3. Replace this placeholder file when the real sleep model is ready")


if __name__ == "__main__":
    main()
