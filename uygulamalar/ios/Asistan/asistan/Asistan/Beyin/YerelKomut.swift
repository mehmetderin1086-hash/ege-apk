import Foundation

/// Model gerektirmeyen tek anlamlı telefon komutları (fener, zamanlayıcı, alarm, takvim, tarih).
/// Saf çözücü: yalnız TAM eşleşme kabul edilir ("feneri aç ve annemi ara" eşleşmez, araçlı modele gider).
/// Çevrimdışıyken de çalışır; `Beyin.yerelKomutDene` var olan araçları doğrudan çağırır.
nonisolated enum YerelKomut {
    enum Komut: Equatable, Sendable {
        case fener(Bool)
        case zamanlayici(saniye: Int, etiket: String?)
        case alarm(saat: Int, dakika: Int)
        /// 0 bugün, 1 yarın.
        case takvim(gun: Int)
        case tarih
        /// Wi-Fi, Bluetooth, uçak modu, odak, görünüm, ses düzeyi, ekran kilidi (`SistemKoprusu`).
        case sistem(SistemKomutu)
    }

    /// Komut metni: normalize (küçük harf, aksansız, ı→i), kıvrık kesme işareti düz, sondaki noktalama ve "lütfen" atılır.
    static func duzle(_ metin: String) -> String {
        var s = AtolyeYonlendirme.normalize(metin).replacingOccurrences(of: "’", with: "'")
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: ".!?,;… ").union(.whitespacesAndNewlines))
        s = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        for ek in ["lutfen "] where s.hasPrefix(ek) { s.removeFirst(ek.count) }
        for ek in [" lutfen"] where s.hasSuffix(ek) { s.removeLast(ek.count) }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: ".!?,; "))
    }

    static func coz(_ metin: String) -> Komut? {
        let s = duzle(metin)
        guard !s.isEmpty, s.count <= 80 else { return nil }
        if let k = fener(s) { return k }
        if let k = sistem(s) { return k }
        if let k = zamanlayici(s, ham: metin) { return k }
        if let k = alarm(s) { return k }
        if let k = takvim(s) { return k }
        if tarihMi(s) { return .tarih }
        return nil
    }

    /// Çevrimdışıyken ağ beklemeden yanıtlanabilecek istek (kısa yanıt, yerel saat ya da yerel komut).
    static func cevrimdisiYanitlanir(_ m: String) -> Bool {
        HizliModelSecimi.yerelKisaYanit(m) != nil || HizliModelSecimi.yerelSaat(m) != nil || coz(m) != nil
    }

    /// Komutun kullandığı araç (izin politikası bu adla denetlenir); tarih araç gerektirmez.
    static func aracAdi(_ k: Komut) -> String? {
        switch k {
        case .fener, .sistem: "cihaz"
        case .zamanlayici, .alarm: "zamanlayici"
        case .takvim: "takvim"
        case .tarih: nil
        }
    }

    /// Telefonda kalıcı yan etkisi olan komut (dış kaynaklı turda kısa yoldan çalışmaz, onaylı zincire düşer).
    static func yanEtkili(_ k: Komut) -> Bool {
        switch k {
        case .fener, .zamanlayici, .alarm, .sistem: true
        case .takvim, .tarih: false
        }
    }

    // MARK: Desenler

    /// Tam eşleşme: yakalama grupları (eşleşmeyen grup nil); eşleşme yoksa nil.
    static func eslesme(_ desen: String, _ s: String) -> [String?]? {
        guard let r = try? NSRegularExpression(pattern: "^(?:" + desen + ")$") else { return nil }
        let ns = s as NSString
        guard let m = r.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }

    static func fener(_ s: String) -> Komut? {
        let ozne = #"(?:el )?fener(?:i|ini|imi)?"#
        if eslesme(ozne + #" (?:ac|yak|acar misin|yakar misin|acsana|yaksana|acabilir misin)"#, s) != nil { return .fener(true) }
        if eslesme(ozne + #" (?:kapat|sondur|kapatir misin|sondurur musun|kapatsana|kapatabilir misin)"#, s) != nil { return .fener(false) }
        return nil
    }

    /// Sistem ayarları: "wifi'yi kapat", "uçak moduna geç", "karanlık moda geç", "sesi yüzde 50 yap", "ekranı kilitle".
    static func sistem(_ s: String) -> Komut? {
        let s = s.replacingOccurrences(of: "'", with: "")
        let ac = #"(ac|acar misin|acsana|acabilir misin|etkinlestir|gec|gecer misin|gecsene|acik yap)"#
        let kapat = #"(kapat|kapatir misin|kapatsana|kapatabilir misin|devre disi birak|cik|cikar misin|cikabilir misin|kaldir|kapa)"#
        let mod = #"(?: mod(?:u|unu|una|undan))?"#
        let ozneler: [(String, SistemKomutu.Ayar)] = [
            (#"wi ?-?fi(?:yi|yu|i)?|kablosuz ag(?:i)?"#, .wifi),
            (#"bluetooth(?:u|yu|i)?"#, .bluetooth),
            (#"ucak mod(?:u|unu|una|undan)"#, .ucak),
            (#"(?:mobil|hucresel) veri(?:yi|leri|lerini)?"#, .mobilveri),
            (#"dusuk guc"# + mod, .dusukguc),
            (#"rahatsiz etme(?:yi)?"# + mod + #"|odak"# + mod + #"|odagi"#, .odak),
            (#"hotspot(?:u)?|kisisel erisim noktas(?:i|ini)"#, .hotspot),
            (#"night shift(?:i)?|gece vardiyas(?:i|ini)"#, .gecevardiyasi),
            (#"true tone(?:u)?"#, .truetone),
            (#"(?:ekran )?(?:donme|yon) kilid(?:i|ini)"#, .donmekilidi),
        ]
        for (ozne, ayar) in ozneler {
            if eslesme("(?:" + ozne + ") " + ac, s) != nil { return .sistem(.anahtar(ayar, true)) }
            if eslesme("(?:" + ozne + ") " + kapat, s) != nil { return .sistem(.anahtar(ayar, false)) }
        }
        if eslesme(#"(?:wi ?-?fi|kablosuz ag)(?:ye|a)? baglan(?:ir misin)?"#, s) != nil { return .sistem(.anahtar(.wifi, true)) }
        if let g = eslesme(#"(karanlik|koyu|aydinlik|acik) mod(?:a|u|unu)? (gec|gecer misin|gecsene|ac|kapat|yap)"#, s), let renk = g[1], let fiil = g[2] {
            let karanlik = renk == "karanlik" || renk == "koyu"
            return .sistem(.gorunum(karanlik: fiil == "kapat" ? !karanlik : karanlik))   // "karanlık modu kapat" → açık
        }
        if let g = eslesme(#"(?:gorunumu|temayi) (karanlik|koyu|aydinlik|acik) yap"#, s), let renk = g[1] {
            return .sistem(.gorunum(karanlik: renk == "karanlik" || renk == "koyu"))
        }
        if let g = eslesme(#"(?:sesi|ses seviyesini|ses duzeyini) (?:yuzde ?|%)?([0-9]{1,3})(?:e|a|ye|ya)? (?:yap|ayarla|getir|indir|cikar|dusur)"#, s),
           let n = g[1].flatMap({ Int($0) }), n <= 100 {
            return .sistem(.ses(Int((Double(n) / 10).rounded()) * 10))
        }
        // "sesi kapat"/"sessize al" bilinçli yok: medya ses düzeyi zili susturmaz, sesli kipte "sesi kapat" konuşmayı kes demektir.
        if eslesme(#"(?:ekrani|telefonu|iphoneu|iphoneyu) kilitle"#, s) != nil { return .sistem(.kilitle) }
        return nil
    }

    static func zamanlayici(_ s: String, ham: String) -> Komut? {
        // "çay için 5 dakikalık zamanlayıcı" → etiket "çay" (özgün yazımla, en çok üç sözcük).
        var govde = s
        var etiket: String?
        if let g = eslesme(#"([a-z ]{2,30}) icin (.+)"#, s), let on = g[1], let kalan = g[2] {
            let sozcuk = on.split(separator: " ")
            guard sozcuk.count <= 3 else { return nil }
            govde = kalan
            let asil = ham.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).map(String.init)
                .drop(while: { AtolyeYonlendirme.normalize($0) == "lutfen" })
            let ad = asil.prefix(sozcuk.count).joined(separator: " ")
            etiket = ad.isEmpty ? nil : ad
        }
        let sayi = #"([0-9]{1,4}|[a-z]+(?: [a-z]+)?|yarim)"#
        let birim = #"(dakika|dk|saniye|sn|saat)"#
        let desenler = [
            sayi + " ?" + birim + #"(?:'?l[iu]k)? (?:zamanlayici|sayac|geri sayim)(?: kur| baslat| ayarla)?"#,
            #"(?:zamanlayici|sayac|geri sayim)(?: kur| baslat)? "# + sayi + " ?" + birim,
            sayi + " " + birim + #" sonra (?:haber ver|uyar|hatirlat|beni uyar|bana haber ver)"#,
        ]
        for d in desenler {
            guard let g = eslesme(d, govde), let n = g[1].flatMap(sayiDegeri), let b = g[2] else { continue }
            let carpan: Int = switch b {
            case "saniye", "sn": 1
            case "saat": 3600
            default: 60
            }
            // "yarım" yalnız saatle (yarım saat = 30 dakika) anlamlıdır.
            let saniye = g[1] == "yarim" ? (b == "saat" ? 1800 : 0) : n * carpan
            guard saniye > 0, saniye <= 86_400 else { return nil }
            return .zamanlayici(saniye: saniye, etiket: etiket)
        }
        return nil
    }

    static func alarm(_ s: String) -> Komut? {
        let zaman = #"([0-9]{1,2})(?:[:.]([0-9]{2}))?"#
        let ek = #"(?:'?(?:de|da|te|ta|e|a|ye|ya))?"#
        let kur = #" (?:icin )?alarm(?:i)?(?: kur| ayarla| kurar misin)?"#
        let desenler: [(String, Int)] = [
            ("(?:saat )?" + zaman + ek + kur, 0),
            ("sabah " + zaman + ek + kur, 0),
            ("aksam " + zaman + ek + kur, 12),
            (#"alarm(?: kur)? (?:saat )?"# + zaman + ek, 0),
        ]
        for (d, ekSaat) in desenler {
            guard let g = eslesme(d, s), let h = g[1].flatMap({ Int($0) }) else { continue }
            let dk = g[2].flatMap { Int($0) } ?? 0
            let saat = (ekSaat > 0 && h < 12) ? h + ekSaat : h
            guard (0...23).contains(saat), (0...59).contains(dk) else { return nil }
            return .alarm(saat: saat, dakika: dk)
        }
        return nil
    }

    static func takvim(_ s: String) -> Komut? {
        let soru = #"(?:ne var|neler var|programim(?: ne)?|programim nasil|takvimim(?: ne)?|takvimde ne var|etkinliklerim(?: ne)?)"#
        if let g = eslesme(#"(bugun|yarin)(?:ku|ki)? "# + soru, s), let gun = g[1] { return .takvim(gun: gun == "bugun" ? 0 : 1) }
        if let g = eslesme(#"(?:takvimde|takvimimde) (bugun|yarin) (?:ne var|neler var)"#, s), let gun = g[1] { return .takvim(gun: gun == "bugun" ? 0 : 1) }
        return nil
    }

    static func tarihMi(_ s: String) -> Bool {
        ["bugun ayin kaci", "ayin kaci", "bugun gunlerden ne", "gunlerden ne", "tarih ne", "bugunun tarihi ne", "bugun tarih ne",
         "bugunun tarihi", "bugun hangi gun", "bugun ne gun", "bugun gunlerden hangisi"].contains(s)
    }

    // MARK: Sayılar

    static let birler: [String: Int] = ["bir": 1, "iki": 2, "uc": 3, "dort": 4, "bes": 5, "alti": 6, "yedi": 7, "sekiz": 8, "dokuz": 9]
    static let onlar: [String: Int] = ["on": 10, "yirmi": 20, "otuz": 30, "kirk": 40, "elli": 50, "altmis": 60]

    /// "10" → 10, "on beş" → 15, "yarım" → 1 (çağıran birimle yorumlar). Yazıyla yalnız 1-60.
    static func sayiDegeri(_ t: String) -> Int? {
        if t == "yarim" { return 1 }
        if let n = Int(t) { return n }
        let p = t.split(separator: " ").map(String.init)
        switch p.count {
        case 1: return birler[p[0]] ?? onlar[p[0]]
        case 2:
            guard let o = onlar[p[0]], o < 60, let b = birler[p[1]] else { return nil }
            return o + b
        default: return nil
        }
    }

    // MARK: Yerel metinler

    static func tarihMetni(_ simdi: Date = .now) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "d MMMM yyyy, EEEE"
        return "Bugün \(f.string(from: simdi))."
    }

    /// Alarm hedefi: bugün HH:MM (geçmişse yarın), yerel saat ISO 8601 metni ("2026-10-21T07:30").
    static func alarmZamani(saat: Int, dakika: Int, simdi: Date = .now, takvim: Calendar = .current) -> (tarih: Date, iso: String)? {
        guard let bugun = takvim.date(bySettingHour: saat, minute: dakika, second: 0, of: simdi) else { return nil }
        let hedef = bugun > simdi ? bugun : (takvim.date(byAdding: .day, value: 1, to: bugun) ?? bugun.addingTimeInterval(86_400))
        return (hedef, yerelISO(hedef, takvim: takvim))
    }

    /// Takvim aralığı: günün başı ve sonu (yerel ISO 8601).
    static func gunAraligi(gun: Int, simdi: Date = .now, takvim: Calendar = .current) -> (baslangic: String, bitis: String) {
        let bas = takvim.startOfDay(for: takvim.date(byAdding: .day, value: gun, to: simdi) ?? simdi)
        let son = (takvim.date(byAdding: .day, value: 1, to: bas) ?? bas.addingTimeInterval(86_400)).addingTimeInterval(-60)
        return (yerelISO(bas, takvim: takvim), yerelISO(son, takvim: takvim))
    }

    static func yerelISO(_ d: Date, takvim: Calendar = .current) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = takvim.timeZone; f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f.string(from: d)
    }

    static func sureMetni(_ saniye: Int) -> String {
        if saniye % 3600 == 0 { return "\(saniye / 3600) saat" }
        if saniye % 60 == 0 { return "\(saniye / 60) dakika" }
        if saniye > 60 { return "\(saniye / 60) dakika \(saniye % 60) saniye" }
        return "\(saniye) saniye"
    }
}
