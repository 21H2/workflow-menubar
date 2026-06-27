// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WorkflowsMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "WorkflowsMenuBar",
            path: "Sources/WorkflowsMenuBar"
        )
    ]
)
