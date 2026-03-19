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
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MementoCapture",
            dependencies: [],
            path: "Sources"
        )
    ]
)
