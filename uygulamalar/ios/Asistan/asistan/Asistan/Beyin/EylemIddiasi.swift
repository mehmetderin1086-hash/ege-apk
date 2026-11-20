import Foundation

/// "Yaptım" bekçisi (P1.3): yanıtın ilk iki cümlesinde birinci tekil şahısla yapılmış bir iş iddiası
/// ("kurdum", "ekledim", "kaydettim", "gönderdim", "indirdim", "açtım", "çalıyorum") varsa ve o işi yapan
/// araç ailesinden hiçbiri bu turda başarıyla çalışmadıysa iddiayı yakalar.
/// Yalnız birinci tekil şahıs biçimleri aranır: "Cumhuriyet 1923'te kuruldu", "Apollo 11 Ay'a gönderildi" gibi
/// bilgi yanıtları sayılmaz. Olumsuz biçimler ("kuramadım", "ekleyemedim") kalıplara uymaz.
/// Bilinen sınır: araç hata metni döndürse de adım "Tamam" sayılır; bekçi yalnız hiç çalışmayan aracı yakalar.
/// Yeni yan etkili araç eklenince ilgili ailenin `araclar` kümesine adını ekle.
nonisolated enum EylemIddiasi {
    struct Kural: Equatable, Sendable {
        let ad: String
        /// `AtolyeYonlendirme.normalize` edilmiş (küçük harf, ASCII) metinde aranan düzenli ifade.
        let desen: String
        /// Doluysa aynı cümlede bu desen de geçmeli (ör. dosya kuralı: "hazırladım" + "pdf").
        let ekDesen: String?
        let araclar: Set<String>
    }

    /// Alt ajan işi kendi araçlarıyla yapmış olabilir; her ailede sayılır.
    static let ortakAraclar: Set<String> = ["altAjanlar"]

    static let kurallar: [Kural] = [
        Kural(ad: "kur", desen: #"\b(kurdum|ayarladim)\b"#, ekDesen: nil,
              araclar: ["hatirlatici", "zamanlayici", "takvim", "ev", "kisayolCalistir", "rutinler", "arkaPlanGorevi", "proje", "mcp", "cihaz"]),
        Kural(ad: "ekle", desen: #"\b(ekledim|isledim)\b"#, ekDesen: nil,
              araclar: ["takvim", "hatirlatici", "hafiza", "calismaAlani", "plan", "beceriler", "mcp", "proje", "rutinler", "tuval"]),
        Kural(ad: "kaydet", desen: #"\b(kaydettim|not ettim|hafizama aldim)\b"#, ekDesen: nil,
              araclar: ["hafiza", "calismaAlani", "takvim", "hatirlatici", "ofisBelgesiOlustur", "excelOlustur", "beceriler", "indirmeler", "pdfIslem", "mcp", "proje", "rutinler", "tuval"]),
        Kural(ad: "gonder", desen: #"\b(gonderdim|ilettim|yolladim)\b"#, ekDesen: nil,
              araclar: ["iletisim", "kisayolCalistir", "mcp"]),
        // "tablo" ve "belge" yok: sohbette yazılan Markdown tablo ya da ders planı dosya sayılmaz.
        Kural(ad: "dosya", desen: #"\b(olusturdum|hazirladim)\b"#, ekDesen: #"\b(dosya\w*|pdf\w*|excel\w*|xlsx|docx|word\w*)\b"#,
              araclar: ["ofisBelgesiOlustur", "excelOlustur", "arsivler", "pdfIslem", "tuval"]),
        Kural(ad: "indir", desen: #"\b(indiriliyor|indirmeye basladi|indirme baslatildi|indirme siraya alindi|indirme kuyruga alindi|yeniden indiriliyor)\b"#, ekDesen: nil,
              araclar: ["indirmeler/ekle", "indirmeler/tekrar"]),
        Kural(ad: "indir", desen: #"\b(indirdim|indiriyorum|indirmeye basladim)\b"#, ekDesen: nil,
              araclar: ["indirmeler/ekle", "indirmeler/tekrar"]),
        Kural(ad: "ac", desen: #"\b(actim|aciyorum|baslattim)\b"#, ekDesen: nil,
              araclar: ["uygulamaAc", "uygulamaIslemi", "tarayici", "kisayolCalistir", "dosyalar", "zamanlayici", "indirmeler", "arkaPlanGorevi", "rutinler", "mcp", "cihaz", "ev"]),
        // Telefon ayarı iddiaları ("Wi-Fi'yi kapattım", "Rahatsız Etme'yi etkinleştirdim", "ekranı kilitledim").
        Kural(ad: "ayar", desen: #"\b(kapattim|etkinlestirdim|devre disi biraktim|kilitledim)\b"#, ekDesen: nil,
              araclar: ["cihaz", "ev", "kisayolCalistir", "uygulamaIslemi", "zamanlayici", "muzik", "mcp"]),
        Kural(ad: "cal", desen: #"\b(caliyorum|caldim)\b"#, ekDesen: nil,
              araclar: ["muzik"]),
    ]

    /// Akan metinde iddia başlangıcı olabilecek fiil kökleri (ASCII, normalize edilmiş metin).
    static let supheliKokler = #"\b(kurd|ayarlad|ekled|isled|kaydett|not ett|hafizama al|gonderd|ilett|yollad|olusturd|hazirlad|indird|indiriyor|indiriliyor|indirmeye|indirme baslatildi|indirme siraya alindi|actim|aciyor|baslatt|caliyor|caldim|kapatt|etkinlestird|devre disi birakt|kilitled)"#

    /// Metni cümlelere böler: nokta/ünlem/soru işaretinden sonra boşluk ya da satır sonu. "09.00" gibi sayılar bölünmez.
    static func cumleler(_ s: String) -> [String] {
        let isaretli = s.replacingOccurrences(of: #"(?<=[.!?])\s+|\n+"#, with: "\u{1F}", options: .regularExpression)
        return isaretli.split(separator: "\u{1F}", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func ilkIkiCumle(_ s: String) -> String {
        cumleler(s).prefix(2).joined(separator: " ")
    }

    /// İlk iki cümlede eşleşen ve araç ailesi bu turda hiç başarıyla çalışmamış ilk kural; yoksa nil.
    /// ":" ile biten cümle ardından gelen içeriği tanıtır ("Programını şöyle ayarladım:"), iddia sayılmaz.
    static func denetle(_ yanit: String, basariliAraclar: Set<String>) -> Kural? {
        for ham in cumleler(yanit).prefix(2) {
            if ham.hasSuffix(":") { continue }
            let cumle = AtolyeYonlendirme.normalize(ham)
            for kural in kurallar {
                guard cumle.range(of: kural.desen, options: .regularExpression) != nil else { continue }
                if let ek = kural.ekDesen, cumle.range(of: ek, options: .regularExpression) == nil { continue }
                if kural.araclar.union(ortakAraclar).isDisjoint(with: basariliAraclar) { return kural }
            }
        }
        return nil
    }

    /// Akan kısmi metinde iddia fiili kökü geçiyor mu.
    static func supheliBaslangic(_ kismi: String) -> Bool {
        AtolyeYonlendirme.normalize(kismi).range(of: supheliKokler, options: .regularExpression) != nil
    }

    /// Yarış akışında bu kısmi metin ekrana/sese yazılmamalı mı: ilk iki cümlede iddia kesinleştiyse hep,
    /// bitmemiş cümlede şüpheli kök varsa cümle bitene ya da açık cümle 80 karakteri aşana kadar.
    static func akistaTut(_ tam: String) -> Bool {
        // Yalnız ilk iki cümle önemli: her akış parçasında bütün metni taramamak için baş kısım yeter.
        let kismi = String(tam.prefix(600))
        if denetle(kismi, basariliAraclar: []) != nil { return true }
        let parcalar = cumleler(kismi)
        let sondaBitti = kismi.range(of: #"[.!?]\s*$|\n\s*$"#, options: .regularExpression) != nil
        let bitmis = sondaBitti ? parcalar.count : max(0, parcalar.count - 1)
        guard bitmis < 2, !sondaBitti, let acik = parcalar.last, acik.count <= 80 else { return false }
        return supheliBaslangic(acik)
    }

    /// Kullanıcı anlatı/kurgu istedi mi (hikâye, masal, şiir, rol): birinci şahıs anlatım iddia sayılmaz.
    static func anlatiIstegi(_ istek: String) -> Bool {
        AtolyeYonlendirme.normalize(istek).range(of: #"\b(hikaye\w*|masal\w*|siir\w*|oyku\w*|senaryo\w*|canlandir\w*|rol yap\w*|kompozisyon\w*|monolog\w*|diyalog yaz\w*)"#, options: .regularExpression) != nil
    }
}

extension Beyin {
    /// Araçlı zincir yanıtı (tamamla): iddia edilen işi yapan araç bu turda çalışmadıysa balona kontrol notu düşer.
    /// Kısa yollar (aktifModel nil) ve cihaz içi model ("iPhone…") denetlenmez. Kullanıcı metni günlüğe yazılmaz.
    func eylemIddiasiniDenetle(_ id: UUID, yanit: String) {
        guard let model = aktifModel, !model.hasPrefix("iPhone"), aktifKip != .yazi,
              !EylemIddiasi.anlatiIstegi(sonKullaniciMetni) else { return }
        let adimlar = AjanDefteri.ortak.gorevler.first?.adimlar.filter { $0.durum == "Tamam" } ?? []
        var basarili = Set(adimlar.map(\.arac))
        basarili.formUnion(adimlar.compactMap { adim in adim.islem.map { "\(adim.arac)/\($0)" } })
        guard let kural = EylemIddiasi.denetle(yanit, basariliAraclar: basarili) else { return }
        kontrolNotuEkle(id, "Bu işlem gerçekte yapılmadı: ilgili araç çalışmadı. İstersen yeniden dene.")
        TaniGunlugu.yaz("EYLEM İDDİASI \(kural.ad) yol=zincir")
    }

    /// Yarış yanıtı iş iddiası taşıyorsa (araçsız yarışta hiçbir araç çalışmaz) istek bir kez araçlı zincire devredilir.
    /// true: devredildi, çağıran `false` döndürüp sıradaki aşamalara bırakmalı (yanıt disGecmis'e eklenmez).
    func yarisEylemIddiasiniYonlendir(_ metin: String, istek: String) -> Bool {
        guard !eylemYonlendirildi, !EylemIddiasi.anlatiIstegi(istek),
              let kural = EylemIddiasi.denetle(metin, basariliAraclar: []) else { return false }
        eylemYonlendirildi = true
        akanMetin = ""
        denemeYenilendi?()
        aktifModel = nil; aktifYol = nil
        durum = .dusunuyor
        TaniGunlugu.yaz("YARIŞ → ZİNCİR (eylem iddiası \(kural.ad))")
        return true
    }
}
