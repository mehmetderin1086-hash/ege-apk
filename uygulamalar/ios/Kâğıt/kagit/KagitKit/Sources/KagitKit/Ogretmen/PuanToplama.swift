import Foundation
import PDFKit

/// Öğretmen işaretlerinin ek anahtarları (puan için `Isaret.puan` kullanılır).
public enum OgretmenIsaret {
    /// “Toplam: 85” kutusu; puan toplamına dahil edilmez.
    public static let toplam = "\(Isaret.onek)toplam"
    public static let yorum = "\(Isaret.onek)yorum"
}

/// Belgedeki puan işaretlerini okur.
public enum PuanOkuyucu {

    /// Sayfa sayfa (0 tabanlı) puan işaretleri.
    public static func puanlar(_ belge: PDFDocument) -> [(sayfa: Int, deger: Double)] {
        var sonuc: [(Int, Double)] = []
        for i in 0..<belge.pageCount {
            guard let s = belge.page(at: i) else { continue }
            for a in s.annotations {
                if let d = Isaret.puanDegeri(a.userName) { sonuc.append((i, d)) }
            }
        }
        return sonuc
    }

    public static func toplam(_ belge: PDFDocument) -> Double {
        puanlar(belge).reduce(0) { $0 + $1.deger }
    }

    public static func sayfaToplamlari(_ belge: PDFDocument) -> [Double] {
        var t = [Double](repeating: 0, count: belge.pageCount)
        for (s, d) in puanlar(belge) { t[s] += d }
        return t
    }
}

public struct PuanSatiri: Sendable, Hashable {
    public var dosya: String
    public var no: String
    public var ad: String
    public var toplam: Double
    public var sayfaPuanlari: [Double]
    /// Belgede hiç puan işareti var mı.
    public var puanVar: Bool
}

/// Notlandırılmış PDF'lerden puan tablosu.
public enum PuanTablosu {

    /// “123 Ayşe Yılmaz - Sınav.pdf” → (“123”, “Ayşe Yılmaz”)
    public static func adAyir(_ dosyaAdi: String) -> (no: String, ad: String) {
        var temel = (dosyaAdi as NSString).deletingPathExtension
        if let r = temel.range(of: " - ") { temel = String(temel[..<r.lowerBound]) }
        temel = temel.trimmingCharacters(in: .whitespaces)
        if let o = SinifAyristirici.satir(temel) { return (o.no, o.ad) }
        let parcalar = temel.split(separator: " ", maxSplits: 1).map(String.init)
        if parcalar.count == 2, parcalar[0].allSatisfy(\.isNumber) { return (parcalar[0], parcalar[1]) }
        return ("", temel)
    }

    public static func olustur(girdiler: [(ad: String, veri: Data)]) -> [PuanSatiri] {
        var satirlar: [PuanSatiri] = []
        for g in girdiler {
            guard let b = PDFDocument(data: g.veri) else { continue }
            let (no, ad) = adAyir(g.ad)
            let puanlar = PuanOkuyucu.puanlar(b)
            satirlar.append(PuanSatiri(dosya: g.ad, no: no, ad: ad, toplam: puanlar.reduce(0) { $0 + $1.deger },
                                       sayfaPuanlari: PuanOkuyucu.sayfaToplamlari(b), puanVar: !puanlar.isEmpty))
        }
        return satirlar.sorted {
            if let a = Int($0.no), let b = Int($1.no), a != b { return a < b }
            if $0.no != $1.no, !$0.no.isEmpty, !$1.no.isEmpty { return $0.no < $1.no }
            return TurkceMetin.kucuk($0.ad) < TurkceMetin.kucuk($1.ad)
        }
    }

    public struct Istatistik: Sendable, Hashable {
        public var ortalama: Double
        public var enYuksek: Double
        public var enDusuk: Double
        public var sayi: Int
    }

    public static func istatistik(_ satirlar: [PuanSatiri]) -> Istatistik? {
        let p = satirlar.filter(\.puanVar).map(\.toplam)
        guard !p.isEmpty else { return nil }
        return Istatistik(ortalama: p.reduce(0, +) / Double(p.count), enYuksek: p.max()!, enDusuk: p.min()!, sayi: p.count)
    }

    private static func basliklar(_ satirlar: [PuanSatiri], sayfaSutunlari: Bool) -> [String] {
        var b = ["No", "Ad Soyad", "Toplam"]
        if sayfaSutunlari {
            let n = satirlar.map { $0.sayfaPuanlari.count }.max() ?? 0
            b += (1...max(n, 1)).prefix(n).map { "Sayfa \($0)" }
        }
        b.append("Dosya")
        return b
    }

    private static func hucreler(_ s: PuanSatiri, sayfaSutunlari: Bool, sayfaSayisi: Int) -> [String] {
        var h = [s.no, s.ad, s.puanVar ? BicimYardimci.sayi(s.toplam) : ""]
        if sayfaSutunlari {
            for i in 0..<sayfaSayisi { h.append(i < s.sayfaPuanlari.count ? BicimYardimci.sayi(s.sayfaPuanlari[i]) : "") }
        }
        h.append(s.dosya)
        return h
    }

    /// CSV (Türkçe Excel için `;` ayırıcı ve UTF-8 BOM).
    public static func csv(_ satirlar: [PuanSatiri], sayfaSutunlari: Bool = false) -> Data {
        func kacis(_ s: String) -> String {
            s.contains(";") || s.contains("\"") || s.contains("\n") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        let n = satirlar.map { $0.sayfaPuanlari.count }.max() ?? 0
        var cikti = basliklar(satirlar, sayfaSutunlari: sayfaSutunlari).map(kacis).joined(separator: ";") + "\n"
        for s in satirlar {
            cikti += hucreler(s, sayfaSutunlari: sayfaSutunlari, sayfaSayisi: n).map(kacis).joined(separator: ";") + "\n"
        }
        if let i = istatistik(satirlar) {
            cikti += "\n;Ortalama;\(BicimYardimci.sayi(i.ortalama))\n;En yüksek;\(BicimYardimci.sayi(i.enYuksek))\n;En düşük;\(BicimYardimci.sayi(i.enDusuk))\n"
        }
        return Data([0xEF, 0xBB, 0xBF]) + Data(cikti.utf8)
    }

    public static func xlsx(_ satirlar: [PuanSatiri], sayfaSutunlari: Bool = false, baslik: String = "Puanlar") -> Data {
        let n = satirlar.map { $0.sayfaPuanlari.count }.max() ?? 0
        var tablo: [[XlsxHucre]] = [basliklar(satirlar, sayfaSutunlari: sayfaSutunlari).map { .kalin($0) }]
        for s in satirlar {
            var r: [XlsxHucre] = [s.no.isEmpty ? .bos : (Double(s.no).map { .sayi($0) } ?? .metin(s.no)), .metin(s.ad),
                                  s.puanVar ? .sayi(s.toplam) : .bos]
            if sayfaSutunlari {
                for i in 0..<n { r.append(i < s.sayfaPuanlari.count ? .sayi(s.sayfaPuanlari[i]) : .bos) }
            }
            r.append(.metin(s.dosya))
            tablo.append(r)
        }
        if let i = istatistik(satirlar) {
            tablo.append([])
            tablo.append([.bos, .kalin("Ortalama"), .sayi((i.ortalama * 100).rounded() / 100)])
            tablo.append([.bos, .kalin("En yüksek"), .sayi(i.enYuksek)])
            tablo.append([.bos, .kalin("En düşük"), .sayi(i.enDusuk)])
        }
        return XlsxYazici.yaz(sayfaAdi: baslik, satirlar: tablo, sutunGenislikleri: [8, 28, 10] + Array(repeating: 9, count: sayfaSutunlari ? n : 0) + [40])
    }
}
