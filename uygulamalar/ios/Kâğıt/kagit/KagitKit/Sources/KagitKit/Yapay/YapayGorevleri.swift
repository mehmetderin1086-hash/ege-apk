import Foundation

public enum OzetStili: String, CaseIterable, Sendable, Identifiable {
    case kisa, ayrintili, maddeler
    public var id: String { rawValue }
    public var ad: String {
        switch self {
        case .kisa: "Kısa"
        case .ayrintili: "Ayrıntılı"
        case .maddeler: "Madde madde"
        }
    }
    var yonerge: String {
        switch self {
        case .kisa: "En çok 5-6 cümlelik kısa bir özet yaz."
        case .ayrintili: "Konu başlıklarına ayrılmış, ayrıntılı ve düzenli bir özet yaz. Önemli kavram, tanım ve sayıları koru."
        case .maddeler: "Önemli noktaları “- ” ile başlayan kısa maddeler olarak yaz."
        }
    }
}

public struct YapayCikti: Sendable, Hashable {
    public var metin: String
    public var kaynakEtiketi: String
}

private let turkceSistem = "Sen Türk lise öğretmenlerine ve öğrencilerine yardım eden bir asistansın. Her zaman Türkçe, açık ve doğru yaz. Markdown başlığı (#) kullanma; kalın/italik işaretleri (**) kullanma."

/// Uzun belgeler için parçala → özetle → birleştir (map-reduce) özetleyici.
public enum Ozetleyici {

    public static func ozetle(sayfalar: [Int: String], stil: OzetStili, yz: YapayZeka,
                              ilerleme: Ilerleme? = nil) async throws -> YapayCikti {
        guard !sayfalar.isEmpty else { throw KagitHata.yapayZeka("Belgede özetlenecek metin bulunamadı.") }
        let sinir = max(Int(Double(yz.baglamSiniri) * 0.6), 1500)
        let toplam = BelgeMetni.birlestir(sayfalar, etiketli: false)
        var etiket = yz.kaynakEtiketi ?? ""

        if toplam.count <= sinir {
            let y = try await yz.yanit(YapayIstek(sistem: turkceSistem,
                kullanici: "Aşağıdaki metni özetle. \(stil.yonerge)\n\nMETİN:\n\(toplam)", azamiToken: 3000))
            ilerleme?(1)
            return YapayCikti(metin: y.metin, kaynakEtiketi: y.kaynakEtiketi)
        }

        // Harita: her parça için kısmi özet
        var parcalar = Parcalayici.parcala(sayfalar, hedef: sinir)
        var kismi: [(etiket: String, metin: String)] = []
        let paralel = yz.baglamSiniri > 10_000 ? 3 : 1
        var tamamlanan = 0
        let toplamIs = Double(parcalar.count) + 1
        var sira = 0
        var sonuclar = [Int: (String, String)]()
        try await withThrowingTaskGroup(of: (Int, String, String).self) { grup in
            func ekle() {
                guard sira < parcalar.count else { return }
                let i = sira; sira += 1
                let p = parcalar[i]
                grup.addTask {
                    let y = try await yz.yanit(YapayIstek(sistem: turkceSistem,
                        kullanici: "Aşağıdaki bölümün (sayfa \(p.sayfaEtiketi)) bütün önemli bilgilerini koruyarak kısa notlar çıkar.\n\nMETİN:\n\(p.metin)",
                        azamiToken: 1500))
                    return (i, y.metin, y.kaynakEtiketi)
                }
            }
            for _ in 0..<paralel { ekle() }
            while let (i, m, e) = try await grup.next() {
                sonuclar[i] = (m, e)
                tamamlanan += 1
                ilerleme?(Double(tamamlanan) / toplamIs)
                ekle()
            }
        }
        for i in 0..<parcalar.count {
            if let (m, e) = sonuclar[i] {
                kismi.append(("sayfa \(parcalar[i].sayfaEtiketi)", m))
                etiket = e
            }
        }
        parcalar.removeAll()

        // İndirge: kısmi özetler sığana dek gruplayarak daralt
        var derinlik = 0
        while kismi.reduce(0, { $0 + $1.metin.count }) > sinir, derinlik < 4 {
            derinlik += 1
            var yeni: [(String, String)] = []
            var grup: [(etiket: String, metin: String)] = []
            var boy = 0
            func bosalt() async throws {
                guard !grup.isEmpty else { return }
                let govde = grup.map { "(\($0.etiket))\n\($0.metin)" }.joined(separator: "\n\n")
                let y = try await yz.yanit(YapayIstek(sistem: turkceSistem,
                    kullanici: "Aşağıdaki notları, bilgi kaybetmeden daha kısa tek bir not metninde birleştir.\n\n\(govde)", azamiToken: 1500))
                yeni.append(("\(grup.first!.etiket) …", y.metin))
                etiket = y.kaynakEtiketi
                grup = []; boy = 0
            }
            for k in kismi {
                if boy + k.metin.count > sinir { try await bosalt() }
                grup.append(k); boy += k.metin.count
            }
            try await bosalt()
            if yeni.count >= kismi.count { break }
            kismi = yeni
        }

        let govde = kismi.map { "(\($0.etiket))\n\($0.metin)" }.joined(separator: "\n\n")
        let son = try await yz.yanit(YapayIstek(sistem: turkceSistem,
            kullanici: "Aşağıda bir belgenin bölüm notları var. Bunlardan belgenin tamamını kapsayan bir özet yaz. \(stil.yonerge)\n\nNOTLAR:\n\(govde)",
            azamiToken: 3500))
        ilerleme?(1)
        return YapayCikti(metin: son.metin, kaynakEtiketi: son.kaynakEtiketi.isEmpty ? etiket : son.kaynakEtiketi)
    }
}

/// Seçili metin üzerinde kısa görevler.
public enum MetinGorevleri {
    public static func acikla(_ metin: String, yz: YapayZeka) async throws -> YapayCikti {
        let y = try await yz.yanit(YapayIstek(sistem: turkceSistem,
            kullanici: "Aşağıdaki metni bir lise öğrencisine açıkla. Terimleri tanımla, gerekirse kısa bir örnek ver.\n\nMETİN:\n\(metin.prefix(yz.baglamSiniri / 2))",
            azamiToken: 1800))
        return YapayCikti(metin: y.metin, kaynakEtiketi: y.kaynakEtiketi)
    }

    public static func sadelestir(_ metin: String, yz: YapayZeka) async throws -> YapayCikti {
        let y = try await yz.yanit(YapayIstek(sistem: turkceSistem,
            kullanici: "Aşağıdaki metni anlamını bozmadan daha basit, kısa cümlelerle yeniden yaz.\n\nMETİN:\n\(metin.prefix(yz.baglamSiniri / 2))",
            azamiToken: 1800))
        return YapayCikti(metin: y.metin, kaynakEtiketi: y.kaynakEtiketi)
    }
}

/// Belgeyle sohbet: Türkçe BM25 ile ilgili parçaları seçer, yanıtta kaynak sayfa numaralarını verir.
public struct BelgeSohbeti: Sendable {
    public struct Yanit: Sendable, Hashable {
        public var metin: String
        /// Yanıtta atıf yapılan (ya da atıf yoksa kullanılan parçaların) sayfaları, artan sırayla.
        public var kaynakSayfalar: [Int]
        public var kaynakEtiketi: String
    }

    let sayfalar: [Int: String]
    let dizin: BM25Dizin
    let yz: YapayZeka

    public init(sayfalar: [Int: String], yz: YapayZeka) {
        self.sayfalar = sayfalar
        self.yz = yz
        dizin = BM25Dizin(parcalar: Parcalayici.parcala(sayfalar, hedef: max(yz.baglamSiniri / 8, 700)))
    }

    /// Soruya konu olacak bağlamı kurar: belge küçükse tamamı, değilse BM25 ile en uygun parçalar.
    func baglam(_ sorgu: String) -> (metin: String, sayfalar: [Int]) {
        let butce = max(Int(Double(yz.baglamSiniri) * 0.55), 1200)
        let tam = BelgeMetni.birlestir(sayfalar)
        if tam.count <= butce { return (tam, sayfalar.keys.sorted()) }
        var secilen: [BelgeParcasi] = []
        var boy = 0
        for (p, _) in dizin.ara(sorgu, en: 12) {
            if boy + p.metin.count > butce { continue }
            secilen.append(p); boy += p.metin.count
        }
        if secilen.isEmpty, let ilk = dizin.parcalar.first { secilen = [ilk] }
        secilen.sort { $0.sayfaBas < $1.sayfaBas }
        let metin = secilen.map { "[Sayfa \($0.sayfaEtiketi)]\n\($0.metin)" }.joined(separator: "\n\n")
        let sf = Set(secilen.flatMap { Array($0.sayfaBas...$0.sayfaSon) }).sorted()
        return (metin, sf)
    }

    public func sor(_ soru: String, gecmis: [YapayMesaj] = []) async throws -> Yanit {
        let onceki = gecmis.last(where: { $0.rol == .kullanici })?.icerik ?? ""
        let (b, sayfalarBaglam) = baglam("\(soru) \(onceki)")
        let sistem = turkceSistem + "\nYalnızca verilen BELGE bölümlerine dayanarak yanıtla. Bilgi belgede yoksa bunu açıkça söyle. Yanıtında kullandığın bilginin sayfasını “(s. 3)” biçiminde parantez içinde belirt."
        var mesajlar = Array(gecmis.suffix(6))
        mesajlar.append(.kullanici("BELGE:\n\(b)\n\nSORU: \(soru)"))
        let y = try await yz.yanit(YapayIstek(sistem: sistem, mesajlar: mesajlar, azamiToken: 2000))
        var atif = Self.atiflar(y.metin).filter { sayfalar[$0] != nil }
        if atif.isEmpty { atif = Array(sayfalarBaglam.prefix(4)) }
        return Yanit(metin: y.metin, kaynakSayfalar: atif, kaynakEtiketi: y.kaynakEtiketi)
    }

    /// “(s. 3)”, “(s. 3-5)”, “sayfa 7, 9” gibi atıflardaki sayfa numaraları.
    public static func atiflar(_ metin: String) -> [Int] {
        guard let re = try? NSRegularExpression(pattern: #"(?:\bs\.|\bsayfa(?:lar)?|\bss\.)\s*(\d+(?:\s*[-–,]\s*\d+|\s+ve\s+\d+)*)"#,
                                                options: [.caseInsensitive]) else { return [] }
        let ns = metin as NSString
        var kume = Set<Int>()
        for m in re.matches(in: metin, range: NSRange(location: 0, length: ns.length)) {
            let ham = ns.substring(with: m.range(at: 1))
            let aralik = ham.contains("-") || ham.contains("–")
            let sayilar = ham.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if aralik, sayilar.count == 2, sayilar[0] <= sayilar[1], sayilar[1] - sayilar[0] < 200 {
                for i in sayilar[0]...sayilar[1] { kume.insert(i) }
            } else {
                sayilar.forEach { kume.insert($0) }
            }
        }
        return kume.sorted()
    }
}

/// Bulutla belge çevirisi (Türkçe ↔ İngilizce).
public enum Cevirmen {
    public enum Hedef: String, CaseIterable, Sendable, Identifiable {
        case turkce, ingilizce
        public var id: String { rawValue }
        public var ad: String { self == .turkce ? "Türkçe" : "İngilizce" }
    }

    /// Sayfaları gruplar hâlinde çevirir; sayfa sınırları işaretçilerle korunur.
    public static func cevir(sayfalar: [Int: String], hedef: Hedef, yz: YapayZeka,
                             ilerleme: Ilerleme? = nil) async throws -> (sayfalar: [Int: String], kaynakEtiketi: String) {
        guard !sayfalar.isEmpty else { throw KagitHata.yapayZeka("Belgede çevrilecek metin bulunamadı.") }
        let sinir = max(Int(Double(yz.baglamSiniri) * 0.3), 1000)
        var gruplar: [[Int]] = []
        var simdiki: [Int] = []
        var boy = 0
        for s in sayfalar.keys.sorted() {
            let n = sayfalar[s]?.count ?? 0
            if !simdiki.isEmpty, boy + n > sinir { gruplar.append(simdiki); simdiki = []; boy = 0 }
            simdiki.append(s); boy += n
        }
        if !simdiki.isEmpty { gruplar.append(simdiki) }

        var sonuc: [Int: String] = [:]
        var etiket = ""
        for (gi, grup) in gruplar.enumerated() {
            try iptalDenetle()
            // Tek sayfa sınırı aşıyorsa parçalara bölünür
            if grup.count == 1, let s = grup.first, (sayfalar[s]?.count ?? 0) > sinir {
                var parcalar: [String] = []
                for p in Parcalayici.birimler(sayfalar[s] ?? "", sinir: sinir) { parcalar.append(p) }
                var cevrilen: [String] = []
                var birikim = ""
                func bosalt() async throws {
                    guard !birikim.isEmpty else { return }
                    let y = try await yz.yanit(cevirIstegi(birikim, hedef))
                    cevrilen.append(y.metin); etiket = y.kaynakEtiketi; birikim = ""
                }
                for p in parcalar {
                    if birikim.count + p.count > sinir { try await bosalt() }
                    birikim += (birikim.isEmpty ? "" : "\n") + p
                }
                try await bosalt()
                sonuc[s] = cevrilen.joined(separator: "\n")
            } else {
                let govde = grup.map { "<<<SAYFA \($0)>>>\n\(sayfalar[$0] ?? "")" }.joined(separator: "\n")
                let y = try await yz.yanit(cevirIstegi(govde, hedef))
                etiket = y.kaynakEtiketi
                let ayrik = isaretciyleAyir(y.metin)
                if ayrik.isEmpty, grup.count == 1 {
                    sonuc[grup[0]] = y.metin
                } else {
                    for s in grup { sonuc[s] = ayrik[s] ?? "" }
                }
            }
            ilerleme?(Double(gi + 1) / Double(gruplar.count))
        }
        return (sonuc, etiket)
    }

    static func cevirIstegi(_ metin: String, _ hedef: Hedef) -> YapayIstek {
        YapayIstek(sistem: "Sen profesyonel bir çevirmensin. Yalnızca çeviriyi yaz; yorum, açıklama ya da ek not ekleme. “<<<SAYFA n>>>” satırlarını olduğu gibi koru.",
                   kullanici: "Aşağıdaki metni \(hedef.ad) diline çevir. Anlamı ve paragraf düzenini koru.\n\n\(metin)",
                   azamiToken: 6000)
    }

    /// “<<<SAYFA n>>>” işaretçilerine göre yanıtı sayfalara ayırır.
    static func isaretciyleAyir(_ metin: String) -> [Int: String] {
        guard let re = try? NSRegularExpression(pattern: #"<<<\s*SAYFA\s+(\d+)\s*>>>"#, options: [.caseInsensitive]) else { return [:] }
        let ns = metin as NSString
        let esler = re.matches(in: metin, range: NSRange(location: 0, length: ns.length))
        var sonuc: [Int: String] = [:]
        for (i, m) in esler.enumerated() {
            let no = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let bas = m.range.location + m.range.length
            let son = i + 1 < esler.count ? esler[i + 1].range.location : ns.length
            sonuc[no] = ns.substring(with: NSRange(location: bas, length: son - bas)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return sonuc
    }
}
