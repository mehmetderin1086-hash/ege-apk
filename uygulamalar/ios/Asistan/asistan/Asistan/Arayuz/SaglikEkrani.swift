import SwiftUI

struct SaglikEkrani: View {
    @Environment(Beyin.self) private var beyin
    @State private var merkez = SaglikMerkezi.ortak
    @State private var baglanti = BaglantiDurumu.ortak
    /// Ayrıntılı tanının bitişi (TaniGunlugu'nun kendi UserDefaults anahtarı; ekran açılırken okunur).
    @State private var ayrintiliBitis = TaniGunlugu.ayrintiliBitis
    @State private var paketURL: URL?
    @State private var paketHazirlaniyor = false
    @State private var paketHatasi: String?

    var body: some View {
        List {
            Section("Bileşenler") {
                if merkez.denetimler.isEmpty && merkez.denetleniyor { ProgressView("Denetleniyor…") }
                ForEach(merkez.denetimler) { d in
                    HStack(alignment: .top) {
                        Image(systemName: simge(d.durum)).foregroundStyle(renk(d.durum))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(d.baslik).font(.headline)
                            Text(d.ayrinti).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                Button(merkez.denetleniyor ? "Denetleniyor…" : "Şimdi yeniden denetle") {
                    Task { await merkez.denetle(zorla: true) }
                }.disabled(merkez.denetleniyor)
            }
            Section("Son \(SaglikMerkezi.sinir) işlemde hız") {
                ForEach(turler, id: \.0) { tur, ad in
                    if let o = merkez.ozet(tur) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(ad); Spacer(); Text(sure(o.ortalamaMs)).monospacedDigit() }
                            Text("medyan \(sure(o.medyanMs)) · p90 \(sure(o.p90Ms)) · p95 \(sure(o.p95Ms)) · \(o.adet) örnek · %\(Int(o.basariOrani * 100)) başarılı")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        LabeledContent(ad, value: "Henüz ölçülmedi").foregroundStyle(.secondary)
                    }
                }
                Text("Hız geçmişinde yalnız süre, başarı ve model/ses adı tutulur. Tanı günlüğünde hata türleri, süreler ve model adları bulunur; istek içeriği yalnız 'Ayrıntılı tanı' açıkken 24 saat yazılır. E-posta, telefon ve anahtar biçimleri maskelenir; günlük telefonda kalır, yedeğe girmez.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Hız geçmişini temizle", role: .destructive) { merkez.temizle() }
                    .disabled(merkez.olcumler.isEmpty)
            }
            baglantiBolumu
            askiBolumu
            taniBolumu
        }
        .navigationTitle("Sağlık ve hız")
        .task { await merkez.denetle() }
    }

    // MARK: Bağlantı halkaları ve askılar (P3.7)

    @ViewBuilder private var baglantiBolumu: some View {
        Section {
            ForEach(BaglantiDurumu.Halka.allCases, id: \.self) { h in
                let hal = baglanti.haller[h] ?? .bilinmiyor
                HStack(alignment: .top) {
                    Image(systemName: h.simge).foregroundStyle(halRengi(hal)).frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(h.ad).font(.headline)
                        Text(hal.metin).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if let s = baglanti.sonYoklama {
                Text("Son yoklama: \(Text(s, style: .relative)) önce").font(.footnote).foregroundStyle(.secondary)
            }
            Button(baglanti.yoklaniyor ? "Yoklanıyor…" : "Şimdi yokla") {
                Task { await baglanti.yokla() }
            }.disabled(baglanti.yoklaniyor)
        } header: {
            Text("Bağlantı halkaları")
        } footer: {
            Text("Sunucu (VPS) erişilemezken zincir sunucu yolunu atlar; telefon yolu ve API anahtarı denenir.")
        }
        .accessibilityIdentifier("baglanti-halkalari")
    }

    @ViewBuilder private var askiBolumu: some View {
        let satirlar = Self.askiSatirlari(rota: beyin.askilar, yol: beyin.modelVitesi.yolAskilari,
                                          genel: beyin.modelVitesi.modelGeneliAskilar)
        Section("Askıdaki rotalar ve modeller") {
            if satirlar.isEmpty {
                Text("Askıda rota ya da model yok.").foregroundStyle(.secondary)
            }
            ForEach(satirlar) { s in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.baslik)
                        Text("\(KotaOzeti.sureMetni(s.kalanSn)) kaldı").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Kaldır") { beyin.askiKaldir(s.id) }.buttonStyle(.borderless)
                }
                .swipeActions { Button("Kaldır", role: .destructive) { beyin.askiKaldir(s.id) } }
            }
            if satirlar.count > 1 {
                Button("Hepsini kaldır", role: .destructive) { beyin.modelVitesi.tumAskilariKaldir() }
            }
        }
        .accessibilityIdentifier("aski-listesi")
    }

    nonisolated struct AskiSatiri: Identifiable, Equatable, Sendable {
        /// Kaldırma anahtarı: rota adı, "model|yol" ya da model.
        let id: String
        let baslik: String
        let kalanSn: Int
    }

    /// Süresi geçmemiş askılar, en uzun kalan önce (saf).
    nonisolated static func askiSatirlari(rota: [ModelZinciri.Yol: Date], yol: [String: Date], genel: [String: Date],
                                          simdi: Date = .now) -> [AskiSatiri] {
        var s: [AskiSatiri] = []
        for (r, t) in rota where t > simdi {
            s.append(AskiSatiri(id: r.rawValue, baslik: "Rota: \(r.ad) (bütün modeller)", kalanSn: Int(t.timeIntervalSince(simdi))))
        }
        for (anahtar, t) in yol where t > simdi {
            let p = anahtar.split(separator: "|", maxSplits: 1).map(String.init)
            let yolAdi = p.count == 2 ? (ModelZinciri.Yol(rawValue: p[1])?.ad ?? p[1]) : ""
            s.append(AskiSatiri(id: anahtar, baslik: "\(Beyin.modelEtiketi(p.first ?? anahtar)) · \(yolAdi)", kalanSn: Int(t.timeIntervalSince(simdi))))
        }
        for (m, t) in genel where t > simdi {
            s.append(AskiSatiri(id: m, baslik: "\(Beyin.modelEtiketi(m)) (bütün yollar)", kalanSn: Int(t.timeIntervalSince(simdi))))
        }
        return s.sorted { $0.kalanSn == $1.kalanSn ? $0.id < $1.id : $0.kalanSn > $1.kalanSn }
    }

    private func halRengi(_ h: BaglantiDurumu.Hal) -> Color {
        switch h {
        case .iyi: .green
        case .yok: .red
        case .bilinmiyor, .yapilandirilmamis: .secondary
        }
    }

    // MARK: Tanı günlüğü (P2.15)

    private var ayrintiliAcik: Binding<Bool> {
        Binding(get: { (ayrintiliBitis ?? .distantPast) > .now },
                set: { acik in
                    ayrintiliBitis = acik ? Date.now.addingTimeInterval(86_400) : nil
                    TaniGunlugu.ayrintiliBitis = ayrintiliBitis
                    TaniGunlugu.yaz("TANI: ayrıntılı tanı \(acik ? "açıldı (24 saat)" : "kapatıldı")")
                })
    }

    @ViewBuilder private var taniBolumu: some View {
        Section("Tanı günlüğü") {
            Toggle("Ayrıntılı tanı (24 saat)", isOn: ayrintiliAcik)
                .accessibilityIdentifier("tani-ayrintili")
            if let bitis = ayrintiliBitis, bitis > .now {
                Text("Kalan süre: \(Text(bitis, style: .relative)) · istek metinleri de yazılıyor (maskeli).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            NavigationLink("Günlüğü göster") { TaniGoruntuleyici() }
                .accessibilityIdentifier("tani-gunlugu-goster")
            Button {
                Task { await paketOlustur() }
            } label: {
                HStack {
                    Text(paketHazirlaniyor ? "Tanı paketi hazırlanıyor…" : "Tanı paketi oluştur")
                    if paketHazirlaniyor { Spacer(); ProgressView() }
                }
            }
            .disabled(paketHazirlaniyor)
            .accessibilityIdentifier("tani-paketi-olustur")
            if let paketURL {
                ShareLink(item: paketURL) {
                    Label("Paylaş: \(paketURL.lastPathComponent)", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("tani-paketi-paylas")
            }
            if let paketHatasi {
                Text(paketHatasi).font(.footnote).foregroundStyle(.red)
            }
            Text("Paket maskeli tani.log, tani.1.log ve cihaz/sürüm özetini içerir; anahtar ve sohbet içeriği girmez. Yalnız sen paylaşırsan telefondan çıkar.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func paketOlustur() async {
        paketHazirlaniyor = true
        paketHatasi = nil
        paketURL = nil
        defer { paketHazirlaniyor = false }
        do {
            paketURL = try await TaniPaketi.olustur(ozet: TaniPaketi.ozetMetni())
        } catch {
            paketHatasi = "Tanı paketi oluşturulamadı: \(error.localizedDescription)"
        }
    }

    private let turler = [("model_ilk_metin", "Model ilk yanıt"), ("model_toplam", "Model toplam yanıt"),
                           ("web_arastirma", "Web araştırması"), ("istem_suzgeci", "İstem süzgeci"),
                           ("stt", "Konuşmayı yazıya çevirme"), ("tts", "Ses üretimi"),
                           ("ses_tur", "Söz bitti → ilk ses"), ("ses_tur_bekleme", "Konuşma sonu bekleme"),
                           ("ses_tur_model", "Sesli turda model ilk metin"), ("ses_tur_tts", "İlk sesin üretimi"),
                           // P3.9: soğuk açılış (AcilisOlcer; süreç başlangıcından).
                           ("acilis_ilk_kare", "Açılış (ilk kare)"), ("acilis_proxy_hazir", "Açılış (istek hazır)")]
    private func sure(_ ms: Double) -> String { ms < 1000 ? "\(Int(ms)) ms" : String(format: "%.2f sn", ms / 1000) }
    private func simge(_ d: SaglikMerkezi.Denetim.Durum) -> String {
        switch d { case .iyi: "checkmark.circle.fill"; case .uyari: "exclamationmark.triangle.fill"; case .hata: "xmark.octagon.fill" }
    }
    private func renk(_ d: SaglikMerkezi.Denetim.Durum) -> Color {
        switch d { case .iyi: .green; case .uyari: .orange; case .hata: .red }
    }
}
