import CoreGraphics
import Foundation
import Vision

/// Bir OCR satırındaki tek sözcük (karartma gibi konum gerektiren işler için).
public struct OCRKelimesi: Sendable, Hashable {
    public let metin: String
    /// `OCRAyrintiliSatir.metin` içindeki UTF-16 aralığı.
    public let aralik: NSRange
    /// Görüntüye göre normalize (0...1, sol alt köken).
    public let kutu: CGRect
}

/// Sözcük kutularıyla birlikte OCR satırı. `metin` ham tanıma çıktısıdır (düzeltme uygulanmaz),
/// böylece düzenli ifade eşleşmelerinin aralıkları sözcüklerle tutarlıdır.
public struct OCRAyrintiliSatir: Sendable, Hashable {
    public let metin: String
    public let kutu: CGRect
    public let kelimeler: [OCRKelimesi]

    /// Metindeki bir aralıkla kesişen sözcüklerin birleşik kutusu.
    public func kutu(aralik: NSRange) -> CGRect? {
        let ilgili = kelimeler.filter { NSIntersectionRange($0.aralik, aralik).length > 0 }
        guard var birlesik = ilgili.first?.kutu else { return nil }
        for k in ilgili.dropFirst() { birlesik = birlesik.union(k.kutu) }
        return birlesik
    }
}

extension MetinTanima {
    /// Sözcük kutulu OCR (yukarıdan aşağıya sıralı).
    public static func taniAyrintili(_ goruntu: CGImage, diller: [String] = varsayilanDiller,
                                     hizli: Bool = false) async throws -> [OCRAyrintiliSatir] {
        var istek = RecognizeTextRequest()
        istek.recognitionLevel = hizli ? .fast : .accurate
        istek.recognitionLanguages = diller.map { Locale.Language(identifier: $0) }
        istek.usesLanguageCorrection = true
        let gozlemler = try await istek.perform(on: goruntu)
        var satirlar: [OCRAyrintiliSatir] = []
        for g in gozlemler {
            guard let aday = g.topCandidates(1).first else { continue }
            let s = aday.string
            let b = g.boundingBox
            let satirKutusu = CGRect(x: b.origin.x, y: b.origin.y, width: b.width, height: b.height)
            var kelimeler: [OCRKelimesi] = []
            var baslangic: String.Index?
            func kapat(_ bitis: String.Index) {
                guard let bas = baslangic else { return }
                baslangic = nil
                let aralik = bas..<bitis
                guard let bolge = aday.boundingBox(for: aralik) else { return }
                let r = bolge.boundingBox
                kelimeler.append(OCRKelimesi(metin: String(s[aralik]), aralik: NSRange(aralik, in: s),
                                             kutu: CGRect(x: r.origin.x, y: r.origin.y, width: r.width, height: r.height)))
            }
            var i = s.startIndex
            while i < s.endIndex {
                if s[i].isWhitespace { kapat(i) } else if baslangic == nil { baslangic = i }
                i = s.index(after: i)
            }
            kapat(s.endIndex)
            satirlar.append(OCRAyrintiliSatir(metin: s, kutu: satirKutusu, kelimeler: kelimeler))
        }
        return satirlar.sorted {
            abs($0.kutu.midY - $1.kutu.midY) > 0.008 ? $0.kutu.midY > $1.kutu.midY : $0.kutu.minX < $1.kutu.minX
        }
    }
}

/// `RecognizeDocumentsRequest` (iOS 26+) ile belge yapısı: paragraflar ve tablolar.
public struct BelgeYapisi: Sendable, Equatable {
    public struct Tablo: Sendable, Equatable {
        public var satirlar: [[String]]

        /// Sekmeyle ayrılmış metin (Excel'e yapıştırmaya uygun).
        public var tsv: String {
            satirlar.map { $0.map { $0.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }
                .joined(separator: "\t") }.joined(separator: "\n")
        }

        /// CSV (noktalı virgül ayraçlı: Türkçe yerelde Excel'in beklediği biçim).
        public var csv: String {
            satirlar.map { satir in
                satir.map { h in
                    let t = h.replacingOccurrences(of: "\n", with: " ")
                    return t.contains(";") || t.contains("\"") ? "\"" + t.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : t
                }.joined(separator: ";")
            }.joined(separator: "\n")
        }
    }

    public var metin: String
    public var paragraflar: [String]
    public var tablolar: [Tablo]

    public static func cikar(_ goruntu: CGImage) async throws -> BelgeYapisi {
        let istek = RecognizeDocumentsRequest()
        let sonuc = try await istek.perform(on: goruntu)
        var yapi = BelgeYapisi(metin: "", paragraflar: [], tablolar: [])
        var parcalar: [String] = []
        for gozlem in sonuc {
            let belge = gozlem.document
            parcalar.append(belge.text.transcript)
            yapi.paragraflar += belge.paragraphs.map(\.transcript)
            for tablo in belge.tables {
                yapi.tablolar.append(Tablo(satirlar: tablo.rows.map { satir in satir.map { $0.content.text.transcript } }))
            }
        }
        yapi.metin = parcalar.joined(separator: "\n")
        return yapi
    }
}
