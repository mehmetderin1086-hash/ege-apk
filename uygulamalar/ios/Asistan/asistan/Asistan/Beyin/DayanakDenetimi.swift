import Foundation

/// P3.5 kanıt tamponu: veri getiren araçların (web, takvim, gelen kutusu, İETT…) çıktıları istek boyunca burada tutulur.
/// Denetçi bunları KANIT olarak görür; `DayanakDenetimi` yanıttaki sayı ve adları burada arar.
/// Saat, plan, hafıza, beceri, cihaz gibi araçların çıktısı kanıt sayılmaz (kanıt hiç boş kalmaz, model bilgisi "uydurma" görünürdü).
/// Her gönderim kabulünde `temizle()` çağrılır (`Beyin.gonder`); yazan `IzlenenArac.call` başarı dalıdır.
@MainActor
final class KanitTamponu {
    static let ortak = KanitTamponu()
    nonisolated static let girdiSiniri = 1500
    nonisolated static let enFazlaGirdi = 8
    nonisolated static let toplamSinir = 8000
    /// Yalnız bunların çıktısı kanıttır (`IzlenenArac` da aynı kümeyle süzer).
    nonisolated static let veriAraclari: Set<String> = ["webArastir", "webAra", "webSayfaOku", "veriKazi", "tarayici", "gelenKutusu", "takvim",
                                                        "kisiler", "dosyalar", "indirmeler", "iett", "gecmisAra", "mcp", "altAjanlar", "havaDurumu",
                                                        "mebKaynak", "mufredat", "kutuphane", "ucretsizServis", "yasamServisleri", "tuval"]
    /// Dinamik MCP araçları (`mcp_<sunucu>_<araç>`) da veri aracıdır.
    nonisolated static func veriAraciMi(_ ad: String) -> Bool { veriAraclari.contains(ad) || ad.hasPrefix("mcp_") }

    nonisolated struct Girdi: Equatable, Sendable {
        let arac: String
        let cikti: String
    }
    private(set) var girdiler: [Girdi] = []

    init() {}

    /// Girdi başına ilk 1500 karakter; en çok 8 girdi ve toplam 8000 karakter (eski girdiler düşer). Veri aracı değilse yok sayılır.
    func ekle(arac: String, cikti: String) {
        guard Self.veriAraciMi(arac) else { return }
        let t = cikti.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        girdiler.append(Girdi(arac: arac, cikti: String(t.prefix(Self.girdiSiniri))))
        while girdiler.count > Self.enFazlaGirdi { girdiler.removeFirst() }
        while girdiler.count > 1, girdiler.reduce(0, { $0 + $1.cikti.count }) > Self.toplamSinir { girdiler.removeFirst() }
    }

    func temizle() { girdiler = [] }

    /// "[araç] çıktı" satırları; boşsa boş metin.
    var metin: String { girdiler.map { "[\($0.arac)] \($0.cikti)" }.joined(separator: "\n") }
}

/// P3.5 kanıta dayalı yanıt: yanıttaki sayı/özel adların kanıtta (araç çıktılarında) geçip geçmediği ve
/// kullanıcının istediği ayrı teslimlerden hangisinin yapılmadığı. Saf; ağ/model gerekmez.
nonisolated enum DayanakDenetimi {
    static let enFazlaBulgu = 2
    /// Yanıtın kaynağa atıf yaptığını gösteren kökler (normalize edilmiş metinde sözcük başı).
    static let atifKokleri = ["kaynak", "sonuc", "bulunan", "listede", "tabloda"]
    static let aylar: Set<String> = ["ocak", "subat", "mart", "nisan", "mayis", "haziran", "temmuz", "agustos", "eylul", "ekim", "kasim", "aralik"]
    static let gunler: Set<String> = ["pazartesi", "sali", "carsamba", "persembe", "cuma", "cumartesi", "pazar"]
    /// Özel ad sayılmayan, sık büyük harfli sözcükler (biçim, ürün, dil adları).
    static let yasakAdlar: Set<String> = ["pdf", "docx", "xlsx", "excel", "word", "turkce", "ingilizce", "turkiye", "asistan", "iphone",
                                          "google", "youtube", "whatsapp", "claude", "tamam", "merhaba", "not", "notlar", "kaynak", "kaynaklar",
                                          "ozet", "sonuc", "toplam", "saat", "tarih", "bugun", "yarin", "dun", "meb", "lgs", "yks", "tyt", "ayt"]

    nonisolated struct Sayi: Equatable, Sendable { let ham: String; let rakamlar: String }

    /// Kanıtta bulunmayan sayı ve özel adlar (en çok 2). Kanıt boşsa ya da yanıt kanıta dayanmıyorsa
    /// (atıf sözcüğü yok ve kanıtla ortak sayı yok: yanıt model bilgisinden gelmiştir) boş döner.
    static func dayanaksizlar(yanit: String, kanit: String, soru: String) -> [String] {
        let kanitTemiz = kanit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kanitTemiz.isEmpty, !yanit.isEmpty else { return [] }
        let kanitSayilari = Set(sayilar(kanitTemiz).flatMap { esdegerler($0) })
        let soruSayilari = Set(sayilar(soru).map(\.rakamlar))
        let yanitSayilari = sayilar(yanit, listeNumarasiAtla: true).filter { $0.rakamlar.count > 1 && !soruSayilari.contains($0.rakamlar) }
        let normYanit = AtolyeYonlendirme.normalize(yanit)
        let atif = normYanit.split(whereSeparator: { !$0.isLetter }).contains { k in atifKokleri.contains { k.hasPrefix($0) } }
        let ortakSayi = yanitSayilari.contains { kanitSayilari.contains($0.rakamlar) }
        guard atif || ortakSayi else { return [] }

        var bulgular: [String] = []
        var gorulen = Set<String>()
        func ekle(_ s: String) { if gorulen.insert(AtolyeYonlendirme.normalize(s)).inserted { bulgular.append(s) } }
        for s in yanitSayilari where !kanitSayilari.contains(s.rakamlar) { ekle(s.ham) }
        let normKanit = AtolyeYonlendirme.normalize(kanitTemiz)
        let normSoru = AtolyeYonlendirme.normalize(soru)
        for ad in ozelAdlar(yanit) {
            let n = AtolyeYonlendirme.normalize(ad)
            if normKanit.contains(n) || normSoru.contains(n) { continue }
            ekle(ad)
        }
        return Array(bulgular.prefix(enFazlaBulgu))
    }

    /// `\d+([.,:]\d+)*` sayıları; karşılaştırma yalnız rakamlarla ("19.45" = "19:45", "1.250" = "1250").
    /// `listeNumarasiAtla`: satır başındaki "12." / "3)" liste numaraları atlanır.
    static func sayilar(_ metin: String, listeNumarasiAtla: Bool = false) -> [Sayi] {
        guard let re = try? NSRegularExpression(pattern: #"\d+(?:[.,:]\d+)*"#) else { return [] }
        let ns = metin as NSString
        var sonuc: [Sayi] = []
        for m in re.matches(in: metin, range: NSRange(location: 0, length: ns.length)) {
            let ham = ns.substring(with: m.range)
            if listeNumarasiAtla {
                let sonra = m.range.location + m.range.length
                let ardi = sonra < ns.length ? ns.substring(with: NSRange(location: sonra, length: 1)) : ""
                let satirBasi = ns.substring(to: m.range.location).split(separator: "\n", omittingEmptySubsequences: false).last?
                    .trimmingCharacters(in: .whitespaces).isEmpty ?? true
                if satirBasi, ardi == "." || ardi == ")" { continue }
            }
            sonuc.append(Sayi(ham: ham, rakamlar: ham.filter(\.isNumber)))
        }
        return sonuc
    }

    /// Kanıttaki bir sayının eşdeğer rakam dizileri: tam hâli ve kuruş/ondalık sıfırı atılmış hâli ("1.250,00" → "125000", "1250").
    static func esdegerler(_ s: Sayi) -> [String] {
        var e = [s.rakamlar]
        if let son = s.ham.lastIndex(where: { $0 == "," || $0 == "." }), s.ham.distance(from: son, to: s.ham.endIndex) == 3 {
            let tam = s.ham[..<son].filter(\.isNumber)
            if !tam.isEmpty { e.append(String(tam)) }
        }
        return e
    }

    /// Cümle başı olmayan, en az 3 harfli, büyük harfle başlayan sözcükler (kesme işaretinden sonrası atılır);
    /// ay/gün adları ve `yasakAdlar` hariç.
    static func ozelAdlar(_ metin: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"(?<![\p{L}\p{M}\d])\p{Lu}[\p{L}\p{M}]{2,}"#) else { return [] }
        let ns = metin as NSString
        let atlanan = CharacterSet(charactersIn: " \t*_#>`\"'“”‘’(«[-•–—")
        var sonuc: [String] = []
        for m in re.matches(in: metin, range: NSRange(location: 0, length: ns.length)) {
            let oncesi = ns.substring(to: m.range.location)
            var kirpik = Substring(oncesi)
            while let c = kirpik.unicodeScalars.last, atlanan.contains(c) { kirpik = kirpik.dropLast() }
            if kirpik.isEmpty || ".!?:\n|".contains(kirpik.last!) { continue }   // cümle/satır/hücre başı
            let ad = ns.substring(with: m.range)
            let n = AtolyeYonlendirme.normalize(ad)
            if aylar.contains(n) || gunler.contains(n) || yasakAdlar.contains(n) { continue }
            sonuc.append(ad)
        }
        return sonuc
    }

    // MARK: Teslim edilmeyen işler

    /// Teslim metninden, o teslimi yapan araçlar. Bilinmeyen teslim nil: teslim edilmiş sayılır (yanlış "Yapılmayan" yazılmaz).
    static func teslimAraclari(_ teslim: String) -> Set<String>? {
        let kelimeler = AtolyeYonlendirme.normalize(teslim).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        func var_(_ kokler: [String]) -> Bool { kelimeler.contains { k in kokler.contains { k.hasPrefix($0) } } }
        var araclar = Set<String>()
        if var_(["excel", "xlsx"]) || (var_(["tablo"]) && var_(["dosya"])) { araclar.insert("excelOlustur") }
        else if var_(["pdf", "docx", "word", "belge"]) { araclar.insert("ofisBelgesiOlustur") }
        if var_(["takvim", "etkinlik", "randevu"]) { araclar.insert("takvim") }
        if var_(["hatirlat", "alarm"]) { araclar.formUnion(["hatirlatici", "zamanlayici"]) }
        if var_(["gonder", "ilet", "sms", "whatsapp"]) { araclar.insert("iletisim") }   // "veliye mesaj yaz" taslaktır, gönderme sayılmaz
        if var_(["indir"]) { araclar.insert("indirmeler") }
        if var_(["not", "hafiza", "kayd"]) { araclar.formUnion(["hafiza", "calismaAlani"]) }
        return araclar.isEmpty ? nil : araclar
    }

    /// Kullanıcının istediği ayrı teslimlerden yapılmayanlar. Plan maddesi bitti ise ya da teslimi yapan araçlardan biri
    /// (alt ajan her aileyi sayar) başarılıysa teslim edilmiş sayılır.
    static func yapilmayanlar(teslimler: [String], plan: [PlanMaddesi], basariliAraclar: Set<String>) -> [String] {
        let bitenler = Set(plan.filter { if case .bitti = $0.durum { true } else { false } }.map { AtolyeYonlendirme.normalize($0.metin) })
        return teslimler.compactMap { ham in
            let t = ham.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            if bitenler.contains(AtolyeYonlendirme.normalize(String(t.prefix(140)))) { return nil }
            guard let araclar = teslimAraclari(t) else { return nil }
            return araclar.union(EylemIddiasi.ortakAraclar).isDisjoint(with: basariliAraclar) ? t : nil
        }
    }

    /// Yanıtın sonuna eklenecek satır ("\n\nYapılmayan: a; b"); boşsa nil.
    static func yapilmayanSatiri(_ yapilmayanlar: [String]) -> String? {
        yapilmayanlar.isEmpty ? nil : "\n\nYapılmayan: " + yapilmayanlar.joined(separator: "; ")
    }
}
