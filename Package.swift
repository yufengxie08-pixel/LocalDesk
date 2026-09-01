// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalDesk",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LocalDeskCore", targets: ["LocalDeskCore"]),
        .executable(name: "LocalDesk", targets: ["LocalDesk"])
    ],
    targets: [
        .target(name: "LocalDeskCore"),
        .executableTarget(name: "LocalDesk", dependencies: ["LocalDeskCore"]),
        .testTarget(name: "LocalDeskCoreTests", dependencies: ["LocalDeskCore"])
    ]
)
