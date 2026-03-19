// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MementoTimeline",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MementoTimeline", targets: ["MementoTimeline"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MementoTimeline",
            path: "Sources",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
    ]
)
