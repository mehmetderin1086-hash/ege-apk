import Foundation
import Observation

/// Yalnız gecikme ve kullanılabilirlik saklanır; konuşma, hesap veya anahtar saklanmaz.
@MainActor @Observable
final class ModelVitesi {
    /// Sunucudaki Antigravity hesabına yönlendirilen, sesli diyalog için hızlı yol.
    /// Bu kimlik iPhone'a hesap anahtarı taşımadan CLIProxy üzerinden kullanılır.
    static let antigravityCanliModel = "antigravity-gemini-3.8-flash-tiered"
    struct Kayit: Codable {
        var ilkSn: Double?
        var ornek = 0
        var aski: Date?
    }
    /// Anahtarlar: "model" (model geneli askı: kota/aile, iptal), "model|low/medium/high" (gecikme),
    /// "model|telefon/vekil/anahtar" (P3.7: yalnız o model o yolda askı).
    private(set) var kayitlar: [String: Kayit]
    /// P3.7: rota askıları (bütün modeller için bir yol); 'zincir.rotaAskilari.v1' altında kalıcı.
    private(set) var rotaAskilari: [ModelZinciri.Yol: Date]
    private let defaults: UserDefaults
    static let rotaAnahtari = "zincir.rotaAskilari.v1"
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        kayitlar = defaults.data(forKey: "modelVitesi.v1").flatMap { try? JSONDecoder().decode([String: Kayit].self, from: $0) } ?? [:]
        // Süresi geçmiş rota askısı yüklenmez.
        var r: [ModelZinciri.Yol: Date] = [:]
        let simdi = Date()
        for (ad, t) in (defaults.dictionary(forKey: Self.rotaAnahtari) as? [String: Double]) ?? [:] {
            if let yol = ModelZinciri.Yol(rawValue: ad), Date(timeIntervalSince1970: t) > simdi { r[yol] = Date(timeIntervalSince1970: t) }
        }
        rotaAskilari = r
    }
    private func sakla() { if let d = try? JSONEncoder().encode(kayitlar) { defaults.set(d, forKey: "modelVitesi.v1") } }
    private func rotaSakla() {
        defaults.set(Dictionary(uniqueKeysWithValues: rotaAskilari.map { ($0.key.rawValue, $0.value.timeIntervalSince1970) }), forKey: Self.rotaAnahtari)
    }
    /// `yol` verilirse o yolun model|yol askısı da kalkar (o yolda yanıt geldi).
    func basari(_ model: String, caba: DusunmeSecimi.Caba, ilkSn: Double, yol: ModelZinciri.Yol? = nil) {
        let key = model + "|" + caba.rawValue
        var k = kayitlar[key] ?? Kayit()
        let sn = min(120, max(0.1, ilkSn))
        k.ilkSn = k.ilkSn.map { $0 * 0.65 + sn * 0.35 } ?? sn; k.ornek += 1
        kayitlar[key] = k; kayitlar[model]?.aski = nil
        if let yol { kayitlar[ModelZinciri.askiAnahtari(model: model, yol: yol)]?.aski = nil }
        sakla()
    }
    /// Model geneli askı (kota/aile ve iptal): `sira` bu modeli hiç önermez.
    func beklet(_ model: String, saniye: Double) {
        var k = kayitlar[model] ?? Kayit(); k.aski = max(k.aski ?? .distantPast, Date().addingTimeInterval(saniye))
        kayitlar[model] = k; sakla()
    }
    /// P3.7: yalnız bu model bu yolda askı (401/404/kota); model öbür yollarda kullanılmaya devam eder.
    func beklet(_ model: String, yol: ModelZinciri.Yol, saniye: Double) {
        beklet(ModelZinciri.askiAnahtari(model: model, yol: yol), saniye: saniye)
    }
    /// Model geneli ya da bu yola özgü askı sürüyor mu?
    func askida(_ model: String, yol: ModelZinciri.Yol, simdi: Date = .now) -> Bool {
        (kayitlar[model]?.aski ?? .distantPast) > simdi
            || (kayitlar[ModelZinciri.askiAnahtari(model: model, yol: yol)]?.aski ?? .distantPast) > simdi
    }
    /// "model|telefon/vekil/anahtar" askıları (ModelZinciri.modelAskilari). Gecikme anahtarları girmez.
    var yolAskilari: [String: Date] {
        var a: [String: Date] = [:]
        for (anahtar, k) in kayitlar {
            guard let t = k.aski, let ek = anahtar.split(separator: "|").last, anahtar.contains("|"),
                  ModelZinciri.Yol(rawValue: String(ek)) != nil else { continue }
            a[anahtar] = t
        }
        return a
    }
    /// Yalnız model geneli askılar (anahtarında '|' yok): sohbet kota uyarısı ve Kullanım ekranı bunu gösterir;
    /// yol askısı modeli öbür yollarda kullanılır bıraktığı için 'Diğer sağlayıcılara geçiliyor' uyarısı üretmez.
    var modelGeneliAskilar: [String: Date] {
        var a: [String: Date] = [:]
        for (m, k) in kayitlar where !m.contains("|") { if let t = k.aski { a[m] = t } }
        return a
    }
    func rotaAskisiYaz(_ yol: ModelZinciri.Yol, bitis: Date?) {
        rotaAskilari[yol] = bitis; rotaSakla()
    }
    func rotaAskilariniAyarla(_ yeni: [ModelZinciri.Yol: Date]) {
        guard yeni != rotaAskilari else { return }
        rotaAskilari = yeni; rotaSakla()
    }
    /// Sağlık ekranından elle kaldırma: rota adı ("telefon"/"vekil"/"anahtar"), model ya da "model|yol".
    func askiKaldir(_ anahtar: String) {
        if let yol = ModelZinciri.Yol(rawValue: anahtar) { rotaAskisiYaz(yol, bitis: nil); return }
        guard kayitlar[anahtar]?.aski != nil else { return }
        kayitlar[anahtar]?.aski = nil; sakla()
    }
    func tumAskilariKaldir() {
        for anahtar in kayitlar.keys where kayitlar[anahtar]?.aski != nil { kayitlar[anahtar]?.aski = nil }
        sakla()
        rotaAskilari = [:]; rotaSakla()
    }
    /// Live için Claude modelleri (hızlıdan güçlüye).
    static let canliClaudeModelleri = ["claude-haiku-4-5", "claude-sonnet-5-5", "claude-opus-5-5"]

    /// Doğrudan hesaptaki modelin Antigravity eşi (varsa): aynı model ailesi, Antigravity hesabından.
    static func antigravityIkizi(_ model: String, caba: DusunmeSecimi.Caba) -> String? {
        let d = caba == .high ? "high" : caba == .medium ? "medium" : "low"
        switch model {
        case "claude-haiku-4-5": return "antigravity-claude-sonnet-5-5-low"
        case "claude-sonnet-5-5": return "antigravity-claude-sonnet-5-5-\(d)"
        case "claude-opus-5-5": return "antigravity-claude-opus-5-5-\(d)"
        case "gemini-3.8-flash": return "antigravity-gemini-3.8-flash-tiered"
        default: return nil
        }
    }

    /// Antigravity önceliği: eşi hesapta varsa önce o, ardından doğrudan model (yedek). Liste boşsa dokunmaz.
    static func antigravityOncele(_ sira: [String], mevcut: [String], caba: DusunmeSecimi.Caba) -> [String] {
        guard !mevcut.isEmpty else { return sira }
        var sonuc: [String] = []
        for m in sira {
            if let t = antigravityIkizi(m, caba: caba), mevcut.contains(t), !sonuc.contains(t) { sonuc.append(t) }
            if !sonuc.contains(m) { sonuc.append(m) }
        }
        return sonuc
    }

    func sira(caba: DusunmeSecimi.Caba, kip: CalismaKipi, metin: String, gorsel: Bool,
              modeller: [String], elle: String, otomatik: Bool, yalnizAnahtar: Bool = false,
              canliSes: Bool = false, canliClaude: Bool = false, simdi: Date = .now) -> [String] {
        guard otomatik else { return [elle] }
        var adaylar = HizliModelSecimi.adaylar(caba)
        // CLIProxy'de bağlı Antigravity hesabının Gemini 3.8 Flash yoludur.
        // Live yedeğinde ilk sesli yanıtı bu hesap üretir.
        // Live: canliClaude açıksa yalnız Claude modelleri (Claude'un gerçek zamanlı ses API'si yok; sıralı Live'da model kısmı Claude).
        if canliSes, canliClaude { adaylar = Self.canliClaudeModelleri }
        else if canliSes { adaylar = [Self.antigravityCanliModel] + adaylar.filter { $0 != Self.antigravityCanliModel } }
        let s = AtolyeYonlendirme.normalize(metin)
        let tercih: String?
        if canliSes { tercih = canliClaude ? "claude-haiku-4-5" : Self.antigravityCanliModel }
        else if gorsel { tercih = caba == .high ? "claude-fable-5-1" : "gemini-3.8-flash" }   // görselli zor soru: Fable, sonra Opus
        else if kip == .kod || s.range(of: #"\b(kanitla|ispatla|integral|turev|hesapla|matematik)\b"#, options: .regularExpression) != nil { tercih = "gpt-6.1-sol" }
        else if s.range(of: #"\b(cevir|tercume|dil)\b"#, options: .regularExpression) != nil { tercih = "gemini-3.8-flash" }
        // Kısa sohbet ve tek komutlarda fiziksel iPhone ölçümünde Haiku'nun
        // ilk parçası zaman zaman takıldı. GPT başlangıç tercihi olur; kota
        // veya erişim sorunu varsa ölçülen hızlı yedekler otomatik kullanılır.
        else if caba == .low { tercih = "claude-haiku-4-5" } // telefonda ölçülen en hızlı ilk metin: 1,1-1,5 sn
        else if caba == .medium { tercih = "claude-haiku-4-5" } // genel sohbet: Haiku 1,2-1,5 sn, GPT 2,3-3,5 sn
        else { tercih = nil }
        if yalnizAnahtar { adaylar = adaylar.filter { $0.hasPrefix("claude-") } }
        else if !modeller.isEmpty { adaylar = adaylar.filter(modeller.contains) }
        let acik = adaylar.filter { (kayitlar[$0]?.aski ?? .distantPast) <= simdi }
        // Tüm adaylar kota/erişim beklemesindeyse tekrar yük bindirme.
        if !adaylar.isEmpty, acik.isEmpty { return [] }
        if adaylar.isEmpty { return (kayitlar[elle]?.aski ?? .distantPast) <= simdi ? [elle] : [] }
        // Hermes tarzı sade seçim: puan/ölçüm yok. Görev türüne özel tercih (varsa) önde, sonra
        // `adaylar` içindeki sabit birincil + yedek sırası. Kota/erişim askıdaki modeller zaten elendi.
        func sirasi(_ model: String) -> Int { model == tercih ? -1 : (adaylar.firstIndex(of: model) ?? Int.max) }
        return acik.sorted { sirasi($0) == sirasi($1) ? $0 < $1 : sirasi($0) < sirasi($1) }
    }
    static func tekrarGuvenli(kismiMetin: String, aracSayisiOnce: Int, aracSayisiSonra: Int) -> Bool {
        kismiMetin.isEmpty && aracSayisiOnce == aracSayisiSonra
    }
    /// Araç çalışmamışsa, kısa ve açıkça yarım kalmış bir doğal dil cevabı
    /// kullanıcıya hiç gösterilmeden başka modele yeniden yazdırılabilir.
    /// Tamamlanmış cümleler ve uzun/biçimli içerikler asla yinelenmez.
    static func eksikKisaYanitGuvenli(kismiMetin: String, aracSayisiOnce: Int, aracSayisiSonra: Int) -> Bool {
        guard aracSayisiOnce == aracSayisiSonra else { return false }
        let metin = kismiMetin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...420).contains(metin.count), !metin.contains("```"),
              let son = metin.last else { return false }
        return !".!?…:;)]}»”\"".contains(son)
    }
}
