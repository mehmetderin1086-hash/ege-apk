import SwiftUI

/// Toplantı kaydı ve tutanak (P4.6): rıza → kayıt (süre, seviye, Duraklat/Bitir) → döküm (vekil Whisper, 5 dk parçalar)
/// → sohbete belge olarak tutanak isteği. Belge turu dış kaynaklı sayılır
/// (`Beyin.disKaynakliTur`), hatırlatıcı eklemesi onay ister; bu bilinçli bir seçimdir.
/// Kimlikler: `kayit-riza`, `kayit-baslat`, `kayit-duraklat`, `kayit-bitir`, `kayit-dokum`, `kayit-satiri`.
struct KayitEkrani: View {
    @Environment(\.dismiss) private var kapat
    @Environment(Beyin.self) private var beyin
    @Environment(SesOturumu.self) private var ses
    /// Tutanak isteği sohbete gönderilince (Üretkenlik sayfası da kapansın diye).
    var gonderildi: (() -> Void)? = nil

    @State private var kaydedici = SesKaydedici.ortak
    @State private var dokumIsi = ToplantiDokumIsi.ortak
    @State private var riza = false
    @State private var kayitlar: [URL] = []
    @State private var baslatiliyor = false

    var body: some View {
        NavigationStack {
            List {
                if kaydedici.suruyor { kayitBolumu } else { rizaBolumu }
                if case .bitti(let url) = kaydedici.durum { bitenBolumu(url) }
                if dokumIsi.calisiyor || dokumIsi.hata != nil { dokumBolumu }
                if !kayitlar.isEmpty { kayitlarBolumu }
            }
            .navigationTitle("Toplantı kaydı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tamam") { kapat() }.disabled(kaydedici.suruyor || dokumIsi.calisiyor)
                }
            }
            // Kayıt ya da döküm sürerken sayfa aşağı kaydırılarak kapanmasın (kayıt yarım kalmaz ama durum görünmez olur).
            .interactiveDismissDisabled(kaydedici.suruyor || dokumIsi.calisiyor)
            .onAppear { kayitlar = SesKaydedici.kayitlar() }
            .onChange(of: kaydedici.durum) { _, _ in kayitlar = SesKaydedici.kayitlar() }
        }
    }

    // MARK: Bölümler

    private var rizaBolumu: some View {
        Section {
            Label("Kayda başlamadan önce katılımcılara kayıt alındığını bildir ve rızalarını al (KVKK). Kayıt yalnız bu telefonda saklanır; döküm için ses parçaları sunucudaki Whisper aktarıcısına gider.", systemImage: "hand.raised")
                .font(.callout)
            Toggle("Katılımcılara bildirdim, rızaları var", isOn: $riza)
                .accessibilityIdentifier("kayit-riza")
            Button {
                Task { await baslat() }
            } label: {
                Label(baslatiliyor ? "Başlatılıyor…" : "Kayda başla", systemImage: "record.circle")
            }
            .disabled(!riza || baslatiliyor)
            .accessibilityIdentifier("kayit-baslat")
            if let h = kaydedici.hata { Text(h).font(.footnote).foregroundStyle(.red) }
        } header: {
            Text("Rıza")
        } footer: {
            Text("En çok 3 saat. Arama gelirse kayıt duraklar, arama bitince sürer. Ekran kilitlense de kayıt sürer.")
        }
    }

    private var kayitBolumu: some View {
        Section("Kayıt") {
            HStack {
                Image(systemName: kaydedici.durum == .kayitta ? "record.circle.fill" : "pause.circle.fill")
                    .foregroundStyle(kaydedici.durum == .kayitta ? .red : .orange)
                Text(Self.sureMetni(kaydedici.sure)).font(.title2.monospacedDigit())
                Spacer()
                Text(kaydedici.durum == .kayitta ? "Kaydediliyor" : "Duraklatıldı").foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            ProgressView(value: Double(kaydedici.seviye))
                .accessibilityLabel("Ses seviyesi")
            HStack {
                if kaydedici.durum == .kayitta {
                    Button { kaydedici.duraklat() } label: { Label("Duraklat", systemImage: "pause.fill") }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("kayit-duraklat")
                } else {
                    Button { kaydedici.surdur() } label: { Label("Sürdür", systemImage: "record.circle") }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("kayit-duraklat")
                }
                Spacer()
                Button(role: .destructive) { kaydedici.bitir() } label: { Label("Bitir", systemImage: "stop.fill") }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("kayit-bitir")
            }
            if let h = kaydedici.hata { Text(h).font(.footnote).foregroundStyle(.red) }
        }
    }

    private func bitenBolumu(_ url: URL) -> some View {
        Section("Kayıt bitti") {
            Label(Self.gorunenAd(url), systemImage: "waveform")
            Button {
                dokumuBaslat(url)
            } label: {
                Label("Dökümü çıkar ve tutanak hazırla", systemImage: "doc.text.magnifyingglass")
            }
            .disabled(dokumIsi.calisiyor)
            .accessibilityIdentifier("kayit-dokum")
            Button("Yeni kayıt") { kaydedici.sifirla(); riza = false }
        }
    }

    private var dokumBolumu: some View {
        Section("Döküm") {
            if dokumIsi.calisiyor {
                if dokumIsi.toplam > 0 {
                    ProgressView(value: Double(dokumIsi.biten), total: Double(dokumIsi.toplam)) {
                        Text("Parça \(min(dokumIsi.biten + 1, dokumIsi.toplam)) / \(dokumIsi.toplam) çözülüyor")
                    }
                } else {
                    ProgressView { Text("Kayıt hazırlanıyor…") }
                }
                Button("Dökümü durdur", role: .cancel) { dokumIsi.iptal() }
            }
            if let h = dokumIsi.hata { Text(h).font(.footnote).foregroundStyle(.red) }
        }
    }

    private var kayitlarBolumu: some View {
        Section {
            ForEach(kayitlar, id: \.self) { url in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.gorunenAd(url))
                        if FileManager.default.fileExists(atPath: SesKaydedici.dokumYolu(url).path) {
                            Text("Döküm hazır").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Menu {
                        Button { dokumuBaslat(url) } label: { Label("Tutanak hazırla", systemImage: "doc.text") }
                            .disabled(dokumIsi.calisiyor || kaydedici.suruyor)
                        ShareLink(item: url) { Label("Sesi paylaş", systemImage: "square.and.arrow.up") }
                        let txt = SesKaydedici.dokumYolu(url)
                        if FileManager.default.fileExists(atPath: txt.path) {
                            ShareLink(item: txt) { Label("Dökümü paylaş", systemImage: "doc.plaintext") }
                        }
                        Button(role: .destructive) { sil(url) } label: { Label("Sil", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle").frame(width: 40, height: 40)
                    }
                    .accessibilityLabel("Kayıt işlemleri")
                }
                .accessibilityIdentifier("kayit-satiri")
                .swipeActions {
                    Button(role: .destructive) { sil(url) } label: { Label("Sil", systemImage: "trash") }
                }
            }
        } header: {
            Text("Kayıtlar")
        } footer: {
            Text("Kayıtlar ve dökümler yalnız bu telefonda, iCloud yedeği dışında saklanır.")
        }
    }

    // MARK: İşler

    private func baslat() async {
        guard riza, !baslatiliyor else { return }
        baslatiliyor = true; defer { baslatiliyor = false }
        // Eller serbest / uyandırma / Live mikrofonu tutuyorsa AVAudioRecorder ile çakışır: önce kapanır.
        // Bitince eski kip kendiliğinden açılmaz; kullanıcı açar.
        await ses.sesliKipiKapat(isaret: false)
        await ses.uyandirmayiDurdur()
        await kaydedici.basla()
    }

    private func sil(_ url: URL) {
        kaydedici.sil(url)
        kayitlar = SesKaydedici.kayitlar()
    }

    private func dokumuBaslat(_ url: URL) {
        dokumIsi.baslat(url) { dokum in
            guard beyin.durum == .bosta else {
                dokumIsi.hata = "Asistan şu an meşgul; yanıt bitince 'Tutanak hazırla' ile yeniden dene (döküm kaydedildi)."
                return
            }
            let txt = SesKaydedici.dokumYolu(url)
            beyin.gonder(ToplantiDokumIsi.istem(kayit: Self.gorunenAd(url)),
                         belge: ToplantiDokumu.belgeMetni(dokum, dosyaAdi: txt.lastPathComponent),
                         gorunenMetin: "Toplantı dökümünden tutanak hazırla (\(Self.gorunenAd(url)))")
            kaydedici.sifirla()
            // Üst sayfa verdiyse o kapatır (bütün yığın iner); yoksa yalnız bu sayfa.
            if let gonderildi { gonderildi() } else { kapat() }
        }
    }

    // MARK: Biçim

    nonisolated static func sureMetni(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// "2026-10-20-1405" → "20.10.2026 14:05"; çözülemezse dosya adı.
    nonisolated static func gorunenAd(_ url: URL) -> String {
        let ad = url.deletingPathExtension().lastPathComponent
        let p = ad.split(separator: "-")
        guard p.count >= 4, p[0].count == 4, p[3].count >= 4 else { return ad }
        let saat = p[3].prefix(4)
        let ek = ad.contains("_") ? " (" + (ad.split(separator: "_").last.map(String.init) ?? "") + ")" : ""
        return "\(p[2]).\(p[1]).\(p[0]) \(saat.prefix(2)):\(saat.suffix(2))" + ek
    }
}

/// Döküm işi: kayıt ekranı kapansa da (kapatma döküm sürerken engelli) durum tek yerde.
@MainActor @Observable
final class ToplantiDokumIsi {
    static let ortak = ToplantiDokumIsi()
    private(set) var biten = 0
    private(set) var toplam = 0
    private(set) var islenen: URL?
    var hata: String?
    @ObservationIgnored private var gorev: Task<Void, Never>?

    var calisiyor: Bool { islenen != nil }

    /// Sohbete giden istem (dökümün kendisi belge olarak gider).
    nonisolated static func istem(kayit: String) -> String {
        "Ekteki toplantı dökümünden (\(kayit) kaydı) tutanak hazırla: tarih, katılımcılar, gündem, alınan kararlar ve sorumlu + son tarihli eylem maddeleri. Dökümde olmayanı uydurma. ofisBelgesiOlustur ile DOCX üret ve son tarihli eylem maddelerini hatırlatıcıya ekle."
    }

    /// Döküm daha önce çıkarıldıysa (.txt) yeniden ağa gidilmez.
    func baslat(_ url: URL, bitince: @escaping @MainActor (String) -> Void) {
        guard gorev == nil else { return }
        hata = nil; biten = 0; toplam = 0; islenen = url
        gorev = Task { await self.calistir(url, bitince: bitince) }
    }

    private func calistir(_ url: URL, bitince: @MainActor (String) -> Void) async {
        defer { gorev = nil; islenen = nil }
        do {
            let txt = SesKaydedici.dokumYolu(url)
            let dokum: String
            if let eski = try? String(contentsOf: txt, encoding: .utf8),
               !eski.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                dokum = eski
            } else {
                guard WhisperIstemcisi.kullanilabilir else {
                    hata = "Sunucu bağlantısı yok; döküm için CLIProxy sunucu bağlantısı gerekir."
                    return
                }
                dokum = try await ToplantiDokumu.cozumle(url, ilerleme: { b, t in
                    Task { @MainActor in ToplantiDokumIsi.ortak.ilerle(b, t) }
                })
            }
            guard !dokum.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                hata = "Kayıtta anlaşılır konuşma bulunamadı."
                return
            }
            try Task.checkCancellation()
            bitince(dokum)
        } catch is CancellationError {
            hata = "Döküm durduruldu."
        } catch {
            hata = error.localizedDescription
        }
    }

    func iptal() { gorev?.cancel() }

    private func ilerle(_ b: Int, _ t: Int) { biten = b; toplam = t }
}
