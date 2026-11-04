import AppKit

/// **A background app's `NSCursor.set()` is ignored unless the process asks for
/// it** — the window server keeps the frontmost app's cursor. This app is never
/// active, so every cursor it sets depends on this.
///
/// Once, at launch (2026-11-04). It was asked for when the first reply pop-up
/// opened, so until one had, the spawn menu's cursor did nothing at all. The same
/// private property every pointer utility sets.
enum BackgroundCursor {
    static let allow: Void = {
        let cid = _CGSDefaultConnection()
        _ = CGSSetConnectionProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }()
}

@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> Int32
@_silgen_name("CGSSetConnectionProperty")
private func CGSSetConnectionProperty(_ cid: Int32, _ target: Int32, _ key: CFString, _ value: CFTypeRef) -> Int32
