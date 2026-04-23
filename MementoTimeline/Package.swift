// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MementoTimeline",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TimelineFeature", targets: ["TimelineFeature"]),
        .executable(name: "MementoTimeline", targets: ["MementoTimeline"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "TimelineFeature",
            path: "Sources",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "MementoTimeline",
            dependencies: ["TimelineFeature"],
            path: "App"
        ),
        .testTarget(
            name: "TimelineFeatureTests",
            dependencies: ["TimelineFeature"],
            path: "Tests/TimelineFeatureTests"
        )
    ]
)
