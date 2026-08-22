import AppKit
import ApplicationServices

// Screen-reader-style text dump of a window's Accessibility tree.
// usage: axdump [front|<app name substring>] [--tree] [--budget N]

let args = Array(CommandLine.arguments.dropFirst())
let target = args.first(where: { !$0.hasPrefix("--") }) ?? "front"
let showTree = args.contains("--tree")

func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
    return v
}
func str(_ el: AXUIElement, _ name: String) -> String? {
    guard let v = attr(el, name) else { return nil }
    if let s = v as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
    return nil
}
func children(_ el: AXUIElement) -> [AXUIElement] {
    guard let v = attr(el, kAXChildrenAttribute as String) else { return [] }
    guard CFGetTypeID(v) == CFArrayGetTypeID() else { return [] }
    let arr = unsafeBitCast(v, to: CFArray.self)
    let n = CFArrayGetCount(arr)
    var out: [AXUIElement] = []
    for i in 0..<n {
        let raw = CFArrayGetValueAtIndex(arr, i)
        guard let raw else { continue }
        let child = unsafeBitCast(raw, to: AXUIElement.self)
        if CFGetTypeID(child) == AXUIElementGetTypeID() { out.append(child) }
    }
    return out
}

let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
let app: NSRunningApplication? = target == "front"
    ? NSWorkspace.shared.frontmostApplication
    : apps.first { ($0.localizedName ?? "").lowercased().contains(target.lowercased()) }

guard let app else {
    FileHandle.standardError.write("no app matching \(target). running: \(apps.compactMap{$0.localizedName}.joined(separator: ", "))\n".data(using: .utf8)!)
    exit(1)
}

let axApp = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(axApp, 5.0)

func focusedWindow() -> AXUIElement? {
    if let w = attr(axApp, kAXFocusedWindowAttribute as String), CFGetTypeID(w) == AXUIElementGetTypeID() {
        return unsafeBitCast(w, to: AXUIElement.self)
    }
    let ws = children(axApp).filter { (str($0, kAXRoleAttribute as String) ?? "") == "AXWindow" }
    if let first = ws.first { return first }
    return nil
}

// Chrome & friends build the renderer a11y tree lazily, on the first query.
var win = focusedWindow()
if win == nil || children(win!).isEmpty {
    Thread.sleep(forTimeInterval: 1.2)
    win = focusedWindow()
}
guard let window = win else { print("no window"); exit(2) }

var lines: [String] = []
var nodes = 0
var start = Date()

// Roles whose *value* is the content (text fields, editors, terminals).
let valueRoles: Set<String> = ["AXTextArea", "AXTextField", "AXStaticText", "AXHeading", "AXValueIndicator"]

func walk(_ el: AXUIElement, depth: Int) {
    if nodes > 20000 || Date().timeIntervalSince(start) > 20 { return }
    nodes += 1
    let role = str(el, kAXRoleAttribute as String) ?? "?"
    var text = ""
    if let v = str(el, kAXValueAttribute as String), !v.isEmpty, valueRoles.contains(role) || v.count > 1 { text = v }
    if text.isEmpty, let t = str(el, kAXTitleAttribute as String), !t.isEmpty { text = t }
    if text.isEmpty, let d = str(el, kAXDescriptionAttribute as String), !d.isEmpty { text = d }
    if !text.isEmpty {
        let flat = text.replacingOccurrences(of: "\n", with: "\\n")
        lines.append(showTree ? String(repeating: " ", count: min(depth,20)) + "\(role): \(flat)" : flat)
    }
    for c in children(el) { walk(c, depth: depth + 1) }
}
walk(window, depth: 0)

let out = lines.joined(separator: "\n")
print(out)
let bytes = out.utf8.count
FileHandle.standardError.write("""

--- app=\(app.localizedName ?? "?") nodes=\(nodes) lines=\(lines.count) chars=\(out.count) bytes=\(bytes) est_tokens~\(bytes/4) elapsed=\(String(format: "%.2f", Date().timeIntervalSince(start)))s

""".data(using: .utf8)!)
