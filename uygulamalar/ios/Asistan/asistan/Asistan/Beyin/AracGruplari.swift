import Foundation
import FoundationModels

/// P3.4: niyete göre araç alt kümesi (yalnız `Ayarlar.aracGruplama` açıkken kullanılır).
/// İstem süzgeci isteğin gerektirdiği grupları (`IstemSuzgeci.Cozumleme.aracGruplari`) verir; araçlı zincir modele yalnız
/// çekirdek araçlar + seçilen grupların araçları + transcript'te geçmişte çağrılmış araçları gösterir. Talimatın sabit
/// bölümünden de seçilmeyen grupların araç maddeleri çıkarılır (`sabitSuz`). Grup bilinmiyorsa ya da boşsa tam set kullanılır.
/// Yeni araç eklerken `grup` sözlüğüne yerini yaz (AracGruplariTestleri her kayıtlı aracın bir grupta olduğunu doğrular).
nonisolated enum AracGruplari {
    /// Araç adı → grup. `mcp_` önekli dinamik MCP araçları `grubu(_:)` ile "web" sayılır.
    static let grup: [String: String] = [
        // iletisim
        "iletisim": "iletisim", "kisiler": "iletisim", "gelenKutusu": "iletisim",
        // zaman
        "takvim": "zaman", "hatirlatici": "zaman", "zamanlayici": "zaman", "rutinler": "zaman",
        // dosya
        "ofisBelgesiOlustur": "dosya", "excelOlustur": "dosya", "dosyalar": "dosya", "arsivler": "dosya",
        "pdfIslem": "dosya", "fotograflar": "dosya", "tuval": "dosya",
        // web
        "webSayfaOku": "web", "veriKazi": "web", "tarayici": "web", "indirmeler": "web", "altAjanlar": "web",
        "mcp": "web", "arkaPlanGorevi": "web", "ucretsizServis": "web", "yasamServisleri": "web",
        // cihaz
        "cihaz": "cihaz", "ev": "cihaz", "uygulamaAc": "cihaz", "uygulamaIslemi": "cihaz", "kisayolCalistir": "cihaz",
        "muzik": "cihaz", "harita": "cihaz", "havaDurumu": "cihaz",
        // hafiza
        "calismaAlani": "hafiza", "gecmisAra": "hafiza", "proje": "hafiza",
    ]

    /// Süzgecin seçebileceği grup adları (sıra süzgeç talimatındaki sıradır).
    static let grupAdlari = ["iletisim", "zaman", "dosya", "web", "cihaz", "hafiza"]

    /// Her alt kümede bulunan araçlar (ana web araması dahil).
    static let cekirdek: Set<String> = ["suankiSaat", "plan", "beceriler", "hafiza", "webArastir"]

    /// Aracın grubu; çekirdek araç ve bilinmeyen ad nil.
    static func grubu(_ ad: String) -> String? {
        if ad.hasPrefix("mcp_") { return "web" }
        return grup[ad]
    }

    /// Geçerli bir grup kümesi mi (boş değil, hepsi bilinen grup adı).
    static func gecerli(_ g: Set<String>) -> Bool { !g.isEmpty && g.isSubset(of: Set(grupAdlari)) }

    /// Süzgecin ham grup listesinden alt küme kararı: boş, eksik ya da bilinmeyen grup içeren liste nil (tam set) verir.
    static func gruplar(_ ham: [String]?) -> Set<String>? {
        let temiz = Set((ham ?? []).prefix(4).map { AtolyeYonlendirme.normalize($0) }.filter { !$0.isEmpty })
        return gecerli(temiz) ? temiz : nil
    }

    /// Çekirdek + seçilen grupların araçları + `ek` (transcript'te daha önce çağrılmış araç adları). Gruba yazılmamış
    /// (yeni eklenmiş) araç güvenli yanda kalır ve her alt kümeye girer. Grup kümesi geçersizse tam set döner.
    static func secilen(_ gruplar: Set<String>, hepsi: [any Tool], ek: Set<String> = []) -> [any Tool] {
        guard gecerli(gruplar) else { return hepsi }
        return hepsi.filter { a in
            let ad = a.name
            if cekirdek.contains(ad) || ek.contains(ad) { return true }
            guard let g = grubu(ad) else { return true }
            return gruplar.contains(g)
        }
    }

    /// Transcript'te geçmiş turlarda çağrılmış araç adları (alt küme dışında kalsa da tanımı gönderilir; sağlayıcı
    /// tanımsız araca ait tool_use bloğunu reddedebilir).
    static func gecmisAraclari(_ t: Transcript) -> Set<String> {
        var adlar = Set<String>()
        for girdi in t {
            if case .toolCalls(let cagrilar) = girdi { for c in cagrilar { adlar.insert(c.toolName) } }
        }
        return adlar
    }

    /// Oturum imzası için kararlı metin ("hepsi" ya da sıralı grup adları).
    static func imza(_ g: Set<String>?) -> String {
        guard let g, gecerli(g) else { return "hepsi" }
        return g.sorted().joined(separator: ",")
    }

    /// Model, alt kümede aracı olmadığı için işi yapamadığını söylüyor mu (yanıtın ilk 400 karakterinde).
    static func yetersizYanit(_ s: String) -> Bool {
        let n = AtolyeYonlendirme.normalize(String(s.prefix(400)))
        return n.range(of: #"(uygun )?arac(im)? yok|bu islemi yapamiyorum|erisimim yok|bunu yapamam"#, options: .regularExpression) != nil
    }

    // MARK: Talimat

    /// Talimatın sabit bölümünden seçilmeyen grupların araç maddelerini çıkarır. Bir satır yalnız şu durumda düşer:
    /// gruplu bir araç adını anıyor, hiçbir çekirdek aracı anmıyor ve andığı grupların hiçbiri seçili değil.
    /// Araç adı anmayan satırlar (davranış, yazım, güvenlik kuralları) her zaman kalır.
    static func sabitSuz(_ metin: String, gruplar: Set<String>) -> String {
        metin.split(separator: "\n", omittingEmptySubsequences: false).filter { satir in
            let sozcukler = Set(satir.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") }).map(String.init))
            if !sozcukler.isDisjoint(with: cekirdek) { return true }
            let anilan = Set(sozcukler.compactMap { grup[$0] })
            return anilan.isEmpty || !anilan.isDisjoint(with: gruplar)
        }.joined(separator: "\n")
    }

    /// Saf birleştirme: `tam` = `Talimatlar.olustur` çıktısı. Gruplar geçerliyse sabit bölüm süzülür; `ekBaglam`
    /// (kestirmeler, kişiselleştirme, proje talimatı) sabit bölümün hemen ardına girer. nil + boş ek bağlamla `tam` aynen döner.
    static func birlestir(tam: String, sabit: String = Talimatlar.sabit, gruplar: Set<String>?, ekBaglam: String) -> String {
        guard tam.hasPrefix(sabit) else { return tam + ekBaglam }
        let kalan = String(tam.dropFirst(sabit.count))
        let bas = gruplar.map { gecerli($0) ? sabitSuz(sabit, gruplar: $0) : sabit } ?? sabit
        return bas + ekBaglam + kalan
    }

    /// Oturum talimatı (P3.4 yolu). `gruplar` nil iken metin `Talimatlar.olustur` ile aynıdır (+ ek bağlam).
    static func talimat(olgular: [String], simdi: Date = .now, gruplar: Set<String>?, ekBaglam: String = "") -> String {
        birlestir(tam: Talimatlar.olustur(olgular: olgular, simdi: simdi), gruplar: gruplar, ekBaglam: ekBaglam)
    }

    /// Her tura eklenmek yerine oturum talimatına giren bağlam (biçim `Beyin.gonder`deki eski tur eklerinin aynısı).
    /// `kestirmeler`: "ad → kestirme" satırları.
    static func ekBaglam(kestirmeler: [String], dostBaglami: String, projeTalimati: String?) -> String {
        var s = ""
        if !kestirmeler.isEmpty {
            s += "\n\n[Uygulama tarafından eklenen kayıtlı telefon kestirmeleri: " + kestirmeler.joined(separator: "; ")
                + ". İstendiğinde kisayolCalistir aracını tam kestirme adıyla kullan.]"
        }
        if !dostBaglami.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            s += "\n\n[Uygulamanın kişiselleştirme ayarı]\n" + dostBaglami
        }
        if let p = projeTalimati, !p.isEmpty { s += "\n\n" + p }
        return s
    }
}
