// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OrangeRobotKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OrangeRobotKit", targets: ["OrangeRobotKit"]),
    ],
    targets: [
        .target(
            name: "OrangeRobotKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "OrangeRobotKitTests",
            dependencies: ["OrangeRobotKit"],
            resources: [.copy("golden.json")]
        ),
    ]
)
