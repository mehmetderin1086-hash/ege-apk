import SwiftUI

struct AtolyeEkrani: View {
    @Environment(Ayarlar.self) private var ayarlar
    @Environment(Beyin.self) private var beyin
    @Environment(\.dismiss) private var kapat
    @State private var sunucuAcik = false
    @State private var gorselAcik = false
    @State private var gecmisAcik = false
    @State private var uzmanlarAcik = false
    @State private var calismaAcik = false

    var body: some View {
        @Bindable var a = ayarlar
        NavigationStack {
            List {
                Section("Çalışma biçimi") {
                    Picker("Kip", selection: $a.calismaKipi) {
                        Text("Otomatik · isteğine göre").tag("otomatik")
                        Text("Sesli asistan").tag("sohbet")
                        Text("Araştırma").tag("arastirma")
                        Text("Kod yardımcısı").tag("kod")
                        Text("Yazı atölyesi").tag("yazi")
                    }
                    if a.calismaKipi == "otomatik" {
                        Text("Yazdığın veya söylediğin isteğe göre kip seçilir. Devam mesajlarında sohbetin bağlamı kullanılır. Görsel üretimi ve arşiv istekleri ilgili ekranı açar.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("Kod ve yazı kiplerinde ayrıntılı yanıt alırsın. Kodlama istekleri sunucu CLIProxy’sine gider; Python kodu izole ortamda çalıştırılıp sonucu gösterilir.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if a.calismaKipi == "arastirma" {
                        Text("Web araması Ayarlar'dan açılır. Kaynak araştırması CLIProxy'deki ChatGPT hesabıyla yapılır; raporu seçtiğin sohbet modeli hazırlar.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Üret ve incele") {
                    NavigationLink { CalismaMerkezi() } label: { Label("Çalışma alanı ve Tuval", systemImage: "rectangle.3.group") }.accessibilityIdentifier("atolye-calisma")
                    Button { uzmanlarAcik = true } label: { Label("Uzmanlar ve beceriler", systemImage: "person.3.sequence") }
                    Button { sunucuAcik = true } label: { Label("Sunucu görevleri", systemImage: "server.rack") }
                    Button { gorselAcik = true } label: { Label("Görsel üret", systemImage: "photo.badge.sparkles") }
                    Label("Sohbette + düğmesi: PDF, metin, CSV, kod dosyası ve fotoğraf", systemImage: "doc.text")
                    Button { gecmisAcik = true } label: { Label("Sohbet arşivi", systemImage: "clock.arrow.circlepath") }
                }
                Section("Bağlı model aileleri") {
                    ForEach(["Claude", "ChatGPT / Codex", "Gemini", "Grok"], id: \.self) { aile in
                        let sayi = TelefonProxy.ortak.modeller.filter { $0.aile == aile && $0.sohbet }.count
                        LabeledContent(aile, value: sayi > 0 ? "\(sayi) model listeleniyor" : "Bağlı model bulunamadı")
                    }
                    Text("Ana kullanım iPhone üzerindedir. Kodlama işleri otomatik sunucuya gider; diğer uzun işler açıkça istediğinde sunucuda sürer. Python için sınırlı çalıştırma ortamı vardır. Grok, video üretimi ve diğer sağlayıcı araçları ayrıca hesap/API desteği gerektirir; model listesi bu erişimi garanti etmez.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Atölye")
            .task(id: CalismaSunucusu.ortak.bildirimGorevi) { if CalismaSunucusu.ortak.bildirimGorevi != nil { calismaAcik = true } }
            .navigationDestination(isPresented: $calismaAcik) { CalismaMerkezi() }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { kapat() } } }
            .sheet(isPresented: $sunucuAcik) { SunucuGorevEkrani() }
            .sheet(isPresented: $gorselAcik) { GorselEkrani() }
            .sheet(isPresented: $gecmisAcik) { GecmisEkrani() }
            .sheet(isPresented: $uzmanlarAcik) { GrokYetenekleriEkrani() }
        }
    }
}

struct GecmisEkrani: View {
    @Environment(Beyin.self) private var beyin
    @Environment(\.dismiss) private var kapat
    @State private var sorgu = ""
    /// Liste açılışta bir kez yüklenir; body her tuşta SwiftData sorgusu çalıştırmaz.
    @State private var sohbetler: [Sohbet] = []
    @State private var gorunen: [Sohbet] = []
    @State private var yuklendi = false
    /// Sohbet başına normalize edilmiş birleşik mesaj metni; ilk içerik aramasında bir kez üretilir
    /// (liste sayfa açıkken değişmez; her aramada 1000 sohbetin ilişkisi açılıp yeniden taranmıyor).
    @State private var icerik: [UUID: String] = [:]
    static let sinir = 1000

    var body: some View {
        NavigationStack {
            List {
                ForEach(gorunen, id: \.kimlik) { sohbet in
                    NavigationLink {
                        SohbetDokumu(sohbet: sohbet)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(sohbet.baslik)
                            Text(sohbet.olusturma, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if sohbetler.count >= Self.sinir {
                    Text("En yeni \(Self.sinir) sohbet listeleniyor ve aranıyor.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .overlay {
                if yuklendi, gorunen.isEmpty {
                    if sorgu.isEmpty { ContentUnavailableView("Henüz sohbet yok", systemImage: "clock.arrow.circlepath") } else { ContentUnavailableView.search(text: sorgu) }
                }
            }
            .task {
                guard !yuklendi else { return }
                sohbetler = beyin.depo.sonSohbetler(Self.sinir)
                gorunen = sohbetler
                yuklendi = true
            }
            .task(id: sorgu) {
                guard yuklendi else { return }
                if !sorgu.isEmpty {
                    try? await Task.sleep(for: .milliseconds(250))   // her harfte değil, yazma durunca ara
                    guard !Task.isCancelled else { return }
                }
                let q = GecmisArama.normalize(sorgu).trimmingCharacters(in: .whitespaces)
                guard !q.isEmpty else { gorunen = sohbetler; return }
                if icerik.isEmpty {   // SwiftData modelleri Sendable değil: ana aktörde bir kez okunur, yalnız metin kopyalanır
                    var yeni: [UUID: String] = [:]
                    for s in sohbetler { yeni[s.kimlik] = GecmisArama.normalize(s.mesajlar.map(\.metin).joined(separator: "\n")) }
                    icerik = yeni
                }
                let basliklar = sohbetler.map { ($0.kimlik, $0.baslik) }
                let tablo = icerik
                let eslesen = await Task.detached(priority: .userInitiated) { GecmisEkrani.eslesenler(basliklar, icerik: tablo, sorgu: q) }.value
                guard !Task.isCancelled else { return }
                gorunen = sohbetler.filter { eslesen.contains($0.kimlik) }
            }
            .searchable(text: $sorgu, prompt: "Başlık veya mesajlarda ara")
            .navigationTitle("Sohbet arşivi")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { kapat() } } }
        }
    }

    /// Başlıkta ya da herhangi bir mesajda geçiyorsa eşleşir (sorgu boşsa hepsi).
    nonisolated static func eslesir(baslik: String, metinler: [String], sorgu: String) -> Bool {
        sorgu.isEmpty || baslik.localizedStandardContains(sorgu) || metinler.contains { $0.localizedStandardContains(sorgu) }
    }

    /// Önbellekli arama: `q` normalize edilmiş sorgu (`GecmisArama.normalize`, Türkçe harf/büyüklük duyarsız), `icerik` normalize edilmiş mesaj metni.
    nonisolated static func eslesenler(_ basliklar: [(UUID, String)], icerik: [UUID: String], sorgu q: String) -> Set<UUID> {
        guard !q.isEmpty else { return Set(basliklar.map { $0.0 }) }
        return Set(basliklar.filter { GecmisArama.normalize($0.1).contains(q) || (icerik[$0.0]?.contains(q) ?? false) }.map { $0.0 })
    }
}

/// Arşivdeki tek sohbetin dökümü: sıralama ve paylaşım metni yalnız açılınca üretilir (satır başına değil).
private struct SohbetDokumu: View {
    let sohbet: Sohbet

    var body: some View {
        let sirali = sohbet.mesajlar.sorted { $0.zaman < $1.zaman }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(sirali, id: \.kimlik) { m in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(m.rol == .kullanici ? "Sen" : "Asistan").font(.caption.bold()).foregroundStyle(.secondary)
                        Text(m.metin).textSelection(.enabled)
                    }
                }
            }.padding()
        }.navigationTitle(sohbet.baslik)
        .toolbar { ShareLink(item: sirali.map { ($0.rol == .kullanici ? "Sen" : "Asistan") + ":\n" + $0.metin }.joined(separator: "\n\n")) { Label("Sohbeti paylaş", systemImage: "square.and.arrow.up") } }
    }
}
