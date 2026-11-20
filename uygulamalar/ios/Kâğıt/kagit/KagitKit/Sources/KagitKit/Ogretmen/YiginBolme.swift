import CoreGraphics
import Foundation
import PDFKit

/// Taranmış sınıf yığınını öğrenci başına parçalara bölme.
public enum YiginKipi: Sendable, Hashable {
    /// Her N sayfa bir öğrenci.
    case herNSayfa(Int)
    /// İlk sayfadaki ad algılanınca yeni öğrenci başlar.
    case adAlgila
    /// Boş sayfalar ayırıcıdır (boş sayfa çıktıya girmez).
    case bosSayfa
}

/// Bir öğrencinin sayfaları.
public struct YiginParcasi: Identifiable, Hashable, Sendable {
    public var id = UUID()
    /// 0 tabanlı sayfa indeksleri (ardışık).
    public var sayfalar: [Int]
    /// Atanan öğrencinin sınıf listesindeki indeksi.
    public var ogrenci: Int?
    /// Algılanan ham metin / güven (gözden geçirmede gösterilir).
    public var algilanan: String = ""
    public var guven: Double = 0

    public init(sayfalar: [Int], ogrenci: Int? = nil, algilanan: String = "", guven: Double = 0) {
        self.sayfalar = sayfalar
        self.ogrenci = ogrenci
        self.algilanan = algilanan
        self.guven = guven
    }
}

public enum YiginBolme {

    // MARK: Kipler

    public static func herN(sayfaSayisi: Int, n: Int) -> [YiginParcasi] {
        let n = max(n, 1)
        return stride(from: 0, to: sayfaSayisi, by: n).map { YiginParcasi(sayfalar: Array($0..<min($0 + n, sayfaSayisi))) }
    }

    /// Boş sayfaya göre: ardışık dolu sayfalar bir parça; boş sayfalar atılır.
    public static func bosSayfaIleBol(bosMu: [Bool]) -> [YiginParcasi] {
        var sonuc: [YiginParcasi] = []
        var simdiki: [Int] = []
        for (i, bos) in bosMu.enumerated() {
            if bos {
                if !simdiki.isEmpty { sonuc.append(YiginParcasi(sayfalar: simdiki)); simdiki = [] }
            } else {
                simdiki.append(i)
            }
        }
        if !simdiki.isEmpty { sonuc.append(YiginParcasi(sayfalar: simdiki)) }
        return sonuc
    }

    /// Sayfaların üst bölgelerinden okunan metinlere göre: bir öğrenci adı bulunan sayfa yeni parçanın başıdır.
    /// Aynı öğrenci art arda algılanırsa (her sayfada ad varsa) parça bölünmez.
    public static func adlaBol(ustMetinler: [String], ogrenciler: [Ogrenci], esik: Double = 0.78) -> [YiginParcasi] {
        let adaylar = ogrenciler.map(\.ad)
        var sonuc: [YiginParcasi] = []
        for (i, metin) in ustMetinler.enumerated() {
            let (idx, puan) = enIyiOgrenci(metin, ogrenciler: ogrenciler, adaylar: adaylar, esik: esik)
            if let idx {
                if let son = sonuc.last, son.ogrenci == idx {
                    sonuc[sonuc.count - 1].sayfalar.append(i)
                } else {
                    sonuc.append(YiginParcasi(sayfalar: [i], ogrenci: idx, algilanan: metin.prefix(80).description, guven: puan))
                }
            } else if sonuc.isEmpty {
                sonuc.append(YiginParcasi(sayfalar: [i]))
            } else {
                sonuc[sonuc.count - 1].sayfalar.append(i)
            }
        }
        return sonuc
    }

    /// Satır satır ve bütün olarak eşleştirir; numara da geçiyorsa güveni artırır.
    static func enIyiOgrenci(_ metin: String, ogrenciler: [Ogrenci], adaylar: [String], esik: Double) -> (Int?, Double) {
        var enIyi: (Int, Double)?
        let satirlar = metin.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        for parca in satirlar + [metin] {
            if let e = TurkceMetin.enIyiEslesme(parca, adaylar, esik: esik), e.puan > (enIyi?.1 ?? 0) {
                enIyi = (e.indeks, e.puan)
            }
        }
        // Numara belirteci: tek başına bile güçlü bir ipucudur
        let belirtecler = Set(TurkceMetin.anahtar(metin).split(separator: " ").map(String.init))
        for (i, o) in ogrenciler.enumerated() where !o.no.isEmpty && o.no.count >= 2 && belirtecler.contains(o.no) {
            if enIyi == nil { /* yalnız numara: ad da kısmen tutmalı */
                let kismen = TurkceMetin.benzerlik(metin, o.ad)
                let sozcukPuani = o.ad.split(separator: " ").map { s in
                    belirtecler.map { TurkceMetin.benzerlik($0, String(s)) }.max() ?? 0
                }.reduce(0, +) / Double(max(o.ad.split(separator: " ").count, 1))
                if max(kismen, sozcukPuani) >= 0.5 { enIyi = (i, 0.8) }
            } else if enIyi!.0 == i {
                enIyi = (i, min(1, enIyi!.1 + 0.05))
            }
        }
        if let e = enIyi { return (e.0, e.1) }
        return (nil, 0)
    }

    // MARK: Sayfa okuma

    /// Sayfanın üst `oran` kadarının metni: önce metin katmanı, yoksa OCR.
    public static func ustMetni(sayfa: PDFPage, oran: CGFloat = 0.25, ocr: Bool = true) async -> String {
        let sinir = sayfa.bounds(for: .cropBox)
        let ust = CGRect(x: sinir.minX, y: sinir.maxY - sinir.height * oran, width: sinir.width, height: sinir.height * oran)
        if let s = sayfa.selection(for: ust)?.string?.trimmingCharacters(in: .whitespacesAndNewlines), s.count >= 3 {
            return s
        }
        guard ocr, let tam = PDFCizim.goruntu(sayfa, dpi: 200) else { return "" }
        let kesit = CGRect(x: 0, y: 0, width: tam.width, height: Int(Double(tam.height) * Double(oran)))   // CGImage'da (0,0) sol üsttür
        guard let kirp = tam.cropping(to: kesit), let satirlar = try? await MetinTanima.tani(kirp) else { return "" }
        return MetinTanima.metin(satirlar)
    }

    /// Düşük çözünürlükte mürekkep oranına bakarak sayfanın boş olup olmadığına karar verir.
    public static func bosSayfaMi(_ sayfa: PDFPage, murekkepEsigi: Double = 0.004) -> Bool {
        guard let g = PDFCizim.goruntu(sayfa, dpi: 36) else { return false }
        let w = g.width, h = g.height
        var piksel = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &piksel, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(g, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Kenarlardan %4'lük pay dışarıda bırakılır (tarama gölgeleri)
        let px = Int(Double(w) * 0.04), py = Int(Double(h) * 0.04)
        var koyu = 0, toplam = 0
        for y in py..<(h - py) {
            for x in px..<(w - px) {
                let i = (y * w + x) * 4
                let parlaklik = (Int(piksel[i]) + Int(piksel[i + 1]) + Int(piksel[i + 2])) / 3
                if parlaklik < 160 { koyu += 1 }
                toplam += 1
            }
        }
        return toplam > 0 && Double(koyu) / Double(toplam) < murekkepEsigi
    }

    /// Belgeden kipe göre ön bölme önerisi üretir.
    public static func oner(veri: Data, kip: YiginKipi, ogrenciler: [Ogrenci], ilerleme: Ilerleme? = nil) async throws -> [YiginParcasi] {
        guard let belge = PDFDocument(data: veri), belge.pageCount > 0 else { throw KagitHata.bosGirdi }
        let n = belge.pageCount
        switch kip {
        case .herNSayfa(let k):
            return herN(sayfaSayisi: n, n: k)
        case .bosSayfa:
            var bos: [Bool] = []
            for i in 0..<n {
                try iptalDenetle()
                bos.append(belge.page(at: i).map { bosSayfaMi($0) } ?? false)
                ilerleme?(Double(i + 1) / Double(n))
            }
            return bosSayfaIleBol(bosMu: bos)
        case .adAlgila:
            var metinler: [String] = []
            for i in 0..<n {
                try iptalDenetle()
                if let s = belge.page(at: i) { metinler.append(await ustMetni(sayfa: s)) } else { metinler.append("") }
                ilerleme?(Double(i + 1) / Double(n))
            }
            return adlaBol(ustMetinler: metinler, ogrenciler: ogrenciler)
        }
    }

    // MARK: Düzenleme

    /// `i`. parçayı sonrakiyle birleştirir.
    public static func birlestir(_ parcalar: [YiginParcasi], _ i: Int) -> [YiginParcasi] {
        guard i >= 0, i + 1 < parcalar.count else { return parcalar }
        var p = parcalar
        p[i].sayfalar += p[i + 1].sayfalar
        p.remove(at: i + 1)
        return p
    }

    /// `i`. parçayı `konum` (parça içindeki sayfa sırası, ilk sayfa 0) öncesinden ikiye böler.
    public static func bol(_ parcalar: [YiginParcasi], _ i: Int, konum: Int) -> [YiginParcasi] {
        guard parcalar.indices.contains(i), konum > 0, konum < parcalar[i].sayfalar.count else { return parcalar }
        var p = parcalar
        let tum = p[i].sayfalar
        p[i].sayfalar = Array(tum[..<konum])
        p.insert(YiginParcasi(sayfalar: Array(tum[konum...])), at: i + 1)
        return p
    }

    // MARK: Çıktı

    /// “123 Ayşe Yılmaz - Sınav.pdf”
    public static func dosyaAdi(ogrenci: Ogrenci?, sinavAdi: String, sira: Int) -> String {
        let on = ogrenci.map { $0.tamAd } ?? "Atanmamış \(sira)"
        let ad = sinavAdi.trimmingCharacters(in: .whitespaces).isEmpty ? on : "\(on) - \(sinavAdi)"
        return TurkceMetin.dosyaAdi(ad)
    }

    /// Her parça için ayrı PDF verisi. Aynı ada denk gelenlere sıra eklenir.
    public static func ciktilar(veri: Data, parcalar: [YiginParcasi], ogrenciler: [Ogrenci],
                                sinavAdi: String) throws -> [(ad: String, veri: Data)] {
        guard let belge = PDFDocument(data: veri) else { throw KagitHata.acilamadi("yığın") }
        var sonuc: [(String, Data)] = []
        var kullanilan: [String: Int] = [:]
        var atanmamis = 0
        for p in parcalar where !p.sayfalar.isEmpty {
            let hedef = PDFDocument()
            for (k, i) in p.sayfalar.enumerated() {
                guard let s = belge.page(at: i) else { continue }
                hedef.insert(Belge.sayfaKopyasi(s), at: k)
            }
            guard hedef.pageCount > 0, let d = hedef.dataRepresentation() else { continue }
            let ogr = p.ogrenci.flatMap { ogrenciler.indices.contains($0) ? ogrenciler[$0] : nil }
            if ogr == nil { atanmamis += 1 }
            var ad = dosyaAdi(ogrenci: ogr, sinavAdi: sinavAdi, sira: atanmamis)
            let n = kullanilan[ad, default: 0] + 1
            kullanilan[ad] = n
            if n > 1 { ad += " (\(n))" }
            sonuc.append((ad, d))
        }
        guard !sonuc.isEmpty else { throw KagitHata.bosGirdi }
        return sonuc
    }
}
