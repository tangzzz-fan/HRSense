# M0 · 基础设施与协议契约冻结 — 实施计划

## 摘要

建立仓库骨架：`Package.swift` + 7 个空 SPM target（可编译）+ CI + 冻结 v1 协议契约文档。M0 是所有后续 milestone 的基础。

**当前状态**：仓库仅有文档，无源码。Swift 6.3.3 已安装，git-lfs 3.7.0 已安装，无远程仓库。

---

## 阶段 1：冻结 v1 协议契约（`docs/03-ble-gatt-protocol.md`）

**目标**：将所有"草案/待定"语言替换为已冻结的肯定措辞。唯一的开放项：「真机校订」。

**修改清单**（13 处精确修改）：

| # | 位置 | 当前 | 替换为 |
|---|---|---|---|
| 1 | 标题 | `（v1 草案）` | `（v1 冻结）` |
| 2 | 前言 | `均为**待冻结草案**，落地前需 review 确认。` | `均已**冻结**。以下定义即为 v1 实现契约。` |
| 3 | L2 FragHdr | `（草案）` | 删除，添加"v1 冻结"脚注 |
| 4 | L3 Flags | `（草案）` | 定义 bit7=req/resp、bit6=需要ACK、bit5..0=保留 |
| 5 | 命令表 | `（v1 草案）` | `（v1）` |
| 6 | 字段字典 | `（v1 草案）` | `（v1）` |
| 7–9 | §8 冻结状态 | 多处草案标记 | 改为"v1 冻结项" |
| 10–11 | §8.2 | "仍待定" | "真机校订（拿到真机后）" |
| 12–13 | §9.3 API 接口 | 草案标注 | v1 接口规划 |

**验证**：`grep -n "草案\|待定\|pending\|draft" docs/03-ble-gatt-protocol.md` 返回零匹配。

---

## 阶段 2：基础设施文件

### 2a. `.gitattributes` — Git LFS 配置

```
*.mlpackage filter=lfs diff=lfs merge=lfs -text
*.mlmodel filter=lfs diff=lfs merge=lfs -text
*.bin filter=lfs diff=lfs merge=lfs -text
*.swift text eol=lf
*.c text eol=lf
*.cpp text eol=lf
*.h text eol=lf
```

### 2b. `.github/workflows/ci.yml` — 最小 CI

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
jobs:
  build:
    name: Build
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
        with:
          lfs: true
      - name: Build
        run: swift build
      - name: Test
        run: swift test
```

### 2c. `THIRD_PARTY_LICENSES.md` — 许可登记存根

记录 TGReduxKit (MIT)、coremltools (BSD-3-Clause)、模型/数据集占位。

### 2d. 更新 `.gitignore`

追加：SPM artifacts、场景输出目录、Python venv、LFS 指针。

---

## 阶段 3：根 `Package.swift` 与空 Target

### 3a. `Package.swift`

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HRSense",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "HRSenseProtocol",     targets: ["HRSenseProtocol"]),
        .library(name: "HRSenseCore",         targets: ["HRSenseCore"]),
        .library(name: "HRSenseCompute",      targets: ["HRSenseCompute"]),
        .library(name: "HRSenseData",         targets: ["HRSenseData"]),
        .library(name: "HRSenseFeature",      targets: ["HRSenseFeature"]),
        .library(name: "HRSenseSimulatorKit", targets: ["HRSenseSimulatorKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tangzzz-fan/TGReduxKit.git", from: "1.0.0"),
    ],
    targets: [
        .target(name: "HRSenseProtocol"),
        .target(name: "HRSenseCore"),
        .target(name: "HRSenseComputeCxx",
                publicHeadersPath: "include",
                cxxSettings: [.headerSearchPath("include")]),
        .target(name: "HRSenseCompute",
                dependencies: ["HRSenseComputeCxx"]),
        .target(name: "HRSenseData",
                dependencies: ["HRSenseProtocol", "HRSenseCore", "HRSenseCompute"]),
        .target(name: "HRSenseFeature",
                dependencies: ["HRSenseCore", .product(name: "TGReduxKit", package: "TGReduxKit")]),
        .target(name: "HRSenseSimulatorKit",
                dependencies: ["HRSenseProtocol"]),
        .testTarget(name: "HRSenseProtocolTests", dependencies: ["HRSenseProtocol"]),
        .testTarget(name: "HRSenseComputeTests", dependencies: ["HRSenseCompute"]),
        .testTarget(name: "HRSenseDataTests", dependencies: ["HRSenseData"]),
        .testTarget(name: "HRSenseFeatureTests", dependencies: ["HRSenseFeature"]),
        .testTarget(name: "HRSenseSimulatorKitTests", dependencies: ["HRSenseSimulatorKit"]),
    ]
)
```

### 3b. 库 Target 占位文件（7 个）

每个 target 至少一个 `.swift`（或 `.cpp`）文件，含 `// M0 placeholder` 注释。

### 3c. C++ Target 关键文件

**`Sources/HRSenseComputeCxx/include/hrs_compute.h`**：
```c
#ifndef HRS_COMPUTE_H
#define HRS_COMPUTE_H
#ifdef __cplusplus
extern "C" {
#endif
int hrs_compute_init(void);
void hrs_compute_deinit(void);
#ifdef __cplusplus
}
#endif
#endif
```

**`Sources/HRSenseComputeCxx/include/module.modulemap`**：
```
module HRSenseComputeCxx {
    header "hrs_compute.h"
    export *
}
```

**`Sources/HRSenseComputeCxx/Placeholder.cpp`**：实现 `hrs_compute_init()`（返回 0）和 `hrs_compute_deinit()`（空操作）。

**`Sources/HRSenseCompute/Placeholder.swift`**：`import HRSenseComputeCxx` 并包装为 Swift `ComputeBridge`。

### 3d. 测试 Target 占位文件（5 个）

每个一个 `XCTestCase` 子类，含 `test_placeholder()` 断言 `XCTAssertTrue(true)`。

### 3e. 预留目录

- `Models/` — CoreML 模型（M8 填充）
- `Scenarios/` — 场景脚本 + 数据集（M2 填充）
- `proto/` — Protobuf schema（可选，M8）
- `tools/` — 转换脚本（M8 填充）

---

## 阶段 4：验证

```bash
swift build       # 7 个 library target 全部通过
swift test        # 5 个 test target 全部通过
grep -n "草案\|待定" docs/03-ble-gatt-protocol.md  # 零匹配
git lfs track     # 验证 LFS 模式
```

---

## 文件创建顺序

```
Phase 1: docs/03-ble-gatt-protocol.md          [EDIT]
Phase 2: .gitattributes, .gitignore, ci.yml, THIRD_PARTY_LICENSES.md  [CREATE]
Phase 3: Models/, Scenarios/, proto/, tools/   [CREATE dirs + .gitkeep]
Phase 3b: Package.swift                        [CREATE]
Phase 3c: 7 library placeholder files          [CREATE]
Phase 3d: C/C++ header + modulemap + cpp       [CREATE]
Phase 3e: 5 test placeholder files             [CREATE]
Phase 4: swift build && swift test             [VERIFY]
```

## 预估工作量

| 阶段 | 工作 | 预计时间 |
|---|---|---|
| 阶段 1 | 编辑 `03`（13 处精确修改） | 20 min |
| 阶段 2 | 基础设施文件（.gitattributes、CI、licenses、.gitignore） | 15 min |
| 阶段 3 | `Package.swift` + 16 个占位文件 + 4 个预留目录 | 30 min |
| 阶段 4 | Build、test、修复问题、commit | 15 min |
| **合计** | | **~80 min** |

## 风险

| 风险 | 缓解措施 |
|---|---|
| TGReduxKit 不可用 | 临时从 M0 中移除 `HRSenseFeature` target，待依赖就绪后恢复 |
| SwiftPM C++ target 编译失败 | 尝试不用 `publicHeadersPath`，用 `cxxSettings` 让 SwiftPM 自动生成模块映射 |
| CI macOS-15 不可用 | 回退到 `macos-14` 或 `macos-latest` |
