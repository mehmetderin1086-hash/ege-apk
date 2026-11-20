import Foundation

/// Yazıyla söylenen Türkçe sayıları rakama çevirir ("on beşinci cüz" → "15. cuz", "yüz otuz sekiz" → "138").
/// YALNIZ karşılaştırma içindir (indirme eşleşmesi, kısıt denetimi); modele ve ekrana gitmez.
/// Girdi `AtolyeYonlendirme.normalize` ile ASCII'ye katlanmış (küçük harfli) metindir.
/// Eş sesli sözcükleri bozmamak için ("yemek yedi", "masanın altı", "bine", "yüz yüze", "Sezen Aksu bestesi", "onda"):
/// - en az İKİ ardışık sayı sözcüğü toplanır ("on beş" → 15, "iki bin yirmi altı" → 2026);
/// - TEK sayı sözcüğü yalnız ardından bir sayaç adı (cüz, bölüm, sayfa, gün …) geliyorsa çevrilir ("yedi gün" → "7 gun");
/// - "bir" tek başına hiç çevrilmez ("bir gün" aynen kalır); yalnız "on bir", "bin bir" gibi bileşiklerde ve "bir buçuk"ta;
/// - hâl eki yalnız dizinin son sözcüğünde tanınır ("on beşte" → "15'te"); tek başına "beşte"/"onda" çevrilmez;
/// - sıra sayıları "N." olur ("yüzüncü" → "100.");
/// - "X buçuk" → "X,5"; saat kalıpları: "saat X Y" → "saat X.Y", "X buçukta" → "X.30", "X'i çeyrek geçe" → "X.15",
///   "X'e çeyrek var" → "(X-1).45".
nonisolated enum TurkceSayi {
    /// Önceki sözcükle arasında yalnız boşluk varsa `bitisik` (aynı sayı dizisine girebilir).
    private struct Sozcuk { let metin: String; let aralik: Range<String.Index>; let bitisik: Bool }
    private struct Cozum { let deger: Int; let sira: Bool; let ek: String; let taban: String }
    private struct Dizi { let deger: Int; let son: Int; let sira: Bool; let ek: String; let adet: Int }

    static let asallar: [String: Int] = ["sifir": 0, "bir": 1, "iki": 2, "uc": 3, "dort": 4, "bes": 5, "alti": 6, "yedi": 7, "sekiz": 8,
                                         "dokuz": 9, "on": 10, "yirmi": 20, "otuz": 30, "kirk": 40, "elli": 50, "altmis": 60, "yetmis": 70,
                                         "seksen": 80, "doksan": 90, "yuz": 100, "bin": 1000]
    static let siralar: [String: Int] = ["birinci": 1, "ikinci": 2, "ucuncu": 3, "dorduncu": 4, "besinci": 5, "altinci": 6, "yedinci": 7,
                                         "sekizinci": 8, "dokuzuncu": 9, "onuncu": 10, "yirminci": 20, "otuzuncu": 30, "kirkinci": 40,
                                         "ellinci": 50, "altmisinci": 60, "yetmisinci": 70, "sekseninci": 80, "doksaninci": 90,
                                         "yuzuncu": 100, "bininci": 1000]
    /// Tek sayı sözcüğünü rakama çeviren sayaç adları (ekli biçimleri de: "gunluk", "sayfalik", "hattin").
    static let sayaclar = ["cuz", "bolum", "sure", "sayfa", "dakika", "saat", "gun", "yil", "sinif", "ayet", "hat", "numara"]
    /// Sayaç önekiyle başlayan ama sayaç olmayan sözcükler.
    private static let sayacDisi = ["cuzdan", "gunes", "yildiz", "yildirim", "surekli", "surec", "suren", "sureyya", "saatci", "hata", "hatir",
                                    "hatun", "hatip", "siniflandir"]
    private static let siraEkleri: Set<String> = ["", "si", "su", "sini", "sunu", "sine", "suna", "sinde", "sunda", "sinden", "sundan", "sinin",
                                                  "sunun", "yi", "yu", "ye", "ya", "de", "da", "den", "dan", "nin", "nun", "ler", "lar", "leri", "lari"]
    private static let belirtmeEkleri: Set<String> = ["i", "u", "yi", "yu"]
    private static let yonelmeEkleri: Set<String> = ["a", "e", "ya", "ye"]

    /// Hâl ekli sayı biçimleri ünlü uyumuyla üretilir: "beste" → (5, "te"), "yirmiye" → (20, "ye"), "dorde" → (4, "e").
    private static let ekliBicimler: [String: (deger: Int, ek: String, taban: String)] = {
        // (taban, ünlüyle başlayan ek için gövde, kalın ünlü (a/ı/o/u), yuvarlak (o/ö/u/ü), sert ünsüzle biter)
        let tablo: [(String, String, Bool, Bool, Bool)] = [
            ("sifir", "sifir", true, false, false), ("bir", "bir", false, false, false), ("iki", "iki", false, false, false),
            ("uc", "uc", false, true, true), ("dort", "dord", false, true, true), ("bes", "bes", false, false, true),
            ("alti", "alti", true, false, false), ("yedi", "yedi", false, false, false), ("sekiz", "sekiz", false, false, false),
            ("dokuz", "dokuz", true, true, false), ("on", "on", true, true, false), ("yirmi", "yirmi", false, false, false),
            ("otuz", "otuz", true, true, false), ("kirk", "kirk", true, false, true), ("elli", "elli", false, false, false),
            ("altmis", "altmis", true, false, true), ("yetmis", "yetmis", false, false, true), ("seksen", "seksen", false, false, false),
            ("doksan", "doksan", true, false, false), ("yuz", "yuz", false, true, false), ("bin", "bin", false, false, false)]
        var sonuc: [String: (deger: Int, ek: String, taban: String)] = [:]
        for (taban, unluGovde, kalin, yuvarlak, sert) in tablo {
            guard let deger = asallar[taban] else { continue }
            let a = kalin ? "a" : "e", i = yuvarlak ? "u" : "i", d = sert ? "t" : "d"
            let unluyleBiter = "aeiou".contains(taban.last ?? "x")
            let bicimler: [(String, String)]   // (gövde, ek)
            if unluyleBiter {
                bicimler = [("y" + a), ("y" + i), ("d" + a), ("d" + a + "n"), ("n" + i + "n"), ("yl" + a)].map { (taban, $0) }
            } else {
                bicimler = [(unluGovde, a), (unluGovde, i), (unluGovde, i + "n"), (taban, d + a), (taban, d + a + "n"), (taban, "l" + a)]
            }
            for (govde, ek) in bicimler where sonuc[govde + ek] == nil {
                // Ekin gövdeye bitişen kısmı ekranda gösterilir: "dorde" → "4'e".
                sonuc[govde + ek] = (deger, String((govde + ek).dropFirst(taban.count)), taban)
            }
        }
        return sonuc
    }()

    /// Metindeki yazıyla sayıları rakama çevirir; dönüşmeyen her şey aynen kalır.
    static func normalize(_ s: String) -> String { cozumle(s).metin }

    /// En az iki sözcükten doğmuş yalın sayılar ("yuz otuz sekiz" → [138]); sıra sayıları, saat kalıpları ve ardından
    /// hat/numara dışı bir sayaç gelen diziler ("yirmi dort saat") dahil değildir. İETT hat kodu ayıklaması kullanır.
    static func cokSozcukluSayilar(_ s: String) -> [Int] { cozumle(s).cokSozcuklu }

    // MARK: Çözümleme

    private static func sozcukle(_ s: String) -> [Sozcuk] {
        guard let re = try? NSRegularExpression(pattern: #"[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*"#) else { return [] }
        var sonuc: [Sozcuk] = []
        var oncekiSon: String.Index?
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let r = Range(m.range, in: s) else { continue }
            var bitisik = false
            if let o = oncekiSon {
                let ara = s[o..<r.lowerBound]
                bitisik = !ara.isEmpty && ara.allSatisfy(\.isWhitespace)
            }
            sonuc.append(Sozcuk(metin: String(s[r]).lowercased(), aralik: r, bitisik: bitisik))
            oncekiSon = r.upperBound
        }
        return sonuc
    }

    private static func cozumle(_ s: String) -> (metin: String, cokSozcuklu: [Int]) {
        let sz = sozcukle(s)
        guard !sz.isEmpty else { return (s, []) }
        var degisimler: [(Range<String.Index>, String)] = []
        var cok: [Int] = []
        var i = 0
        while i < sz.count {
            if let e = eslestir(sz, i) {
                degisimler.append((sz[i].aralik.lowerBound..<sz[e.son].aralik.upperBound, e.metin))
                if let c = e.cok { cok.append(c) }
                i = e.son + 1
            } else {
                i += 1
            }
        }
        guard !degisimler.isEmpty else { return (s, cok) }
        var out = ""
        var imlec = s.startIndex
        for (r, m) in degisimler {
            out += s[imlec..<r.lowerBound]
            out += m
            imlec = r.upperBound
        }
        out += s[imlec...]
        return (out, cok)
    }

    /// Tek sözcüğün sayı değeri: yalın ("bes"), hâl ekli ("beste") ya da sıra sayısı ("besinci", "besincisi").
    private static func coz(_ w: String) -> Cozum? {
        if let v = asallar[w] { return Cozum(deger: v, sira: false, ek: "", taban: w) }
        if let e = ekliBicimler[w] { return Cozum(deger: e.deger, sira: false, ek: e.ek, taban: e.taban) }
        for (k, v) in siralar where w.hasPrefix(k) && siraEkleri.contains(String(w.dropFirst(k.count))) {
            return Cozum(deger: v, sira: true, ek: "", taban: k)
        }
        return nil
    }

    /// Rakamla yazılmış sözcük ("3", "3'u"): yalnız buçuk/çeyrek kalıplarına girer.
    private static func rakam(_ w: String) -> (deger: Int, ek: String)? {
        let parca = w.split(whereSeparator: { $0 == "'" || $0 == "’" }).map(String.init)
        guard let ilk = parca.first, (1...4).contains(ilk.count), ilk.allSatisfy(\.isASCII), let v = Int(ilk), parca.count <= 2 else { return nil }
        return (v, parca.count == 2 ? parca[1] : "")
    }

    /// `i`. sözcükten başlayan en uzun geçerli sayı dizisi. Basamak sırası bozulursa ("bes on", "alti yedi") dizi orada biter.
    private static func dizi(_ sz: [Sozcuk], _ i: Int, birIzinli: Bool) -> Dizi? {
        var toplam = 0, grup = 0, sonBasamak = Int.max, adet = 0, j = i
        var yuzVar = false, binVar = false, sira = false, ek = ""
        while j < sz.count, j == i || sz[j].bitisik {
            guard let c = coz(sz[j].metin) else { break }
            let v = c.deger
            if v == 0 {
                // Sıfır başka sözcükle birleşmez.
                guard adet == 0 else { break }
                adet = 1; sira = c.sira; ek = c.ek; j += 1
                break
            }
            if v == 1000 {
                guard !binVar else { break }
                toplam = (grup == 0 ? 1 : grup) * 1000; grup = 0; sonBasamak = Int.max; yuzVar = false; binVar = true
            } else if v == 100 {
                guard !yuzVar, grup < 10 else { break }
                grup = (grup == 0 ? 1 : grup) * 100; yuzVar = true; sonBasamak = 100
            } else {
                let basamak = v >= 10 ? 10 : 1
                guard basamak < sonBasamak else { break }
                grup += v; sonBasamak = basamak
            }
            adet += 1; sira = c.sira; ek = c.ek
            j += 1
            if c.sira || !c.ek.isEmpty { break }
            // Tek başına "bir" bileşik başlatmaz ("bir yuz" = bir yüz, "bir bin" anlamsız).
            if adet == 1, c.taban == "bir", !birIzinli { break }
        }
        guard adet > 0 else { return nil }
        return Dizi(deger: toplam + grup, son: j - 1, sira: sira, ek: ek, adet: adet)
    }

    private static func sayacMi(_ sz: [Sozcuk], _ k: Int, yalnizHat: Bool = false) -> Bool {
        guard k < sz.count, sz[k].bitisik else { return false }
        let w = sz[k].metin
        if sayacDisi.contains(where: { w.hasPrefix($0) }) { return false }
        let liste = yalnizHat ? ["hat", "numara"] : sayaclar
        return liste.contains { w == $0 || (w.hasPrefix($0) && w.count - $0.count <= 6) }
    }

    private static func ekMetni(_ ek: String) -> String { ek.isEmpty ? "" : "'" + ek }

    /// Buçuk ve çeyrek kalıpları: "uc bucuk" → "3,5", "iki bucukta" → "2.30", "ucu ceyrek gece" → "3.15", "dorde ceyrek var" → "3.45".
    private static func kalip(_ sz: [Sozcuk], son: Int, deger: Int, ek: String, saat: Bool) -> (son: Int, metin: String)? {
        let n = son + 1
        guard n < sz.count, sz[n].bitisik else { return nil }
        let s1 = sz[n].metin
        if ek.isEmpty, s1.hasPrefix("bucu") {
            let zaman = saat || s1 == "bucukta" || s1 == "bucukda"
            return (n, zaman ? "\(deger).30" : "\(deger),5")
        }
        guard !ek.isEmpty, s1 == "ceyrek", n + 1 < sz.count, sz[n + 1].bitisik else { return nil }
        let s2 = sz[n + 1].metin
        if belirtmeEkleri.contains(ek), s2.hasPrefix("gec") { return (n + 1, "\(deger).15") }
        if yonelmeEkleri.contains(ek), s2 == "var" || s2.hasPrefix("kal") {
            return (n + 1, "\(deger <= 1 ? 12 : deger - 1).45")
        }
        return nil
    }

    private static func eslestir(_ sz: [Sozcuk], _ i: Int) -> (son: Int, metin: String, cok: Int?)? {
        let oncekiSaat = i > 0 && sz[i].bitisik && sz[i - 1].metin == "saat"
        if let r = rakam(sz[i].metin) {
            guard let k = kalip(sz, son: i, deger: r.deger, ek: r.ek, saat: oncekiSaat) else { return nil }
            return (k.son, k.metin, nil)
        }
        guard let d = dizi(sz, i, birIzinli: oncekiSaat) else { return nil }
        if !d.sira, let k = kalip(sz, son: d.son, deger: d.deger, ek: d.ek, saat: oncekiSaat) { return (k.son, k.metin, nil) }
        if oncekiSaat, !d.sira, d.deger <= 24 {
            // "saat on dort otuz" → "saat 14.30"; "saat yedide" → "saat 7'de".
            if d.ek.isEmpty, d.son + 1 < sz.count, sz[d.son + 1].bitisik,
               let y = dizi(sz, d.son + 1, birIzinli: true), !y.sira, (1...59).contains(y.deger) {
                return (y.son, "\(d.deger)." + String(format: "%02d", y.deger) + ekMetni(y.ek), nil)
            }
            return (d.son, "\(d.deger)" + ekMetni(d.ek), nil)
        }
        if d.adet >= 2 {
            let metin = "\(d.deger)" + (d.sira ? "." : ekMetni(d.ek))
            let sonraSayac = sayacMi(sz, d.son + 1) && !sayacMi(sz, d.son + 1, yalnizHat: true)
            return (d.son, metin, d.sira || sonraSayac ? nil : d.deger)
        }
        if d.sira { return (d.son, "\(d.deger).", nil) }
        // Tek sözcük: yalnız ekisiz, "bir" değil ve ardından sayaç geliyorsa ("yedi gun", "on cuz").
        if d.ek.isEmpty, sz[i].metin != "bir", sayacMi(sz, d.son + 1) { return (d.son, "\(d.deger)", nil) }
        return nil
    }
}
