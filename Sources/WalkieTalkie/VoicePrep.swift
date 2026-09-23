import Foundation

/// **Vocea, pregătită pentru presetele care așteaptă muzică.**
///
/// Presetele MilkDrop sunt desenate pentru muzică, iar Victor vorbește. Măsurat pe
/// zece înregistrări din corpusul lui, din orele de curs (9–17, L–V, 8 s+):
///
/// - **3,2%** din energia vocii stă sub 120 Hz (între 0,5% și 11%), acolo unde o tobă
///   de bas pune 30–50% — iar bass-ul e ce mișcă majoritatea presetelor;
/// - 90% din energie e între **145 și 3900 Hz**, mediana la 466 Hz: o bandă îngustă,
///   fix la mijloc, unde presetele au cel mai puțin de lucru;
/// - nivelul brut sare cu **28 dB** de la o înregistrare la alta, deci un câștig fix
///   nu are cum să fie bun de două ori la rând;
/// - **48%** din mișcarea anvelopei e în 2–8 Hz, adică silabele: ritmul există, doar
///   că e în locul greșit din spectru. Asta se poate muta.
///
/// ## Capcana care face portarea altceva decât o copiere
///
/// `ProjectMHalo.feed` predă motorului eșantioane de **16 kHz declarate ca 44,1 kHz**,
/// deliberat (vezi comentariul de acolo: ambele motoare sunt detectorul de beat al lui
/// MilkDrop, care citește benzile din bini de spectru presupunând 44,1 kHz, iar ruta
/// web îi dă lui butterchurn exact aceste eșantioane brute). Consecința: **tot ce
/// aude motorul e urcat cu un factor de 2,756**. Fundamentala lui Victor, ~150 Hz,
/// ajunge la motor pe la 414 Hz, iar banda pe care motorul o numește „bass" (20–320 Hz)
/// corespunde la 7–116 Hz reali — unde vocea lui chiar nu are nimic.
///
/// Deci orice frecvență din lanțul ăsta se alege **în termenii motorului** și se împarte
/// la raport ca să ajungă în termeni reali: un sub care trebuie să se audă la 60 Hz
/// pentru motor se generează la 60 × 16000/44100 ≈ **21,8 Hz**. Un sub pus la 60 Hz
/// reali ar ateriza la 165 Hz pentru motor, adică peste vocea lui, nu sub ea.
///
/// Lanțurile sunt aceleași cinci ca în pagina de demo (`voice-halo/index.html`), ca
/// să poată fi comparate: ce alegi acolo cu degetul, alegi aici din meniu.
enum HaloVoice: String, CaseIterable {
    /// Ce iese din microfon, neatins — reperul, și ce rulează până alegi altceva.
    case direct
    /// Compresie tare + câștig: aceeași forță indiferent de cât de departe ești de
    /// microfon. Pe ăsta mor cei 28 dB de diferență între înregistrări.
    case normalized
    /// `normalized` + un sub a cărui amplitudine urmărește anvelopa vocii: le dă
    /// presetelor toba pe care o așteaptă, pe ritmul silabelor.
    case bass
    /// `normalized` + rafturi de ±12 dB jos și sus: întinde banda îngustă peste
    /// tot spectrul pe care presetele îl citesc.
    case spectrum
    /// `spectrum` + `bass`, varianta agresivă.
    case all

    static let defaultsKey = "haloVoice"
    static var current: HaloVoice {
        if let n = ProcessInfo.processInfo.environment["WT_HALO_VOICE"], let v = HaloVoice(rawValue: n) { return v }
        if let n = UserDefaults.standard.string(forKey: defaultsKey), let v = HaloVoice(rawValue: n) { return v }
        return .direct
    }
    var title: String {
        switch self {
        case .direct:     return "Direct"
        case .normalized: return "Normalized (any distance)"
        case .bass:       return "Syllable beat"
        case .spectrum:   return "Spectrum (band stretched)"
        case .all:        return "Everything"
        }
    }
}

/// Un biquad, forma direct II transposed. Starea e per instanță, deci un lanț
/// trebuie să-și păstreze filtrele între bucăți — ce vine la `feed` sunt bucăți
/// consecutive de ~1/30 s, nu semnalul întreg.
private struct Biquad {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    var z1: Float = 0, z2: Float = 0

    mutating func reset() { z1 = 0; z2 = 0 }

    /// RBJ cookbook, cu câștigul normalizat la a0.
    private mutating func set(_ b0: Double, _ b1: Double, _ b2: Double, _ a0: Double, _ a1: Double, _ a2: Double) {
        self.b0 = Float(b0/a0); self.b1 = Float(b1/a0); self.b2 = Float(b2/a0)
        self.a1 = Float(a1/a0); self.a2 = Float(a2/a0)
    }

    mutating func highpass(_ f: Double, _ sr: Double, q: Double = 0.707) {
        let w = 2 * Double.pi * f / sr, cw = cos(w), sw = sin(w), al = sw / (2*q)
        set((1+cw)/2, -(1+cw), (1+cw)/2, 1+al, -2*cw, 1-al)
    }
    mutating func lowShelf(_ f: Double, _ sr: Double, gainDB: Double) {
        let A = pow(10, gainDB/40), w = 2 * Double.pi * f / sr, cw = cos(w), sw = sin(w)
        let al = sw/2 * sqrt((A + 1/A) * (1/0.707 - 1) + 2), sq = 2*sqrt(A)*al
        set(A*((A+1) - (A-1)*cw + sq), 2*A*((A-1) - (A+1)*cw), A*((A+1) - (A-1)*cw - sq),
            (A+1) + (A-1)*cw + sq, -2*((A-1) + (A+1)*cw), (A+1) + (A-1)*cw - sq)
    }
    mutating func highShelf(_ f: Double, _ sr: Double, gainDB: Double) {
        let A = pow(10, gainDB/40), w = 2 * Double.pi * f / sr, cw = cos(w), sw = sin(w)
        let al = sw/2 * sqrt((A + 1/A) * (1/0.707 - 1) + 2), sq = 2*sqrt(A)*al
        set(A*((A+1) + (A-1)*cw + sq), -2*A*((A-1) + (A+1)*cw), A*((A+1) + (A-1)*cw - sq),
            (A+1) - (A-1)*cw + sq, 2*((A-1) - (A+1)*cw), (A+1) - (A-1)*cw - sq)
    }

    mutating func run(_ x: inout [Float]) {
        for i in x.indices {
            let v = x[i]
            let y = b0*v + z1
            z1 = b1*v - a1*y + z2
            z2 = b2*v - a2*y
            x[i] = y
        }
    }
}

/// Lanțul propriu-zis. O singură instanță, atinsă doar de pe coada de randare a
/// haloului — `ProjectMHalo.feed` e singurul apelant.
final class VoicePrep {
    static let shared = VoicePrep()

    /// Raportul dintre ce crede motorul și ce e în fișier: eșantioanele sunt la
    /// 16 kHz, dar îi sunt predate ca 44,1 kHz.
    static let engineRatio = Double(ProjectMHalo.sampleRate) / 44100.0

    private var mode: HaloVoice = .direct
    private var hp = Biquad(), lo = Biquad(), hi = Biquad()
    private var subPhase: Double = 0
    private var env: Float = 0          // anvelopa vocii, pentru sub

    /// **Nu un compresor cu prag, ci un AGC cu țintă.** Prima variantă a fost
    /// portată din pagină (prag −45 dBFS, raport 12:1, makeup ×6) și, măsurată pe
    /// două minute din vocea lui, a ieșit mai ÎNCET decât originalul: 0,0262 față de
    /// 0,0425 RMS. Motivul e că în browser compresorul primește semnalul deja trecut
    /// prin AGC-ul microfonului, iar aici primește fișierul brut, care are vârfuri
    /// la 0,99 — 45 dB peste prag, adică 41 dB de reducere pe care un makeup fix de
    /// ×6 nu-i acoperă. Ținta declarată a modului ăsta e „aceeași forță indiferent
    /// de cât de departe ești de microfon", și asta se scrie direct: măsori RMS-ul
    /// lent și îl duci la o țintă, cu un limitator în spate ca să nu tai.
    private let targetRMS: Float = 0.10      // ~−20 dBFS, nivelul la care presetele au ce mânca
    private let maxGain: Float = 24, minGain: Float = 0.5
    private let ceiling: Float = 0.95
    private var rmsSq: Float = 0             // media pătratelor, netezită
    private var gain: Float = 1
    private var rmsPole: Float = 0, attack: Float = 0, release: Float = 0

    /// `shared` is the native engine's; the page keeps one of its own for Fairy
    /// dust, because the chain's filters carry state between chunks.
    init() { configure(for: .direct, sampleRate: Double(ProjectMHalo.sampleRate)) }

    private func configure(for m: HaloVoice, sampleRate sr: Double) {
        mode = m
        // Pragul de jos se alege ca să NU taie subul: 12 Hz reali = 33 Hz pentru motor.
        hp.highpass(12, sr)
        // Rafturile se aleg în termenii motorului și se coboară la real.
        lo.lowShelf(170 * Self.engineRatio, sr, gainDB: 12)
        hi.highShelf(3500 * Self.engineRatio, sr, gainDB: 12)
        hp.reset(); lo.reset(); hi.reset()
        // RMS pe ~300 ms: destul de lent cât să nu urmărească silabele (alea sunt
        // treaba subului), destul de rapid cât să prindă că te-ai apropiat de microfon
        rmsPole = Float(exp(-1.0 / (0.300 * sr)))
        attack = Float(exp(-1.0 / (0.050 * sr)))    // câștigul scade repede
        release = Float(exp(-1.0 / (0.800 * sr)))   // și urcă încet, ca să nu pompeze
        gain = 1; rmsSq = 0; env = 0
    }

    /// Cheamă-l când s-a schimbat alegerea din meniu.
    func refresh() {
        let m = HaloVoice.current
        if m != mode { configure(for: m, sampleRate: Double(ProjectMHalo.sampleRate)) }
    }

    /// Trece o bucată de semnal prin lanțul ales. Bucata e modificată pe loc.
    func process(_ x: inout [Float]) {
        refresh()
        guard mode != .direct, !x.isEmpty else { return }
        let sr = Double(ProjectMHalo.sampleRate)

        // anvelopa se citește din semnalul BRUT, înainte ca vreun compresor să-l
        // aplatizeze — altfel subul urmărește ce a rămas, nu ce ai spus
        var envIn = x

        hp.run(&x)
        if mode == .spectrum || mode == .all { lo.run(&x); hi.run(&x) }

        // AGC: RMS lent → câștig spre țintă → limitator moale la ±0,95
        for i in x.indices {
            let v = x[i]
            rmsSq = v*v + (rmsSq - v*v) * rmsPole
            let rms = sqrtf(max(rmsSq, 1e-12))
            // sub pragul de zgomot nu se ridică nimic: tăcerea trebuie să rămână tăcere
            let wanted: Float = rms < 0.0015 ? 1 : min(maxGain, max(minGain, targetRMS / rms))
            gain = wanted < gain ? wanted + (gain - wanted) * attack
                                 : wanted + (gain - wanted) * release
            var y = v * gain
            if y > ceiling { y = ceiling } else if y < -ceiling { y = -ceiling }
            x[i] = y
        }

        guard mode == .bass || mode == .all else { return }
        // subul: 60 Hz PENTRU MOTOR, deci 21,8 Hz reali — un sinus care nu se aude
        // ca ton, se simte ca lovitură, cu amplitudinea lipită de anvelopa vocii
        let subHz = 60 * Self.engineRatio
        let step = 2 * Double.pi * subHz / sr
        for i in x.indices {
            let a = abs(envIn[i])
            // atac instant, cădere lentă: o silabă lovește, apoi se stinge, ca o tobă
            env = a > env ? a : env * 0.9994 + a * 0.0006
            let drive = min(1, max(0, (env - 0.004) * 26))
            subPhase += step
            if subPhase > 2 * Double.pi { subPhase -= 2 * Double.pi }
            // 0,55 dădea 61% din spectrul văzut de motor — peste cât are muzica
            // (30–50%). Măsurat, 0,22 aduce banda la ~21%: o lovitură care se aude,
            // fără să înece vocea din care e făcută.
            var y = x[i] + Float(sin(subPhase)) * drive * 0.22
            // limitatorul de mai sus a tăiat la 0,95, dar subul se ADUNĂ după el:
            // fără clamp aici, `bass` și `all` ieșeau fix la 1,000, adică tăiate.
            if y > ceiling { y = ceiling } else if y < -ceiling { y = -ceiling }
            x[i] = y
        }
        envIn.removeAll(keepingCapacity: false)
    }
}
