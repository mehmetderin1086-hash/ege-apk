import AVFoundation
import KagitKit
import PDFKit
import SwiftUI
import Translation

/// Belge ekranı “Yapay Zekâ” kipi.
struct YapayZekaCubugu: View {
    let oturum: BelgeOturumu
    @Environment(Kitaplik.self) private var kitaplik
    @Environment(Yonlendirici.self) private var yon
    @State private var okuyucu = SesliOkuyucu()
    @State private var ozet = false
    @State private var sohbet = false
    @State private var cevirSayfasi = false
    @State private var secimSonucu: SecimGorevi?
    @State private var ceviriMetni = ""
    @State private var ceviriAcik = false
    @State private var ileti: Ileti?

    enum SecimGorevi: String, Identifiable { case acikla, sadelestir; var id: String { rawValue } }

    private var yz: YapayZeka { YapayAyar.paylasilan.yapayZeka() }

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    dugme("Özetle", "text.append") { ozet = true }
                    dugme("Sohbet", "bubble.left.and.text.bubble.right") { sohbet = true }
                    dugme("Açıkla", "lightbulb") { secimle(.acikla) }
                    dugme("Sadeleştir", "text.redaction") { secimle(.sadelestir) }
                    dugme("Soru üret", "sparkles.rectangle.stack") { soruUret() }
                    dugme("Seçimi çevir", "character.bubble") { secimiCevir() }
                    dugme("Belgeyi çevir", "doc.on.doc") { cevirSayfasi = true }
                }
                .padding(.horizontal, 12)
            }
            HStack(spacing: 14) {
                Button { okuyucu.oynat(oturum) } label: { Image(systemName: okuyucu.okuyor ? "pause.fill" : "play.fill") }
                Button { okuyucu.durdur() } label: { Image(systemName: "stop.fill") }.disabled(!okuyucu.aktif)
                Text(okuyucu.aktif ? "Okunuyor · sayfa \(okuyucu.sayfa + 1)" : "Sesli oku (bu sayfadan)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Picker("Hız", selection: $okuyucu.hiz) {
                        Text("Yavaş").tag(Float(0.4)); Text("Normal").tag(Float(0.5)); Text("Hızlı").tag(Float(0.58)); Text("Çok hızlı").tag(Float(0.66))
                    }
                } label: { Label("Hız", systemImage: "gauge.with.dots.needle.33percent").font(.caption) }
            }
            .padding(.horizontal, 16)
            HStack {
                if let e = yz.kaynakEtiketi { KaynakRozeti(etiket: e) }
                else if let n = yz.kullanilamazNedeni { Text(n).font(.caption).foregroundStyle(.orange).lineLimit(3) }
                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .onDisappear { okuyucu.durdur() }
        .sheet(isPresented: $ozet) { OzetSayfasi(oturum: oturum) }
        .sheet(isPresented: $sohbet) { SohbetSayfasi(oturum: oturum).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $cevirSayfasi) { BelgeCeviriSayfasi(oturum: oturum) }
        .sheet(item: $secimSonucu) { g in SecimSayfasi(oturum: oturum, gorev: g, metin: secili) }
        .translationPresentation(isPresented: $ceviriAcik, text: ceviriMetni)
        .iletiGoster($ileti)
    }

    private var secili: String { oturum.pdfView?.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }

    private func dugme(_ ad: String, _ simge: String, _ eylem: @escaping () -> Void) -> some View {
        Button(action: eylem) {
            Label(ad, systemImage: simge).font(.callout).padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.indigo.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func secimle(_ g: SecimGorevi) {
        guard !secili.isEmpty else {
            ileti = Ileti(baslik: "Metin seçin", metin: "Önce belgede açıklanacak metni seçin.", hata: false)
            return
        }
        secimSonucu = g
    }

    private func secimiCevir() {
        guard !secili.isEmpty else {
            ileti = Ileti(baslik: "Metin seçin", metin: "Önce belgede çevrilecek metni seçin.", hata: false)
            return
        }
        ceviriMetni = secili
        ceviriAcik = true
    }

    /// Belgeyi kaydedip kapatır, Soru üret aracını bu belgeyle açar.
    private func soruUret() {
        Task {
            if oturum.degisti { _ = await oturum.kaydet() }
            let u = oturum.url
            yon.acikBelge = nil
            try? await Task.sleep(for: .milliseconds(450))
            yon.aracAc(id: "soruUret", girdiler: [u])
        }
    }
}

// MARK: - Sesli okuma

@MainActor @Observable
final class SesliOkuyucu: NSObject, AVSpeechSynthesizerDelegate {
    private let sentez = AVSpeechSynthesizer()
    private(set) var okuyor = false
    private(set) var aktif = false
    private(set) var sayfa = 0
    var hiz: Float = 0.5
    @ObservationIgnored private var sayfalar: [(indeks: Int, metin: String)] = []
    @ObservationIgnored private weak var oturum: BelgeOturumu?

    override init() {
        super.init()
        sentez.delegate = self
    }

    /// Çalıyorsa duraklatır, duruyorsa devam eder, hiç başlamadıysa mevcut sayfadan başlar.
    func oynat(_ o: BelgeOturumu) {
        if aktif {
            if okuyor { sentez.pauseSpeaking(at: .word); okuyor = false } else { sentez.continueSpeaking(); okuyor = true }
            return
        }
        guard let b = o.belge else { return }
        oturum = o
        sayfalar = (o.seciliSayfa..<b.pageCount).compactMap { i in
            guard let s = b.page(at: i)?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return (i, s)
        }
        guard !sayfalar.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        aktif = true
        okuyor = true
        for (i, s) in sayfalar {
            let u = AVSpeechUtterance(string: s)
            u.voice = AVSpeechSynthesisVoice(language: "tr-TR")
            u.rate = hiz
            u.accessibilityHint = "\(i)"
            sentez.speak(u)
        }
        sayfa = sayfalar[0].indeks
    }

    func durdur() {
        sentez.stopSpeaking(at: .immediate)
        aktif = false
        okuyor = false
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, willSpeakRangeOfSpeechString r: NSRange, utterance u: AVSpeechUtterance) {
        guard let i = Int(u.accessibilityHint ?? "") else { return }
        Task { @MainActor in
            if sayfa != i {
                sayfa = i
                if let p = oturum?.belge?.page(at: i) { oturum?.pdfView?.go(to: p) }
            }
        }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in
            if !sentez.isSpeaking { aktif = false; okuyor = false }
        }
    }
}
