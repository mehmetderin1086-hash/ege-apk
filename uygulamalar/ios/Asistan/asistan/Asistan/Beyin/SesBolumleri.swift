import Foundation

/// Sesli anlatım transkriptinden satır/bölüm listesi ve TAHMİNİ zaman damgaları (saf mantık, arayüz ve ses yok).
/// Sunucu (vps/asistan-jobs/audio_workspace.py) yalnız MP3 ve "**Konuşmacı N:** metin" + "Kaynak: id" dökümü verir;
/// gerçek zaman damgası YOKTUR. Burada üretilen zamanlar karakter-orantılı kestirimdir ve arayüzde kesin gibi gösterilmemelidir.

/// Transkriptte tek bir konuşma satırı. Zamanlar saniyedir ve TAHMİNİDİR.
nonisolated struct SesSatiri: Sendable, Equatable, Identifiable {
    let indeks: Int
    let konusmaci: String?
    let metin: String
    let bolum: Int
    let baslangic: Double
    let bitis: Double
    var id: Int { indeks }
}

nonisolated struct SesBolumu: Sendable, Equatable, Identifiable {
    let indeks: Int
    let baslik: String
    let ilkSatir: Int
    /// Son satırdan sonraki indeks (dışlayıcı).
    let sonSatir: Int
    let baslangic: Double
    let bitis: Double
    var id: Int { indeks }
}

nonisolated struct SesPlani: Sendable, Equatable {
    var satirlar: [SesSatiri] = []
    var bolumler: [SesBolumu] = []
    var sure: Double = 0
    /// Zaman damgaları her zaman kestirimdir; bayrak arayüzün uyarıyı koşulsuz göstermesi içindir.
    let tahmini: Bool = true
}

/// Uyku zamanlayıcısı seçenekleri.
nonisolated enum UykuSecenegi: Sendable, Equatable, Hashable {
    case kapali
    case dakika(Int)
    case bolumSonu

    static let secenekler: [UykuSecenegi] = [.kapali, .dakika(15), .dakika(30), .dakika(60), .bolumSonu]

    var etiket: String {
        switch self {
        case .kapali: return "Kapalı"
        case .dakika(let d): return "\(d) dakika"
        case .bolumSonu: return "Bölüm sonu"
        }
    }
}

/// Çalma süresine göre geri sayan uyku sayacı. Duraklatılmışken ilerletilmez (arayüz yalnız çalarken çağırır).
nonisolated struct UykuSayaci: Sendable, Equatable {
    private(set) var secenek: UykuSecenegi
    private(set) var kalan: Double?
    private(set) var bolumBitisi: Double?

    /// `bolumBitisi` yalnız `.bolumSonu` için anlamlıdır (kurulduğu andaki bölümün bitiş zamanı).
    init(secenek: UykuSecenegi, bolumBitisi: Double? = nil) {
        self.secenek = secenek
        switch secenek {
        case .kapali: kalan = nil; self.bolumBitisi = nil
        case .dakika(let d): kalan = Double(max(0, d)) * 60; self.bolumBitisi = nil
        case .bolumSonu: kalan = nil; self.bolumBitisi = bolumBitisi
        }
    }

    /// `gecen`: son çağrıdan beri çalınan saniye; `zaman`: güncel konum. true dönerse oynatma durdurulmalı.
    mutating func ilerlet(gecen: Double, zaman: Double) -> Bool {
        switch secenek {
        case .kapali:
            return false
        case .dakika:
            guard let k = kalan else { return false }
            let yeni = k - max(0, gecen.isFinite ? gecen : 0)
            kalan = max(0, yeni)
            return yeni <= 0
        case .bolumSonu:
            guard let b = bolumBitisi else { return false }
            return zaman >= b - 0.25
        }
    }
}

nonisolated enum SesBolumleri {
    static let hizAdimlari: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    static let atlamaSaniyesi: Double = 15
    /// Başlık yokken otomatik bölümleme: bu süreden kısa anlatım tek bölümdür, uzunsa yaklaşık bu aralıkla bölünür.
    static let otomatikBolumSaniyesi: Double = 300
    /// Parça sınırlarındaki sessizliği temsil eden karakter eşdeğeri (yalnız satır sayısı = parça sayısı ise).
    static let parcaAraAgirligi: Double = 12

    // MARK: Ayrıştırma

    private enum Oge { case baslik(String), satir(String?, String) }

    static func coz(transkript: String, sure: Double, parcaSayisi: Int? = nil) -> SesPlani {
        let toplamSure = sure.isFinite ? max(0, sure) : 0
        var ogeler: [Oge] = []
        let paragraflar = transkript.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n")
        for p in paragraflar {
            var oncekiSatirVar = false
            for ham in p.split(separator: "\n", omittingEmptySubsequences: true) {
                let satir = ham.trimmingCharacters(in: .whitespaces)
                if satir.isEmpty || kaynakSatiri(satir) || konusulmayanOnSoz(satir) { continue }
                if let b = baslikMetni(satir) { ogeler.append(.baslik(b)); oncekiSatirVar = false; continue }
                let (ad, metin) = konusmaciAyir(satir)
                if metin.isEmpty { continue }
                if ad == nil, oncekiSatirVar, case .satir(let a, let onceki)? = ogeler.last {
                    ogeler[ogeler.count - 1] = .satir(a, onceki + " " + metin)   // aynı paragrafın devamı
                } else {
                    ogeler.append(.satir(ad, metin))
                }
                oncekiSatirVar = true
            }
        }

        var basliklar: [String] = []
        var bekleyen: String?
        var basligiVar = false
        var mevcut = -1
        var taslak: [(String?, String, Int)] = []
        for oge in ogeler {
            switch oge {
            case .baslik(let b): bekleyen = b; basligiVar = true
            case .satir(let ad, let metin):
                if let b = bekleyen { basliklar.append(b); mevcut = basliklar.count - 1; bekleyen = nil }
                else if mevcut == -1 { basliklar.append("Giriş"); mevcut = 0 }
                taslak.append((ad, metin, mevcut))
            }
        }
        guard !taslak.isEmpty else { return SesPlani(satirlar: [], bolumler: [], sure: toplamSure) }

        let araAgirlik = (parcaSayisi == taslak.count) ? parcaAraAgirligi : 0
        let agirliklar = taslak.map { Double($0.1.count) + araAgirlik }
        let toplamAgirlik = agirliklar.reduce(0, +)
        var satirlar: [SesSatiri] = []
        var birikim = 0.0
        for (i, t) in taslak.enumerated() {
            let b = toplamAgirlik > 0 ? toplamSure * birikim / toplamAgirlik : 0
            birikim += agirliklar[i]
            let e = (i == taslak.count - 1) ? toplamSure : (toplamAgirlik > 0 ? toplamSure * birikim / toplamAgirlik : 0)
            satirlar.append(SesSatiri(indeks: i, konusmaci: t.0, metin: t.1, bolum: t.2, baslangic: b, bitis: e))
        }

        if !basligiVar {
            // Başlık yok: süreye göre otomatik bölümle (satır sınırında).
            var yeniBolum = 0
            var bolumBasi = 0.0
            for i in satirlar.indices {
                if satirlar[i].baslangic - bolumBasi >= otomatikBolumSaniyesi { yeniBolum += 1; bolumBasi = satirlar[i].baslangic }
                let s = satirlar[i]
                satirlar[i] = SesSatiri(indeks: s.indeks, konusmaci: s.konusmaci, metin: s.metin, bolum: yeniBolum, baslangic: s.baslangic, bitis: s.bitis)
            }
            let adet = (satirlar.last?.bolum ?? 0) + 1
            basliklar = adet == 1 ? ["Anlatım"] : (1...adet).map { "Bölüm \($0)" }
        }

        var bolumler: [SesBolumu] = []
        var bas = 0
        while bas < satirlar.count {
            let b = satirlar[bas].bolum
            var son = bas
            while son < satirlar.count, satirlar[son].bolum == b { son += 1 }
            bolumler.append(SesBolumu(indeks: bolumler.count, baslik: basliklar[b], ilkSatir: bas, sonSatir: son,
                                      baslangic: satirlar[bas].baslangic, bitis: satirlar[son - 1].bitis))
            bas = son
        }
        return SesPlani(satirlar: satirlar, bolumler: bolumler, sure: toplamSure)
    }

    private static func kaynakSatiri(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "*_ >"))
        return t.hasPrefix("Kaynak:") || t.hasPrefix("Kaynaklar:")
    }

    /// Sunucu tek sesli durumda başa eklenen, SESLENDİRİLMEYEN bilgi notu.
    private static func konusulmayanOnSoz(_ s: String) -> Bool { s.hasPrefix("Katalogda tek uygun ses bulundu") }

    private static func baslikMetni(_ s: String) -> String? {
        if s.hasPrefix("#") {
            let t = s.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            let temiz = yildizsiz(t)
            return temiz.isEmpty ? nil : temiz
        }
        if s.count <= 80, let ilk = s.split(separator: " ").first {
            let k = String(ilk).lowercased(with: Locale(identifier: "tr_TR")).trimmingCharacters(in: CharacterSet(charactersIn: "*_"))
            if ["parça", "parca", "bölüm", "bolum", "kısım", "kisim"].contains(k), s.contains(where: { $0.isNumber }) {
                let temiz = yildizsiz(s).trimmingCharacters(in: CharacterSet(charactersIn: ":- "))
                // "Bölüm 2: ..." başlıktır; "Bölüm 2'de ... anlatıyorum." gibi cümle değil.
                if !temiz.hasSuffix(".") && !temiz.hasSuffix("!") && !temiz.hasSuffix("?") { return temiz }
            }
        }
        if s.hasPrefix("**"), s.hasSuffix("**"), s.count > 4, !s.contains(":") {
            let temiz = yildizsiz(s)
            return temiz.isEmpty ? nil : temiz
        }
        return nil
    }

    private static func yildizsiz(_ s: String) -> String {
        s.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "*_ \t"))
    }

    /// "**Konuşmacı 1:** metin" → ("Konuşmacı 1", "metin"). Konuşmacı yoksa (nil, tüm satır).
    static func konusmaciAyir(_ satir: String) -> (String?, String) {
        var t = satir.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("- ") || t.hasPrefix("> ") { t = String(t.dropFirst(2)) }
        let govde = t.hasPrefix("**") ? String(t.dropFirst(2)) : t
        guard let iki = govde.firstIndex(of: ":") else { return (nil, yildizsiz(t)) }
        let ad = govde[govde.startIndex..<iki].trimmingCharacters(in: CharacterSet(charactersIn: "* "))
        var kalan = String(govde[govde.index(after: iki)...])
        let adGecerli = !ad.isEmpty && ad.count <= 32 && ad.split(separator: " ").count <= 3
            && (ad.first?.isUppercase ?? false) && !ad.contains(where: { "/\\.,;!?".contains($0) })
        guard adGecerli else { return (nil, yildizsiz(t)) }
        if kalan.hasPrefix("**") { kalan = String(kalan.dropFirst(2)) }
        return (ad, yildizsiz(kalan))
    }

    // MARK: Arama

    /// Sıralı `baslangiclar` içinde `baslangic <= zaman` koşulunu sağlayan SON indeks (ikili arama).
    /// Boş dizi → nil; zaman ilk başlangıçtan önceyse ya da sonlu değilse 0.
    static func sonBaslayan(zaman: Double, baslangiclar: [Double]) -> Int? {
        guard !baslangiclar.isEmpty else { return nil }
        guard zaman.isFinite, zaman >= baslangiclar[0] else { return 0 }
        var alt = 0, ust = baslangiclar.count - 1
        while alt < ust {
            let orta = (alt + ust + 1) / 2
            if baslangiclar[orta] <= zaman { alt = orta } else { ust = orta - 1 }
        }
        return alt
    }

    static func aktifSatir(zaman: Double, plan: SesPlani) -> Int? {
        if plan.sure <= 0 { return plan.satirlar.isEmpty ? nil : 0 }
        return sonBaslayan(zaman: zaman, baslangiclar: plan.satirlar.map(\.baslangic))
    }

    static func aktifBolum(zaman: Double, plan: SesPlani) -> Int? {
        sonBaslayan(zaman: zaman, baslangiclar: plan.bolumler.map(\.baslangic))
    }

    // MARK: Sınırlama ve yardımcılar

    static func hizSinirla(_ hiz: Double) -> Double {
        guard hiz.isFinite else { return 1 }
        return min(2, max(0.75, hiz))
    }

    /// Geçerli hızdan bir sonraki/önceki adıma geçer (uçlarda sabit kalır).
    static func hizAdimi(_ hiz: Double, ileri: Bool) -> Double {
        let h = hizSinirla(hiz)
        let i = hizAdimlari.enumerated().min(by: { abs($0.element - h) < abs($1.element - h) })?.offset ?? 1
        return hizAdimlari[min(hizAdimlari.count - 1, max(0, i + (ileri ? 1 : -1)))]
    }

    /// `zaman + fark`, [0, sure] aralığına sıkıştırılır. Süre bilinmiyorsa (<= 0) yalnız alt sınır uygulanır.
    static func atla(zaman: Double, fark: Double, sure: Double) -> Double {
        let z = zaman.isFinite ? zaman : 0
        let hedef = z + (fark.isFinite ? fark : 0)
        guard sure.isFinite, sure > 0 else { return max(0, hedef) }
        return min(sure, max(0, hedef))
    }

    /// Kaldığı yerden devam: kayıt yok/çok başta/bitişe çok yakınsa baştan.
    static func devamZamani(kayitli: Double?, sure: Double) -> Double {
        guard let k = kayitli, k.isFinite, k >= 5 else { return 0 }
        guard sure.isFinite, sure > 0 else { return k }
        return k >= sure - 3 ? 0 : k
    }

    /// Mevcut bölümün başına, zaten ilk 3 sn içindeyse bir öncekine gider (önceki-parça kumandası davranışı).
    static func oncekiBolumHedefi(zaman: Double, plan: SesPlani) -> Double {
        guard let b = aktifBolum(zaman: zaman, plan: plan) else { return 0 }
        if zaman - plan.bolumler[b].baslangic > 3 || b == 0 { return plan.bolumler[b].baslangic }
        return plan.bolumler[b - 1].baslangic
    }

    static func sonrakiBolumHedefi(zaman: Double, plan: SesPlani) -> Double? {
        guard let b = aktifBolum(zaman: zaman, plan: plan), b + 1 < plan.bolumler.count else { return nil }
        return plan.bolumler[b + 1].baslangic
    }

    /// "m:ss" ya da "h:mm:ss".
    static func zamanMetni(_ saniye: Double) -> String {
        let t = Int((saniye.isFinite ? max(0, saniye) : 0).rounded(.down))
        let s = t % 60, d = (t / 60) % 60, sa = t / 3600
        return sa > 0 ? String(format: "%d:%02d:%02d", sa, d, s) : String(format: "%d:%02d", d, s)
    }

    static func devamAnahtari(_ kimlik: String) -> String { "sesOynatici.devam.v1.\(kimlik)" }
}
