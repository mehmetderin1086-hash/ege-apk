import Foundation

nonisolated enum CalismaKipi: String, CaseIterable, Sendable {
    case sohbet, arastirma, kod, yazi, gorsel, arsiv, belge
    var ad: String {
        switch self {
        case .sohbet: "Sesli asistan"
        case .arastirma: "Araştırma"
        case .kod: "Kod yardımcısı"
        case .yazi: "Yazı atölyesi"
        case .gorsel: "Görsel üretimi"
        case .arsiv: "Sohbet arşivi"
        case .belge: "Belge seçimi"
        }
    }
    var talimat: String {
        switch self {
        case .sohbet: "Günlük sesli asistan kipi. Uygun telefon aracını kullan; kısa ve doğal cevap ver."
        case .kod: "Kod kipi. Kod blokları, dosya adları ve gerektiğinde test örnekleri ver. Çalıştırmadığın kod için çalıştı deme. Terminal erişimin yok."
        case .arastirma: "Araştırma kipi. Güncel bilgi için webArastir aracını (canlı/bugünkü konularda guncel=true) kullan; kaynak bağlantılarını ver. Canlı skor, haber, fiyat gibi değişen konularda ve bunların devam sorularında (\"goller\", \"kim attı\") ezberden ya da önceki turdan yanıt verme, her seferinde yeniden ara ve verinin tarihini söyle. Web kapalıysa veya başarısızsa bunu belirt, doğrulanmış gibi konuşma."
        case .yazi: "Yazı kipi. İstenen metni, özeti veya düzenlemeyi eksiksiz hazırla. Seslendirme için kısaltma yapma."
        case .gorsel, .arsiv, .belge: ""
        }
    }
}

nonisolated enum AtolyeYonlendirme {
    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// Only clear commands bypass semantic routing. Negations and mixed requests go to the model.
    static func hizli(_ metin: String, ekVar: Bool = false) -> CalismaKipi? {
        let s = normalize(metin)
        if ["merhaba", "selam", "tesekkurler", "sag ol", "saat kac", "saat kac?", "pilim kac", "pil durumu"].contains(s) { return .sohbet }
        if s.range(of: #"\b(degil|istemiyorum|yapma|uretme|yazma|cizme|acma)\b"#, options: .regularExpression) != nil { return nil }
        if s.range(of: #"\b(arastir|kaynaklardan dogrula|kaynaklariyla karsilastir)[.!?]*$"#, options: .regularExpression) != nil { return .arastirma }
        // Güncel olgu soruları model bilgisiyle yanıtlanamaz; tek web araması model→araç→model döngüsünden çok daha hızlıdır.
        if !ekVar, s.range(of: #"\b(mac|maci|macin|fikstur\w*|skor\w*|puan durumu|dolar|euro|altin|borsa|son dakika|kimle oynuyor)\b"#, options: .regularExpression) != nil { return .arastirma }
        if ["sohbet arsivini ac", "eski sohbetlerimi goster", "gecmis sohbetleri ac", "sohbet gecmisimi goster"].contains(s) { return .arsiv }
        if !ekVar, ["pdf sec", "dosya sec", "belge yukle", "pdf yukle", "belge ekle"].contains(s) { return .belge }
        // Literal output requests; terms embedded in questions or code are resolved semantically.
        if !ekVar, s.range(of: #"^(bir |bana |benim icin )?(resim|gorsel|afis|logo) (uret|olustur|ciz|tasarla)(\b|:)"#, options: .regularExpression) != nil { return .gorsel }
        return nil
    }
    static func devamKipi(_ metin: String, onceki: CalismaKipi, oncekiIstek: String) -> CalismaKipi? {
        guard !oncekiIstek.isEmpty, [.kod, .yazi, .arastirma, .sohbet].contains(onceki) else { return nil }
        let s = normalize(metin).trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        if ["bunu kisalt", "biraz kisalt", "devam et", "bunu daha samimi yap", "bunu daha ayrintili yaz", "tekrar dene", "yeniden dene", "gelmedi", "indirmiyor", "sorun mu var"].contains(s) { return onceki }
        if onceki == .kod, ["buna birim testlerini de ekle", "test de ekle", "buna test ekle"].contains(s) { return .kod }
        return nil
    }
    /// Local selection adds no network round trip. The answer model still understands arbitrary requests.
    static func yerel(_ metin: String, ekVar: Bool = false) -> CalismaKipi {
        let s = normalize(metin)
        let webKaynak = ["internetten", "web sitesinde", "web sitesinden", "sitede", "sitesinden", "kitapyurdu", "hepsiburada", "trendyol"].contains(where: s.contains) || s.contains("https://")
        let veriIstegi = ["bul", "listele", "tara", "kazi", "karsilastir", "fiyat", "tumunu", "butununu"].contains(where: s.contains)
        if webKaynak && veriIstegi { return .arastirma }
        // "uygulama/program" tek başına kod sinyali değil ("sınıf içi uygulama hazırla", "takvime program ekle"); dil adı ya da "kod" gerekir.
        // Platform (ios/android) ve script/betik yalnız kod nesnesiyle sayılır: "iOS kestirmesi oluştur", "Android telefonuna mesaj yaz",
        // "ders videosu için script yaz" telefon/yazı işidir, sunucu kodlamasına gitmez.
        let kod = s.range(of: #"\b(python|swift|swiftui|javascript|typescript|html|css|sql|kod|kodu|kodunu|fonksiyon|birim test|bug|xcode)\b"#, options: .regularExpression) != nil
            || s.range(of: #"\b(ios|android|mobil)( icin)? (uygulama\w*|app\w*|widget\w*|proje\w*)\b"#, options: .regularExpression) != nil
            || s.range(of: #"\b(bash|shell|zsh|kabuk|terminal|python) (script\w*|betig\w*|betik\w*)\b"#, options: .regularExpression) != nil
        let eylem = s.range(of: #"\b(yaz|yazdir|duzelt|gelistir|hazirla|olustur|calistir|derle|test et|ekle)\b"#, options: .regularExpression) != nil
        if kod && eylem { return .kod }
        if s.contains("arastir") && !s.contains("arastirma yapma") { return .arastirma }
        // Sözcük sınırlı: "resmî tatil", "resmi dilekçe" sıfatı görsel değildir; tek başına "resmi" yalnız çiz/üret ile sayılır.
        // "kedi resmi oluştur/tasarla": iyelikli "resmi" fiilin hemen önündedir; sıfat "resmî" ise bir adın önünde durur.
        let gorselSoz = s.range(of: #"\b(resim\w*|resmin\w*|gorsel\w*|afis\w*|logo\w*)\b"#, options: .regularExpression) != nil
            || (s.range(of: #"\bresmi\b"#, options: .regularExpression) != nil && ["ciz", "uret"].contains(where: { s.hasSuffix($0) }))
            || s.range(of: #"\bresmi (tasarla|olustur)$"#, options: .regularExpression) != nil
        if !ekVar, !s.contains("uretme"), !s.contains("cizme"), s.range(of: #"\byaz\w*"#, options: .regularExpression) == nil,
           gorselSoz,
           ["ciz", "uret", "tasarla", "olustur"].contains(where: { s.hasSuffix($0) }) { return .gorsel }
        // Emir/rica biçimi; "yazdı", "beyaz", "yazılı", "yazın" (mevsim), "düzenleyici", "kısaltması" soruları sohbet kalır.
        // Rica her kökte aynı: -(a/i)r mısın(ız), -(y)abilir/-(y)ebilir mısın(ız), -sana/-sene. "çevirebilir mi?" (soru) sohbet kalır.
        if s.range(of: #"\b(yaz|yazsana|hazirla|hazirlasana|ozetle|ozetlesene|cevir|cevirsene|kisalt|kisaltsana|duzenle|duzenlesene)\b|\b(yaz|hazirla|ozetle|cevir|kisalt|duzenle)(ir|ar|r|y?[ae]bilir) misin(iz)?\b"#,
                   options: .regularExpression) != nil { return .yazi }
        return .sohbet
    }
    static func coz(_ yanit: String) -> CalismaKipi? {
        CalismaKipi(rawValue: normalize(yanit).trimmingCharacters(in: CharacterSet(charactersIn: "`\". \n")))
    }
    /// P3.4: istem süzgecinin seçebildiği kipler (görsel/arşiv/belge yerel kurallarla seçilir, modelden alınmaz).
    static let suzgecKipleri: [CalismaKipi] = [.sohbet, .arastirma, .kod, .yazi]

    /// P3.4: süzgeç talimatına giren kısa kip tanımları (eski, hiç kullanılmayan sınıflandırma talimatının kısaltılmışı).
    static let suzgecKipTanimi = """
    kip, isteğin ASIL amacına göre: sohbet = gündelik sohbet, bilgi sorusu ya da telefon işlemi (saat, uygulama açma, alarm); \
    arastirma = web/kaynak tarama, güncel bilgi doğrulama, kaynaklı karşılaştırma; kod = kod yazma, hata düzeltme, yazılım inceleme; \
    yazi = makale, mesaj taslağı, öykü, çeviri, özet ya da metin düzenleme. Olumsuz ifadeleri dikkate al; "bunu kısalt", "devam et" \
    gibi devam mesajlarında önceki isteğin kipini koru.
    """
}
