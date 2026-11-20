import Foundation

/// P3.10-arıza: telefonda koşan sınamaların (`--asistan-*` bayrakları, Documents/asistan-<ad>.json raporları) kalıcı tablosu.
/// Satırlar Documents/sinama-kayitlari.jsonl dosyasında, her satır bir JSON kayıt. Saf veridir: Release'te derlenir
/// ama kullanılmaz (ekranı yalnız DEBUG'da vardır).
nonisolated struct SinamaKaydi: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    var ad: String
    var zaman: Date
    var surum: String
    var kosu: String?
    var basarili: Bool
    var sureSn: Double?
    var ozet: String

    init(id: UUID = UUID(), ad: String, zaman: Date = Date(), surum: String = SurumBilgisi.simdiki.kisa,
         kosu: String? = nil, basarili: Bool, sureSn: Double? = nil, ozet: String) {
        self.id = id; self.ad = ad; self.zaman = zaman; self.surum = surum
        self.kosu = kosu; self.basarili = basarili; self.sureSn = sureSn; self.ozet = ozet
    }

    static let dosyaAdi = "sinama-kayitlari.jsonl"
    static let enFazla = 500
    /// Sınama raporlarının ad kalıbı: "asistan-<ad>.json".
    static let raporOneki = "asistan-"

    static var varsayilanKlasor: URL { URL.documentsDirectory }

    private static let kilit = NSLock()

    private static func kodlayici() -> JSONEncoder {
        let k = JSONEncoder(); k.dateEncodingStrategy = .iso8601; k.outputFormatting = [.sortedKeys]; return k
    }
    private static func cozucu() -> JSONDecoder {
        let c = JSONDecoder(); c.dateDecodingStrategy = .iso8601; return c
    }

    /// Kaydı dosyanın sonuna ekler; `enFazla` satırı aşınca en eski satırlar kırpılır.
    static func ekle(_ kayit: SinamaKaydi, klasor: URL = varsayilanKlasor) {
        ekle([kayit], klasor: klasor)
    }

    static func ekle(_ kayitlar: [SinamaKaydi], klasor: URL = varsayilanKlasor) {
        guard !kayitlar.isEmpty else { return }
        let url = klasor.appending(path: dosyaAdi)
        let k = kodlayici()
        kilit.lock(); defer { kilit.unlock() }
        var satirlar = hamSatirlar(url)
        for kayit in kayitlar {
            guard let v = try? k.encode(kayit) else { continue }
            satirlar.append(String(decoding: v, as: UTF8.self))
        }
        if satirlar.count > enFazla { satirlar.removeFirst(satirlar.count - enFazla) }
        try? FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        try? Data((satirlar.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
    }

    /// Bütün kayıtlar, eskiden yeniye. Bozuk satır atlanır.
    static func oku(klasor: URL = varsayilanKlasor) -> [SinamaKaydi] {
        let url = klasor.appending(path: dosyaAdi)
        let c = cozucu()
        kilit.lock(); let satirlar = hamSatirlar(url); kilit.unlock()
        return satirlar.compactMap { try? c.decode(SinamaKaydi.self, from: Data($0.utf8)) }
    }

    static func temizle(klasor: URL = varsayilanKlasor) {
        kilit.lock(); defer { kilit.unlock() }
        try? FileManager.default.removeItem(at: klasor.appending(path: dosyaAdi))
    }

    private static func hamSatirlar(_ url: URL) -> [String] {
        guard let veri = try? Data(contentsOf: url) else { return [] }
        return String(decoding: veri, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Sınama raporu JSON'undan özet: basarili = tamamlandi == true && hata boş; süre = toplamSn | sureSaniye | sureMs/1000.
    static func ozetle(ad: String, json: [String: Any], zaman: Date = Date(), surum: String = SurumBilgisi.simdiki.kisa) -> SinamaKaydi {
        let tamam = (json["tamamlandi"] as? Bool) == true
        let hata = ((json["hata"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let sure: Double? = sayi(json["toplamSn"]) ?? sayi(json["sureSaniye"]) ?? sayi(json["sureMs"]).map { $0 / 1000 }
        let kosu = (json["kosu"] as? String) ?? (json["kip"] as? String)
        var ozet: String
        if !hata.isEmpty { ozet = "Hata: " + String(hata.prefix(160)) }
        else if !tamam { ozet = "Tamamlanmadı" }
        else { ozet = "Tamam" }
        if let n = (json["sonuclar"] as? [Any])?.count ?? (json["turlar"] as? [Any])?.count ?? (json["dosyalar"] as? [Any])?.count {
            ozet += " · \(n) öğe"
        }
        return SinamaKaydi(ad: ad, zaman: zaman, surum: surum, kosu: kosu, basarili: tamam && hata.isEmpty && !altHataVar(json), sureSn: sure, ozet: ozet)
    }

    /// İç içe sonuçtaki başarısızlık üst düzey tamamlandı işaretiyle örtülemez.
    static func altHataVar(_ deger: Any) -> Bool {
        if let d = deger as? [String: Any] {
            for (ad, v) in d {
                if ["hata", "girdiHatasi", "uyandirmaHata"].contains(ad), let h = v as? String,
                   !h.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
                if ["zamanAsimi", "kabulZamanAsimi"].contains(ad), v as? Bool == true { return true }
                if ["bitti", "tamamlandi", "basarili", "dinlemeyeDondu", "okundu", "oynatmaBasladi", "testSesiyleUyandi", "uyandirmaSesCaldi", "pdfDogrulandi", "hafizaAraciCalisti", "zipIcerikDogru", "telefonProxyHazir", "oynatmaBitti", "durdu"].contains(ad),
                   v as? Bool == false { return true }
                if altHataVar(v) { return true }
            }
        } else if let a = deger as? [Any] { return a.contains { altHataVar($0) } }
        return false
    }

    private static func sayi(_ d: Any?) -> Double? {
        if let x = d as? Double { return x }
        if let x = d as? Int { return Double(x) }
        if let x = d as? NSNumber { return x.doubleValue }
        if let x = d as? String { return Double(x) }
        return nil
    }

    /// "asistan-ofis-sinama.json" → "ofis-sinama". Kalıba uymayan ad nil.
    static func raporAdi(_ dosyaAdi: String) -> String? {
        guard dosyaAdi.hasPrefix(raporOneki), dosyaAdi.hasSuffix(".json") else { return nil }
        let ad = String(dosyaAdi.dropFirst(raporOneki.count).dropLast(5))
        return ad.isEmpty ? nil : ad
    }

    /// Klasördeki asistan-*.json raporlarından henüz tabloda olmayanları (ad + dosya değişiklik saniyesi) özetleyip ekler.
    /// Sınama kodu raporu yazınca kayıt eklemek zorunda kalmaz; ekran açılınca tablo güncellenir. Eklenen sayıyı döndürür.
    @discardableResult
    static func iceAktar(klasor: URL = varsayilanKlasor) -> Int {
        let fm = FileManager.default
        guard let adlar = try? fm.contentsOfDirectory(at: klasor, includingPropertiesForKeys: [.contentModificationDateKey]) else { return 0 }
        let mevcut = Set(oku(klasor: klasor).map { "\($0.ad)|\(Int($0.zaman.timeIntervalSince1970))" })
        var yeni: [SinamaKaydi] = []
        for url in adlar {
            guard let ad = raporAdi(url.lastPathComponent) else { continue }
            let zaman = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            guard !mevcut.contains("\(ad)|\(Int(zaman.timeIntervalSince1970))") else { continue }
            guard let veri = try? Data(contentsOf: url),
                  let json = (try? JSONSerialization.jsonObject(with: veri)) as? [String: Any] else { continue }
            yeni.append(ozetle(ad: ad, json: json, zaman: zaman))
        }
        yeni.sort { $0.zaman < $1.zaman }
        ekle(yeni, klasor: klasor)
        return yeni.count
    }

    /// Satıra dokununca gösterilen ham rapor (Documents/asistan-<ad>.json); yoksa nil.
    static func hamRapor(ad: String, klasor: URL = varsayilanKlasor) -> String? {
        guard let veri = try? Data(contentsOf: klasor.appending(path: raporOneki + ad + ".json")) else { return nil }
        return String(decoding: veri, as: UTF8.self)
    }
}
