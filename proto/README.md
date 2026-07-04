# HRSense Protobuf Schemas

## Purpose

This directory contains protocol-level `.proto` schemas shared across platforms.

These schemas are part of the BLE protocol contract, not UI DTOs and not local
storage models.

## Current Scope

- Phase 1 rollout only covers low-risk structured response payloads.
- High-throughput waveform blocks remain on the existing compact binary path.
- OTA image chunks remain on the existing custom binary path.

## Directory Layout

```text
proto/
├── hrsense/
│   ├── common/
│   │   └── v1/
│   │       └── device_info.proto
│   └── session/
│       └── v1/
│           └── hello.proto
```

## Generation

Run:

```bash
./tools/generate_proto.sh
```

The generated Swift files are written into:

```text
Sources/HRSenseProtocol/Generated
```

## Governance Rules

- Update `docs/03-ble-gatt-protocol.md` before changing any protocol schema.
- Never reuse removed field numbers.
- Add new fields in a backward-compatible way.
- Treat this directory as shared protocol contract asset.
