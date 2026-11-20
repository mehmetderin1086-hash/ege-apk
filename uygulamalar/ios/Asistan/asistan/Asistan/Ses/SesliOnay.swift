import Foundation

/// P2.13: Sesli kipte (eller serbest / sıralı Live) `OnayKapisi` diyaloğunun sesli yanıtı. Saf karar: onayda fail-closed.
/// Yalnız tam kelime eşleşmesi onay sayılır ("evet ama bekle" belirsizdir); enerji kapısı sessizlikte tanıyıcının
/// uydurduğu "evet"i eler. Belirsizde diyalog ekranda kalır, dokunarak yanıtlanır.
nonisolated enum SesliOnayKarari {
    enum Sonuc: Equatable, Sendable { case evet, hayir, belirsiz }

    /// Onay sayılan tam ifadeler (normalleştirilmiş). "tamam"/"olur" yoktur: sohbet sözü ('tamam, anladım') onay sayılmasın.
    // "tamam"/"olur" sohbet sözüdür (arka plandaki TV/konuşma da üretir): yalnız açık onay sözcükleri sayılır.
    static let evetler: Set<String> = ["evet", "evet gönder", "evet yap", "evet ara", "onaylıyorum", "onayla"]
    /// Ret sayılan tam ifadeler (normalleştirilmiş).
    static let hayirlar: Set<String> = ["hayır", "hayır gönderme", "iptal", "vazgeç", "dur", "istemiyorum", "gönderme"]
    /// En yüksek 250 ms penceresinin RMS alt sınırı: uzun tamponda kısa "evet" seyrelmesin, sessizlik geçmesin.
    static let pencereEsigi: Float = 0.02
    /// Enerji penceresinin süresi (sn).
    static let pencereSuresi: Double = 0.25
    /// Seslendirilen sorunun üst sınırı (karakter).
    static let soruSiniri = 400

    /// Türkçe küçük harf, birleşik biçim (NFD "İ" = I + U+0307 dahil), noktalama silinir, boşluklar sadeleşir.
    static func normalle(_ s: String) -> String {
        let tr = Locale(identifier: "tr_TR")
        let k = s.precomposedStringWithCanonicalMapping.lowercased(with: tr).precomposedStringWithCanonicalMapping
        let harfler = k.unicodeScalars.map { u -> Character in
            CharacterSet.punctuationCharacters.contains(u) || CharacterSet.symbols.contains(u) ? " " : Character(u)
        }
        // NFD'den kalan birleştirici nokta (U+0307) "i"nin üstünde kalmasın.
        let temiz = String(harfler).replacingOccurrences(of: "\u{0307}", with: "")
        return temiz.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Sözlük kararı (enerjiden bağımsız): tam eşleşme; aksi `.belirsiz`.
    static func sozcukKarari(_ metin: String) -> Sonuc {
        let n = normalle(metin)
        if evetler.contains(n) { return .evet }
        if hayirlar.contains(n) { return .hayir }
        return .belirsiz
    }

    /// Ses örnekleriyle birlikte karar. Örnek yoksa ya da enerji kapısı geçilmezse `.belirsiz` (onay asla tahmin edilmez).
    /// Kapı: `SesTamponu.konusmaVar` (kısa onay sözcüklerinde 0,02 RMS + 0,04 tepe) ve en yüksek 250 ms pencere RMS'i ≥ 0,02.
    static func karar(metin: String, ornekler: [Float], oran: Double) -> Sonuc {
        guard !ornekler.isEmpty, oran > 0 else { return .belirsiz }
        guard SesTamponu.konusmaVar(ornekler, oran: oran, metin: metin, enAzSure: 0.25) else { return .belirsiz }
        guard pencereRms(ornekler, oran: oran) >= pencereEsigi else { return .belirsiz }
        return sozcukKarari(metin)
    }

    /// En yüksek `pencereSuresi` kadarlık pencerenin RMS'i (50 ms adımla kayar); tampon pencereden kısaysa tamamının RMS'i.
    static func pencereRms(_ o: [Float], oran: Double) -> Float {
        guard !o.isEmpty, oran > 0 else { return 0 }
        let boy = max(1, Int(pencereSuresi * oran))
        guard o.count > boy else { return SesTamponu.enerji(o).rms }
        var birikim = [Double](repeating: 0, count: o.count + 1)
        for (i, x) in o.enumerated() { birikim[i + 1] = birikim[i] + Double(x) * Double(x) }
        let adim = max(1, Int(0.05 * oran))
        var enYuksek = 0.0
        var bas = 0
        while bas + boy <= o.count {
            enYuksek = max(enYuksek, birikim[bas + boy] - birikim[bas])
            bas += adim
        }
        enYuksek = max(enYuksek, birikim[o.count] - birikim[o.count - boy])   // son pencere de bakılır
        return Float((enYuksek / Double(boy)).squareRoot())
    }

    /// Seslendirilecek onay sorusu: başlık + ayrıntı (alıcı adı böylece sesli tekrarlanır) + soru; `soruSiniri`nda
    /// ayrıntıdan kesilir, soru kısmı her zaman kalır.
    static func soruMetni(baslik: String, ayrinti: String) -> String {
        let son = "Onaylıyor musun? Evet ya da hayır de."
        var b = baslik.trimmingCharacters(in: .whitespacesAndNewlines)
        if b.count > soruSiniri / 3 { b = String(b.prefix(soruSiniri / 3)).trimmingCharacters(in: .whitespacesAndNewlines) }
        var a = ayrinti.trimmingCharacters(in: .whitespacesAndNewlines)
        let yer = max(0, soruSiniri - son.count - b.count - 4)
        if a.count > yer { a = String(a.prefix(yer)).trimmingCharacters(in: .whitespacesAndNewlines) }
        return ([b, a].filter { !$0.isEmpty }.map(cumle) + [son]).joined(separator: " ")
    }

    /// Cümle sonu işareti yoksa nokta ekler ("Gönderilsin mi?" iki kez noktalanmasın).
    private static func cumle(_ s: String) -> String {
        guard let u = s.last else { return s }
        return ".!?…:".contains(u) ? s : s + "."
    }
}
