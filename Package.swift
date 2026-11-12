// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Xueji",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "XuejiCore", targets: ["XuejiCore"]),
        .executable(name: "Xueji", targets: ["XuejiApp"]),
    ],
    targets: [
        .target(name: "XuejiCore"),
        .executableTarget(
            name: "XuejiApp",
            dependencies: ["XuejiCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "XuejiCoreTests", dependencies: ["XuejiCore"]),
    ]
)
