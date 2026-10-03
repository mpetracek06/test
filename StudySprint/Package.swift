// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StudySprint",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic: API client, streaming, parsing, scheduling. No UI, fully unit-tested.
        .target(
            name: "StudySprintCore",
            path: "Sources/StudySprintCore"
        ),
        // The SwiftUI app.
        .executableTarget(
            name: "StudySprint",
            dependencies: ["StudySprintCore"],
            path: "Sources/StudySprint"
        ),
        // End-to-end check of free mode against a real Ollama + YouTube (run in CI).
        .executableTarget(
            name: "free-mode-smoke",
            dependencies: ["StudySprintCore"],
            path: "Sources/FreeModeSmoke"
        ),
        .testTarget(
            name: "StudySprintCoreTests",
            dependencies: ["StudySprintCore"],
            path: "Tests/StudySprintCoreTests"
        ),
    ]
)
