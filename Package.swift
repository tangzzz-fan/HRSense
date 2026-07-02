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
        .library(name: "HRSenseSimulatorKit", targets: ["HRSenseSimulatorKit"]),
        // HRSenseFeature — deferred to M4 (TGReduxKit uses iOS-only fullScreenCover,
        // incompatible with macOS builds; will resolve in M4 when Redux layer is implemented).
    ],
    dependencies: [
        // TGReduxKit integration deferred to M4.
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
        // HRSenseFeature target deferred to M4 (see above).
        .target(name: "HRSenseSimulatorKit",
                dependencies: ["HRSenseProtocol"]),
        .testTarget(name: "HRSenseProtocolTests", dependencies: ["HRSenseProtocol"]),
        .testTarget(name: "HRSenseComputeTests", dependencies: ["HRSenseCompute"]),
        .testTarget(name: "HRSenseDataTests", dependencies: ["HRSenseData"]),
        // HRSenseFeatureTests deferred to M4.
        .testTarget(name: "HRSenseSimulatorKitTests", dependencies: ["HRSenseSimulatorKit"]),
    ]
)
