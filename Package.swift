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
        .executable(name: "HRSenseSimulator", targets: ["HRSenseSimulator"]),
        .executable(name: "HRSenseApp",       targets: ["HRSenseApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tangzzz-fan/TGReduxKit.git", from: "2.0.0"),
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
        .executableTarget(name: "HRSenseSimulator",
                dependencies: ["HRSenseSimulatorKit"]),
        .executableTarget(name: "HRSenseApp",
                dependencies: ["HRSenseFeature", "HRSenseData", "HRSenseCore", "HRSenseProtocol"]),
        .testTarget(name: "HRSenseProtocolTests", dependencies: ["HRSenseProtocol"]),
        .testTarget(name: "HRSenseComputeTests", dependencies: ["HRSenseCompute", "HRSenseComputeCxx"]),
        .testTarget(name: "HRSenseDataTests", dependencies: ["HRSenseData", "HRSenseComputeCxx"]),
        .testTarget(name: "HRSenseFeatureTests", dependencies: ["HRSenseFeature", "HRSenseComputeCxx"]),
        .testTarget(name: "HRSenseSimulatorKitTests", dependencies: ["HRSenseSimulatorKit", "HRSenseComputeCxx"]),
    ]
)
