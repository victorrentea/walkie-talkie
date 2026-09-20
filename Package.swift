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
        // **projectM 4.1.7, statically linked** (the `projectm` branch, 2026-09-21):
        // the engine behind the native MilkDrop halo (`ProjectMHalo`). The
        // library is prebuilt into `vendor/projectm/lib` from the upstream
        // tarball plus `vendor/projectm/target-fbo.patch` (see
        // `vendor/projectm/README.md` for the exact build); its C headers are
        // under `include/projectM-4`, and `pmhalo.cpp` is our GL glue.
        .target(
            name: "CProjectM",
            path: "Sources/CProjectM",
            cxxSettings: [.define("PROJECTM_STATIC_DEFINE")],
            linkerSettings: [
                .unsafeFlags(["-L", "\(Context.packageDirectory)/vendor/projectm/lib"]),
                .linkedLibrary("projectM-4"),
                .linkedLibrary("projectM_eval"),
                .linkedLibrary("c++"),
                .linkedFramework("OpenGL"),
                .linkedFramework("IOSurface"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .executableTarget(
            name: "WalkieTalkie",
            dependencies: [.product(name: "VictorMacKit", package: "victor-mac-kit"), "CProjectM"]
        ),
    ]
)
