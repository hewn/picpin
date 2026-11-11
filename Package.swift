// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PicPin",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "PicPin", path: "Sources/PicPin"),
        .testTarget(name: "PicPinTests", dependencies: ["PicPin"], path: "Tests/PicPinTests"),
    ]
)
