import Foundation
import XCTest
@testable import WalkieTalkie

final class BrowserGateTests: XCTestCase {
    private let host = "127.0.0.1:8917"

    func testToolsPass() {
        XCTAssertFalse(BrowserGate.refuses(host: host, origin: nil, fetchSite: nil))
        XCTAssertFalse(BrowserGate.refuses(host: "localhost:8917", origin: nil, fetchSite: nil))
        XCTAssertFalse(BrowserGate.refuses(host: "[::1]:8917", origin: nil, fetchSite: nil))
        XCTAssertFalse(BrowserGate.refuses(host: nil, origin: nil, fetchSite: nil))
    }

    /// The Walkie Talkie Inspector extension was the one browser caller with a pass;
    /// it is gone (2026-11-20), so an extension's worker is refused like a page.
    func testAnExtensionIsRefused() {
        let origin = "chrome-extension://abcdefghijklmnop"
        XCTAssertTrue(BrowserGate.refuses(host: host, origin: origin, fetchSite: "none"))
        XCTAssertTrue(BrowserGate.refuses(host: host, origin: origin, fetchSite: "cross-site"))
        XCTAssertTrue(BrowserGate.refuses(host: host, origin: origin, fetchSite: nil))
        // A typed URL in the address bar: no Origin, `Sec-Fetch-Site: none`.
        XCTAssertFalse(BrowserGate.refuses(host: host, origin: nil, fetchSite: "none"))
    }

    func testAPageIsRefused() {
        // A form or fetch POST.
        XCTAssertTrue(BrowserGate.refuses(host: host, origin: "https://evil.example", fetchSite: "cross-site"))
        // An <img>: no Origin at all.
        XCTAssertTrue(BrowserGate.refuses(host: host, origin: nil, fetchSite: "cross-site"))
        // A sandboxed frame.
        XCTAssertTrue(BrowserGate.refuses(host: host, origin: "null", fetchSite: "cross-site"))
        // Another page on this machine, on another port.
        XCTAssertTrue(BrowserGate.refuses(host: host, origin: "http://localhost:3000", fetchSite: "same-site"))
        // An older browser without Fetch Metadata still sends Origin on a POST.
        XCTAssertTrue(BrowserGate.refuses(host: host, origin: "https://evil.example", fetchSite: nil))
    }

    func testAForeignHostIsRefused() {
        XCTAssertTrue(BrowserGate.refuses(host: "evil.example:8917", origin: nil, fetchSite: nil))
        XCTAssertTrue(BrowserGate.refuses(host: "evil.example", origin: nil, fetchSite: nil))
        XCTAssertTrue(BrowserGate.refuses(host: "host.docker.internal:8917", origin: nil, fetchSite: nil))
        XCTAssertTrue(BrowserGate.refuses(host: "127.0.0.1.evil.example:8917", origin: nil, fetchSite: nil))
    }

    /// The payload that broke out of the `echo`, run for real through zsh with
    /// `claude` off the PATH: its `touch` must stay text.
    func testResumeScriptKeepsASessionInert() throws {
        let marker = NSTemporaryDirectory() + "walkie-injected-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: marker) }
        let session = "x\"\nfi\n/usr/bin/touch \(marker)\nif true; then\n echo \""
        let body = SpawnTerminal.resumeScript(session: session, directory: "/tmp")
            .replacingOccurrences(of: "exec /bin/zsh -l", with: "exit 0")
            .replacingOccurrences(of: "PATH=\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\"",
                                  with: "PATH=/nonexistent")
        let script = NSTemporaryDirectory() + "walkie-script-\(UUID().uuidString).sh"
        defer { try? FileManager.default.removeItem(atPath: script) }
        try body.write(toFile: script, atomically: true, encoding: .utf8)
        let zsh = Process()
        zsh.executableURL = URL(fileURLWithPath: "/bin/zsh")
        zsh.arguments = ["-f", script]
        zsh.standardOutput = FileHandle.nullDevice
        zsh.standardError = FileHandle.nullDevice
        try zsh.run()
        zsh.waitUntilExit()
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker), "the session escaped into the script")
    }

    func testResumeRefusesAnythingButASessionId() {
        guard case .failed = SpawnTerminal.resumeClaude(session: "x\"; touch /tmp/x; \"", directory: "/tmp") else {
            return XCTFail("a non-uuid session must never reach Terminal")
        }
    }
}

/// The loopback server's request parser runs before `BrowserGate`: a negative
/// `Content-Length` must not trap in `prefix` (it took the relay down).
final class LoopbackRequestTests: XCTestCase {
    func testANegativeLengthIsAnEmptyBody() {
        let raw = Data("GET /x HTTP/1.1\r\nContent-Length: -1\r\n\r\n".utf8)
        let request = ElementPicker.Request(raw)
        XCTAssertEqual(request?.path, "/x")
        XCTAssertEqual(request?.body.count, 0)
    }

    func testTheBodyIsCutAtItsLength() {
        let raw = Data("POST /y HTTP/1.1\r\nContent-Length: 2\r\n\r\nabc".utf8)
        XCTAssertEqual(ElementPicker.Request(raw).map { String(decoding: $0.body, as: UTF8.self) }, "ab")
    }
}
