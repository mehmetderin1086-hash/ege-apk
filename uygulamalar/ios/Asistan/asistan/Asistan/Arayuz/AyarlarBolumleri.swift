import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// P2.4: Ayarlar altı başlığa (Asistan, Model, Ses ve Live, Görünüm, Hafıza, Bağlantı ve kota) ve katlanmış
// Gelişmiş'e bölündü. Yeni ayar eklerken ilgili alt sayfaya koy ve `AyarDizini.hepsi`'ne anahtar sözcükleriyle yaz
// (Ayarlar'daki arama yalnız dizinde olanı bulur).

// MARK: - Dizin (saf, birim testli)

nonisolated enum AyarBolumu: String, CaseIterable, Sendable {
    case asistan, model, sesLive, gorunum, hafiza, baglanti, gelismis

    var baslik: String {
        switch self {
        case .asistan: "Asistan"
        case .model: "Model"
        case .sesLive: "Ses ve Live"
        case .gorunum: "Görünüm"
        case .hafiza: "Hafıza"
        case .baglanti: "Bağlantı ve kota"
        case .gelismis: "Gelişmiş"
        }
    }

    var simge: String {
        switch self {
        case .asistan: "person.crop.circle"
        case .model: "cpu"
        case .sesLive: "waveform"
        case .gorunum: "paintpalette"
        case .hafiza: "brain.head.profile"
        case .baglanti: "network"
        case .gelismis: "wrench.and.screwdriver"
        }
    }

    /// Ayarlar kökündeki altı başlık; Gelişmiş ayrı, katlanmış durur.
    static var anaBasliklar: [AyarBolumu] { allCases.filter { $0 != .gelismis } }
}

/// Arama sonucuna dokununca açılacak ekran. `.bolum` öğenin bulunduğu alt sayfayı açar.
nonisolated enum AyarHedefi: Sendable, Equatable {
    case bolum, izinler, gorunum, komutlar, imza, uyandirma, dikteSozlugu
    case hafiza, beceriler, calismaAlani, kullanim
    case saglik, izleme, nabiz, mcp, indirmeMotoru, kurulum
    case kalite, sistemAramasi, surusKipi, hakkinda
}

nonisolated struct AyarOgesi: Identifiable, Sendable {
    let id: String
    let baslik: String
    let bolum: AyarBolumu
    let anahtarlar: [String]
    var hedef: AyarHedefi = .bolum
    /// Arama sonucunda bölüm adı yerine gösterilen konum: öğe bir bölüm sayfasında değil, Ayarlar kökündeyse "Ayarlar".
    var etiket: String? = nil
}

nonisolated enum AyarDizini {
    static let hepsi: [AyarOgesi] = [
        // Asistan
        AyarOgesi(id: "dost-adi", baslik: "Dostunun adı ve konuşma tarzı", bolum: .asistan,
                  anahtarlar: ["ad", "isim", "tarz", "samimi", "sakin", "neşeli", "kişiselleştir"]),
        AyarOgesi(id: "izinler", baslik: "İzinler", bolum: .asistan,
                  anahtarlar: ["izin", "mikrofon", "takvim", "kişiler", "konum", "kamera", "fotoğraf", "bildirim"], hedef: .izinler),
        AyarOgesi(id: "komutlar", baslik: "Komutlarım ve kaydedilenler", bolum: .asistan,
                  anahtarlar: ["komut", "kaydedilen", "kısayol", "kişisel alan"], hedef: .komutlar),
        AyarOgesi(id: "imzam", baslik: "İmzam", bolum: .asistan, anahtarlar: ["imza", "pdf imzala"], hedef: .imza),
        AyarOgesi(id: "istem-suzgeci", baslik: "İstem süzgeci", bolum: .asistan,
                  anahtarlar: ["süzgeç", "anlama", "dikte düzeltme", "kısıt"]),
        AyarOgesi(id: "arac-gruplama", baslik: "Araçları işe göre seç (deneysel)", bolum: .asistan,
                  anahtarlar: ["araç", "araç grubu", "yönlendirme", "deneysel", "süzgeç"]),
        AyarOgesi(id: "uyandirma", baslik: "Hey Asistan ve diğer uygulamalardan erişim", bolum: .asistan,
                  anahtarlar: ["hey asistan", "siri", "kestirme", "kontrol merkezi", "arkaya dokun", "eylem düğmesi", "tetik", "arka plan", "kilit ekranı"], hedef: .uyandirma),
        AyarOgesi(id: "kurulum", baslik: "Kurulum durumu", bolum: .asistan,
                  anahtarlar: ["kurulum", "eksik", "başlangıç", "hazırlık", "denetle"], hedef: .kurulum),
        // Model
        AyarOgesi(id: "otomatik-model", baslik: "İşe göre otomatik model", bolum: .model,
                  anahtarlar: ["otomatik", "vites", "model seçimi"]),
        AyarOgesi(id: "model", baslik: "Model", bolum: .model,
                  anahtarlar: ["model", "claude", "chatgpt", "gemini", "grok", "yedek model"]),
        AyarOgesi(id: "caba", baslik: "Düşünme çabası", bolum: .model, anahtarlar: ["çaba", "düşünme", "effort"]),
        AyarOgesi(id: "antigravity", baslik: "Önce Antigravity hesabını kullan", bolum: .model,
                  anahtarlar: ["antigravity", "öncelik", "hesap"]),
        AyarOgesi(id: "web-arama", baslik: "Web araması", bolum: .model, anahtarlar: ["web", "arama", "araştırma", "internet"]),
        // Ses ve Live
        AyarOgesi(id: "soz-kesme", baslik: "Konuşurken sözünü kesebilirim", bolum: .sesLive, anahtarlar: ["söz kesme", "araya girme", "sustur"]),
        AyarOgesi(id: "stt", baslik: "Konuşma tanıma", bolum: .sesLive,
                  anahtarlar: ["stt", "whisper", "yazıya çevir", "apple", "cihaz içi"]),
        AyarOgesi(id: "whisper-modeli", baslik: "Whisper modeli", bolum: .sesLive, anahtarlar: ["whisper", "model indir", "çevrimdışı"]),
        AyarOgesi(id: "sesli-yanit", baslik: "Yanıtları sesli oku", bolum: .sesLive, anahtarlar: ["sesli", "oku", "tts"]),
        AyarOgesi(id: "isaret-sesleri", baslik: "İşaret sesleri", bolum: .sesLive, anahtarlar: ["ton", "bip", "dinliyorum", "aldım"]),
        // P3.12 (SesHattiAyarlari.swift)
        AyarOgesi(id: "kulaklik-mikrofonu", baslik: "Kulaklık mikrofonu", bolum: .sesLive,
                  anahtarlar: ["airpods", "kulaklık", "bluetooth", "hfp", "mikrofon yolu"]),
        AyarOgesi(id: "kulaklik-dugmesi", baslik: "Kulaklık düğmesi", bolum: .sesLive,
                  anahtarlar: ["airpods", "kulaklık", "düğme", "kumanda", "duraklat", "şu an çalan"]),
        AyarOgesi(id: "akilli-konusma-sonu", baslik: "Akıllı konuşma sonu", bolum: .sesLive,
                  anahtarlar: ["konuşma sonu", "sessizlik", "bekleme", "kesiyor", "erken gönder"]),
        AyarOgesi(id: "ilk-ses-hizli", baslik: "İlk sesi hızlı başlat", bolum: .sesLive, anahtarlar: ["ilk ses", "gecikme", "virgül"]),
        AyarOgesi(id: "okuma-hizi", baslik: "Okuma hızı", bolum: .sesLive, anahtarlar: ["hız", "okuma", "yavaş", "hızlı oku"]),
        AyarOgesi(id: "dikte-sozlugu", baslik: "Dikte sözlüğü", bolum: .sesLive,
                  anahtarlar: ["dikte", "sözlük", "düzeltme", "terim"], hedef: .dikteSozlugu),
        AyarOgesi(id: "ses-kimligi", baslik: "Asistanın sesi", bolum: .sesLive,
                  anahtarlar: ["ses", "elif", "azure", "tts", "konuşma sesi", "openai sesi"]),
        AyarOgesi(id: "live-motoru", baslik: "Live motoru", bolum: .sesLive,
                  anahtarlar: ["live", "canlı", "realtime", "gerçek zamanlı", "sesli diyalog"]),
        AyarOgesi(id: "openai-anahtari", baslik: "OpenAI anahtarı (Live)", bolum: .sesLive, anahtarlar: ["openai", "anahtar", "api"]),
        AyarOgesi(id: "live-arka-plan", baslik: "Live arka planda sürsün", bolum: .sesLive,
                  anahtarlar: ["arka plan", "kilit ekranı", "kilitliyken", "ekran kapalı", "canlı"]),
        // Görünüm
        AyarOgesi(id: "gorunum", baslik: "Görünüm stüdyosu", bolum: .gorunum,
                  anahtarlar: ["tema", "renk", "koyu", "açık", "yazı tipi", "balon", "sohbet teması", "görünüm"], hedef: .gorunum),
        // Hafıza
        AyarOgesi(id: "otomatik-hafiza", baslik: "Konuşmadan otomatik olgu çıkar", bolum: .hafiza, anahtarlar: ["olgu", "otomatik", "hafıza"]),
        AyarOgesi(id: "anlamsal-hafiza", baslik: "Anlamsal hafıza", bolum: .hafiza, anahtarlar: ["anlamsal", "gömme", "bge", "vektör"]),
        AyarOgesi(id: "hafiza", baslik: "Asistan seni böyle tanıyor", bolum: .hafiza,
                  anahtarlar: ["hafıza", "olgu", "profil", "günlük", "yedek", "geçmiş"], hedef: .hafiza),
        AyarOgesi(id: "beceriler", baslik: "Beceriler", bolum: .hafiza, anahtarlar: ["beceri", "skill"], hedef: .beceriler),
        AyarOgesi(id: "calisma-alani", baslik: "Çalışma alanı (SOUL · USER · AGENTS)", bolum: .hafiza,
                  anahtarlar: ["soul", "user", "agents", "profil", "kurallar"], hedef: .calismaAlani),
        // Bağlantı ve kota
        AyarOgesi(id: "proxy", baslik: "iPhone CLIProxy bağlantısı", bolum: .baglanti,
                  anahtarlar: ["bağlantı", "proxy", "cliproxy", "hesap", "sına"]),
        AyarOgesi(id: "kullanim", baslik: "Kullanım ve kota", bolum: .baglanti,
                  anahtarlar: ["kullanım", "kota", "istek sayısı", "sınır"], hedef: .kullanim),
        AyarOgesi(id: "kalite", baslik: "Kalite ve değerlendirme", bolum: .asistan,
                  anahtarlar: ["kalite", "beğeni", "değerlendirme", "geri bildirim"], hedef: .kalite, etiket: "Ayarlar"),
        AyarOgesi(id: "sistem-aramasi", baslik: "Sistem araması", bolum: .asistan,
                  anahtarlar: ["spotlight", "arama", "fotoğraf metni", "ocr", "galeri"], hedef: .sistemAramasi, etiket: "Ayarlar"),
        AyarOgesi(id: "surus-kipi", baslik: "Sürüş kipi", bolum: .asistan,
                  anahtarlar: ["sürüş", "carplay", "araç", "araba", "direksiyon", "ertelenen", "bluetooth"], hedef: .surusKipi, etiket: "Ayarlar"),
        AyarOgesi(id: "hakkinda", baslik: "Hakkında", bolum: .asistan,
                  anahtarlar: ["sürüm", "derleme", "versiyon", "build", "kurulum tarihi"], hedef: .hakkinda, etiket: "Ayarlar"),
        // Gelişmiş
        AyarOgesi(id: "saglik", baslik: "Sağlık ve hız merkezi", bolum: .gelismis,
                  anahtarlar: ["sağlık", "hız", "gecikme", "tanı", "ölçüm"], hedef: .saglik),
        AyarOgesi(id: "izleme", baslik: "Çökme ve performans", bolum: .gelismis,
                  anahtarlar: ["çökme", "performans", "crash", "izleme"], hedef: .izleme),
        AyarOgesi(id: "nabiz", baslik: "Nabız (proaktif kontrol)", bolum: .gelismis,
                  anahtarlar: ["nabız", "proaktif", "arka plan"], hedef: .nabiz),
        AyarOgesi(id: "mcp", baslik: "MCP sunucuları", bolum: .gelismis, anahtarlar: ["mcp", "sunucu", "eklenti"], hedef: .mcp),
        AyarOgesi(id: "yt-dlp", baslik: "İndirme motoru (yt-dlp)", bolum: .gelismis,
                  anahtarlar: ["yt-dlp", "youtube", "indirme", "motor", "python"], hedef: .indirmeMotoru),
        AyarOgesi(id: "cerez", baslik: "Çerez dosyası (cookies.txt)", bolum: .gelismis,
                  anahtarlar: ["çerez", "cookie", "yaş sınırı", "giriş"], hedef: .indirmeMotoru),
        AyarOgesi(id: "sunucu-yardimcisi", baslik: "Uzun görevleri sunucuya verebil", bolum: .gelismis,
                  anahtarlar: ["sunucu", "uzun görev", "atölye", "kodlama"]),
    ]

    /// Türkçe duyarsız arama: her sözcük başlıkta ya da anahtar sözcüklerde geçmeli. Başlıkta eşleşenler önce gelir.
    static func ara(_ q: String) -> [AyarOgesi] {
        let sozcukler = GecmisArama.normalize(q).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !sozcukler.isEmpty else { return [] }
        var baslikta: [AyarOgesi] = [], anahtarda: [AyarOgesi] = []
        for o in hepsi {
            let b = GecmisArama.normalize(o.baslik)
            let metin = b + " " + o.anahtarlar.map(GecmisArama.normalize).joined(separator: " ")
            guard sozcukler.allSatisfy({ metin.contains($0) }) else { continue }
            if sozcukler.allSatisfy({ b.contains($0) }) { baslikta.append(o) } else { anahtarda.append(o) }
        }
        return baslikta + anahtarda
    }
}

// MARK: - Yönlendirme

/// Arama sonucunun hedef ekranı. `AyarHedefi` her durumu kapsar (derleyici denetler).
struct AyarHedefEkrani: View {
    let oge: AyarOgesi

    var body: some View {
        switch oge.hedef {
        case .bolum: AyarBolumSayfasi(bolum: oge.bolum)
        case .izinler: IzinlerEkrani()
        case .gorunum: GorunumEkrani()
        case .komutlar: KisiselAlanEkrani()
        case .imza: ImzaEkrani()
        case .uyandirma: UyandirmaEkrani()
        case .dikteSozlugu: DikteSozluguEkrani()
        case .hafiza: HafizaEkrani()
        case .beceriler: BecerilerEkrani()
        case .calismaAlani: CalismaAlaniEkrani()
        case .kullanim: KullanimEkrani()
        case .saglik: SaglikEkrani()
        case .izleme: IzlemeEkrani()
        case .nabiz: NabizEkrani()
        case .mcp: McpEkrani()
        case .indirmeMotoru: GelismisIndirmeMotoru()
        case .kurulum: KurulumEkrani()
        case .kalite: KaliteEkrani()
        case .sistemAramasi: SistemAramasiAyarlari()
        case .surusKipi: SurusKipiAyarlari()
        case .hakkinda: HakkindaSayfasi()
        }
    }
}

struct AyarBolumSayfasi: View {
    let bolum: AyarBolumu

    var body: some View {
        switch bolum {
        case .asistan: AsistanAyarlari()
        case .model: ModelAyarlari()
        case .sesLive: SesVeLiveAyarlari()
        case .gorunum: GorunumEkrani()
        case .hafiza: HafizaAyarlari()
        case .baglanti: BaglantiVeKotaAyarlari()
        case .gelismis: GelismisAyarlari()
        }
    }
}

// MARK: - Asistan

struct AsistanAyarlari: View {
    @Environment(Ayarlar.self) private var ayarlar

    var body: some View {
        @Bindable var a = ayarlar
        Form {
            Section("Dostunu kişiselleştir") {
                TextField("Dostunun adı", text: $a.dostAdi)
                Picker("Konuşma tarzı", selection: $a.dostTarzi) {
                    Text("Samimi").tag("samimi")
                    Text("Sakin ve destekleyici").tag("sakin")
                    Text("Kısa ve doğrudan").tag("dogrudan")
                    Text("Neşeli").tag("neseli")
                }
                Text("Adı ve tarzı sonraki mesajında uygulanır.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Sana özel") {
                NavigationLink { IzinlerEkrani() } label: { Label("İzinler", systemImage: "hand.raised") }
                    .accessibilityIdentifier("ayarlar-izinler")
                NavigationLink { KisiselAlanEkrani() } label: { Label("Komutlarım ve kaydedilenler", systemImage: "square.grid.2x2") }
                NavigationLink { ImzaEkrani() } label: { Label("İmzam", systemImage: "signature") }
                    .accessibilityIdentifier("ayar-imzam")
            }
            Section("Anlama") {
                Toggle("İstem süzgeci: iş isteklerini göndermeden önce çözümle", isOn: $a.istemSuzgeci)
                Text("Dikte hatalarını düzeltir ve kaynak, kişi, numara gibi zorunlu kısıtları çıkarır; yalnız iş isteklerinde en çok birkaç saniye bekler.")
                    .font(.footnote).foregroundStyle(.secondary)
                // P3.4: varsayılan kapalı; açıkken her sohbet mesajında bir süzgeç çağrısı daha yapılır.
                Toggle("Araçları işe göre seç (deneysel)", isOn: $a.aracGruplama)
                    .accessibilityIdentifier("arac-gruplama-ayari")
                Text("Süzgeç isteğin hangi araçları gerektirdiğine karar verir; model yalnız onları görür. Her sohbet mesajında küçük bir model çağrısı daha yapılır.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Tetikleyiciler") {
                NavigationLink("Hey Asistan ve diğer uygulamalardan erişim") { UyandirmaEkrani() }
                Text("Siri'ye \"Asistan ile konuş\" de ya da Kontrol Merkezi'ne \"Asistan'ı başlat\" kontrolünü ekle; Arkaya Dokun ile de kestirme atayabilirsin.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Asistan")
    }
}

// MARK: - Model

struct ModelAyarlari: View {
    @Environment(Ayarlar.self) private var ayarlar
    @Environment(Beyin.self) private var beyin

    var body: some View {
        @Bindable var a = ayarlar
        Form {
            Section {
                Toggle("İşe göre otomatik model", isOn: $a.otomatikModel)
                Picker(a.otomatikModel ? "Yedek model" : "Model", selection: $a.modelKimligi) {
                    ForEach(modelSecenekleri) { Text("\($0.aile) · \($0.id)").tag($0.id) }
                }
                Picker("Düşünme çabası", selection: $a.caba) {
                    Text("Otomatik (işe göre)").tag("auto")
                    Text("Düşük (hızlı)").tag("low"); Text("Orta").tag("medium"); Text("Yüksek").tag("high")
                }
                Text("Otomatik: isteğin türüne ve zorluğuna göre model ve çaba seçilir; sınıra takılan model bir süre bekletilir.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Önce Antigravity hesabını kullan", isOn: $a.antigravityOncelik)
                Text("Sohbet, Siri ve araçlı işler önce Antigravity hesabındaki modelleri dener; hata olursa doğrudan hesaplara döner.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Web araması", isOn: $a.webArama)
                Text("Web araştırması CLIProxy'deki ChatGPT bağlantısını kullanır; sohbet modelinden bağımsızdır.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Son istek") {
                if let model = beyin.aktifModel { LabeledContent("Son kullanılan model", value: model) }
                if let caba = beyin.secilenCaba { LabeledContent("Son istek için seçilen çaba", value: caba.ad) }
                if !beyin.modelSecimNotu.isEmpty { Text(beyin.modelSecimNotu).font(.footnote).foregroundStyle(.secondary) }
                Text("Model listesi CLIProxy hesabından gelir; listede olmak kotanın açık olduğunu garanti etmez.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Model")
    }

    private var modelSecenekleri: [TelefonProxy.Model] {
        var liste = TelefonProxy.ortak.modeller.filter(\.sohbet)
        if !liste.contains(where: { $0.id == ayarlar.modelKimligi }) { liste.insert(.init(id: ayarlar.modelKimligi), at: 0) }
        return liste
    }
}

// MARK: - Ses ve Live

struct SesVeLiveAyarlari: View {
    @Environment(Ayarlar.self) private var ayarlar
    @Environment(SesOturumu.self) private var ses
    @State private var sttDestek: Bool?

    var body: some View {
        @Bindable var a = ayarlar
        Form {
            Section("Konuşma tanıma") {
                Toggle("Konuşurken sözünü kesebilirim", isOn: $a.sozKesme)
                    .accessibilityHint("Asistan konuşurken sen konuşmaya başlarsan susar ve seni dinler.")
                Picker("Konuşma tanıma", selection: $a.sttMotoru) {
                    Text("Whisper, telefonda (çevrimdışı)").tag("yerel")
                    Text("Whisper, OpenAI bulut").tag("whisper")
                    Text("Apple cihaz içi").tag("apple")
                }
                .onChange(of: ayarlar.sttMotoru) { _, _ in ses.whisperiHazirla() }
                if ayarlar.yerelWhisperKullan {
                    Picker("Whisper modeli", selection: $a.whisperModeli) {
                        ForEach(YerelWhisper.secenekler) { Text("\($0.ad) · \($0.boyut)").tag($0.id) }
                    }
                    .onChange(of: ayarlar.whisperModeli) { _, _ in ses.whisperiHazirla() }
                    // İndirilmiş modeli "indirildi", çökme işaretini hata olarak göster (yükleme yapmaz).
                    .task(id: ayarlar.whisperModeli) { ses.yerelWhisper.durumuTazele(model: ayarlar.whisperModeli) }
                    whisperDurumu
                    if let h = ses.sonWhisperHatasi { Text(h).font(.footnote).foregroundStyle(.orange) }
                }
                if ayarlar.sttMotoru == "whisper", !WhisperIstemcisi.kullanilabilir { Text("Bulut Whisper için VPS erişim anahtarı gerekir.").font(.footnote).foregroundStyle(.orange) }
                LabeledContent("Cihaz içi Türkçe STT", value: sttDestek.map { $0 ? "destekleniyor" : "YOK" } ?? "…")
                Toggle("Dikte sözlüğü (kişiler, düzeltmeler)", isOn: $a.dikteSozlugu)
                    .accessibilityIdentifier("ayar-dikte-sozlugu")
                NavigationLink("Dikte sözlüğü") { DikteSozluguEkrani() }
                    .accessibilityIdentifier("ayar-dikte-sozlugu-ekrani")
            }
            SesHattiAyarBolumu()   // P3.12: kulaklık mikrofonu/düğmesi, akıllı konuşma sonu, ilk ses, okuma hızı
            Section("Sesli yanıt") {
                Toggle("Yanıtları sesli oku", isOn: $a.sesliYanit)
                Toggle("İşaret sesleri (dinliyorum/aldım)", isOn: $a.isaretSesleri)
                Text("Mikrofon açılınca, söz alınınca, dinleme kapanınca ve hata olunca kısa bir ton çalar.").font(.footnote).foregroundStyle(.secondary)
                Picker("Asistanın sesi", selection: $a.sesKimligi) {
                    Text("iPhone · Türkçe (çevrimdışı)").tag("apple")
                    ForEach(AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("tr") }, id: \.identifier) { voice in
                        Text("iPhone · " + voice.name).tag("apple:" + voice.identifier)
                    }
                    ForEach(AsistanSesleri.ortak.sesler) { Text($0.title).tag($0.id) }
                }
                .onChange(of: ayarlar.sesKimligi) { _, yeni in ses.konusmaci.sesiYenidenDene(yeni) }
                Button(ses.konusmaci.konusuyor ? "Ses provasını durdur" : "Seçili sesi dinle") {
                    if ses.konusmaci.konusuyor { ses.konusmaci.sustur() }
                    else { ses.konusmaci.akisBasladi(); ses.konusmaci.akisBitti("Merhaba Mehmet. Ben senin asistanınım. Bugün sana nasıl yardımcı olabilirim?") }
                }
                if let hata = ses.konusmaci.sesHatasi { Text(hata).font(.footnote).foregroundStyle(.orange) }
                if let hata = AsistanSesleri.ortak.hata { Text(hata).font(.footnote).foregroundStyle(.orange) }
                Text("Azure HD Elif varsayılandır; bulut sesleri internet kullanır, iPhone sesi çevrimdışı çalışır.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Live") {
                Picker("Live motoru", selection: $a.canliMotor) {
                    Text("Claude (sıralı: yazıya çevir → Claude → ses)").tag("claude")
                    Text("OpenAI Realtime (gerçek zamanlı sesten sese)").tag("openai")
                }
                if a.canliMotor == "openai" { OpenAIAnahtarSatiri() }
                Toggle("Live modunda yalnız Claude kullan", isOn: $a.canliClaude)
                // P4.2: sıralı (Claude) Live ekran kilitlenince sürer; varsayılan kapalı.
                Toggle("Live arka planda sürsün", isOn: $a.canliArkaPlan)
                    .accessibilityIdentifier("ayar-live-arka-plan")
                Text("Yalnız Claude motorunda; ekran kilitlenince sürer, 10 dk sessizlikte kapanır; pil tüketir.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Claude'un gerçek zamanlı ses API'si yok: konuşma yazıya çevrilir, Claude yanıtlar, ses sentezlenir.").font(.footnote).foregroundStyle(.secondary)
                Text("Konuşma modunu menüdeki (çekmece) mod şeridinden seçersin. Hey Asistan ile açıldığında her çağrıda tek komut dinlenir.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Ses ve Live")
        .task { sttDestek = await SesDinleyici.destekleniyor(); await AsistanSesleri.ortak.yenile() }
    }

    @ViewBuilder
    private var whisperDurumu: some View {
        switch ses.yerelWhisper.durum {
        case .indirilmedi:
            Button("Modeli indir") { ses.whisperiHazirla(elle: true) }
        case .indirildi:
            Button("Modeli yükle") { ses.whisperiHazirla(elle: true) }
            Text("İndirildi, belleğe yüklenmedi.").font(.footnote).foregroundStyle(.secondary)
        case .indiriliyor(let p):
            VStack(alignment: .leading) { Text("İndiriliyor… %\(Int(p * 100))"); ProgressView(value: p) }
        case .yukleniyor:
            HStack { ProgressView(); Text("Model yükleniyor (ilk açılışta 10-60 sn)…") }
        case .hazir:
            LabeledContent("Durum", value: "hazır" + (ses.yerelWhisper.sonSure.map { String(format: " · son çözüm %.1f sn", $0) } ?? ""))
        case .hata(let h):
            Text(h).font(.footnote).foregroundStyle(.red)
            Button("Yeniden dene") { ses.whisperiHazirla(elle: true) }
        }
    }
}

// MARK: - Hafıza

struct HafizaAyarlari: View {
    @Environment(Ayarlar.self) private var ayarlar
    @Environment(Beyin.self) private var beyin
    /// Olgular her çizimde değil, sayfa açılınca ve gömme tamamlanınca bir kez okunur.
    @State private var olguSayisi = 0
    @State private var gomuluOlguSayisi = 0

    private func olgulariSay() {
        let o = beyin.depo.olgular()
        olguSayisi = o.count
        gomuluOlguSayisi = o.filter { UzakGomlemci.gecerli($0.vektor) != nil }.count
    }

    var body: some View {
        @Bindable var a = ayarlar
        Form {
            Section {
                Toggle("Konuşmadan otomatik olgu çıkar (işe göre model)", isOn: $a.otomatikHafiza)
                Toggle("Anlamsal hafıza (sunucu bge-m3)", isOn: $a.anlamsalHafiza)
                    .accessibilityIdentifier("ayar-anlamsal-hafiza")
                    .onChange(of: ayarlar.anlamsalHafiza) { _, acik in
                        // Açılınca eksik gömmeler arka planda tamamlanır (32'lik toplu istek, ilk hatada durur).
                        if acik { Task { await beyin.depo.vektorleriTamamla(); await beyin.depo.mesajVektorleriniTamamla(); olgulariSay() } }
                    }
                Text("Açıkken olgu ve mesaj metinleri anlamca arama için vekile gönderilir; kapalıyken yalnız sözcükle aranır ve hiçbir metin gönderilmez.")
                    .font(.footnote).foregroundStyle(.secondary)
                if ayarlar.anlamsalHafiza {
                    LabeledContent("Gömmesi olan olgu", value: "\(gomuluOlguSayisi)/\(olguSayisi)")
                    if !WhisperIstemcisi.kullanilabilir { Text("Vekil erişim anahtarı yok; gömme yapılamaz.").font(.footnote).foregroundStyle(.orange) }
                }
            }
            Section {
                NavigationLink { HafizaEkrani() } label: {
                    Label("Asistan seni böyle tanıyor (\(olguSayisi) olgu)", systemImage: "brain.head.profile")
                }
                Text("Beceriler ve çalışma alanı dosyaları Hafıza ekranındaki 'Profil ve kurallar' bölümündedir.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Hafıza")
        .task { olgulariSay() }
    }
}

// MARK: - Bağlantı ve kota

struct BaglantiVeKotaAyarlari: View {
    @Environment(Beyin.self) private var beyin

    var body: some View {
        Form {
            Section("iPhone CLIProxy bağlantısı") {
                Label(TelefonProxy.ortak.durum, systemImage: TelefonProxy.ortak.hazir ? "checkmark.shield.fill" : "network")
                Text("CLI Proxy'deki bağlı hesapların kullanılır; CLI Proxy uygulamasının açık kalması gerekmez.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button(TelefonProxy.ortak.sinaniyor ? "Sınanıyor…" : "Bağlantıyı sına") {
                    Task { await TelefonProxy.ortak.sina(); await KurulumDurumu.ortak.yenile() }
                }.disabled(TelefonProxy.ortak.sinaniyor)
                if let sonuc = TelefonProxy.ortak.sonSinama { Text(sonuc).font(.footnote) }
                if let y = beyin.aktifYol { LabeledContent("Son kullanılan", value: y.ad) }
            }
            Section("Kota") {
                NavigationLink { KullanimEkrani() } label: { Label("Kullanım ve kota", systemImage: "gauge.with.dots.needle.67percent") }
                Text("Kalan kota yüzdesi sağlayıcı vermezse tahmin edilmez; gerçek sınır hatalarıyla yönetilir.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Bağlantı ve kota")
    }
}

// MARK: - Gelişmiş

/// Ayarlar kökündeki katlanmış Gelişmiş grubunun satırları; aramadan açılan Gelişmiş sayfası da bunları kullanır.
struct GelismisSatirlari: View {
    @Environment(Ayarlar.self) private var ayarlar

    var body: some View {
        @Bindable var a = ayarlar
        NavigationLink { SaglikEkrani() } label: { Label("Sağlık ve hız merkezi", systemImage: "gauge.with.dots.needle.50percent") }
            .accessibilityIdentifier("ayarlar-saglik")
        NavigationLink { IzlemeEkrani() } label: { Label("Çökme ve performans", systemImage: "stethoscope") }
            .accessibilityIdentifier("ayarlar-izleme")
        NavigationLink { NabizEkrani() } label: { Label("Nabız (proaktif kontrol)", systemImage: "waveform.path.ecg") }
            .accessibilityIdentifier("ayarlar-nabiz")
        NavigationLink { McpEkrani() } label: { Label("MCP sunucuları", systemImage: "puzzlepiece.extension") }
            .accessibilityIdentifier("ayarlar-mcp")
        NavigationLink { GelismisIndirmeMotoru() } label: { Label("İndirme motoru (yt-dlp)", systemImage: "arrow.down.circle") }
            .accessibilityIdentifier("ayarlar-indirme-motoru")
        Toggle("Uzun görevleri sunucuya verebil", isOn: $a.sunucuGorevleri)
        Text("Kodlama işleri otomatik; diğer uzun işler istediğinde sunucuya gider ve Python izole ortamda çalışır. Kapatmak gönderilmiş görevi durdurmaz; Atölye'den durdurabilirsin.")
            .font(.footnote).foregroundStyle(.secondary)
    }
}

struct GelismisAyarlari: View {
    var body: some View {
        Form { Section { GelismisSatirlari() } }
            .navigationTitle("Gelişmiş")
    }
}

/// Gömülü yt-dlp motoru ve çerez dosyası. Sürüm yalnız istenince okunur (Python her açılışta başlatılmasın).
struct GelismisIndirmeMotoru: View {
    @State private var motorSurum: PythonMotoru.Surum?
    @State private var motorMesgul = false
    @State private var motorDurum: String?
    @State private var cerezSeciliyor = false
    @State private var cerezVar = false

    var body: some View {
        Form {
            Section {
                LabeledContent("yt-dlp sürümü", value: motorSurum?.yt_dlp ?? "—")
                Button("Sürümü göster") { motorIslemi { try await PythonMotoru.shared.surum() } }
                Button("Güncelle") { motorIslemi { try await PythonMotoru.shared.guncelle() } }
                Button("Paket sürümüne dön", role: .destructive) { motorIslemi { try await PythonMotoru.shared.paketSurumuneDon() } }
                Button(cerezVar ? "Çerez dosyasını değiştir" : "Çerez dosyası ekle") { cerezSeciliyor = true }
                if cerezVar { Button("Çerezleri sil", role: .destructive) { cerezleriSil() } }
                if motorMesgul { HStack { ProgressView(); Text("İndirme motoru çalışıyor…") } }
                if let motorDurum { Text(motorDurum).font(.footnote) }
                Text("YouTube değişip indirme bozulursa Güncelle en yeni yt-dlp'yi PyPI'den kurar; sorun çıkarsa paketteki sürüme dönebilirsin. Çerez dosyası (Netscape biçimli cookies.txt) yaş sınırlı ya da giriş isteyen videolar için gerekir; yalnız bu telefonda saklanır, iCloud ve bilgisayar yedeğine girmez.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .disabled(motorMesgul)
        }
        .navigationTitle("İndirme motoru")
        .fileImporter(isPresented: $cerezSeciliyor, allowedContentTypes: [.plainText, .data]) { cerezIceAktar($0) }
        .task {
            cerezVar = FileManager.default.fileExists(atPath: PythonMotoru.cerezDosyasi.path)
            // Eski sürümde yedekten dışlanmadan yazılmış dosya varsa bir kez işaretlenir.
            if cerezVar { _ = AyarlarEkrani.yedektenDisla(PythonMotoru.cerezDosyasi) }
        }
    }

    private func motorIslemi(_ islem: @escaping @Sendable () async throws -> PythonMotoru.Surum) {
        motorMesgul = true; motorDurum = nil
        Task {
            defer { motorMesgul = false }
            do {
                let surum = try await islem()
                motorSurum = surum
                motorDurum = "Hazır: yt-dlp \(surum.yt_dlp) · Python \(surum.python)"
            } catch {
                motorDurum = "İşlem yapılamadı: \(error.localizedDescription)"
            }
        }
    }

    private func cerezIceAktar(_ sonuc: Result<URL, any Error>) {
        let kaynak: URL
        switch sonuc {
        case .success(let u): kaynak = u
        case .failure(let e): motorDurum = "Dosya seçilemedi: \(e.localizedDescription)"; return
        }
        let erisim = kaynak.startAccessingSecurityScopedResource()
        defer { if erisim { kaynak.stopAccessingSecurityScopedResource() } }
        guard let veri = try? Data(contentsOf: kaynak), PythonMotoru.cerezMetniGecerli(String(decoding: veri, as: UTF8.self)) else {
            motorDurum = "Bu dosya Netscape biçimli bir çerez dosyası (cookies.txt) değil."
            return
        }
        do {
            // Oturum çerezleri cihaz yedeğine gitmesin. .atomic yazım dosyayı yeniden oluşturup işareti düşürdüğü için
            // dışlama her yazımdan sonra yeniden konur.
            try veri.write(to: PythonMotoru.cerezDosyasi, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            _ = AyarlarEkrani.yedektenDisla(PythonMotoru.cerezDosyasi)
        } catch {
            motorDurum = "Çerez dosyası kaydedilemedi: \(error.localizedDescription)"
            return
        }
        cerezVar = true
        cerezleriBildir("Çerez dosyası eklendi.")
    }

    private func cerezleriSil() {
        try? FileManager.default.removeItem(at: PythonMotoru.cerezDosyasi)
        cerezVar = FileManager.default.fileExists(atPath: PythonMotoru.cerezDosyasi.path)
        // Silmede motoru yapılandırmak gerekmez: motor her indirmede dosyanın varlığını kendisi denetler.
        // (Yapılandırma çağrısı Python'u gereksiz yere başlatır ve süren indirmenin arkasında bölümü kilitlerdi.)
        motorDurum = cerezVar ? "Çerez dosyası silinemedi." : "Çerezler silindi."
    }

    /// Çerez dosyası eklenince motoru yeniden yapılandırır (sonraki indirmede geçerli olur).
    /// Bölüm kilitlenmez: motor süren bir indirmeyle meşgulse yapılandırma kuyrukta arkada bekler, arayüz beklemez.
    private func cerezleriBildir(_ ileti: String) {
        motorDurum = ileti + " Sonraki indirmede geçerli olur."
        Task {
            do { try await PythonMotoru.shared.cerezleriYenile() }
            catch { motorDurum = "\(ileti) Motor yeniden yapılandırılamadı: \(error.localizedDescription)" }
        }
    }
}
