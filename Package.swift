// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WalkieTalkie",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "WalkieTalkie"),
    ]
)
