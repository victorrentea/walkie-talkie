import AppKit
import ImageIO

/// **A copied GIF moves in the prompt preview too** (2026-10-30, Victor: *"Dacă
/// îți copiezi un clip din GIF animat, îl rendez animat și în panoul de preview
/// de prompturi"*).
///
/// What a copy brings is still the JPEG every picture is (`fileImage`) — the
/// agent reads that. The GIF itself is kept beside it, `screenshot-N.gif`, and
/// the panel plays it where the JPEG would stand: in the words (an image whose
/// drawing asks the clock which frame it is) and in the strip (an
/// `NSImageView` that animates).
///
/// **Where the GIF comes from.** Chrome's *Copy Image* puts only the first
/// frame on the board, as PNG/TIFF, plus `<img src="…">` as HTML — so the bytes
/// are fetched again from that `src` when it names a GIF (`.gif`, `data:image/gif`,
/// a giphy-style URL with `gif` in it). Safari writes the GIF itself
/// (`com.compuserve.gif`). A still GIF (one frame) is not kept: nothing would move.
enum AnimatedCopy {

    static let gifType = NSPasteboard.PasteboardType("com.compuserve.gif")

    /// The `src` of the first `<img>` in a copy's HTML, entities undone.
    static func imageSource(inHTML html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<img\b[^>]*?\bsrc\s*=\s*["']([^"']+)["']"#,
                                                   options: [.caseInsensitive]),
              let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return String(html[r]).replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Worth fetching: it says GIF somewhere. Everything else a copy carries is
    /// a still the board already holds — a download per copied photo buys nothing.
    static func mayBeGIF(_ src: String) -> Bool {
        src.lowercased().hasPrefix("data:image/gif") || src.range(of: "gif", options: .caseInsensitive) != nil
    }

    /// The GIF behind a copy, or nil. **Off the main thread**: it may download
    /// (≤ 5 s, ≤ 20 MB).
    static func fetch(_ src: String) -> Data? {
        if src.lowercased().hasPrefix("data:") {
            guard let comma = src.firstIndex(of: ","), src[..<comma].contains(";base64") else { return nil }
            return Data(base64Encoded: String(src[src.index(after: comma)...]))
                .flatMap { isAnimated($0) ? $0 : nil }
        }
        guard let url = URL(string: src), url.scheme == "https" || url.scheme == "http" else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue("image/gif,image/*;q=0.8", forHTTPHeaderField: "Accept")
        let done = DispatchSemaphore(value: 0)
        var body: Data?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            body = data
            done.signal()
        }.resume()
        guard done.wait(timeout: .now() + 6) == .success, let data = body, data.count <= 20_000_000,
              isAnimated(data) else { return nil }
        return data
    }

    /// `GIF8…` with more than one frame.
    static func isAnimated(_ data: Data) -> Bool {
        guard data.starts(with: Array("GIF8".utf8)),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 1
    }

    /// `…/screenshot-3-original.jpg` or `…-800px.jpg` → `…/screenshot-3.gif`.
    static func gifPath(beside picture: String) -> String {
        let url = URL(fileURLWithPath: picture)
        var stem = url.deletingPathExtension().lastPathComponent
        for suffix in ["-original", "-800px"] where stem.hasSuffix(suffix) {
            stem.removeLast(suffix.count)
        }
        return url.deletingLastPathComponent().appendingPathComponent(stem + ".gif").path
    }

    /// Keeps the GIF beside the picture `fileImage` wrote.
    @discardableResult
    static func keep(_ gif: Data, beside picture: String) -> Bool {
        let path = gifPath(beside: picture)
        do {
            try gif.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            Log.error("could not keep the copied GIF at \((path as NSString).lastPathComponent): \(error)")
            return false
        }
    }

    /// The GIF beside a picture, when there is one.
    static func gif(beside picture: String) -> String? {
        let path = gifPath(beside: picture)
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// One GIF's frames, decoded once at the size they are shown, and when
    /// each one starts.
    final class Film {
        let frames: [CGImage]
        let starts: [Double]
        let duration: Double

        init?(path: String, maxPixels: Int) {
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
            let count = min(CGImageSourceGetCount(source), Self.maxFrames)
            guard count > 1 else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixels),
            ]
            var frames: [CGImage] = [], starts: [Double] = [], t = 0.0
            for i in 0..<count {
                guard let frame = CGImageSourceCreateThumbnailAtIndex(source, i, options as CFDictionary) else { continue }
                frames.append(frame)
                starts.append(t)
                t += Self.delay(source, i)
            }
            guard frames.count > 1 else { return nil }
            self.frames = frames
            self.starts = starts
            self.duration = t
        }

        /// The frame on screen at `time`, looping.
        func frame(at time: Double) -> CGImage {
            let t = time.truncatingRemainder(dividingBy: duration)
            var lo = 0, hi = starts.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if starts[mid] <= t { lo = mid } else { hi = mid - 1 }
            }
            return frames[lo]
        }

        /// Browsers' rule: a delay under 20 ms plays at 100 ms.
        private static func delay(_ source: CGImageSource, _ i: Int) -> Double {
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let d = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            return d < 0.02 ? 0.1 : d
        }

        /// A long GIF is cut, not refused: 200 frames at the panel's ≤ 440 px
        /// is ~150 MB at the worst.
        static let maxFrames = 200
    }

    private static var films: [String: Film] = [:]

    /// **A picture that is a different frame each time it is drawn** — at
    /// `size`, drawn on the main thread. `cacheMode = .never`, so every draw
    /// asks the handler again; whoever shows it redraws on `tick`.
    static func picture(gif path: String, size: NSSize) -> NSImage? {
        let px = Int((max(size.width, size.height) * 2).rounded(.up))
        let key = "\(path)@\(px)"
        let film: Film
        if let known = films[key] {
            film = known
        } else {
            guard let made = Film(path: path, maxPixels: px) else { return nil }
            if films.count > 8 { films.removeAll() }
            films[key] = made
            film = made
        }
        let image = NSImage(size: size, flipped: false) { rect in
            NSGraphicsContext.current?.cgContext.draw(film.frame(at: CACurrentMediaTime()), in: rect)
            return true
        }
        image.cacheMode = .never
        return image
    }

    /// How often a view showing `picture` repaints — 25 a second, which no
    /// GIF's own pace outruns by enough to see.
    static let tick: TimeInterval = 0.04
}
