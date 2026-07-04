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
        .library(name: "HRSenseSimulatorUI",  targets: ["HRSenseSimulatorUI"]),
        .library(name: "HRSenseAppUI",        targets: ["HRSenseAppUI"]),
        .executable(name: "HRSenseSimulator", targets: ["HRSenseSimulator"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tangzzz-fan/TGReduxKit.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.38.1"),
    ],
    targets: [
        .target(
            name: "HRSenseProtocol",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        .target(name: "HRSenseCore"),
        .target(name: "HRSenseComputeCxx",
                publicHeadersPath: "include",
                cxxSettings: [.headerSearchPath("include")]),
        .target(name: "HRSenseCompute",
                dependencies: ["HRSenseCore", "HRSenseComputeCxx"]),
        .target(name: "HRSenseData",
                dependencies: ["HRSenseProtocol", "HRSenseCore", "HRSenseCompute"]),
        .target(name: "HRSenseFeature",
                dependencies: [
                    "HRSenseCore",
                    "HRSenseProtocol",
                    .product(name: "TGReduxKit", package: "TGReduxKit"),
                ]),
        .target(name: "HRSenseSimulatorKit",
                dependencies: ["HRSenseProtocol"]),
        .target(name: "HRSenseSimulatorUI",
                dependencies: ["HRSenseSimulatorKit", "HRSenseProtocol"]),
        .target(name: "HRSenseAppUI",
                dependencies: [
                    "HRSenseFeature",
                    "HRSenseData",
                    .product(name: "TGReduxKit", package: "TGReduxKit"),
                ]),
        .executableTarget(name: "HRSenseSimulator",
                dependencies: ["HRSenseSimulatorKit"]),
        .testTarget(name: "HRSenseProtocolTests", dependencies: ["HRSenseProtocol"]),
        .testTarget(name: "HRSenseComputeTests", dependencies: ["HRSenseCompute", "HRSenseComputeCxx"]),
        .testTarget(name: "HRSenseDataTests", dependencies: ["HRSenseData", "HRSenseComputeCxx"]),
        .testTarget(name: "HRSenseFeatureTests", dependencies: ["HRSenseFeature", "HRSenseComputeCxx"]),
        .testTarget(name: "HRSenseSimulatorKitTests", dependencies: ["HRSenseSimulatorKit", "HRSenseComputeCxx"]),
    ]
)
