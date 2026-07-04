#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/Sources/HRSenseProtocol/Generated"

mkdir -p "$OUTPUT_DIR"

# This script generates Swift sources via the `protoc-gen-swift` plugin.
# The generated `.pb.swift` files import the `SwiftProtobuf` runtime module,
# which is linked by SwiftPM from the package dependency declared in
# `Package.swift`.
protoc \
  --proto_path="$ROOT_DIR/proto" \
  --swift_out="$OUTPUT_DIR" \
  --swift_opt=Visibility=Public \
  "$ROOT_DIR/proto/hrsense/common/v1/device_info.proto" \
  "$ROOT_DIR/proto/hrsense/session/v1/hello.proto"

echo "Generated Swift Protobuf sources in $OUTPUT_DIR"
