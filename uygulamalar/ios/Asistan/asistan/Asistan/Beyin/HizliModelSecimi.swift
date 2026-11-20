import Foundation
import ProxyKit

private actor CanliHizliYarisKapisi {
    private var kapali = false
    func kapat() -> Bool {
        guard !kapali else { return false }
        kapali = true
        return true
    }
}

/// Yerel karar; seçim için ayrı bir model çağrısı yapılmaz. Elle seçim korunur.
nonisolated enum HizliModelSecimi {
    static func sec(otomatik: Bool, elle: String, caba: DusunmeSecimi.Caba,
                    modeller: [String], yalnizAnahtar: Bool = false) -> String {
        guard otomatik else { return elle }
        let adaylar = adaylar(caba)
        if yalnizAnahtar || modeller.isEmpty { return adaylar[0] }
        return adaylar.first(where: { modeller.contains($0) }) ?? elle
    }
    static func adaylar(_ caba: DusunmeSecimi.Caba) -> [String] {
        switch caba {
        case .low: ["claude-haiku-4-5", "gpt-6.1-sol", "gemini-3.8-flash", "claude-sonnet-5-5", "claude-opus-5-5"]
        // Sonnet orta seviyede iPhone bağlantısında ilk metni uzun süre
        // geciktirebildi. Genel orta işlerde hızlı GPT, ardından Gemini ile
        // başlanır; Sonnet kalite yedeği olarak korunur.
        case .medium: ["claude-haiku-4-5", "gpt-6.1-sol", "gemini-3.8-flash", "claude-sonnet-5-5", "claude-opus-5-5"]
        case .high: ["claude-opus-5-5", "claude-fable-5-1", "gpt-6.1-sol", "gemini-3.8-flash-high"]
        }
    }
    static func yerelSaat(_ metin: String, simdi: Date = .now) -> String? {
        let s = AtolyeYonlendirme.normalize(metin).trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        guard ["saat kac", "su an saat kac"].contains(s) else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "HH:mm"
        return "Saat \(f.string(from: simdi))."
    }
    /// Ağa veya model kararına ihtiyaç duymayan, anlamı tek ve yan etkisiz kısa
    /// konuşmalar. Canlı modda ilk sesi model beklemeden başlatır.
    static func yerelKisaYanit(_ metin: String) -> String? {
        let s = AtolyeYonlendirme.normalize(metin).trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        switch s {
        case "merhaba", "selam": return "Merhaba, buradayım. Nasıl yardımcı olayım?"
        case "nasilsin": return "İyiyim, hazırım. Sen nasılsın?"
        case "beni duyuyor musun", "sesim geliyor mu": return "Evet, seni duyuyorum."
        case "tesekkurler", "sag ol": return "Rica ederim."
        default: return nil
        }
    }
    static func dogrudanArastirma(_ metin: String) -> Bool {
        let s = AtolyeYonlendirme.normalize(metin)
        // Bir web yanıtı telefon işlemini yerine getiremez; karma komutlar araçlı modele gider.
        return s.range(of: #"\b(ac|ara|gonder|oynat|cal|kur|sil|ekle|kaydet|hatirlat|paylas|kestirme|excel|xlsx|docx|word|pptx|powerpoint|pdf|csv|dosya|belge)\b"#, options: .regularExpression) == nil
    }
}

/// Live moddaki araç gerektirmeyen kısa sohbetleri FoundationModels oturumunun
/// ana-aktör bağımlılığından çıkarır. Telefon işlemleri ve araştırma istekleri
/// araçlı Beyin akışında kalır.
nonisolated enum CanliHizliIstemci {
    enum Hata: LocalizedError {
        case uygunModelYok, http(Int), bosYanit
        var errorDescription: String? {
            switch self {
            case .uygunModelYok: "Live için uygun hızlı model bulunamadı."
            case .http(let kod): "Live sağlayıcısı HTTP \(kod) döndürdü."
            case .bosYanit: "Live sağlayıcısı boş yanıt döndürdü."
            }
        }
    }

    /// Tam eşleşmesi gereken kısa kökler (ek almış biçimleri ayrıca `onekler` ile yakalanır).
    private static let tamSozcukler: Set<String> = [
        "ara", "ac", "at", "sil", "not", "kis", "yak", "bul", "oku", "cal", "kur", "ekle", "web", "internet", "guncel", "bugun",
        "haber", "kaynak", "foto", "gorsel", "video", "muzik", "telefon", "kod", "mac", "maci", "puan", "sonuc", "fiyat", "dolar",
        "euro", "altin", "borsa", "yarin", "hafta", "haftaki", "simdi", "trafik", "vizyon", "kimle", "usd", "bist", "deprem",
        "hava", "wifi", "zip", "rar", "sms", "gecen", "beceri", "becerisi"
    ]
    /// Ek alabilen eylem/konu kökleri: "arar mısın", "göndersene", "hatırlatır mısın", "açar mısın" gibi biçimler.
    private static let onekler = [
        "arar", "arayi", "arama", "aray", "acar", "acin", "acsa", "gonder", "mesaj", "whatsapp", "mail", "bildirim", "hatirla", "hatirlat",
        "alarm", "zamanlay", "takvim", "harita", "konum", "dosya", "indir", "yukle", "olustur", "duzenle", "donustur", "arsiv",
        "uygulama", "paylas", "kapat", "kapa", "fener", "parlaklik", "bluetooth", "randevu", "toplanti", "etkinlik", "rehber",
        "navigasyon", "tarif", "yakinimda", "kaydet", "sayac", "oynat", "unutma", "aklinda", "ogren", "kisayol", "kestirme",
        "spotify", "youtube", "fikstur", "skor", "onumuzdeki", "gelecek", "nobetci", "uyar", "uyandir", "artir", "azalt",
        "sesi", "ekran", "bulun", "okur", "okuy", "yakar", "yakin", "kisiyi", "kisi",
        // Sistem ayarları (cihaz aracı, Sistem Köprüsü): "uçak moduna geçer misin", "Wi-Fi'yi…", "telefonu kilitle".
        "wifi", "ucak", "hotspot", "kilitle", "etkinlestir", "rahatsiz", "vardiya", "karanlik", "hucresel", "acabilir", "seviyesi", "duzeyi",
        // Geçmiş sohbete atıf: gecmisAra aracı gerekir.
        "beceri", "iceakt", "agents", "soul", "heartbeat", "nabiz", "gecmis", "demist", "soylemist", "konusmust", "konustuk", "belirlemist", "bahsetmist", "anlatmist", "konustugumuz",
        // Belge ve plan işleri: ofis/plan araçlarıyla yürür, araçsız yarışta "hazırladım" diye uydurulmasın.
        // "haftalık planı"nda "plani" ayrı sözcüktür; "planl" onu yakalamaz.
        "tutana", "dilekce", "plan", "planl", "plani", "yazili"
    ]
    /// Bir önekle başlayan ama sıradan soru olan sözcükler ("yazılım nedir" yarışta kalır).
    private static let istisnaOnekleri = ["yazilim"]

    /// Henüz kaydı olmayabilecek araçların tetik kökleri; anahtar araç adıdır (`Tool.name`).
    /// Yalnız `kayitliAraclar` içindeki araçların kökleri yarışı engeller: araç gelene kadar bu istekler yarışta kalır.
    static let aracTetikleri: [String: [String]] = [
        "tuval": ["tuval"],
        "ceviri": ["cevir", "tercume"],
        "fotograf": ["fotog"],
        "cizim": ["cizer", "cizsen", "cizim"],
        // "dondur" yok: "dondurma"yı da yakalar.
        "pdfIslem": ["birlestir", "imzala", "sikistir", "kucult"],
        // "fotog" kökü bilinçli olarak yok: soru fotoğrafı istekleri yarıştan çıkmasın.
        "fotograflar": ["galeri", "fotograflarim", "selfie"],
        "ucretsizServis": ["doviz", "kur", "resmi", "tatil", "ulke"],
        "yasamServisleri": ["polen", "hava kalitesi", "deprem", "barkod", "nutriscore", "wikipedia", "tur", "makale", "openalex", "sabah ozeti"],
    ]
    /// `AracKaydi.adlar` içinde bulunan `aracTetikleri` anahtarları (derleme zamanı listesi; çalışma anında doldurulmaz).
    /// Yeni araç kaydedilince adı buraya da yazılır; `OgretmenYonlendirmeTestleri` iki listenin eşliğini denetler.
    static let varsayilanAraclar: Set<String> = ["pdfIslem", "fotograflar", "ucretsizServis", "yasamServisleri", "tuval"]

    /// e-Okul / "e okul" / "eokul": sözcük sınırlı ("Türkçe okulda" eşleşmez).
    private static func eOkulMu(_ s: String) -> Bool {
        s.range(of: #"(^|[^a-z0-9])e[- ]?okul"#, options: .regularExpression) != nil
    }

    /// - Parameters:
    ///   - kayitliAraclar: kökleri yarışı engelleyecek araç adları (testler açıkça verir).
    ///   - beceriKokleri: nil ise kayıtlı + hazır becerilerin kökleri (`BeceriDeposu.tetikKokleri()`).
    static func uygun(_ metin: String, kayitliAraclar: Set<String> = varsayilanAraclar, beceriKokleri: [[String]]? = nil) -> Bool {
        let s = AtolyeYonlendirme.normalize(metin) // "ı"→"i" dahil; "hatırla" ile "hatirla" aynı sayılır
        guard !s.isEmpty, s.count <= 1200 else { return false }
        // Adres içeren istek web okuma/içe aktarma gerektirebilir: araçlı yola gider.
        if s.contains("http://") || s.contains("https://") || s.contains("www.") { return false }
        if s.contains("daha once") || s.contains("bir onceki konus") { return false }
        // Tire ayırıcı olduğundan "e-okul" tek sözcük olarak yakalanamaz.
        if eOkulMu(s) { return false }
        let kelimeler = s.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let aracKokleri = kayitliAraclar.flatMap { aracTetikleri[$0] ?? [] }
        let cumle = " " + kelimeler.joined(separator: " ") + " "
        if aracKokleri.contains(where: { $0.contains(" ") && cumle.contains(" " + $0 + " ") }) { return false }
        for k in kelimeler {
            if tamSozcukler.contains(k) { return false }
            guard k.count >= 4 else { continue }
            if !istisnaOnekleri.contains(where: { k.hasPrefix($0) }), onekler.contains(where: { k.hasPrefix($0) }) { return false }
            if aracKokleri.contains(where: { k.hasPrefix($0) }) { return false }
        }
        // Beceri adı istekte geçiyorsa ("ders programı", "mitoz kartı") beceri aracı gerekir: bütün kökler bulunmalı.
        for kokler in beceriKokleri ?? BeceriDeposu.tetikKokleri() where !kokler.isEmpty {
            if kokler.allSatisfy({ kok in kelimeler.contains { $0.hasPrefix(kok) } }) { return false }
        }
        return true
    }

    /// 18 Eki 2026 telefonda ölçüldü (düz sohbet): haiku-4-5 1,2-1,7 sn, gpt-6.1-sol 1,9-2,7 sn,
    /// antigravity-gemini-3.8-flash-tiered 2,6-4,2 sn. Hızlı ve birbirinden bağımsız üç sağlayıcı denenir.
    static func modelSirasi(_ modeller: [String]) -> [String] {
        var sonuc: [String] = []
        for aday in ["claude-haiku-4-5", "gpt-6.1-sol", "antigravity-gemini-3.8-flash-tiered", "gemini-3-flash", "gpt-5.4-mini"] where modeller.isEmpty || modeller.contains(aday) {
            if !sonuc.contains(aday) { sonuc.append(aday) }
        }
        return sonuc
    }

    private static func tani(_ metin: String) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--asistan-live-sinama") {
            print("[LIVE-HIZLI] \(metin)")
        }
        #endif
    }

    @concurrent static func yanit(motor: ProxyEngine, anahtar: String, modeller: [String], baglam: String, soru: String,
                                  zamanAsimi: Duration = .seconds(6), sabitModel: String? = nil) async throws -> (metin: String, model: String) {
        let adaylar = sabitModel.map { [$0] } ?? modelSirasi(modeller)
        guard !adaylar.isEmpty else { throw Hata.uygunModelYok }
        var sonHata: any Error = Hata.bosYanit
        for model in adaylar.prefix(3) {
            do {
                tani("\(model) istek hazırlanıyor")
                let govde = try JSONSerialization.data(withJSONObject: [
                    "model": model,
                    "stream": false,
                    "messages": [
                        ["role": "system", "content": "Türkçe, doğal bir sesli asistan gibi yanıtla. En fazla 1-3 kısa cümle kullan. Önceki konuşma bağlamını koru. Araç kullandığını veya işlem yaptığını iddia etme."],
                        ["role": "user", "content": String("Önceki konuşma:\n\(baglam)\n\nKullanıcı:\n\(soru)".prefix(12000))]
                    ]
                ])
                let istek = ProxyRequest(method: "POST", path: "/v1/chat/completions",
                                         headers: ["authorization": "Bearer \(anahtar)", "content-type": "application/json"],
                                         body: govde)
                let is_ = Task { () throws -> Data in
                    tani("\(model) motor başladı")
                    let yanit = await motor.handle(istek)
                    tani("\(model) motor döndü HTTP \(yanit.status)")
                    guard yanit.status == 200 else { throw Hata.http(yanit.status) }
                    var veri = Data()
                    for try await parca in yanit.body { veri.append(parca) }
                    tani("\(model) gövde bitti \(veri.count) bayt")
                    return veri
                }
                let kapi = CanliHizliYarisKapisi()
                let veri = try await withCheckedThrowingContinuation { devam in
                    Task {
                        do {
                            let sonuc = try await is_.value
                            if await kapi.kapat() { devam.resume(returning: sonuc) }
                        } catch {
                            if await kapi.kapat() { devam.resume(throwing: error) }
                        }
                    }
                    Task {
                        try? await Task.sleep(for: zamanAsimi)
                        // URLSession.bytes içeren ProxyEngine görevini burada
                        // eşzamanlı iptal etmek bazı gerçek iPhone koşularında
                        // tam zaman aşımı anında yürütücüyü kilitliyordu. Yarış
                        // kapısını kapatıp çağıranı hemen serbest bırak; geç
                        // kalan sonuç kapı tarafından sessizce yok sayılır.
                        tani("\(model) dört saniye kapısı")
                        if await kapi.kapat() {
                            tani("\(model) zaman aşımı teslim edildi")
                            devam.resume(throwing: URLError(.timedOut))
                            // Çağıranı önce serbest bırak, ardından artık sonucu
                            // kullanılamayacak ağ görevini iptal et. Böylece iki
                            // sağlayıcı da gecikirse 600 saniyeye kadar arkada
                            // istek birikmez. URLSession taşıyıcısı iptali hem
                            // başlık bekleyişine hem de açık gövde akışına iletir.
                            Task { is_.cancel() }
                        }
                    }
                }
                let metin = try coz(veri)
                tani("\(model) yanıt çözüldü")
                return (metin, model)
            } catch {
                tani("\(model) başarısız: \(error.localizedDescription)")
                if error is CancellationError { throw error }
                sonHata = error
            }
        }
        throw sonHata
    }

    static func coz(_ veri: Data) throws -> String {
        guard let kok = try JSONSerialization.jsonObject(with: veri) as? [String: Any] else { throw Hata.bosYanit }
        if let secim = (kok["choices"] as? [[String: Any]])?.first,
           let mesaj = secim["message"] as? [String: Any],
           let icerik = mesaj["content"] as? String,
           !icerik.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return icerik.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let dogrudan = kok["output_text"] as? String, !dogrudan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return dogrudan.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let metinler = (kok["output"] as? [[String: Any]] ?? []).flatMap { oge in
            (oge["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }
        }
        let metin = metinler.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !metin.isEmpty else { throw Hata.bosYanit }
        return metin
    }
}
