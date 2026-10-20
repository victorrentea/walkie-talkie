import Foundation

/// **How many fingers are on the trackpad, and where** — Apple's private
/// MultitouchSupport, opened with `dlopen` (2026-10-20).
///
/// The one way to see a **three-finger** swipe: the event stream has no such
/// thing. Two fingers arrive as a scroll, but three are the Dock's (Mission
/// Control / spaces on his Mac) and no app hears them. The frame callback runs
/// on MultitouchSupport's own thread for every frame of every built-in or
/// Magic trackpad, with the touches' normalised positions (0…1, y up).
/// Read-only: nothing here can move the pointer or block a gesture — that is
/// `HotkeyTap`'s, for the length of its chord.
enum Multitouch {

    struct Point { var x: Float; var y: Float }
    struct Readout { var position: Point; var velocity: Point }
    /// MultitouchSupport's `Finger`, field for field (96 bytes —
    /// `MultitouchTests` holds the stride to it).
    struct Finger {
        var frame: Int32
        var timestamp: Double
        var identifier: Int32
        var state: Int32
        var fingerId: Int32
        var handId: Int32
        var normalized: Readout
        var size: Float
        var zero1: Int32
        var angle: Float
        var majorAxis: Float
        var minorAxis: Float
        var millimeters: Readout
        var zero2: Int32
        var zero3: Int32
        var density: Float
    }

    typealias FrameCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias CreateList = @convention(c) () -> Unmanaged<CFMutableArray>?
    private typealias Register = @convention(c) (UnsafeRawPointer?, FrameCallback) -> Void
    private typealias Start = @convention(c) (UnsafeRawPointer?, Int32) -> Void

    /// Fingers down and their centroid, per frame, on MultitouchSupport's
    /// thread. Set once, before `start`.
    nonisolated(unsafe) static var onFrame: ((Int, Float, Float) -> Void)?

    private static let callback: FrameCallback = { _, data, count, _, _ in
        let n = Int(max(0, count))
        var x: Float = 0, y: Float = 0
        if n > 0, let data {
            let fingers = data.bindMemory(to: Finger.self, capacity: n)
            for i in 0..<n {
                x += fingers[i].normalized.position.x
                y += fingers[i].normalized.position.y
            }
            x /= Float(n)
            y /= Float(n)
        }
        Multitouch.onFrame?(n, x, y)
        return 0
    }

    /// Starts every trackpad's frame callback; answers how many devices.
    /// Zero when the framework will not open — the three-finger swipe is then
    /// simply not there, and nothing else changes.
    @discardableResult
    static func start() -> Int {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let lib = dlopen(path, RTLD_NOW),
              let c = dlsym(lib, "MTDeviceCreateList"),
              let r = dlsym(lib, "MTRegisterContactFrameCallback"),
              let s = dlsym(lib, "MTDeviceStart") else { return 0 }
        let createList = unsafeBitCast(c, to: CreateList.self)
        let register = unsafeBitCast(r, to: Register.self)
        let startDevice = unsafeBitCast(s, to: Start.self)
        guard let list = createList()?.takeUnretainedValue() else { return 0 }
        let count = CFArrayGetCount(list)
        for i in 0..<count {
            let device = CFArrayGetValueAtIndex(list, i)
            register(device, callback)
            startDevice(device, 0)
        }
        return count
    }
}
