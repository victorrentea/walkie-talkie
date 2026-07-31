// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WisprRelay",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "WisprRelay"),
    ]
)
