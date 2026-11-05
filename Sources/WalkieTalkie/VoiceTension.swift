import Accelerate
import AVFoundation

/// **😡 from the sound alone** (2026-11-05, Victor: *"nu pe cuvinte, totul e pe
/// sunet, pe undele sonore … dacă este detectată furia sau supărarea s-o marchez,
/// dacă nu, nu"*). Pitch off the take's WAV, so it works on every recogniser.
///
/// **Pitch only**: his voice rises when he is wound up, and pitch does not depend
/// on how close the microphone is, where level does. A whisper has no pitch, so it
/// reads as nothing. This is `evals/audio-affect/tense_app.py`, line for line; the
/// weights and the bar come from there: 1,748 clips, rho 0.82 against the arousal
/// teacher on held-out days, and against his blind ear 4 of 6 tense over the bar,
/// 4 of 27 under it. Thin evidence, one listener.
enum VoiceTension {
    private static let halvedRate = 8000
    private static let window = 320, hop = 160           // 40 ms every 20 ms
    private static let shortestLag = 8000 / 400, longestLag = 8000 / 75
    private static let pitched: Float = 0.6              // the correlation that counts as a voice
    private static let gate: Float = 180                 // the meter's absolute floor, int16 units
    /// 3 s of pitched voice: under it the median is the sentence's first words.
    private static let fewestFrames = 150
    private static let longestTake = 120                 // seconds read
    /// Fires on about one sentence in ten of his corpus.
    static let bar = 0.99

    struct Reading {
        let score: Double
        let frames: Int
        var tense: Bool { score >= VoiceTension.bar }
    }

    /// Nil when the take has too little pitched voice to say anything.
    static func read(wav: URL) -> Reading? {
        guard let samples = samples(of: wav) else { return nil }
        return reading(pitch: pitch(samples))
    }

    static func reading(pitch p: [Float]) -> Reading? {
        guard p.count >= fewestFrames else { return nil }
        return Reading(score: score(pitch: p), frames: p.count)
    }

    /// The sum `tense_app.py`'s ridge fitted: median, its reach upward, its spread.
    static func score(pitch p: [Float]) -> Double {
        let sorted = p.map(Double.init).sorted()
        let median = percentile(sorted, 50)
        let mean = sorted.reduce(0, +) / Double(sorted.count)
        let spread = (sorted.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(sorted.count)).squareRoot()
        return 0.2287 * median + 0.0631 * (percentile(sorted, 95) - median) - 0.1787 * spread - 1.6357
    }

    /// numpy's linear interpolation.
    private static func percentile(_ sorted: [Double], _ q: Double) -> Double {
        let at = q / 100 * Double(sorted.count - 1), low = Int(at)
        guard low + 1 < sorted.count else { return sorted[low] }
        return sorted[low] + (sorted[low + 1] - sorted[low]) * (at - Double(low))
    }

    /// Semitones over 100 Hz, one per pitched frame. `x` is 16 kHz, int16 units.
    static func pitch(_ x: [Float]) -> [Float] {
        let n = x.count / 2
        guard n > window + longestLag else { return [] }
        let y = (0..<n).map { (x[2 * $0] + x[2 * $0 + 1]) / 2 }
        var a = [Float](repeating: 0, count: window), b = a
        var fit = [Float](repeating: 0, count: longestLag + 1)
        var out: [Float] = []
        func centred(_ from: Int, into frame: inout [Float]) -> Float {
            var mean: Float = 0, energy: Float = 0, shift: Float = 0
            y.withUnsafeBufferPointer { vDSP_meanv($0.baseAddress! + from, 1, &mean, vDSP_Length(window)) }
            shift = -mean
            y.withUnsafeBufferPointer {
                vDSP_vsadd($0.baseAddress! + from, 1, &shift, &frame, 1, vDSP_Length(window))
            }
            vDSP_dotpr(frame, 1, frame, 1, &energy, vDSP_Length(window))
            return energy
        }
        for start in stride(from: 0, to: n - window - longestLag, by: hop) {
            let e0 = centred(start, into: &a)
            guard (e0 / Float(window)).squareRoot() >= gate else { continue }
            for lag in shortestLag...longestLag {
                let e = centred(start + lag, into: &b)
                var dot: Float = 0
                vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(window))
                fit[lag] = e > 0 ? dot / (e0 * e).squareRoot() : 0
            }
            let top = fit[shortestLag...longestLag].max() ?? 0
            // The shortest lag near the top, so no octave down; then up to its peak.
            guard top >= pitched,
                  var lag = (shortestLag...longestLag).first(where: { fit[$0] >= 0.9 * top }) else { continue }
            while lag < longestLag, fit[lag + 1] > fit[lag] { lag += 1 }
            var exact = Float(lag)
            if lag > shortestLag, lag < longestLag {
                let bend = fit[lag - 1] - 2 * fit[lag] + fit[lag + 1]
                if bend < 0 { exact += 0.5 * (fit[lag - 1] - fit[lag + 1]) / bend }
            }
            out.append(12 * log2(Float(halvedRate) / exact / 100))
        }
        return out
    }

    private static func samples(of wav: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: wav), file.processingFormat.sampleRate == 16000 else { return nil }
        let frames = AVAudioFrameCount(min(file.length, AVAudioFramePosition(16000 * longestTake)))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames),
              (try? file.read(into: buffer, frameCount: frames)) != nil,
              let channel = buffer.floatChannelData?[0] else { return nil }
        return (0..<Int(buffer.frameLength)).map { channel[$0] * 32768 }
    }
}
