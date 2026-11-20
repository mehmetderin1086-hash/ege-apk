import AVFoundation
import SwiftUI

/// #15: bölümün ses kimliği. Müzik cihazda sentezlenir (telifsiz); yalnız girişte, konu geçişlerinde ve kapanışta çalar.
/// `SoundDesign.isEnabled == false` → genel ayar "Yok".
nonisolated enum SoundIdentity: String, CaseIterable, Sendable {
    case sade, sicak, odak, yok
    static let key = "sound.identity"

    static var current: SoundIdentity {
        guard SoundDesign.isEnabled else { return .yok }
        return UserDefaults.standard.string(forKey: key).flatMap(SoundIdentity.init(rawValue:)) ?? .sade
    }

    static func resolve(_ raw: String?) -> SoundIdentity { raw.flatMap(SoundIdentity.init(rawValue:)) ?? current }

    /// Birleştirme seçenekleri (üretim ve sahne düzenlemede aynı olmalı): `design` = seviye eşitleme ve müziğe izin
    /// (Ayarlar → Ses tasarımı), kimlik = bölüme özel seçim ya da genel ayar. Tasarım kapalıysa müzik çalmaz.
    static func options(for raw: String?, designEnabled: Bool = SoundDesign.isEnabled,
                        fallback: SoundIdentity = current) -> (design: Bool, identity: SoundIdentity) {
        (designEnabled, raw.flatMap(SoundIdentity.init(rawValue:)) ?? fallback)
    }

    /// Genel varsayılanı değiştirir. Müzikli bir kimlik seçilirse ses tasarımı da açılır.
    static func setDefault(_ identity: SoundIdentity) {
        UserDefaults.standard.set(identity.rawValue, forKey: key)
        if identity != .yok { UserDefaults.standard.set(true, forKey: SoundDesign.key) }
    }

    var title: String {
        switch self {
        case .sade: "Sade"
        case .sicak: "Sıcak"
        case .odak: "Odak"
        case .yok: "Yok"
        }
    }

    var subtitle: String {
        switch self {
        case .sade: "Kısa, berrak çan sesleri ve hafif bir zemin."
        case .sicak: "Yumuşak elektrik piyano akorları; sıcak ve sakin."
        case .odak: "Sakin, tekrarlayan notalar; çalışmaya odaklayan bir tını."
        case .yok: "Müzik yok; yalnız ses seviyesi eşitlenir."
        }
    }

    // MARK: Müzik

    /// Giriş müziğinde konuşmanın başladığı an (sn).
    var introLead: Double {
        switch self {
        case .sade: 2.2
        case .sicak: 2.6
        case .odak: 2.0
        case .yok: 0
        }
    }

    /// Giriş müziği (konuşma `introLead`'de başlar, kalan kısım konuşmanın altında kısılarak çalar).
    func intro(sampleRate: Int) -> PCMClip? {
        guard self != .yok else { return nil }
        var s = Synth(seconds: self == .sicak ? 6.5 : 6.0, sampleRate: sampleRate)
        switch self {
        case .sade:
            for (i, m) in [72, 76, 79, 84].enumerated() { s.bell(Synth.hz(m), at: [0, 0.18, 0.36, 0.6][i], length: 1.6, amp: 0.25) }
            s.pad([60, 67, 76].map(Synth.hz), at: 0, length: 6.0, amp: 0.06, attack: 0.8)
        case .sicak:
            s.piano([53, 57, 60, 64].map(Synth.hz), at: 0, length: 3.2, amp: 0.16)
            s.piano([41].map(Synth.hz), at: 0, length: 3.2, amp: 0.2)
            s.piano([52, 55, 59, 64].map(Synth.hz), at: 2.4, length: 4.0, amp: 0.15)
            s.piano([48].map(Synth.hz), at: 2.4, length: 4.0, amp: 0.2)
            s.lowPass(2500)
        case .odak:
            let pattern = [69, 72, 76, 81, 76, 72, 69, 76, 69, 72, 76, 81, 79, 76, 72, 76]
            for (i, m) in pattern.enumerated() { s.pluck(Synth.hz(m), at: Double(i) * 0.3, amp: i % 4 == 0 ? 0.22 : 0.16) }
            s.pad([45, 52].map(Synth.hz), at: 0, length: 6.0, amp: 0.07, attack: 1.0)
        case .yok:
            break
        }
        s.fadeOut(1.6)
        return s.clip(targetLUFS: -23)
    }

    /// Konu geçişi (öncesi ve sonrası sessizlikle); "Yok" → nil (düz sessizlik kullanılır).
    func transition(sampleRate: Int) -> PCMClip? {
        guard self != .yok else { return nil }
        var s = Synth(seconds: 1.1, sampleRate: sampleRate)
        switch self {
        case .sade:
            s.bell(Synth.hz(79), at: 0, length: 0.7, amp: 0.2)
            s.bell(Synth.hz(84), at: 0.12, length: 0.8, amp: 0.2)
        case .sicak:
            s.piano([53, 57, 60, 64].map(Synth.hz), at: 0, length: 1.1, amp: 0.15)
            s.lowPass(2500)
        case .odak:
            s.pluck(Synth.hz(76), at: 0, amp: 0.2)
            s.pluck(Synth.hz(81), at: 0.22, amp: 0.2)
        case .yok:
            break
        }
        s.fadeOut(0.3)
        guard let music = s.clip(targetLUFS: -26) else { return nil }
        return PCMClip.silence(seconds: 0.3, sampleRate: sampleRate).appending(music).appending(.silence(seconds: 0.3, sampleRate: sampleRate))
    }

    /// Kapanış (öncesinde 0,6 sn sessizlik).
    func outro(sampleRate: Int) -> PCMClip? {
        guard self != .yok else { return nil }
        var s = Synth(seconds: self == .sicak ? 3.2 : 2.6, sampleRate: sampleRate)
        switch self {
        case .sade:
            s.bell(Synth.hz(84), at: 0, length: 1.2, amp: 0.2)
            s.bell(Synth.hz(79), at: 0.22, length: 1.4, amp: 0.2)
            s.bell(Synth.hz(72), at: 0.45, length: 2.0, amp: 0.2)
        case .sicak:
            s.piano([53, 57, 60, 64].map(Synth.hz), at: 0, length: 1.2, amp: 0.15)
            s.piano([48, 52, 55, 59].map(Synth.hz), at: 0.9, length: 2.3, amp: 0.15)
            s.lowPass(2500)
        case .odak:
            for (i, m) in [69, 76, 81].enumerated() { s.pluck(Synth.hz(m), at: Double(i) * 0.3, amp: 0.2) }
            s.pad([45, 52].map(Synth.hz), at: 0, length: 2.6, amp: 0.06, attack: 0.2)
        case .yok:
            break
        }
        s.fadeOut(1.0)
        guard let music = s.clip(targetLUFS: -24) else { return nil }
        return PCMClip.silence(seconds: 0.6, sampleRate: sampleRate).appending(music)
    }

    /// Konuşma başlayınca müziği kısar: −18 dB, 300 ms saldırı, 800 ms bırakma. `music` konuşmayla aynı anda başlar.
    static func mixUnderSpeech(_ speech: PCMClip, music: ArraySlice<Int16>) -> PCMClip {
        guard !music.isEmpty, !speech.samples.isEmpty else { return speech }
        let rate = Double(speech.sampleRate)
        let frame = max(1, speech.sampleRate / 100)
        let count = min(speech.samples.count, music.count)
        var active = [Bool](repeating: false, count: count / frame + 1)
        speech.samples.withUnsafeBufferPointer { s in
            for f in active.indices {
                let start = f * frame, end = min(count, start + frame)
                guard end > start else { continue }
                var sum = 0.0
                for i in start..<end { let v = Double(s[i]) / 32768; sum += v * v }
                active[f] = (sum / Double(end - start)).squareRoot() > 0.015
            }
        }
        let down = 18 / (0.3 * rate), up = 18 / (0.8 * rate)
        var gainDB = 0.0
        var out = speech.samples
        let limit = Double(Mastering.ceiling) * 32768
        let base = music.startIndex
        for i in 0..<count {
            let target = active[i / frame] ? -18.0 : 0
            gainDB = gainDB > target ? max(target, gainDB - down) : min(target, gainDB + up)
            // Müzik konuşmadan önce biterse son 50 ms'de sön.
            let tail = Double(count - i) / (0.05 * rate)
            let fade = count < music.count ? min(1, tail) : 1
            let mixed = Double(out[i]) + Double(music[base + i]) * pow(10, gainDB / 20) * fade
            out[i] = Int16(max(-limit, min(limit, mixed)).rounded(.towardZero))
        }
        return PCMClip(samples: out, sampleRate: speech.sampleRate)
    }
}

/// Basit toplamsal sentezleyici (çan, elektrik piyano, koparma, zemin).
nonisolated struct Synth {
    let rate: Double
    var buffer: [Double]

    init(seconds: Double, sampleRate: Int) {
        rate = Double(sampleRate)
        buffer = [Double](repeating: 0, count: Int(seconds * Double(sampleRate)))
    }

    static func hz(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

    mutating func tone(_ freq: Double, at start: Double, length: Double, amp: Double, partials: [(Double, Double)],
                       attack: Double, decay: Double, detune: Double = 0) {
        let s0 = Int(start * rate)
        let n = Int(length * rate)
        guard s0 < buffer.count else { return }
        for i in 0..<n where s0 + i < buffer.count {
            let t = Double(i) / rate
            let env = min(1, t / attack) * exp(-decay * t / length) * min(1, (length - t) / 0.05)
            var v = 0.0
            for (k, (mult, a)) in partials.enumerated() {
                // Üst harmonikler daha çabuk söner.
                v += a * exp(-Double(k) * 1.5 * t / length) * sin(2 * .pi * freq * mult * t)
                if detune > 0 { v += 0.5 * a * sin(2 * .pi * freq * mult * (1 + detune) * t) }
            }
            buffer[s0 + i] += amp * env * v
        }
    }

    mutating func bell(_ freq: Double, at start: Double, length: Double, amp: Double) {
        tone(freq, at: start, length: length, amp: amp, partials: [(1, 1), (2, 0.25), (3, 0.08)], attack: 0.01, decay: 3.2)
    }

    mutating func piano(_ freqs: [Double], at start: Double, length: Double, amp: Double) {
        for (i, f) in freqs.enumerated() {
            tone(f, at: start + Double(i) * 0.025, length: length, amp: amp,
                 partials: [(1, 1), (2, 0.4), (3, 0.15), (4, 0.06)], attack: 0.008, decay: 2.2, detune: 0.003)
        }
    }

    mutating func pluck(_ freq: Double, at start: Double, amp: Double) {
        tone(freq, at: start, length: 0.9, amp: amp, partials: [(1, 1), (2, 0.5), (3, 0.25), (4, 0.12), (5, 0.06)],
             attack: 0.004, decay: 6)
    }

    mutating func pad(_ freqs: [Double], at start: Double, length: Double, amp: Double, attack: Double) {
        let s0 = Int(start * rate)
        let n = Int(length * rate)
        for i in 0..<n where s0 + i < buffer.count {
            let t = Double(i) / rate
            let env = min(1, t / attack) * min(1, (length - t) / 1.5)
            var v = 0.0
            for f in freqs { v += sin(2 * .pi * f * t) + 0.6 * sin(2 * .pi * f * 1.004 * t) }
            buffer[s0 + i] += amp * max(0, env) * v
        }
    }

    /// Tek kutuplu alçak geçiren (sıcak tını).
    mutating func lowPass(_ cutoff: Double) {
        let a = 1 - exp(-2 * .pi * cutoff / rate)
        var y = 0.0
        for i in buffer.indices {
            y += a * (buffer[i] - y)
            buffer[i] = y
        }
    }

    mutating func fadeOut(_ seconds: Double) {
        let n = min(buffer.count, Int(seconds * rate))
        guard n > 0 else { return }
        for k in 0..<n {
            let i = buffer.count - n + k
            buffer[i] *= Double(n - k) / Double(n)
        }
    }

    /// Hedef ses yüksekliğine ölçeklenmiş ve sınırlanmış klip.
    func clip(targetLUFS: Double) -> PCMClip? {
        var x = buffer.map { Float($0) }
        guard let lufs = Mastering.loudness(x, sampleRate: Int(rate)) else { return nil }
        let gain = Float(pow(10, (targetLUFS - lufs) / 20))
        for i in x.indices { x[i] *= gain }
        Mastering.limit(&x, sampleRate: Int(rate), ceiling: Mastering.ceiling)
        return PCMClip(samples: Mastering.int16(x), sampleRate: Int(rate))
    }
}

// MARK: - Seçici

/// Kimliğin giriş müziğini çalar (önizleme).
@MainActor
@Observable
final class SoundIdentityPreview {
    private(set) var playing: SoundIdentity?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var stopTask: Task<Void, Never>?

    func toggle(_ identity: SoundIdentity) {
        if playing == identity { stop(); return }
        stop()
        guard let intro = identity.intro(sampleRate: 24_000),
              let outro = identity.outro(sampleRate: 24_000),
              let player = try? AVAudioPlayer(data: WAV.encode(intro.appending(outro))) else { return }
        // Bölüm çalıyorsa durur (üst üste çalmasın); oturum oynatıcınınkiyle aynı kalır (mixWithOthers olsaydı
        // kilit ekranı ve kulaklık denetimleri bir sonraki oynatmaya kadar çalışmazdı).
        AppState.current?.player.suspendForLiveSession()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        self.player = player
        player.play()
        playing = identity
        let seconds = player.duration
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds + 0.1))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        stopTask?.cancel()
        player?.stop()
        player = nil
        playing = nil
    }
}

/// Bölümün ses kimliği seçimi. `nil` = genel ayar (`sound.identity`).
struct SoundIdentityPicker: View {
    @Binding var selection: String?
    @State private var preview = SoundIdentityPreview()
    @State private var defaultIdentity = SoundIdentity.current

    private var effective: SoundIdentity { selection.flatMap(SoundIdentity.init(rawValue:)) ?? defaultIdentity }

    var body: some View {
        Picker(selection: $selection) {
            Text("Genel ayar (\(defaultIdentity.title))").tag(String?.none)
            ForEach(SoundIdentity.allCases, id: \.self) { identity in
                Text(identity.title).tag(Optional(identity.rawValue))
            }
        } label: {
            Label("Ses kimliği", systemImage: "music.note")
        }
        VStack(alignment: .leading, spacing: 8) {
            Text(SoundDesign.isEnabled || effective == .yok
                 ? effective.subtitle
                 : "Ayarlar'da ses tasarımı kapalı: müzik çalmaz, ses eşitlenmez. \"Her bölümde kullan\" ile açılır.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack { previewButton; Spacer(); defaultButton }
                VStack(alignment: .leading, spacing: 8) { previewButton; defaultButton }
            }
        }
        .onDisappear { preview.stop() }
    }

    private var previewButton: some View {
        Button {
            preview.toggle(effective)
        } label: {
            Label(preview.playing == effective ? "Durdur" : "Dinle",
                  systemImage: preview.playing == effective ? "stop.fill" : "play.fill")
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .disabled(effective == .yok)
        .accessibilityLabel(preview.playing == effective ? "Önizlemeyi durdur" : "\(effective.title) kimliğini dinle")
    }

    @ViewBuilder private var defaultButton: some View {
        if let raw = selection, let identity = SoundIdentity(rawValue: raw), identity != defaultIdentity || !SoundDesign.isEnabled {
            Button {
                SoundIdentity.setDefault(identity)
                defaultIdentity = SoundIdentity.current
                selection = nil
            } label: {
                Text("Her bölümde kullan").frame(minHeight: 44)
            }
            .buttonStyle(.borderless)
        }
    }
}
