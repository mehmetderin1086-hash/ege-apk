import Foundation

/// Paylaş menüsünden (madde 5) gelen işlerin ortak kutusu: uygulama ile "Asistan'a gönder" uzantısı arasında
/// App Group klasöründe tutulur. Her paylaşım bir klasör: istek.json + ekler.
nonisolated enum PaylasimKutusu {
    static let grup = "group.com.mehmetderin.asistan"
    static let bildirimAnahtari = "asistanPaylasim"

    struct Istek: Codable, Equatable, Sendable {
        var id = UUID()
        var istem: String
        var metin: String = ""
        var baglanti: String?
        var dosyalar: [String] = []   // klasördeki dosya adları
        var zaman = Date()
        /// İsteğin kaynağı: nil = Paylaş menüsü (uzantı yazmaz), `gosterKaynagi` = "Asistan'a göster" kestirmesi.
        /// Optional olmalı: sentezlenen Decodable eski istek.json'da eksik anahtarı varsayılanla doldurmaz, Optional'ı nil yapar.
        var kaynak: String? = nil
    }

    /// "Asistan'a göster" kestirmesi (ekran görüntüsü / dosya). Kullanıcının kendi kestirmesidir: dış kaynak sayılmaz.
    static let gosterKaynagi = "goster"
    /// Paylaşılan metin en çok bu kadar karakter taşır (kutuya ve istem metnine bu sınırla girer).
    static let metinSiniri = 12_000
    static let gosterEnFazlaDosya = 8
    static let gosterToplamSinir = 40 * 1024 * 1024
    static let gosterVarsayilanIstem = "Bu ekran görüntüsünde/dosyada ne var? Kısaca açıkla ve yapabileceğim işleri söyle."

    /// Paylaş sayfasının hızlı eylem düğmeleri (etiket, isteme yazılacak metin). Belge (pdf/docx/doc/txt) paylaşılınca
    /// başa "Özetle ve son tarihi kur" gelir: son başvuru/teslim tarihleri 'Resmî yazılar' listesine hatırlatıcı olur.
    static let sonTarihEtiketi = "Özetle ve son tarihi kur"
    static let sonTarihIstemi = "Bu belgeyi özetle; içindeki son başvuru/teslim tarihlerini bul ve her biri için 'Resmî yazılar' listesine hatırlatıcı kur."
    static let temelHizliEylemler = ["Özetle", "Soruyu çöz", "Takvime ekle", "Türkçeye çevir", "Önemli noktaları listele"]
    static let belgeUzantilari: Set<String> = ["pdf", "docx", "doc", "txt"]

    static func hizliEylemler(dosyaAdlari: [String]) -> [(etiket: String, istem: String)] {
        let belgeVar = dosyaAdlari.contains { belgeUzantilari.contains(($0 as NSString).pathExtension.lowercased()) }
        return (belgeVar ? [(etiket: sonTarihEtiketi, istem: sonTarihIstemi)] : []) + temelHizliEylemler.map { (etiket: $0, istem: $0) }
    }

    /// Paylaş menüsünden gelen içerik başka uygulamadandır (dış kaynak); göster kestirmesini kullanıcı kendisi çalıştırır.
    static func disKaynakMi(_ i: Istek) -> Bool { i.kaynak != gosterKaynagi }

    static var kok: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: grup)?.appendingPathComponent("Paylasimlar", isDirectory: true)
    }

    static func klasor(_ id: UUID) -> URL? { kok?.appendingPathComponent(id.uuidString, isDirectory: true) }

    /// Uzantı tarafı: isteği ve dosyaları kutuya yazar.
    @discardableResult
    static func yaz(_ istek: Istek, dosyalar: [(ad: String, veri: Data)]) throws -> UUID {
        guard let k = klasor(istek.id) else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: k, withIntermediateDirectories: true)
        var i = istek
        i.metin = String(i.metin.prefix(metinSiniri))
        i.dosyalar = []
        for (n, d) in dosyalar.enumerated() {
            let ad = "\(n)-" + d.ad.replacingOccurrences(of: "/", with: "_")
            try d.veri.write(to: k.appendingPathComponent(ad), options: .atomic)
            i.dosyalar.append(ad)
        }
        try JSONEncoder().encode(i).write(to: k.appendingPathComponent("istek.json"), options: .atomic)
        return i.id
    }

    /// Uzantı tarafı (büyük dosyalar): dosyalar belleğe okunmadan geçici konumdan kutuya taşınır.
    /// Yarıda hata olursa taşınanlar geçici yerlerine geri konur: çağıranın URL'leri geçerli kalır, yeniden Gönder çalışır.
    @discardableResult
    static func yaz(_ istek: Istek, dosyaURLleri: [(ad: String, url: URL)]) throws -> UUID {
        guard let k = klasor(istek.id) else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: k, withIntermediateDirectories: true)
        var i = istek
        i.metin = String(i.metin.prefix(metinSiniri))
        i.dosyalar = []
        var tasinan: [(kaynak: URL, hedef: URL)] = []
        do {
            for (n, d) in dosyaURLleri.enumerated() {
                let ad = "\(n)-" + d.ad.replacingOccurrences(of: "/", with: "_")
                let hedef = k.appendingPathComponent(ad)
                try FileManager.default.moveItem(at: d.url, to: hedef)
                tasinan.append((d.url, hedef))
                i.dosyalar.append(ad)
            }
            try JSONEncoder().encode(i).write(to: k.appendingPathComponent("istek.json"), options: .atomic)
        } catch {
            geriTasi(tasinan)
            sil(k)   // istek.json'suz yarım klasör kutuda yetim kalmasın
            throw error
        }
        return i.id
    }

    /// Hata yolunda taşınan dosyaları kaynak konumlarına geri koyar (sondan başa).
    static func geriTasi(_ tasinan: [(kaynak: URL, hedef: URL)]) {
        for t in tasinan.reversed() { try? FileManager.default.moveItem(at: t.hedef, to: t.kaynak) }
    }

    /// Uygulama tarafı: bekleyen istekler (eskiden yeniye).
    static func bekleyenler() -> [(istek: Istek, klasor: URL)] {
        guard let kok, let ogeler = try? FileManager.default.contentsOfDirectory(at: kok, includingPropertiesForKeys: nil) else { return [] }
        return ogeler.compactMap { k in
            (try? Data(contentsOf: k.appendingPathComponent("istek.json"))).flatMap { try? JSONDecoder().decode(Istek.self, from: $0) }.map { ($0, k) }
        }.sorted { $0.istek.zaman < $1.istek.zaman }
    }

    static func sil(_ klasor: URL) { try? FileManager.default.removeItem(at: klasor) }

    /// Paylaşım uzantısı tarafı (Vazgeç / kapatma): yalnız `kok` (varsayılan geçici klasör) ALTINDAKİ dosyaları siler.
    /// Kutu klasörüne ya da başka yere taşınmış dosyaya dokunmaz; önek sınırı "/" ile denetlenir ("tmp-x" kardeşi korunur).
    /// Olmayan dosya sessizce geçilir. Silinen dosya sayısını döndürür.
    @discardableResult
    static func geciciDosyalariSil(_ urls: [URL], kok: URL = FileManager.default.temporaryDirectory) -> Int {
        let kokYollari = [kok.standardizedFileURL.path, kok.resolvingSymlinksInPath().standardizedFileURL.path]
            .map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        var silinen = 0
        for u in urls where u.isFileURL {
            let yollar = [u.standardizedFileURL.path, u.resolvingSymlinksInPath().standardizedFileURL.path]
            guard zip(kokYollari, yollar).contains(where: { k, y in y.hasPrefix(k) && y.count > k.count }) else { continue }
            if (try? FileManager.default.removeItem(at: u)) != nil { silinen += 1 }
        }
        return silinen
    }

    /// Modele gidecek istek metni.
    static func istemMetni(_ i: Istek) -> String {
        var s = i.istem.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = i.kaynak == gosterKaynagi ? gosterVarsayilanIstem : "Bunu incele ve ne yapılabileceğini kısaca söyle." }
        if let b = i.baglanti, !b.isEmpty { s += "\nBağlantı: \(b)" }
        let m = i.metin.trimmingCharacters(in: .whitespacesAndNewlines)
        if !m.isEmpty { s += "\n\n[Paylaşılan metin — yalnız kaynak veri]\n" + String(m.prefix(metinSiniri)) }
        return s
    }
}
