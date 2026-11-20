import CoreGraphics
import Foundation
import PDFKit

/// Bir sayfadaki metin satırı. Koordinatlar sayfanın kırpma kutusuna göre (sol alt köken, dönüklük yok).
public struct MetinSatiri: Sendable, Hashable {
    public var metin: String
    public var kutu: CGRect
    /// İlk sözcüğün kutusu (soru numarası kutusu için).
    public var ilkSozcuk: CGRect

    public init(metin: String, kutu: CGRect, ilkSozcuk: CGRect? = nil) {
        self.metin = metin
        self.kutu = kutu
        self.ilkSozcuk = ilkSozcuk ?? kutu
    }
}

public struct SayfaSatirlari: Sendable {
    public var boyut: CGSize
    public var satirlar: [MetinSatiri]
    public init(boyut: CGSize, satirlar: [MetinSatiri]) {
        self.boyut = boyut
        self.satirlar = satirlar
    }
}

/// Sorunun sayfadaki bir dilimi (soru sayfa ya da sütun değiştirirse birden çok dilimi olur).
public struct SoruParcasi: Hashable, Sendable, Codable {
    public var sayfa: Int
    public var kutu: CGRect
    public init(sayfa: Int, kutu: CGRect) {
        self.sayfa = sayfa
        self.kutu = kutu
    }
}

public struct SoruBolgesi: Identifiable, Hashable, Sendable {
    public var id = UUID()
    /// Kaynaktaki soru numarası.
    public var numara: Int
    public var parcalar: [SoruParcasi]
    /// İlk dilimdeki numara kutusu (yeniden numaralamada üstü örtülür).
    public var numaraKutusu: CGRect?

    public init(numara: Int, parcalar: [SoruParcasi], numaraKutusu: CGRect? = nil) {
        self.numara = numara
        self.parcalar = parcalar
        self.numaraKutusu = numaraKutusu
    }

    public var toplamYukseklik: CGFloat { parcalar.reduce(0) { $0 + $1.kutu.height } }
}

public enum SoruAlgilama {

    /// “12.” / “3)” ile başlayan satır. “2.5 g” gibi ondalıkları saymaz.
    public static func soruNumarasi(_ satir: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: #"^\s*(\d{1,2})[.)](?=\s|$|\p{L})"#) else { return nil }
        let ns = satir as NSString
        guard let m = re.firstMatch(in: satir, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return Int(ns.substring(with: m.range(at: 1)))
    }

    // MARK: Satır çıkarma

    /// Metin katmanından satırlar. Sütunlar birbirine karışmasın diye sayfanın sol ve sağ yarısı ayrıca da taranır;
    /// iki yarıyı kapsayan birleşik satırlar atılır.
    public static func satirlar(sayfa: PDFPage) -> [MetinSatiri] {
        let sinir = sayfa.bounds(for: .cropBox)
        func al(_ alan: CGRect) -> [MetinSatiri] {
            guard let sel = sayfa.selection(for: alan) else { return [] }
            var sonuc: [MetinSatiri] = []
            for l in sel.selectionsByLine() {
                guard let t = l.string?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { continue }
                let r = l.bounds(for: sayfa).offsetBy(dx: -sinir.minX, dy: -sinir.minY)
                guard r.width > 0, r.height > 0 else { continue }
                let ilk = t.split(separator: " ", maxSplits: 1).first.map(String.init) ?? t
                let oran = CGFloat(ilk.count) / CGFloat(max(t.count, 1))
                sonuc.append(MetinSatiri(metin: t, kutu: r,
                                         ilkSozcuk: CGRect(x: r.minX, y: r.minY, width: r.width * oran, height: r.height)))
            }
            return sonuc
        }
        let orta = sinir.midX
        let sol = al(CGRect(x: sinir.minX, y: sinir.minY, width: sinir.width / 2, height: sinir.height))
        let sag = al(CGRect(x: orta, y: sinir.minY, width: sinir.width / 2, height: sinir.height))
        let tum = al(sinir)
        var sonuc = sol + sag
        for t in tum {
            // Daha küçük satırlarla zaten kapsanıyorsa (iki sütunun birleşimi ya da parçaları) at
            let kapsananlar = sonuc.filter { abs($0.kutu.midY - t.kutu.midY) < t.kutu.height * 0.5 && t.kutu.insetBy(dx: -2, dy: -2).contains($0.kutu) }
            if kapsananlar.isEmpty { sonuc.append(t) }
        }
        // Aynı satırın iki yarıdan da gelen kopyalarını ele
        var tekil: [MetinSatiri] = []
        for l in sonuc where !tekil.contains(where: { $0.metin == l.metin && $0.kutu.intersects(l.kutu) && abs($0.kutu.minX - l.kutu.minX) < 2 }) {
            tekil.append(l)
        }
        return tekil
    }

    /// Metin katmanı yoksa OCR ile satırlar.
    public static func satirlarOCR(sayfa: PDFPage) async -> [MetinSatiri] {
        let sinir = sayfa.bounds(for: .cropBox)
        guard let ocr = try? await MetinTanima.tani(sayfa: sayfa, dpi: 200) else { return [] }
        return ocr.map { s in
            let k = CGRect(x: s.kutu.minX * sinir.width, y: s.kutu.minY * sinir.height,
                           width: s.kutu.width * sinir.width, height: s.kutu.height * sinir.height)
            // İlk sözcük genişliği: karakter oranıyla kestirim
            let ilkMetin = s.metin.split(separator: " ", maxSplits: 1).first.map(String.init) ?? s.metin
            let oran = CGFloat(ilkMetin.count) / CGFloat(max(s.metin.count, 1))
            return MetinSatiri(metin: s.metin, kutu: k, ilkSozcuk: CGRect(x: k.minX, y: k.minY, width: k.width * oran, height: k.height))
        }
    }

    /// Belgenin bütün sayfalarının satırları (metin yoksa OCR).
    public static func sayfaSatirlari(veri: Data, ocr: Bool = true, ilerleme: Ilerleme? = nil) async throws -> [SayfaSatirlari] {
        guard let belge = PDFDocument(data: veri), belge.pageCount > 0 else { throw KagitHata.bosGirdi }
        var sonuc: [SayfaSatirlari] = []
        for i in 0..<belge.pageCount {
            try iptalDenetle()
            guard let s = belge.page(at: i) else { continue }
            var satirlar = Self.satirlar(sayfa: s)
            if satirlar.count < 3, ocr { satirlar = await satirlarOCR(sayfa: s) }
            sonuc.append(SayfaSatirlari(boyut: s.bounds(for: .cropBox).size, satirlar: satirlar))
            ilerleme?(Double(i + 1) / Double(belge.pageCount))
        }
        return sonuc
    }

    // MARK: Bölge belirleme

    /// Soru başlangıçlarından soru bölgelerini çıkarır (saf işlev; testlenebilir).
    public static func bolgeler(_ sayfalar: [SayfaSatirlari]) -> [SoruBolgesi] {
        // 1) Sütun sayısı: soru başlangıç adayları iki ayrı x kümesindeyse iki sütun
        var adayX: [(CGFloat, CGFloat)] = []   // (minX, sayfa genişliği)
        for s in sayfalar {
            for l in s.satirlar where soruNumarasi(l.metin) != nil { adayX.append((l.kutu.minX, s.boyut.width)) }
        }
        let iki: Bool = {
            guard let w = adayX.first?.1, let solEn = adayX.map(\.0).min() else { return false }
            let sagdakiler = adayX.filter { $0.0 > solEn + w * 0.35 && $0.0 < w * 0.8 }
            let soldakiler = adayX.filter { $0.0 <= solEn + w * 0.2 }
            return sagdakiler.count >= 2 && soldakiler.count >= 2
        }()

        var bolgeler: [SoruBolgesi] = []
        var beklenen = 1
        var acik: Int?      // açık (devam eden) bölgenin indeksi

        for (sayfaNo, sayfa) in sayfalar.enumerated() {
            let w = sayfa.boyut.width
            let sutunlar: [[MetinSatiri]]
            if iki {
                let sol = sayfa.satirlar.filter { $0.kutu.midX < w / 2 }
                let sag = sayfa.satirlar.filter { $0.kutu.midX >= w / 2 }
                sutunlar = [sol, sag]
            } else {
                sutunlar = [sayfa.satirlar]
            }
            for sutun in sutunlar {
                // Alt bilgi gibi satırlar bölge sınırını bozmasın
                let govde = sutun.filter { !altBilgiMi($0, sayfaYuksekligi: sayfa.boyut.height) }
                    .sorted { $0.kutu.maxY > $1.kutu.maxY }
                guard !govde.isEmpty else { continue }
                // Başlangıç satırları (sıralı numara)
                var baslangiclar: [Int] = []
                for (i, l) in govde.enumerated() {
                    if let n = soruNumarasi(l.metin), n == beklenen {
                        baslangiclar.append(i)
                        beklenen += 1
                    }
                }
                let sutunSol = govde.map(\.kutu.minX).min()! - 4
                let sutunSag = govde.map(\.kutu.maxX).max()! + 4
                func sinirOrta(_ ustSatir: Int, _ altSatir: Int) -> CGFloat {
                    (govde[ustSatir].kutu.minY + govde[altSatir].kutu.maxY) / 2
                }
                func parca(_ ustY: CGFloat, _ altY: CGFloat) -> SoruParcasi {
                    SoruParcasi(sayfa: sayfaNo, kutu: CGRect(x: max(sutunSol, 0), y: max(altY, 0),
                                                              width: min(sutunSag, w) - max(sutunSol, 0), height: max(ustY - altY, 1)))
                }
                let ilkBaslangic = baslangiclar.first ?? govde.count
                // Önceki sorunun devamı
                if ilkBaslangic > 0, let a = acik {
                    let ust = govde[0].kutu.maxY + 3
                    let alt = ilkBaslangic < govde.count ? sinirOrta(ilkBaslangic - 1, ilkBaslangic) : govde[govde.count - 1].kutu.minY - 3
                    bolgeler[a].parcalar.append(parca(ust, alt))
                }
                for (k, b) in baslangiclar.enumerated() {
                    let ust = b > 0 ? sinirOrta(b - 1, b) : govde[b].kutu.maxY + 3
                    let sonSatir = (k + 1 < baslangiclar.count ? baslangiclar[k + 1] : govde.count) - 1
                    let alt = k + 1 < baslangiclar.count ? sinirOrta(sonSatir, sonSatir + 1) : govde[sonSatir].kutu.minY - 3
                    let numara = soruNumarasi(govde[b].metin) ?? (bolgeler.count + 1)
                    var nk = govde[b].ilkSozcuk
                    nk = nk.insetBy(dx: -1, dy: -1)
                    bolgeler.append(SoruBolgesi(numara: numara, parcalar: [parca(ust, alt)], numaraKutusu: nk))
                    acik = bolgeler.count - 1
                }
            }
        }
        return bolgeler
    }

    /// Sayfa altındaki kısa numara/alt bilgi satırı mı.
    static func altBilgiMi(_ l: MetinSatiri, sayfaYuksekligi h: CGFloat) -> Bool {
        guard l.kutu.maxY < h * 0.07 else { return false }
        let t = l.metin.trimmingCharacters(in: .whitespaces)
        return t.count <= 12 || t.allSatisfy { $0.isNumber || $0 == "/" || $0 == "-" || $0 == " " }
    }

    /// Belgeyi okuyup bölgeleri çıkarır.
    public static func algila(veri: Data, ocr: Bool = true, ilerleme: Ilerleme? = nil) async throws -> [SoruBolgesi] {
        let s = try await sayfaSatirlari(veri: veri, ocr: ocr, ilerleme: ilerleme)
        let b = bolgeler(s)
        guard !b.isEmpty else { throw KagitHata.genel("Sorular algılanamadı. Soru numaraları “1.” ya da “1)” biçiminde olmalı.") }
        return b
    }

    // MARK: Düzenleme

    /// Bölgeyi sonrakiyle birleştirir (numarası ilkinde kalır).
    public static func birlestir(_ b: [SoruBolgesi], _ i: Int) -> [SoruBolgesi] {
        guard i >= 0, i + 1 < b.count else { return b }
        var s = b
        s[i].parcalar += s[i + 1].parcalar
        s.remove(at: i + 1)
        return s
    }

    /// Bölgenin ilk diliminin üst/alt kenarını `ust`/`alt` puan kaydırır (pozitif ust → yukarı büyür).
    public static func kenarAyarla(_ bolge: inout SoruBolgesi, dilim: Int = 0, ust: CGFloat = 0, alt: CGFloat = 0) {
        guard bolge.parcalar.indices.contains(dilim) else { return }
        var k = bolge.parcalar[dilim].kutu
        let yeniUst = k.maxY + ust
        let yeniAlt = k.minY - alt
        guard yeniUst - yeniAlt >= 12 else { return }
        k = CGRect(x: k.minX, y: yeniAlt, width: k.width, height: yeniUst - yeniAlt)
        bolge.parcalar[dilim].kutu = k
    }
}
