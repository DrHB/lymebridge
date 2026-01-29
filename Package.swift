// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "lymebridge",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "lymebridge",
            path: "Sources/lymebridge"
        )
    ]
)
