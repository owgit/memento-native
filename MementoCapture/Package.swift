// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MementoCapture",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "memento-capture", targets: ["MementoCapture"])
    ],
    dependencies: [
        .package(path: "../MementoTimeline")
    ],
    targets: [
        .executableTarget(
            name: "MementoCapture",
            dependencies: [
                .product(name: "TimelineFeature", package: "MementoTimeline")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "MementoCaptureTests",
            dependencies: ["MementoCapture"],
            path: "Tests"
        )
    ]
)
