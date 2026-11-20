import Foundation

// "Her Yerde Ara" çekirdeği: saf mantık, arayüz/SwiftData bağımlılığı yok. Kaynaklar protokolle verilir; test sahte kaynak kullanır.

// MARK: Türler

nonisolated enum AramaTuru: String, CaseIterable, Sendable, Hashable, Identifiable {
    case tuval, sohbet, hafiza, dosya, gorev
    var id: String { rawValue }
    var etiket: String {
        switch self {
        case .tuval: "Tuval"
        case .sohbet: "Sohbetler"
        case .hafiza: "Hafıza"
        case .dosya: "Dosyalar"
        case .gorev: "Sunucu görevleri"
        }
    }
    var simge: String {
        switch self {
        case .tuval: "doc.text"
        case .sohbet: "bubble.left.and.bubble.right"
        case .hafiza: "brain"
        case .dosya: "folder"
        case .gorev: "server.rack"
        }
    }
}

/// Satıra dokununca hangi ekranın açılacağını söyler; açma işini çağıran taraf yapar.
nonisolated enum AramaHedefi: Hashable, Sendable {
    case tuval(UUID), sohbet(UUID), hafiza(UUID), dosya(String), gorev(String)

    var tur: AramaTuru {
        switch self {
        case .tuval: .tuval
        case .sohbet: .sohbet
        case .hafiza: .hafiza
        case .dosya: .dosya
        case .gorev: .gorev
        }
    }
}

nonisolated struct AramaOgesi: Identifiable, Equatable, Sendable {
    let hedef: AramaHedefi
    let baslik: String
    let govde: String
    let tarih: Date?
    var id: AramaHedefi { hedef }
    var tur: AramaTuru { hedef.tur }

    init(hedef: AramaHedefi, baslik: String, govde: String = "", tarih: Date? = nil) {
        self.hedef = hedef; self.baslik = baslik; self.govde = govde; self.tarih = tarih
    }
}

nonisolated struct AramaSonucu: Identifiable, Equatable, Sendable {
    let oge: AramaOgesi
    let puan: Double
    /// UTF-16 konumlu (NSRange/AttributedString ile doğrudan uyumlu) vurgu aralıkları.
    let baslikVurgulari: [NSRange]
    let ozet: String
    let ozetVurgulari: [NSRange]
    var id: AramaHedefi { oge.hedef }
}

nonisolated struct AramaCikti: Sendable, Equatable {
    var sonuclar: [AramaSonucu] = []
    /// Yüklenemeyen kaynakların türleri (hata yalıtımı: diğer kaynaklar yine sonuç verir).
    var atlanan: [AramaTuru] = []
    /// Süzgeç ve sınırdan önce eşleşen öğe sayısı.
    var toplam = 0
}

nonisolated struct AramaAgirliklari: Sendable, Equatable {
    var baslik = 5.0
    var govde = 1.0
    var yakinlik = 2.0
    var guncellik = 1.5
    /// Güncellik katkısının yarıya indiği gün sayısı.
    var yarilanmaGunu = 30.0
    static let varsayilan = AramaAgirliklari()
}

// MARK: Kaynaklar

nonisolated protocol AramaKaynagi: Sendable {
    var tur: AramaTuru { get }
    func ogeler() async throws -> [AramaOgesi]
}

nonisolated struct KapanisAramaKaynagi: AramaKaynagi {
    let tur: AramaTuru
    let yukle: @Sendable () async throws -> [AramaOgesi]
    func ogeler() async throws -> [AramaOgesi] { try await yukle() }
}

// MARK: Normalizasyon

/// Türkçe duyarlı katlama: İ/I/ı → i, ç ğ ö ş ü ve diğer aksanlar tabana, büyük/küçük harf yok.
/// Katlanmış her skalerin özgün metindeki UTF-16 konumu izlenir (vurgu için).
nonisolated enum AramaMetni {
    struct Jeton: Sendable, Equatable { let bas: Int; let son: Int }

    struct Hazir: Sendable {
        var skalerler: [UInt32] = []
        var jetonlar: [Jeton] = []
        /// Yalnız `konumlarla: true` iken dolu: katlanmış skalerin özgün UTF-16 [bas, son) aralığı.
        var bas: [Int32] = []
        var son: [Int32] = []
    }

    static let azamiAlan = 20_000

    private static let ozelKatlama: [UInt32: [UInt32]] = [
        0xDF: [0x73, 0x73], 0xE6: [0x61, 0x65], 0x153: [0x6F, 0x65], 0xF8: [0x6F], 0x111: [0x64], 0x142: [0x6C],
        0x130: [0x69], 0x131: [0x69],
    ]

    private static func harfMi(_ v: UInt32) -> Bool {
        if v < 0x80 { return (v >= 0x61 && v <= 0x7A) || (v >= 0x30 && v <= 0x39) }
        guard let s = Unicode.Scalar(v) else { return false }
        return s.properties.isAlphabetic || s.properties.numericType != nil
    }

    private static func isaretMi(_ s: Unicode.Scalar) -> Bool {
        switch s.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: true
        default: false
        }
    }

    /// Tek skaleri katlar; birleştirici işaretler boş döner.
    private static func katla(_ s: Unicode.Scalar, _ cikti: inout [UInt32]) {
        let v = s.value
        if v < 0x80 {
            cikti.append(v >= 0x41 && v <= 0x5A ? v + 32 : v)
            return
        }
        if let o = ozelKatlama[v] { cikti.append(contentsOf: o); return }
        if isaretMi(s) { return }
        let kucuk = String(s).lowercased()
        for k in kucuk.decomposedStringWithCanonicalMapping.unicodeScalars where !isaretMi(k) {
            if let o = ozelKatlama[k.value] { cikti.append(contentsOf: o) } else { cikti.append(k.value) }
        }
    }

    static func hazirla(_ metin: String, azami: Int = azamiAlan, konumlarla: Bool = false) -> Hazir {
        var h = Hazir()
        var ofset: Int32 = 0
        var jetonBasi: Int?
        var gecici: [UInt32] = []
        for s in metin.unicodeScalars {
            let uzun: Int32 = s.value > 0xFFFF ? 2 : 1
            let bas = ofset
            ofset += uzun
            gecici.removeAll(keepingCapacity: true)
            katla(s, &gecici)
            if gecici.isEmpty {
                // Birleştirici işaret: bir önceki katlanmış skalerin aralığına katılır.
                if konumlarla, !h.son.isEmpty { h.son[h.son.count - 1] = ofset }
                continue
            }
            for v in gecici {
                if h.skalerler.count >= azami {
                    if let b = jetonBasi { h.jetonlar.append(Jeton(bas: b, son: h.skalerler.count)) }
                    return h
                }
                let i = h.skalerler.count
                h.skalerler.append(v)
                if konumlarla { h.bas.append(bas); h.son.append(ofset) }
                if harfMi(v) {
                    if jetonBasi == nil { jetonBasi = i }
                } else if let b = jetonBasi {
                    h.jetonlar.append(Jeton(bas: b, son: i)); jetonBasi = nil
                }
            }
        }
        if let b = jetonBasi { h.jetonlar.append(Jeton(bas: b, son: h.skalerler.count)) }
        return h
    }

    /// Dışarıdan karşılaştırma için katlanmış metin ("ÇAĞRI" → "cagri", "ISPARTA" → "isparta").
    static func katlanmis(_ metin: String) -> String {
        var s = String.UnicodeScalarView()
        for v in hazirla(metin).skalerler { if let u = Unicode.Scalar(v) { s.append(u) } }
        return String(s)
    }
}

// MARK: Sorgu

nonisolated struct AramaSorgusu: Sendable, Equatable {
    static let azamiUzunluk = 256
    static let azamiJeton = 8
    let jetonlar: [[UInt32]]

    /// Boş ya da jeton çıkmayan sorgu için nil.
    init?(_ ham: String) {
        let kirpik = String(ham.prefix(Self.azamiUzunluk))
        let h = AramaMetni.hazirla(kirpik, azami: Self.azamiUzunluk * 2)
        var gorulen = Set<[UInt32]>(), liste: [[UInt32]] = []
        for j in h.jetonlar {
            let t = Array(h.skalerler[j.bas..<j.son])
            if gorulen.insert(t).inserted { liste.append(t) }
            if liste.count >= Self.azamiJeton { break }
        }
        guard !liste.isEmpty else { return nil }
        jetonlar = liste
    }
}

// MARK: Dizin

nonisolated struct AramaDizini: Sendable {
    struct Girdi: Sendable {
        let oge: AramaOgesi
        let baslik: AramaMetni.Hazir
        let govde: AramaMetni.Hazir
    }
    private(set) var girdiler: [Girdi] = []
    var sayi: Int { girdiler.count }

    init() {}
    init(ogeler: [AramaOgesi]) {
        girdiler.reserveCapacity(ogeler.count)
        for o in ogeler { ekle(o) }
    }

    mutating func ekle(_ o: AramaOgesi) {
        girdiler.append(Girdi(oge: o, baslik: AramaMetni.hazirla(o.baslik, azami: 2_000), govde: AramaMetni.hazirla(o.govde)))
    }
    mutating func ekle(_ ogeler: [AramaOgesi]) { for o in ogeler { ekle(o) } }
}

// MARK: Motor

nonisolated enum BirlesikArama {
    private enum Eslesme: Double { case alt = 0.4, onek = 0.75, tam = 1.0 }

    private static func eslestir(_ q: [UInt32], _ doc: [UInt32], _ j: AramaMetni.Jeton) -> (Eslesme, Int)? {
        let n = j.son - j.bas, m = q.count
        guard n >= m else { return nil }
        // Önek (n == m ise tam eşleşme).
        var i = 0
        while i < m, doc[j.bas + i] == q[i] { i += 1 }
        if i == m { return (n == m ? .tam : .onek, 0) }
        guard m >= 3, n > m else { return nil }
        var k = 1
        while k + m <= n {
            var t = 0
            while t < m, doc[j.bas + k + t] == q[t] { t += 1 }
            if t == m { return (.alt, k) }
            k += 1
        }
        return nil
    }

    private struct AlanDegeri {
        var puan: [Double]
        var konum: [Int]
        var hepsi: Bool { !puan.contains(0) }
    }

    private static func alan(_ q: AramaSorgusu, _ h: AramaMetni.Hazir, sikligi: Bool) -> AlanDegeri {
        var d = AlanDegeri(puan: Array(repeating: 0, count: q.jetonlar.count), konum: Array(repeating: -1, count: q.jetonlar.count))
        guard !h.jetonlar.isEmpty else { return d }
        for (qi, t) in q.jetonlar.enumerated() {
            var en = 0.0, konum = -1, adet = 0
            for (ji, j) in h.jetonlar.enumerated() {
                guard let (tur, _) = eslestir(t, h.skalerler, j) else { continue }
                adet += 1
                if tur.rawValue > en { en = tur.rawValue; konum = ji }
            }
            if en > 0 {
                d.puan[qi] = en + (sikligi ? min(0.3, 0.05 * Double(adet - 1)) : 0)
                d.konum[qi] = konum
            }
        }
        return d
    }

    private static func yakinlik(_ d: AlanDegeri) -> Double {
        let n = d.konum.count
        guard n >= 2, d.hepsi, let en = d.konum.min(), let cok = d.konum.max() else { return 0 }
        let bosluk = max(0, (cok - en) - (n - 1))
        let sirali = zip(d.konum, d.konum.dropFirst()).allSatisfy { $0 + 1 == $1 }
        return (1.0 / Double(1 + bosluk)) * (sirali ? 1.0 : 0.6)
    }

    private static func guncellik(_ tarih: Date?, simdi: Date, _ a: AramaAgirliklari) -> Double {
        guard let tarih else { return 0 }
        let gun = max(0, simdi.timeIntervalSince(tarih)) / 86_400
        return a.guncellik * pow(0.5, gun / max(a.yarilanmaGunu, 0.001))
    }

    /// Süzgeç `turler` boşsa her tür. Sonuç: puan, sonra tarih, sonra başlık sırasıyla (deterministik).
    static func ara(_ sorguMetni: String, dizin: AramaDizini, turler: Set<AramaTuru> = [], simdi: Date = .now,
                    sinir: Int = 100, agirlik: AramaAgirliklari = .varsayilan) -> AramaCikti {
        guard let q = AramaSorgusu(sorguMetni), sinir > 0 else { return AramaCikti() }
        var bulunan: [(Double, Int)] = []
        for (i, g) in dizin.girdiler.enumerated() {
            if !turler.isEmpty, !turler.contains(g.oge.tur) { continue }
            let b = alan(q, g.baslik, sikligi: false), v = alan(q, g.govde, sikligi: true)
            var toplam = 0.0, tamam = true
            for qi in q.jetonlar.indices {
                let p = max(b.puan[qi] * agirlik.baslik, v.puan[qi] * agirlik.govde)
                if p == 0 { tamam = false; break }
                toplam += p
            }
            guard tamam else { continue }
            toplam += agirlik.yakinlik * max(yakinlik(b), yakinlik(v))
            toplam += guncellik(g.oge.tarih, simdi: simdi, agirlik)
            bulunan.append((toplam, i))
        }
        bulunan.sort { a, b in
            if a.0 != b.0 { return a.0 > b.0 }
            let x = dizin.girdiler[a.1].oge, y = dizin.girdiler[b.1].oge
            if x.tarih != y.tarih { return (x.tarih ?? .distantPast) > (y.tarih ?? .distantPast) }
            if x.baslik != y.baslik { return x.baslik < y.baslik }
            return a.1 < b.1
        }
        var cikti = AramaCikti()
        cikti.toplam = bulunan.count
        cikti.sonuclar = bulunan.prefix(sinir).map { puan, ix in
            let o = dizin.girdiler[ix].oge
            let bv = vurgular(o.baslik, q, azami: 2_000)
            let (ozet, ov) = ozetle(o.govde, q)
            return AramaSonucu(oge: o, puan: puan, baslikVurgulari: bv, ozet: ozet, ozetVurgulari: ov)
        }
        return cikti
    }

    /// Kaynaklardan öğeleri toplayıp dizin kurar; bir kaynağın hatası yalnız o türü `atlanan` yapar.
    static func dizinle(kaynaklar: [any AramaKaynagi], turler: Set<AramaTuru> = []) async -> (AramaDizini, [AramaTuru]) {
        let secili = kaynaklar.filter { turler.isEmpty || turler.contains($0.tur) }
        var alinan: [(AramaTuru, [AramaOgesi]?)] = []
        await withTaskGroup(of: (AramaTuru, [AramaOgesi]?).self) { grup in
            for k in secili { grup.addTask { (k.tur, try? await k.ogeler()) } }
            for await s in grup { alinan.append(s) }
        }
        var dizin = AramaDizini(), atlanan: [AramaTuru] = []
        // Kaynak sırası sabit kalsın (grup tamamlanma sırası belirsiz).
        for k in secili {
            guard let (_, ogeler) = alinan.first(where: { $0.0 == k.tur }) else { continue }
            if let ogeler { dizin.ekle(ogeler.filter { $0.tur == k.tur }) } else if !atlanan.contains(k.tur) { atlanan.append(k.tur) }
        }
        return (dizin, atlanan)
    }

    /// Tek adımda: kaynakları yükle, dizinle, ara.
    static func ara(_ sorgu: String, kaynaklar: [any AramaKaynagi], turler: Set<AramaTuru> = [], simdi: Date = .now,
                    sinir: Int = 100) async -> AramaCikti {
        guard AramaSorgusu(sorgu) != nil else { return AramaCikti() }
        let (dizin, atlanan) = await dizinle(kaynaklar: kaynaklar, turler: turler)
        var c = ara(sorgu, dizin: dizin, turler: turler, simdi: simdi, sinir: sinir)
        c.atlanan = atlanan
        return c
    }

    /// Hafıza FTS'sinin mesaj eşleşmelerini sohbet sonuçlarına katar. Dizin sohbetin yalnız başını taşır; mesajın
    /// derininde geçen terim için sohbet burada eklenir (başlık/tarih dizinden). Zaten çıkan sohbet yinelenmez.
    /// `eslesmeler` FTS sırasıyla (en ilgili önce); `metin` mesajın baştan bir bölümü, `yedekOzet` FTS snippet'i.
    static func mesajEslesmeleriniKat(_ c: AramaCikti, eslesmeler: [(sohbet: UUID, metin: String, yedekOzet: String)],
                                      dizin: AramaDizini, sorgu: String, turler: Set<AramaTuru> = [], sinir: Int = 30) -> AramaCikti {
        guard turler.isEmpty || turler.contains(.sohbet), let q = AramaSorgusu(sorgu) else { return c }
        var sonuc = c
        var gorulen = Set(c.sonuclar.compactMap { s -> UUID? in if case .sohbet(let id) = s.oge.hedef { id } else { nil } })
        var eklenen = 0
        // FTS terimleri VEYA ile eşler; birleşik arama VE ile. "mitoz bölünme" yalnız "bölünme" geçen sohbeti getirmesin.
        let terimler = AramaMetni.katlanmis(sorgu).split(whereSeparator: \.isWhitespace).map(String.init)
        for e in eslesmeler where eklenen < sinir && !gorulen.contains(e.sohbet) {
            let govde = AramaMetni.katlanmis(e.metin + " " + e.yedekOzet)
            guard terimler.allSatisfy({ govde.contains($0) }) else { continue }
            guard let girdi = dizin.girdiler.first(where: { $0.oge.hedef == .sohbet(e.sohbet) }) else { continue }
            gorulen.insert(e.sohbet)
            var (ozet, vurgu) = ozetle(e.metin, q)
            if vurgu.isEmpty, !e.yedekOzet.isEmpty { ozet = e.yedekOzet; vurgu = [] }
            sonuc.sonuclar.append(AramaSonucu(oge: girdi.oge, puan: 0, baslikVurgulari: vurgular(girdi.oge.baslik, q),
                                              ozet: ozet, ozetVurgulari: vurgu))
            sonuc.toplam += 1; eklenen += 1
        }
        return sonuc
    }

    // MARK: Vurgu ve özet

    /// Sorgu jetonlarının metindeki UTF-16 aralıkları (önek ve içerik eşleşmesinde yalnız eşleşen kısım), birleşik ve sıralı.
    static func vurgular(_ metin: String, _ q: AramaSorgusu, azami: Int = AramaMetni.azamiAlan) -> [NSRange] {
        let h = AramaMetni.hazirla(metin, azami: azami, konumlarla: true)
        var araliklar: [(Int, Int)] = []
        for t in q.jetonlar {
            for j in h.jetonlar {
                guard let (_, ofset) = eslestir(t, h.skalerler, j) else { continue }
                let a = j.bas + ofset, b = a + t.count
                araliklar.append((Int(h.bas[a]), Int(h.son[b - 1])))
            }
        }
        return birlestir(araliklar)
    }

    private static func birlestir(_ a: [(Int, Int)]) -> [NSRange] {
        var sirali = a.sorted { $0.0 < $1.0 }, sonuc: [NSRange] = []
        guard var (bas, son) = sirali.first else { return [] }
        sirali.removeFirst()
        for (b, s) in sirali {
            if b <= son { son = max(son, s) } else { sonuc.append(NSRange(location: bas, length: son - bas)); bas = b; son = s }
        }
        sonuc.append(NSRange(location: bas, length: son - bas))
        return sonuc
    }

    /// İlk eşleşme çevresinden kısa kesit; satır sonları boşluğa çevrilir (uzunluk korunur), vurgular kesite göre kaydırılır.
    static func ozetle(_ govde: String, _ q: AramaSorgusu, uzunluk: Int = 160, oncesi: Int = 40) -> (String, [NSRange]) {
        guard !govde.isEmpty else { return ("", []) }
        let birimler = Array(govde.utf16)
        let vurgular = vurgular(govde, q)
        var bas = max(0, (vurgular.first?.location ?? 0) - oncesi)
        var son = min(birimler.count, bas + uzunluk)
        if bas > 0, bas < birimler.count, UTF16.isTrailSurrogate(birimler[bas]) { bas -= 1 }
        if son < birimler.count, UTF16.isTrailSurrogate(birimler[son]) { son += 1 }
        let kesit = birimler[bas..<son].map { $0 < 0x20 ? UInt16(0x20) : $0 }
        let basEk = bas > 0 ? "…" : "", sonEk = son < birimler.count ? "…" : ""
        let ozet = basEk + String(decoding: kesit, as: UTF16.self) + sonEk
        let kayma = basEk.utf16.count - bas
        let kirpik: [NSRange] = vurgular.compactMap { r in
            let a = max(r.location, bas), b = min(r.location + r.length, son)
            return b > a ? NSRange(location: a + kayma, length: b - a) : nil
        }
        return (ozet, kirpik)
    }
}

// MARK: Son aramalar

nonisolated enum SonAramalar {
    static func ekle(_ sorgu: String, _ liste: [String], sinir: Int = 8) -> [String] {
        let temiz = sorgu.trimmingCharacters(in: .whitespacesAndNewlines)
        guard temiz.count >= 2 else { return liste }
        let anahtar = AramaMetni.katlanmis(temiz)
        guard !anahtar.isEmpty else { return liste }
        let digerleri = liste.filter { AramaMetni.katlanmis($0) != anahtar }
        return Array(([String(temiz.prefix(AramaSorgusu.azamiUzunluk))] + digerleri).prefix(max(sinir, 0)))
    }
}
