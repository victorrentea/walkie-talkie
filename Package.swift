// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WalkieTalkie",
    platforms: [.macOS(.v13)],
    dependencies: [
        // The region selector, shared with Victor Addons. A path dependency on
        // purpose: both apps are built on this Mac, from local, and the point of
        // sharing the crop was to be able to edit it and rebuild in one step —
        // no push, no version bump, no resolve. A fresh clone needs
        // `victor-mac-kit` checked out beside this folder.
        .package(path: "../victor-mac-kit"),
    ],
    targets: [
        .executableTarget(
            name: "WalkieTalkie",
            dependencies: [.product(name: "VictorMacKit", package: "victor-mac-kit")]
        ),
    ]
)
