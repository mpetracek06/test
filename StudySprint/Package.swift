// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StudySprint",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "StudySprint",
            path: "Sources/StudySprint"
        )
    ]
)
