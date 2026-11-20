import Foundation
import FoundationModels

/// Hermes Agent tarzı beceriler (agentskills.io `SKILL.md` biçimi): `Application Support/Beceriler/<ad>/SKILL.md`.
/// Yeniden kullanılabilir yöntem notlarıdır; talimata yalnız ad + açıklama girer, gövde gerektiğinde `oku` ile yüklenir.
nonisolated struct Beceri: Equatable, Sendable {
    let ad: String
    let aciklama: String
    let icerik: String
    /// Yalnız hazır paket becerilerinde anlamlıdır (`beceri-<ad>.json`); SKILL.md biçimine yazılmaz, `coz` 1 döner.
    var surum: Int = 1
}

nonisolated enum BeceriDeposu {
    static let enFazlaIcerik = 30_000   // topluluk becerileri (ör. SKILL.md) uzun olabilir
    static let enFazlaAciklama = 200
    static let enFazlaBeceri = 60
    nonisolated(unsafe) static var kok: URL = {
        let taban = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return taban.appendingPathComponent("Beceriler", isDirectory: true)
    }()

    /// "Haftalık Plan Yap" → "haftalik-plan-yap"; geçersiz/boşsa nil.
    static func gecerliAd(_ ham: String) -> String? {
        let s = ham.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i").lowercased()
        var cikti = ""
        for ch in s {
            if ch.isASCII, ch.isLetter || ch.isNumber { cikti.append(ch) }
            else if (ch == " " || ch == "-" || ch == "_"), cikti.last != "-", !cikti.isEmpty { cikti.append("-") }
        }
        cikti = cikti.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return cikti.isEmpty || cikti.count > 48 ? nil : cikti
    }

    static func yaz(_ b: Beceri) -> String {
        "---\nname: \(b.ad)\ndescription: \(b.aciklama.replacingOccurrences(of: "\n", with: " "))\n---\n\(b.icerik)\n"
    }

    static func coz(_ metin: String) -> Beceri? {
        let satirlar = metin.components(separatedBy: "\n")
        guard satirlar.first == "---", let son = satirlar.dropFirst().firstIndex(of: "---") else { return nil }
        var ad = "", aciklama = ""
        for s in satirlar[1..<son] {
            if s.hasPrefix("name:") { ad = s.dropFirst(5).trimmingCharacters(in: .whitespaces) }
            if s.hasPrefix("description:") { aciklama = s.dropFirst(12).trimmingCharacters(in: .whitespaces) }
        }
        guard !ad.isEmpty else { return nil }
        let govde = satirlar[(son + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return Beceri(ad: ad, aciklama: aciklama, icerik: govde)
    }

    private static func dosya(_ ad: String) -> URL { kok.appendingPathComponent(ad, isDirectory: true).appendingPathComponent("SKILL.md") }

    static func listele() -> [Beceri] {
        let klasorler = (try? FileManager.default.contentsOfDirectory(at: kok, includingPropertiesForKeys: nil)) ?? []
        return klasorler.compactMap { k in
            (try? String(contentsOf: k.appendingPathComponent("SKILL.md"), encoding: .utf8)).flatMap(coz)
        }.sorted { $0.ad < $1.ad }
    }

    static func oku(_ ad: String) -> Beceri? {
        guard let a = gecerliAd(ad) else { return nil }
        return (try? String(contentsOf: dosya(a), encoding: .utf8)).flatMap(coz)
    }

    enum Hata: LocalizedError {
        case gecersizAd, bos, cokUzun, cokFazla
        var errorDescription: String? {
            switch self {
            case .gecersizAd: "Beceri adı yalnız harf/rakam ve tire içerebilir (en çok 48 karakter)."
            case .bos: "Açıklama ve içerik boş olamaz."
            case .cokUzun: "İçerik \(BeceriDeposu.enFazlaIcerik) karakteri aşamaz; daha kısa yaz."
            case .cokFazla: "En fazla \(BeceriDeposu.enFazlaBeceri) beceri tutulur; önce eskilerden birini sil."
            }
        }
    }

    /// Dönüş: true = yeni oluşturuldu, false = var olan güncellendi.
    @discardableResult
    static func kaydet(ad: String, aciklama: String, icerik: String) throws -> Bool {
        guard let a = gecerliAd(ad) else { throw Hata.gecersizAd }
        // Açıklama sistem istemindeki dizine girer: tek satır (sahte istem bölümü açamasın).
        let ac = tekSatir(aciklama)
        let ic = icerik.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ac.isEmpty, !ic.isEmpty else { throw Hata.bos }
        guard ic.count <= enFazlaIcerik else { throw Hata.cokUzun }
        let varMi = FileManager.default.fileExists(atPath: dosya(a).path)
        if !varMi, listele().count >= enFazlaBeceri { throw Hata.cokFazla }
        try FileManager.default.createDirectory(at: dosya(a).deletingLastPathComponent(), withIntermediateDirectories: true)
        try yaz(Beceri(ad: a, aciklama: String(ac.prefix(enFazlaAciklama)), icerik: ic)).write(to: dosya(a), atomically: true, encoding: .utf8)
        tetikOnbelleginiSifirla()
        return !varMi
    }

    @discardableResult
    static func sil(_ ad: String) -> Bool {
        guard let a = gecerliAd(ad), FileManager.default.fileExists(atPath: dosya(a).path) else { return false }
        defer { tetikOnbelleginiSifirla() }
        return (try? FileManager.default.removeItem(at: dosya(a).deletingLastPathComponent())) != nil
    }

    // MARK: Hızlı yarış tetik kökleri (P1.1)

    private static let atilanParcalar: Set<String> = ["ile", "ve", "icin", "bir"]
    private static let tetikKilidi = NSLock()
    /// Anahtar `kok.path`: testler `kok`'u değiştirince önbellek kendiliğinden yeniden hesaplanır.
    nonisolated(unsafe) private static var tetikOnbellegi: (yol: String, kokler: [[String]])?

    /// Beceri adlarından sözcük kökleri: "ders-programi" → ["ders", "program"], "ikra-ile-calis" → ["ikra", "cali"].
    /// Parça 4 harf ya da kısaysa kendisi, değilse son harfi düşmüş hâli (Türkçe iyelik/belirtme ekini tolere eder);
    /// bağlaçlar ve 3 harften kısa parçalar atılır. Kökü kalmayan beceri listeye girmez.
    static func tetikKokleri(_ beceriler: [Beceri]) -> [[String]] {
        var gorulen = Set<String>()
        var sonuc: [[String]] = []
        for b in beceriler {
            // İçe aktarılan SKILL.md adları büyük harf/alt çizgi taşıyabilir: önce "ders-programi" biçimine getir.
            let ad = gecerliAd(b.ad) ?? b.ad.lowercased()
            guard gorulen.insert(ad).inserted else { continue }
            let kokler = ad.split(separator: "-").map(String.init)
                .filter { $0.count >= 3 && !atilanParcalar.contains($0) }
                .map { $0.count <= 4 ? $0 : String($0.dropLast()) }
            if !kokler.isEmpty { sonuc.append(kokler) }
        }
        return sonuc
    }

    /// Hazır + kayıtlı becerilerin kökleri (ada göre tekil); `kaydet`/`sil` ya da `kok` değişince yeniden hesaplanır.
    static func tetikKokleri() -> [[String]] {
        tetikKilidi.withLock {
            let yol = kok.path
            if let o = tetikOnbellegi, o.yol == yol { return o.kokler }
            let kokler = tetikKokleri(hazirBeceriler + listele())
            tetikOnbellegi = (yol: yol, kokler: kokler)
            return kokler
        }
    }

    private static func tetikOnbelleginiSifirla() {
        tetikKilidi.withLock { tetikOnbellegi = nil }
    }

    // MARK: Sürümlü hazır beceri paketi (P2.5)

    /// `Resources/beceri-<ad>.json` biçimi; metin değişince `surum` artırılır.
    private nonisolated struct PaketBecerisi: Decodable {
        let ad: String
        let aciklama: String
        let surum: Int
        let icerik: String
    }

    /// Uygulamayla gelen hazır beceriler (paketten bir kez okunur; tetik kökleri de buradan hesaplanır).
    static let hazirBeceriler: [Beceri] = hazirPaket()

    /// Bundle'daki `beceri-*.json` dosyaları: ada göre sıralı; çözülemeyen, adı geçersiz ya da boş olanlar atlanır.
    static func hazirPaket(_ b: Bundle = .main) -> [Beceri] {
        let dosyalar = (b.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("beceri-") }
        var gorulen = Set<String>()
        return dosyalar.compactMap { u -> Beceri? in
            guard let d = try? Data(contentsOf: u), let p = try? JSONDecoder().decode(PaketBecerisi.self, from: d),
                  gecerliAd(p.ad) == p.ad, p.surum >= 1,
                  !p.aciklama.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !p.icerik.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return Beceri(ad: p.ad, aciklama: p.aciklama, icerik: p.icerik, surum: p.surum)
        }
        .sorted { $0.ad < $1.ad }
        .filter { gorulen.insert($0.ad).inserted }
    }

    static func hazirAnahtar(_ ad: String, _ surum: Int) -> String { "beceri.hazir.\(ad).v\(surum)" }

    /// Hazır becerileri kurar/yükseltir. Kurallar:
    /// - Bu sürümün anahtarı varsa dokunulmaz.
    /// - Önceki bir sürüm kurulmuş ve beceri diskte yoksa kullanıcı silmiştir: geri getirilmez, yalnız anahtar yazılır.
    /// - Önceki sürüm kurulmuş ve diskte varsa yeni metin yazılır; içerik farklıysa eski dosya aynı klasörde
    ///   `SKILL.onceki.md` olarak saklanır (`listele` yalnız SKILL.md okur, yedek dizine girmez).
    /// - Hiçbir hazır sürüm kurulmamış ama aynı adla beceri varsa kullanıcınındır: dokunulmaz, anahtar yazılır.
    /// - Kayıt başarısızsa (ör. 60 beceri sınırı) anahtar yazılmaz; sonraki açılışta yeniden denenir.
    static func hazirBecerileriYukle(_ d: UserDefaults = .standard, paket: [Beceri] = hazirPaket()) {
        for b in paket {
            let anahtar = hazirAnahtar(b.ad, b.surum)
            guard !d.bool(forKey: anahtar) else { continue }
            let oncekiKurulu = b.surum > 1 && (1..<b.surum).contains { d.bool(forKey: hazirAnahtar(b.ad, $0)) }
            let mevcut = oku(b.ad)
            switch (mevcut, oncekiKurulu) {
            case (nil, true):
                break // kullanıcı silmiş
            case (let m?, true):
                let yeniIcerik = b.icerik.trimmingCharacters(in: .whitespacesAndNewlines)
                if m.icerik != yeniIcerik {
                    let asil = dosya(b.ad)
                    let yedek = asil.deletingLastPathComponent().appendingPathComponent("SKILL.onceki.md")
                    try? FileManager.default.removeItem(at: yedek)
                    guard (try? FileManager.default.copyItem(at: asil, to: yedek)) != nil else { continue }
                }
                guard (try? kaydet(ad: b.ad, aciklama: b.aciklama, icerik: b.icerik)) != nil else { continue }
            case (.some, false):
                break // kullanıcının aynı adlı kendi becerisi
            case (nil, false):
                guard (try? kaydet(ad: b.ad, aciklama: b.aciklama, icerik: b.icerik)) != nil else { continue }
            }
            d.set(true, forKey: anahtar)
        }
    }

    /// 29 Ekim 2026'da kaldırılan hazır beceriler (okul/öğretmen paketi ve resmî yazı becerileri).
    static let kaldirilanHazirlar = ["ders-plani", "ders-programi", "dilekce", "ikra-ile-calis", "kazanim-esleme", "odev-takibi", "resmi-yazi",
                                     "sinav-hazirla", "sinav-programi", "toplanti-dokumu", "tutanak", "veli-mesaji", "yoklama"]

    /// Uygulamanın kurduğu (kurulum anahtarı olan) kaldırılmış hazır becerileri bir kez gizler: SKILL.md silinmez,
    /// SKILL.kaldirildi.md adını alır (`listele` yalnız SKILL.md okur; kullanıcının değiştirdiği metin kaybolmaz).
    /// Anahtarı olmayan aynı adlı beceri kullanıcınındır, dokunulmaz.
    static func kaldirilanHazirlariGizle(_ d: UserDefaults = .standard) {
        let anahtar = "beceri.hazirKaldirildi.v1"
        guard !d.bool(forKey: anahtar) else { return }
        for ad in kaldirilanHazirlar where (1...9).contains(where: { d.bool(forKey: hazirAnahtar(ad, $0)) }) {
            let asil = dosya(ad)
            guard FileManager.default.fileExists(atPath: asil.path) else { continue }
            let hedef = asil.deletingLastPathComponent().appendingPathComponent("SKILL.kaldirildi.md")
            try? FileManager.default.removeItem(at: hedef)
            guard (try? FileManager.default.moveItem(at: asil, to: hedef)) != nil else { return }   // sonraki açılışta yeniden denenir
        }
        d.set(true, forKey: anahtar)
    }

    /// Talimata girecek dizin: yalnız ad + açıklama (gövde yüklenmez; token tasarrufu).
    /// GitHub "blob" bağlantısını ham dosya adresine çevirir (ClawHub/agentskills depoları); diğerleri aynen kalır.
    static func hamAdres(_ u: URL) -> URL {
        guard u.host == "github.com" else { return u }
        let p = u.pathComponents.filter { $0 != "/" }
        guard p.count >= 5, p[2] == "blob" else { return u }
        return URL(string: "https://raw.githubusercontent.com/\(p[0])/\(p[1])/\(p[3...].joined(separator: "/"))") ?? u
    }

    static func dizin(enFazla: Int = 40) -> String {
        // Sık kullanılan beceriler öne (kullanım sayısı yan bilgi olarak).
        let l = listele().sorted { kullanim($0.ad) > kullanim($1.ad) }
        guard !l.isEmpty else { return "Kayıtlı beceri yok." }
        return l.prefix(enFazla).map { b in
            let n = kullanim(b.ad)
            return "- \(b.ad): \(tekSatir(b.aciklama))" + (n > 0 ? " (\(n) kez kullanıldı)" : "")
        }.joined(separator: "\n")
    }

    /// Satır sonlarını boşluğa çevirir, kırpar (dizin satırı tek satır kalır).
    static func tekSatir(_ s: String) -> String {
        s.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Becerinin kaç kez yüklendiği (oku). Sık kullanılanlar dizinde öne çıkar.
    static func kullanim(_ ad: String) -> Int { UserDefaults.standard.integer(forKey: "beceri.kullanim.\(ad)") }
    static func kullanildi(_ ad: String) { UserDefaults.standard.set(kullanim(ad) + 1, forKey: "beceri.kullanim.\(ad)") }
}

nonisolated struct BeceriAraci: Tool {
    let name = "beceriler"
    let description = "Yeniden kullanılabilir becerileri (adım adım yöntem notları) yönetir. 'listele', 'oku' (ad: tam yöntemi yükler), 'kaydet' (ad, aciklama, icerik: Markdown adımlar; aynı adla kaydedersen becerinin yeni sürümü olur), 'sil' (ad), 'iceAktar' (url: topluluk becerisini SKILL.md adresinden getirir; kullanıcı onayı ister)."

    let onay: OnayKapisi

    @Generable
    struct Arguments {
        @Guide(description: "'listele', 'oku', 'kaydet', 'sil' ya da 'iceAktar'") var islem: String
        @Guide(description: "iceAktar: SKILL.md dosyasının https adresi (GitHub blob bağlantısı da olur)") var url: String?
        @Guide(description: "Beceri adı, küçük harf ve tire (örn. haftalik-plan)") var ad: String?
        @Guide(description: "kaydet: becerinin ne zaman kullanılacağını anlatan tek cümle") var aciklama: String?
        @Guide(description: "kaydet: Markdown, numaralı adımlar; kişisel veri ve gizli anahtar içermez") var icerik: String?
    }

    func call(arguments a: Arguments) async throws -> String {
        switch a.islem.lowercased() {
        case "oku":
            guard let ad = a.ad, let b = BeceriDeposu.oku(ad) else { return "Bu adla beceri yok. Önce 'listele' ile bak." }
            BeceriDeposu.kullanildi(b.ad)
            return "# \(b.ad)\n\(b.aciklama)\n\n\(b.icerik)\n\n(Bu yöntemi uygularken eksik ya da yanlış adım görürsen iş bitince 'kaydet' ile aynı adla düzeltilmiş sürümü kaydet.)"
        case "kaydet":
            // Beceri açıklaması her oturumun istemine girer: dış kaynaklı turda kalıcı kayıt kullanıcıya sorulur.
            guard await onay.disKaynaktaIste(baslik: "Beceri kaydedilsin mi: \(a.ad ?? "")", ayrinti: "\(a.aciklama ?? "")\n\n\((a.icerik ?? "").prefix(300))") else { return "Kullanıcı onaylamadı; beceri kaydedilmedi." }
            do {
                let yeni = try BeceriDeposu.kaydet(ad: a.ad ?? "", aciklama: a.aciklama ?? "", icerik: a.icerik ?? "")
                return yeni ? "Beceri kaydedildi: \(a.ad ?? "")" : "Beceri güncellendi: \(a.ad ?? "")"
            } catch { return "Kaydedilemedi: \(error.localizedDescription)" }
        case "sil":
            guard await onay.disKaynaktaIste(baslik: "Beceri silinsin mi: \(a.ad ?? "")", ayrinti: "Kayıtlı beceri kalıcı olarak silinir.") else { return "Kullanıcı onaylamadı; beceri silinmedi." }
            return BeceriDeposu.sil(a.ad ?? "") ? "Beceri silindi." : "Bu adla beceri yok."
        case "iceaktar":
            guard let u = a.url.flatMap({ URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }) else { return "Geçerli bir adres ver." }
            do {
                let (veri, _) = try await WebSayfa.govdeGetir(BeceriDeposu.hamAdres(u))
                guard let b = BeceriDeposu.coz(String(decoding: veri, as: UTF8.self)), let ad = BeceriDeposu.gecerliAd(b.ad) else { return "Bu adres geçerli bir SKILL.md (name/description başlığı) içermiyor." }
                let ozet = "\(b.aciklama)\n\n\(String(b.icerik.prefix(300)))…"
                // Dış beceri kalıcı talimat olur: kullanıcı "onay sorma" seçse bile sorulur.
                guard await onay.iste(baslik: "Dış kaynaklı beceri eklensin mi: \(ad)", ayrinti: "Kaynak: \(u.host ?? "")\n" + ozet, zorunlu: true) else { return "Kullanıcı onaylamadı; beceri eklenmedi." }
                let yeni = try BeceriDeposu.kaydet(ad: ad, aciklama: b.aciklama, icerik: b.icerik)
                return yeni ? "Beceri içe aktarıldı: \(ad)" : "Beceri güncellendi: \(ad)"
            } catch { return "İçe aktarılamadı: \(error.localizedDescription)" }
        default:
            return BeceriDeposu.dizin(enFazla: BeceriDeposu.enFazlaBeceri)
        }
    }
}
