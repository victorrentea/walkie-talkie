// swift-tools-version: 5.9
import Foundation
import PackageDescription

// The region selector, shared with Victor Mac. On Victor's Mac both apps are
// built from local with `victor-mac-kit` checked out beside them, and the point
// of sharing the crop was to edit it and rebuild in one step — no push, no
// version bump, no resolve. Anyone else's fresh clone has no such sibling
// (issue #2, 2026-10-16): it gets the kit from GitHub instead.
let macKitBeside = "\(Context.packageDirectory)/../victor-mac-kit"
let macKit: Package.Dependency = FileManager.default.fileExists(atPath: "\(macKitBeside)/Package.swift")
    ? .package(path: "../victor-mac-kit")
    : .package(url: "https://github.com/victorrentea/victor-mac-kit.git", branch: "master")

let package = Package(
    name: "WalkieTalkie",
    platforms: [.macOS(.v13)],
    dependencies: [
        macKit,
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
        // `@try` for the Objective-C exceptions `AVAudioEngine` raises at runtime
        // (2026-09-30): Swift cannot catch one, and one uncaught kills the relay
        // mid-sentence. `WTTry { … }` answers it as an `NSError`.
        .target(
            name: "ObjCTry",
            path: "Sources/ObjCTry"
        ),
        .executableTarget(
            name: "WalkieTalkie",
            dependencies: [.product(name: "VictorMacKit", package: "victor-mac-kit"), "CProjectM", "ObjCTry"]
        ),
        // `swift test` — the pure parts only (2026-09-23: the transcription
        // estimate and the rewind's timeline). Everything that needs the running
        // relay is still a `/test/…` route.
        .testTarget(
            name: "WalkieTalkieTests",
            dependencies: ["WalkieTalkie", "ObjCTry"]
        ),
    ]
)
