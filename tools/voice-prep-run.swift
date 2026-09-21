// Rulează lanțul de voce din `VoicePrep.swift` peste un WAV, fără aplicație.
//
//   swiftc -O tools/voice-prep-run.swift Sources/WalkieTalkie/VoicePrep.swift -o /tmp/vp
//   for m in direct normalized bass spectrum all; do
//     WT_HALO_VOICE=$m /tmp/vp in-16k.wav out-$m.wav
//   done
//
// De ce un fișier și nu o rută de loopback: lanțul se judecă pe SPECTRU, nu pe
// ecran, iar spectrul se citește dintr-un fișier. Compilează EXACT fișierul care
// se livrează — `ProjectMHalo` de mai jos e doar un ciot pentru rata de eșantionare,
// singurul lucru pe care VoicePrep îl citește din el.
//
// Intrarea trebuie să fie **16 kHz, 16-bit, mono** — exact ce scrie `MicRecorder`
// în corpus (`~/.walkie-talkie/voice-corpus/<zi>/*.wav`), deci o mostră din corpus
// merge direct. Bucățile sunt tăiate la 1/30 s, ca la `feed`, fiindcă filtrele au
// stare și un lanț testat pe semnalul întreg nu e lanțul care rulează.
//
// La citirea rezultatului: benzile trebuie socotite ÎN TERMENII MOTORULUI, adică
// frecvențele înmulțite cu 44100/16000 = 2,756 — vezi comentariul din VoicePrep.

import Foundation

// Ține locul tipului real; VoicePrep.swift citește din el doar rata.
enum ProjectMHalo { static let sampleRate = 16000 }

// WAV 16-bit PCM mono, exact ce scrie MicRecorder în corpus
func readWav(_ path: String) -> [Float] {
    let d = try! Data(contentsOf: URL(fileURLWithPath: path))
    var i = 12, dataOff = 0, dataLen = 0
    while i + 8 <= d.count {
        let id = String(bytes: d[i..<i+4], encoding: .ascii) ?? ""
        let sz = Int(d[i+4]) | Int(d[i+5])<<8 | Int(d[i+6])<<16 | Int(d[i+7])<<24
        if id == "data" { dataOff = i + 8; dataLen = sz; break }
        i += 8 + sz + (sz & 1)
    }
    var out = [Float](); out.reserveCapacity(dataLen/2)
    var p = dataOff
    while p + 1 < dataOff + dataLen {
        let v = Int16(bitPattern: UInt16(d[p]) | UInt16(d[p+1]) << 8)
        out.append(Float(v) / 32768); p += 2
    }
    return out
}

func writeWav(_ x: [Float], _ path: String) {
    var d = Data(); let sr = 16000, n = x.count
    func le32(_ v: Int) { d.append(contentsOf: [UInt8(v & 255), UInt8((v>>8) & 255), UInt8((v>>16) & 255), UInt8((v>>24) & 255)]) }
    func le16(_ v: Int) { d.append(contentsOf: [UInt8(v & 255), UInt8((v>>8) & 255)]) }
    d.append(contentsOf: Array("RIFF".utf8)); le32(36 + n*2); d.append(contentsOf: Array("WAVE".utf8))
    d.append(contentsOf: Array("fmt ".utf8)); le32(16); le16(1); le16(1); le32(sr); le32(sr*2); le16(2); le16(16)
    d.append(contentsOf: Array("data".utf8)); le32(n*2)
    for v in x { le16(Int(Int16(max(-32768, min(32767, v * 32767))))) }
    try! d.write(to: URL(fileURLWithPath: path))
}

let inPath = CommandLine.arguments[1], outPath = CommandLine.arguments[2]
let x = readWav(inPath)
// EXACT cum vine la feed: bucăți de ~1/30 s, consecutive
let chunk = 16000 / 30
var out = [Float]()
var i = 0
while i < x.count {
    var piece = Array(x[i..<min(i+chunk, x.count)])
    VoicePrep.shared.process(&piece)
    out.append(contentsOf: piece)
    i += chunk
}
writeWav(out, outPath)
FileHandle.standardError.write("mod \(HaloVoice.current.rawValue): \(out.count) eșantioane\n".data(using: .utf8)!)
