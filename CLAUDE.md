# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Current Phase

**Implementation phase.** The repo now contains a real SwiftPM codebase, two App shells under `Apps/`, and a root `HRSense.xcworkspace`. Design docs are still the source of truth for architecture and protocol contracts, but build/test validation must use the live codebase and the workspace-backed app shells.

## Commands

Use these commands as the default validation entry points:

```bash
swift build          # Root Package.swift with multiple targets
swift test           # Run all unit tests
swift test --filter HRSenseProtocolTests  # Run a single test target
xcodebuild -workspace HRSense.xcworkspace -scheme HRSenseApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
xcodebuild -workspace HRSense.xcworkspace -scheme HRSenseSimulator \
  -destination 'platform=macOS' build
```

Workspace rule:
- **Always open `HRSense.xcworkspace` in Xcode.**
- Do **not** keep `Apps/HRSenseApp/HRSenseApp.xcodeproj` and `Apps/HRSenseSimulator/HRSenseSimulator.xcodeproj` open as separate Xcode windows at the same time, because both reference the same local package path (`../..`) and Xcode may surface false "Missing package product" errors.

Execution-quality notes for when code exists:
- Treat **both** `HRSenseApp` and `HRSenseSimulator` as first-class executables. Do not validate only the iOS app shell while ignoring simulator build health.
- Milestone acceptance is not satisfied by compile success alone; use `docs/11-delivery-plan.md` as the executable gate and run the milestone-specific checks that apply (unit tests, headless simulator scenarios, real-device + simulator E2E where required).
- The simulator is a permanent CI/regression asset, so any change that affects BLE contract, scenarios, headless mode, or fault injection should be validated against the simulator path as well as the app path.

## Architecture (Fundamental Concepts)

This is a **BLE heart-rate iOS app** with two key properties that drive every design choice:

1. **No physical hardware exists yet** — a macOS app (`HRSenseSimulator`) acts as the BLE Peripheral so all development, testing, and CI can happen without hardware. See `docs/05-simulator-macos.md`.
2. **A custom protocol stack runs over BLE GATT** — not the standard Bluetooth Heart Rate Service (`0x180D`). See `docs/03-ble-gatt-protocol.md`.

### Critical Symmetry: Shared Protocol Package

**`HRSenseProtocol` is the single most important module.** It implements layers L2–L4 (framing/reliability, session/commands, application data) of the custom protocol. Both the iOS app and the macOS simulator depend on this exact same package — one side encodes, the other decodes, but the code is identical. This prevents protocol drift between the two ends. See `docs/03-ble-gatt-protocol.md` §9.

The protocol stack layering (L0–L4) and the GATT Profile with 128-bit custom UUIDs using a Nordic-style Short ID scheme are defined in `docs/03-ble-gatt-protocol.md`. That doc **is the contract** — any protocol change must be reflected there first, then in the shared package, then in both ends.

### App Architecture: Clean + Redux

The iOS app uses Clean Architecture (Domain/Data/Presentation layers) with a self-built lightweight Redux store based on **TGReduxKit** (MIT, iOS 17+, Swift Observation). See `docs/04-app-clean-redux.md`.

Key architectural rules:
- **Dependency direction**: `HRSenseFeature` must never directly import `HRSenseData`. The two layers communicate through `HRSenseCore`'s repository protocols (dependency inversion). The app shell (composition root) wires implementations at startup.
- **Reducer is pure**: `(State, Action) -> State`. All I/O (BLE, computation, CoreML) happens in Middleware/Effects.
- **Store reduce is serial** on MainActor (state feeds SwiftUI). BLE callbacks and protocol decoding happen on background queues; actions are dispatched via `await MainActor`.
- **One Middleware per concern**: `ConnectionMiddleware` / `BLEStreamMiddleware` / `ComputeMiddleware` / `InferenceMiddleware` / `OTAMiddleware`. Middleware orchestrates threading, lifecycle, and throttling; UseCases encapsulate single business rules (pure, testable); Middleware calls UseCases which go through repository interfaces.
- **Sample windows are bounded**: HR ring buffer ~10 min (~600 points @ 1 Hz), RR ~5 min (HRV short-term window standard). UI refresh ≤2 Hz; trend lines downsampled to ~120 points. Raw data still feeds compute/inference pipelines at full rate.

### Shared Protocol + C++ Compute + CoreML Pipeline

Data flows: `BLE raw bytes → HRSenseProtocol decode → Redux Store → (when window fills) C++ feature extraction → CoreML inference → dispatch result back to Store`. See `docs/06-coreml-and-compute.md`.

- C++ integration uses **C ABI**: C++ internally, but exposes pure `extern "C"` functions. Swift calls through a module map. See `docs/specs/0001-cpp-compute-integration.spec.md`.
- CoreML uses a **placeholder-model-first** strategy: wire up the full pipeline with a trivial model, then swap in real models later. See `docs/specs/0002-coreml-inference-pipeline.spec.md`.

### Simulator as a Development/CI Asset

The macOS simulator is not a throwaway stub — it's designed as a **persistent tool** that remains useful even after real hardware arrives (CI, regression, offline development). It includes: a scenario engine, configurable data generators, a fault injector (packet loss/delay/reorder/disconnect/CRC errors), and headless mode for CI. See `docs/05-simulator-macos.md`.

### Project Structure: SwiftPM-First

All reusable logic lives in SPM targets under a single root `Package.swift`. The two executable apps (iOS app, macOS simulator) are thin Xcode project shells that only handle entry points, permissions (`Info.plist`), and composition root wiring. Open them through the root `HRSense.xcworkspace`, not as isolated projects. See `docs/08-project-structure.md`.

### Persistence Strategy: Replaceable Storage Boundary

Structured persistence currently targets **SwiftData**, while waveform/raw large blobs live in files. This is an implementation choice, **not** an architectural dependency. See `docs/specs/0004-local-storage.spec.md`.

Rules:
- `HRSenseCore` owns the `PersistenceStore` abstraction and domain entities; upper layers must not depend on `SwiftData` types such as `@Model`, `ModelContext`, or framework-specific query DSL.
- `HRSenseData` may implement `SwiftDataStore` now, but the boundary must remain compatible with a future `GRDBStore` / SQLite migration if real-world data volume, query complexity, or aggregation requirements demand it.
- `WaveformFileStore` and waveform binary formats must remain decoupled from the structured database choice so that replacing `SwiftData` does not force waveform-format redesign.

### Key Frozen Design Decisions (v1)

These are considered decided; do not reopen without a strong reason:
- 128-bit custom GATT UUIDs (Nordic-style, Short ID-based). See `docs/03-ble-gatt-protocol.md` §3.1.
- CRC-16/CCITT-FALSE for frame integrity. See `docs/03-ble-gatt-protocol.md` §4.2.1.
- All multi-byte fields: **little-endian**.
- Data channel reliability: **best-effort** (notify + `sampleSeq`/`blockSeq` for loss detection, no per-sample ACK).
- Timestamps: device-relative `u32` milliseconds from `START_STREAM` acceptance (not absolute/RTC).
- App minimum deployment: **iOS 17**, **macOS 14**.
- Architecture: **Clean + self-built Redux (TGReduxKit)**, not TCA.

## Development Practices

### Contract-First Workflow

The protocol document (`docs/03-ble-gatt-protocol.md`) is the single source of truth for any interaction between the iOS app and the device/simulator. When you need to change how the two ends communicate:

1. Update `docs/03-ble-gatt-protocol.md` first (the contract).
2. Update `HRSenseProtocol` package (the shared implementation of L2–L4).
3. Update the iOS app and/or simulator to match.
4. Add or update golden-value tests for any new or changed byte formats.

The doc explicitly states: "本文档是 App 与设备/模拟器之间的**契约**。任何改动应先改此文档与 `HRSenseProtocol` 包，再改两端实现。"

### Protobuf Boundary (Optional, L4 Only)

The project default remains the custom TLV-based payload design in `docs/03-ble-gatt-protocol.md`. If Protobuf is introduced later, it belongs **only** to the **L4 application payload encoding** boundary — not to GATT, not to L2 framing/reliability, not to UI, and not to persistence. See `docs/03-ble-gatt-protocol.md` §6.4 and `docs/08-project-structure.md`.

Rules:
- Keep BLE GATT transport and L2 framing/CRC/seq behavior unchanged; Protobuf only replaces the L4 payload representation.
- Store shared `.proto` schemas under the repo-root `proto/` directory.
- Treat `.proto` as a cross-platform schema contract shared by **iOS / Android / firmware**, with each platform generating and consuming its own language bindings.
- `HRSenseProtocol` remains the entry point for protocol-layer encode/decode orchestration even if the L4 payload switches from TLV to Protobuf.

### Definition of Done (per `docs/11-delivery-plan.md` §0)

Every milestone is gated on all five conditions:

1. **Builds and tests pass**: `swift build` / `xcodebuild` passes, all related unit tests green.
2. **Acceptance criteria met**: each milestone's specific checklist in `docs/11-delivery-plan.md` is fully satisfied.
3. **Observability in place**: key paths have logging/metrics per `docs/10-observability.md`.
4. **Protocol doc synced**: any protocol-affecting change is reflected in `docs/03-ble-gatt-protocol.md` and the `HRSenseProtocol` package.
5. **Documentation updated**: relevant spec files and doc sections are updated.

### Testing Strategy by Layer

Each architectural layer has a prescribed testing approach — do not test a layer through a mechanism designed for a different layer:

| Layer | How to test |
|---|---|
| `HRSenseProtocol` | Pure unit tests: feed bytes in, assert decoded models out; encode models, assert bytes out. Golden-value tests (`CRC16("123456789")==0x29B1`). Round-trip property: `decode(encode(x)) == x`. Target ≥80% code coverage. |
| Reducer | Pure function tests: given `(State, Action)`, assert output `State`. |
| UseCase | Unit tests with fake Repository implementations (no real BLE/CoreML). |
| Middleware | Unit tests with fake Repository + assert the sequence of dispatched Actions. |
| End-to-end | Connect real iOS device to macOS simulator; use scenario scripts and fault injection for error paths. |

### Where Fault Injection Belongs

**The app does not have its own runtime fault injection.** Fault injection lives exclusively in the macOS simulator (`docs/05-simulator-macos.md` §5 and §10):

- Link/device errors (packet loss, CRC errors, disconnects, command timeouts, etc.): covered by **simulator fault injection**.
- App internal errors (decode failures, compute/inference failures, buffer boundaries): covered by **protocol unit tests** (feed malformed bytes directly to `FrameAssembler.feed`) and **fake Repository/DataSource** implementations.
- iOS system errors (Bluetooth unauthorized/powered off, background state): covered by **manual system toggles** and unit tests with fake BLE state.

See the error coverage matrix in `docs/05-simulator-macos.md` §10.2 for the full breakdown of which errors are covered by which mechanism.

### Error Handling Model

All errors flow through a single canonical `AppError` enum (defined in `docs/04-app-clean-redux.md` §8.5). Never introduce ad-hoc error types outside this enum. Errors enter `AppState.error` and drive UI presentation. Connection-class errors (`connectionTimeout`, `connectionLost`, `bluetoothPoweredOff`, etc.) also feed the reconnection state machine (§5) — do not handle reconnection manually outside that state machine.

### Spec Lifecycle

Specifications follow a defined lifecycle: `draft → review → accepted → implemented`. Write new specs using the template at `docs/specs/spec-template.md` (background → goals/non-goals → design → alternatives → impact → test strategy → risks → milestones). Most current specs are `draft (决策已固化)` — decisions frozen, waiting for implementation.

Frozen decisions use `[x]` checkboxes; open questions use `[ ]`. Protocol-level open questions (UUIDs, CRC, endianness, timestamps, reliability) were closed inline in `docs/03-ble-gatt-protocol.md` §8 rather than as separate specs.

### Naming and Module Boundaries

- Swift module prefix: `HRSense*` (e.g. `HRSenseProtocol`, `HRSenseCore`, `HRSenseData`).
- C interface prefix: `hrs_` (e.g. `hrs_compute_hrv`, `hrs_extract_features`).
- Dependencies only flow inward: `Core` and `Protocol` must never import upper layers.
- Cross-layer communication goes through **protocols** (interfaces), never concrete types. Wire implementations in the app shell composition root.

### Hard Implementation Ordering

The milestones have a strict dependency chain that must be respected:

1. M0 (infrastructure + contract freeze) → M1 (protocol library with unit tests)
2. M1 → M2 (simulator MVP) ∥ M3 (app BLE integration)
3. M3 → M4 (Redux presentation layer)
4. M4 → everything else (waveform, OTA, observability, compute/CoreML, storage, background BLE)

The protocol library (`HRSenseProtocol`) must exist before either the app or the simulator can be built, because both depend on it. Do not start app or simulator code before the protocol package compiles with passing unit tests.

## Document Map

| What you need | Where to look |
|---|---|
| Project overview, scope, glossary, ADR summary | `docs/00-overview.md` |
| Milestone roadmap (parallel tracks, dependencies) | `docs/01-roadmap.md` |
| Executable delivery plan with acceptance criteria | `docs/11-delivery-plan.md` |
| System architecture, components, data flow | `docs/02-architecture.md` |
| Custom protocol stack (GATT Profile, framing, commands, TLV, UUIDs) | `docs/03-ble-gatt-protocol.md` |
| App Clean Architecture + Redux design | `docs/04-app-clean-redux.md` |
| macOS simulator design (Peripheral, generators, fault injection) | `docs/05-simulator-macos.md` |
| CoreML + C++ compute integration | `docs/06-coreml-and-compute.md` |
| OTA/DFU firmware upgrade design | `docs/07-ota-dfu.md` |
| Project structure (SPM targets, file layout) | `docs/08-project-structure.md` |
| JD coverage gap analysis | `docs/09-jd-coverage-analysis.md` |
| Observability (logging, crash, metrics) | `docs/10-observability.md` |
| Specs index (detailed implementation specs) | `docs/specs/README.md` |

## Working Conventions

- **All design docs are in `docs/`; detailed implementation specs in `docs/specs/`.** If a design question is disputed, check `docs/03-ble-gatt-protocol.md` — it's the source of truth for anything protocol-related.
- **No code lives directly in the repo root** beyond `Package.swift`. All source code will be under `Sources/<TargetName>/` with corresponding tests under `Tests/`.
- **JD alignment**: This project is designed to demonstrate skills matching the AxiLab senior iOS engineer JD (see `JD.md`). The gap analysis in `docs/09-jd-coverage-analysis.md` tracks coverage of every JD requirement.
- **Third-party license tracking**: Any external model weights, datasets, or dependencies must be registered in `THIRD_PARTY_LICENSES.md`. CoreML runtime and `coremltools` are BSD-3-Clause/Apple SDK and introduce no copyleft obligations, but model/dataset sources must be individually checked. Start with self-trained placeholder models to avoid licensing risk.
