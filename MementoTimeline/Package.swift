// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MementoTimeline",
    platforms: [
        .macOS(.v14)
    ],
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

