import Foundation
import PDFKit

/// PDF'ten sayfa sayfa metin çıkarma (metin katmanı yoksa OCR) ve parçalama.
public enum BelgeMetni {

    /// Sayfa → metin (anahtar: 1 tabanlı sayfa numarası). `sayfalar` 0 tabanlıdır; nil ise hepsi.
    public static func sayfaMetinleri(veri: Data, sayfalar: [Int]? = nil, ocr: Bool = true,
                                      ilerleme: Ilerleme? = nil) async throws -> [Int: String] {
        guard let belge = PDFDocument(data: veri) else { throw KagitHata.acilamadi("belge") }
        let hedef = sayfalar ?? Array(0..<belge.pageCount)
        var sonuc: [Int: String] = [:]
        for (sira, i) in hedef.enumerated() {
            try iptalDenetle()
            guard let sayfa = belge.page(at: i) else { continue }
            var m = (sayfa.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if m.count < 20, ocr, let satirlar = try? await MetinTanima.tani(sayfa: sayfa, dpi: 200) {
                let o = MetinTanima.metin(satirlar)
                if o.count > m.count { m = o }
            }
            if !m.isEmpty { sonuc[i + 1] = m }
            ilerleme?(Double(sira + 1) / Double(max(hedef.count, 1)))
        }
        return sonuc
    }

    /// Sayfa numarasına göre sıralı birleşik metin; her sayfanın başında "[Sayfa N]" etiketi.
    public static func birlestir(_ sayfalar: [Int: String], etiketli: Bool = true) -> String {
        sayfalar.keys.sorted().map { k in etiketli ? "[Sayfa \(k)]\n\(sayfalar[k] ?? "")" : (sayfalar[k] ?? "") }
            .joined(separator: "\n\n")
    }
}

/// Belgenin bir bölümü: hangi sayfalardan geldiği ile birlikte.
public struct BelgeParcasi: Sendable, Hashable, Identifiable {
    public let id: Int
    public let sayfaBas: Int
    public let sayfaSon: Int
    public let metin: String

    public var sayfaEtiketi: String { sayfaBas == sayfaSon ? "\(sayfaBas)" : "\(sayfaBas)-\(sayfaSon)" }
}

public enum Parcalayici {

    /// Sayfa metinlerini en çok `hedef` karakterlik, paragraf sınırlarına saygılı parçalara böler.
    public static func parcala(_ sayfalar: [Int: String], hedef: Int) -> [BelgeParcasi] {
        let hedef = max(hedef, 100)
        var parcalar: [BelgeParcasi] = []
        var biriken = ""
        var bas = 0, son = 0

        func kapat() {
            let t = biriken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { parcalar.append(BelgeParcasi(id: parcalar.count, sayfaBas: bas, sayfaSon: son, metin: t)) }
            biriken = ""
            bas = 0
        }

        for sayfa in sayfalar.keys.sorted() {
            for p in birimler(sayfalar[sayfa] ?? "", sinir: hedef) {
                if !biriken.isEmpty, biriken.count + p.count + 2 > hedef { kapat() }
                if biriken.isEmpty { bas = sayfa }
                biriken += (biriken.isEmpty ? "" : "\n\n") + p
                son = sayfa
            }
        }
        kapat()
        return parcalar
    }

    /// Paragraflara, uzun paragrafları cümlelere, onları da sert kesime böler.
    static func birimler(_ metin: String, sinir: Int) -> [String] {
        var sonuc: [String] = []
        let paragraflar = metin.components(separatedBy: "\n\n").flatMap { $0.components(separatedBy: "\n") }
        for p in paragraflar {
            let t = p.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if t.count <= sinir { sonuc.append(t); continue }
            var cur = ""
            for c in cumleler(t) {
                if c.count > sinir {
                    if !cur.isEmpty { sonuc.append(cur); cur = "" }
                    var kalan = Substring(c)
                    while kalan.count > sinir {
                        sonuc.append(String(kalan.prefix(sinir)))
                        kalan = kalan.dropFirst(sinir)
                    }
                    cur = String(kalan)
                } else if cur.count + c.count + 1 > sinir {
                    sonuc.append(cur)
                    cur = c
                } else {
                    cur += (cur.isEmpty ? "" : " ") + c
                }
            }
            if !cur.isEmpty { sonuc.append(cur) }
        }
        return sonuc
    }

    static func cumleler(_ s: String) -> [String] {
        var sonuc: [String] = []
        s.enumerateSubstrings(in: s.startIndex..., options: .bySentences) { alt, _, _, _ in
            if let alt { sonuc.append(alt.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        return sonuc.isEmpty ? [s] : sonuc
    }
}

/// Türkçe'ye uyarlanmış BM25 sıralayıcı (ek-kök sorununa karşı sözcüklerin ilk 5 harfi kullanılır).
public struct BM25Dizin: Sendable {
    public let parcalar: [BelgeParcasi]
    private let belirtecler: [[String]]
    private let df: [String: Int]
    private let ortalamaUzunluk: Double
    private let k1 = 1.5, b = 0.75

    static let durak: Set<String> = [
        "ve", "ile", "bir", "bu", "su", "da", "de", "mi", "icin", "ne", "nedir", "nasil", "hangi", "olan", "gibi",
        "daha", "en", "cok", "ya", "ama", "veya", "ise", "kadar", "her", "olarak", "ki", "o", "ben", "sen", "biz",
        "bana", "bunu", "bunlar", "neden", "kac", "var", "yok", "midir", "olur", "olup", "ancak", "fakat", "hem",
    ]

    public static func belirtecler(_ metin: String) -> [String] {
        TurkceMetin.anahtar(metin).split(separator: " ").map(String.init)
            .filter { $0.count >= 2 && !durak.contains($0) }
            .map { String($0.prefix(5)) }
    }

    public init(parcalar: [BelgeParcasi]) {
        self.parcalar = parcalar
        let b = parcalar.map { Self.belirtecler($0.metin) }
        belirtecler = b
        var d: [String: Int] = [:]
        for liste in b { for t in Set(liste) { d[t, default: 0] += 1 } }
        df = d
        ortalamaUzunluk = max(1, Double(b.reduce(0) { $0 + $1.count }) / Double(max(b.count, 1)))
    }

    /// Sorguya en uygun parçalar (puanı sıfırdan büyük olanlar), puana göre azalan.
    public func ara(_ sorgu: String, en k: Int = 5) -> [(parca: BelgeParcasi, puan: Double)] {
        let q = Set(Self.belirtecler(sorgu))
        guard !q.isEmpty, !parcalar.isEmpty else { return [] }
        let n = Double(parcalar.count)
        var sonuc: [(BelgeParcasi, Double)] = []
        for (i, liste) in belirtecler.enumerated() {
            var tf: [String: Int] = [:]
            for t in liste { tf[t, default: 0] += 1 }
            var puan = 0.0
            let uzunlukOrani: Double = Double(liste.count) / ortalamaUzunluk
            for t in q {
                guard let tfT = tf[t] else { continue }
                let f = Double(tfT)
                let dfT = Double(df[t] ?? 0)
                let idf: Double = log(1 + (n - dfT + 0.5) / (dfT + 0.5))
                let pay: Double = f * (k1 + 1)
                let payda: Double = f + k1 * (1 - b + b * uzunlukOrani)
                puan += idf * pay / payda
            }
            if puan > 0 { sonuc.append((parcalar[i], puan)) }
        }
        return sonuc.sorted { $0.1 > $1.1 }.prefix(k).map { ($0.0, $0.1) }
    }
}
