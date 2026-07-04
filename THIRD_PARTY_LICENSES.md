# Third-Party Licenses

## Runtime Dependencies

| Package | License | Usage |
|---|---|---|
| TGReduxKit | MIT | Redux store for iOS app (HRSenseFeature) |
| swift-protobuf | Apache-2.0 | Optional protocol payload runtime for generated protobuf schemas |

## Apple SDKs

| Framework | License |
|---|---|
| CoreML | Apple SDK (BSD-3-Clause) |
| coremltools (tools/) | BSD-3-Clause |

## Model & Dataset Resources

| Resource | License | Notes |
|---|---|---|
| StressClassifier_v1 (placeholder) | Proprietary / self-trained | Placeholder model, no third-party data |
| PhysioNet reference RR intervals (test vectors) | ODC-BY 1.0 | Used only in unit test gold-value fixtures |

## Protocol Buffer (proto/)

Google Protocol Buffers (proto3) — the `.proto` schema files are project-authored.
Current iOS runtime dependency is `swift-protobuf` (Apache-2.0). Firmware-side
runtime such as `nanopb` is not introduced in this repository yet.
