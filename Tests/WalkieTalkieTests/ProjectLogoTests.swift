import XCTest
@testable import WalkieTalkie

/// The bound project's logo in place of the resting walkie (2026-11-22, replacing it since 2026-11-24).
final class ProjectLogoTests: XCTestCase {
    private var root = ""

    override func setUp() {
        root = NSTemporaryDirectory() + "project-logo-\(UUID().uuidString)/acme"
        try? FileManager.default.createDirectory(atPath: root + "/.git", withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: (root as NSString).deletingLastPathComponent)
    }

    /// A full opaque square, `side` px.
    private func write(_ path: String, colour: NSColor = .systemRed, side: Int = 64) {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        colour.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        NSGraphicsContext.restoreGraphicsState()
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }

    func testAProjectWithNoLogoShowsNothing() {
        XCTAssertNil(ProjectLogo.logo(forDirectory: root))
        XCTAssertEqual(ProjectLogo.source(forDirectory: root), "none")
    }

    func testTheRepoRootIsTheProjectWhereverTheSessionSits() {
        let deep = root + "/web/src/app"
        try? FileManager.default.createDirectory(atPath: deep, withIntermediateDirectories: true)
        XCTAssertEqual(ProjectLogo.repoRoot(of: deep), (root as NSString).standardizingPath)
    }

    /// No search through the project's files (2026-11-23): bound to `~/workspace`
    /// a course repo's favicon stood beside the walkie. Only `.walkie/logo.*` counts.
    func testTheProjectsFilesAreNotSearchedOnlyItsWalkieLogo() {
        write(root + "/logo.png")
        write(root + "/docs/Logo.png")
        write(root + "/web/src/favicon.png")
        write(root + "/web/src/main/resources/static/images/logo.png")
        XCTAssertNil(ProjectLogo.logo(forDirectory: root))
        XCTAssertEqual(ProjectLogo.source(forDirectory: root), "none")
        write(root + "/.walkie/logo.png")
        XCTAssertEqual(ProjectLogo.override(inRoot: root), root + "/.walkie/logo.png")
        XCTAssertNotNil(ProjectLogo.logo(forDirectory: root + "/web"))
    }

    func testASquareTileIsRoundedAndFitsTheChip() throws {
        write(root + "/.walkie/logo.png")
        let logo = try XCTUnwrap(ProjectLogo.logo(forDirectory: root))
        XCTAssertEqual(logo.size, NSSize(width: ProjectLogo.side, height: ProjectLogo.side))
        let rep = try XCTUnwrap(logo.representations.first as? NSBitmapImageRep)
        XCTAssertEqual(rep.colorAt(x: 0, y: 0)?.alphaComponent ?? 1, 0, accuracy: 0.05)
        XCTAssertEqual(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.alphaComponent ?? 0, 1, accuracy: 0.05)
    }

    /// Victor's own marks win over a file: petclinic is the cat, whatever favicon
    /// its frontend ships — **in its greys since 2026-11-26** (every logo on the
    /// chip is monochrome).
    func testPetclinicIsItsCatInGrey() throws {
        let pet = (root as NSString).deletingLastPathComponent + "/petclinic"
        write(pet + "/petclinic-frontend/src/favicon.png", colour: .systemGreen)
        XCTAssertEqual(ProjectLogo.source(forDirectory: pet), "ProjectIcons colour mark")
        let logo = try XCTUnwrap(ProjectLogo.logo(forDirectory: pet))
        let rep = try XCTUnwrap(logo.representations.first as? NSBitmapImageRep)
        var inked = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.1 else { continue }
                inked += 1
                XCTAssertLessThan(c.saturationComponent, 0.05, "monochrome only, at \(x),\(y)")
            }
        }
        XCTAssertGreaterThan(inked, 20, "the cat is drawn")
    }

    /// training-assistant is its mortarboard in black and white (2026-11-23), on the
    /// chip and in the spawn menu, whatever coloured 🎓 favicon the repo ships.
    func testTrainingAssistantIsItsMortarboardInBlackAndWhite() throws {
        let ta = (root as NSString).deletingLastPathComponent + "/training-assistant"
        write(ta + "/static/favicon.png", colour: .systemGreen)
        XCTAssertEqual(ProjectLogo.source(forDirectory: ta), "ProjectIcons template mark")
        let logo = try XCTUnwrap(ProjectLogo.logo(forDirectory: ta))
        let rep = try XCTUnwrap(logo.representations.first as? NSBitmapImageRep)
        for x in 0..<rep.pixelsWide { for y in 0..<rep.pixelsHigh {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.1 else { continue }
            XCTAssertLessThan(c.saturationComponent, 0.05, "black and white only, at \(x),\(y)")
        }}
        guard case .template? = ProjectIcons.mark(for: "training-assistant") else {
            return XCTFail("the spawn menu draws it in the row's ink")
        }
    }

    /// One project, one picture (2026-11-26): the spawn menu's mark beats a
    /// `.walkie/logo.*` file, so walkie-talkie is the bare walkie on the chip too,
    /// not its Dock disc.
    func testTheSpawnMenusMarkWinsOverTheLogoFile() throws {
        let walkie = (root as NSString).deletingLastPathComponent + "/walkie-talkie"
        try? FileManager.default.createDirectory(atPath: walkie + "/.git", withIntermediateDirectories: true)
        write(walkie + "/.walkie/logo.png", colour: .systemGreen)
        XCTAssertEqual(ProjectLogo.source(forDirectory: walkie), "ProjectIcons template mark")
        guard case .template? = ProjectIcons.mark(for: "walkie-talkie") else {
            return XCTFail("the spawn menu draws walkie-talkie's walkie in the row's ink")
        }
    }

    func testTheLabelRemembersTheDirectoryItWasReadFrom() {
        let label = TerminalBinding.label(forDirectory: root)
        XCTAssertEqual(ProjectLogo.directory(forLabel: label), root)
    }

    /// The chip draws the logo only where it draws the walkie — instead of it — and the binding
    /// going takes it along.
    func testTheWiring() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/WalkieTalkie")
        let chip = try String(contentsOf: sources.appendingPathComponent("RelayWindow.swift"), encoding: .utf8)
        XCTAssertTrue(chip.contains("private var restingLogo: NSImage? { collapsed ? projectLogo : nil }"))
        XCTAssertTrue(chip.contains("if label == nil { projectLogo = nil }"))
        // In place of the walkie, not beside it (2026-11-24).
        XCTAssertTrue(chip.contains("titleGlyph.isHidden = !bound || restingLogo != nil"))
        let app = try String(contentsOf: sources.appendingPathComponent("AppDelegate.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains("ProjectLogo.resolve(label: target.folder)"))
    }
}
