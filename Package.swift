// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AppCameraSimple",
    platforms: [.macOS(.v15)],
    targets: [
        // Pure, framework-light logic that can be unit-tested without AppKit.
        .target(name: "AppCameraSimpleCore"),
        .executableTarget(
            name: "AppCameraSimple",
            dependencies: ["AppCameraSimpleCore"]
        ),
        .testTarget(
            name: "AppCameraSimpleTests",
            dependencies: ["AppCameraSimpleCore"]
        ),
    ]
)
