// swift-tools-version:6.3.2
import PackageDescription

let package = Package(
    name: "miyoi",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MiyoiKit", targets: ["MiyoiKit"]),
        .executable(name: "miyoi", targets: ["miyoi"]),
        .executable(name: "miyoictl", targets: ["miyoictl"]),
        .executable(name: "miyoi-selftest", targets: ["miyoi-selftest"]),
    ],
    targets: [
        .target(name: "MiyoiKit", path: "MiyoiKit/Sources/MiyoiKit"),
        .testTarget(name: "MiyoiKitTests", dependencies: ["MiyoiKit"], path: "MiyoiKit/Tests/MiyoiKitTests"),
        .executableTarget(
            name: "miyoi",
            dependencies: ["MiyoiKit"],
            path: "miyoi/Sources/miyoi",
            resources: [.process("Resources")]
        ),
        .executableTarget(name: "miyoictl", dependencies: ["MiyoiKit"], path: "miyoictl/Sources/miyoictl"),
        .executableTarget(name: "miyoi-selftest", dependencies: ["MiyoiKit"], path: "SelfTests"),
    ]
)
