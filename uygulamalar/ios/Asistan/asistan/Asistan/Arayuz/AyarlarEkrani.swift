import SwiftUI

/// P2.4: kökte Kurulum durumu + altı başlık (Asistan, Model, Ses ve Live, Görünüm, Hafıza, Bağlantı ve kota) +
/// katlanmış Gelişmiş + Hakkında. Alt sayfalar `AyarlarBolumleri.swift`'te; arama `AyarDizini.ara` ile.
struct AyarlarEkrani: View {
    @Environment(\.dismiss) private var kapat
    @State private var sorgu = ""
    @State private var gelismisAcik = false

    private var aramaBos: Bool { sorgu.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollViewReader { vekil in
            Form {
                if aramaBos {
                    anaBolumler
                    // Telefondaki sürüm şüpheliyse ilk bakılacak yer: kurulum defterindeki satırla karşılaştırılır.
                    Section("Hakkında") { HakkindaSatirlari() }
                    #if DEBUG
                    // P3.10-arıza: yalnız Debug kurulumda; Release/TestFlight'ta bu bölüm yoktur.
                    GelistiriciBolumu()
                    #endif
                } else {
                    aramaSonuclari
                }
            }
            .navigationTitle("Ayarlar")
            // Alan her zaman görünür: UI testi ve kullanıcı aşağı çekmeden bulur.
            .searchable(text: $sorgu, placement: .navigationBarDrawer(displayMode: .always), prompt: "Ayarlarda ara")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { kapat() } } }
            .task { await KurulumDurumu.ortak.yenile() }
            // Gelişmiş ekran altındayken açılan satırlar görüş alanının dışında kalıyordu: başlığı üste getir.
            .onChange(of: gelismisAcik) { _, acik in
                guard acik else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    withAnimation { vekil.scrollTo("ayarlar-gelismis", anchor: .top) }
                }
            }
            }
        }
        // Ayarlar bir sheet; sohbetteki tost katmanı sayfanın altında kalır. Alt sayfaların tostları burada görünür.
        .overlay(alignment: .bottom) { TostKatmani().padding(.bottom, 24) }
    }

    // MARK: Kök

    @ViewBuilder
    private var anaBolumler: some View {
        Section {
            NavigationLink { KurulumEkrani() } label: { KurulumSatiri() }
                .accessibilityIdentifier("ayarlar-kurulum")
        }
        Section {
            ForEach(AyarBolumu.anaBasliklar, id: \.self) { b in
                NavigationLink { AyarBolumSayfasi(bolum: b) } label: { Label(b.baslik, systemImage: b.simge) }
                    .accessibilityIdentifier("ayarlar-bolum-\(b.rawValue)")
            }
            // P4.4: Spotlight (sohbet/dosya) ve fotoğraf metni indeksi.
            NavigationLink { SistemAramasiAyarlari() } label: { Label("Sistem araması", systemImage: "magnifyingglass.circle") }
                .accessibilityIdentifier("ayarlar-sistem-aramasi")
            // P4.7: sürüş kipi (CarPlay'de otomatik, araç kitinde elle; ertelenen istekler).
            NavigationLink { SurusKipiAyarlari() } label: { Label("Sürüş kipi", systemImage: "car") }
                .accessibilityIdentifier("ayarlar-surus-kipi")
            // P3.3: yanıt kalitesi özeti ve değerlendirme seti (paylaşılabilir JSON).
            NavigationLink { KaliteEkrani() } label: { Label("Kalite ve değerlendirme", systemImage: "checkmark.bubble") }
                .accessibilityIdentifier("ayarlar-kalite")
        }
        Section {
            // DisclosureGroup yerine düğme: başlığa kimlik verilebilir ve dokunuş her iOS sürümünde aynı davranır.
            Button { withAnimation { gelismisAcik.toggle() } } label: {
                HStack {
                    Label(AyarBolumu.gelismis.baslik, systemImage: AyarBolumu.gelismis.simge).foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(gelismisAcik ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .id("ayarlar-gelismis")
            .accessibilityIdentifier("ayarlar-gelismis")
            .accessibilityValue(gelismisAcik ? "açık" : "kapalı")
            .accessibilityHint("Sağlık, çökme kayıtları, Nabız, MCP ve indirme motoru")
            if gelismisAcik { GelismisSatirlari() }
        }
    }

    // MARK: Arama

    @ViewBuilder
    private var aramaSonuclari: some View {
        let sonuclar = AyarDizini.ara(sorgu)
        if sonuclar.isEmpty {
            ContentUnavailableView.search(text: sorgu)
        } else {
            Section {
                // Gelişmiş öğeleri de doğrudan açılır; katlı grubu açmak gerekmez.
                ForEach(sonuclar) { o in
                    NavigationLink { AyarHedefEkrani(oge: o) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(o.baslik)
                            Text(o.etiket ?? o.bolum.baslik).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("ayar-sonuc-\(o.id)")
                }
            }
        }
    }

    // MARK: Yedek dışlama

    /// Dosyayı iCloud/bilgisayar yedeğinden dışlar; başarıyı döndürür. (İndirme motoru `GelismisIndirmeMotoru`'na
    /// taşındı; bu yardımcı Duzeltme2K9 testi ve çerez yazımı için burada kalır.)
    nonisolated static func yedektenDisla(_ url: URL) -> Bool {
        var u = url
        var d = URLResourceValues(); d.isExcludedFromBackup = true
        do { try u.setResourceValues(d); return true } catch { return false }
    }
}

/// Sürüm satırları: Ayarlar kökündeki "Hakkında" bölümü ve arama sonucunun açtığı sayfa aynı satırları kullanır.
struct HakkindaSatirlari: View {
    var body: some View {
        // Telefondaki sürüm şüpheliyse ilk bakılacak yer: kurulum defterindeki satırla karşılaştırılır.
        Group {
            LabeledContent("Sürüm", value: SurumBilgisi.simdiki.kisa)
                .accessibilityIdentifier("surum-satiri")
            LabeledContent("Derleme", value: SurumBilgisi.simdiki.derlemeOzeti)
                .accessibilityIdentifier("derleme-satiri")
            if let tarih = SurumBilgisi.simdiki.derlemeTarihi {
                LabeledContent("Derlendi", value: tarih.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .textSelection(.enabled)
    }
}

struct HakkindaSayfasi: View {
    var body: some View {
        Form { Section { HakkindaSatirlari() } }
            .navigationTitle("Hakkında")
    }
}
