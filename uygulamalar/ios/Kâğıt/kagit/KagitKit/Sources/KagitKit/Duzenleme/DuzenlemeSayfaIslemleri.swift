import CoreGraphics
import Foundation
import PDFKit

/// Sayfa düzenleyicinin mantığı: sıralama, döndürme, çoğaltma, çıkarma, boş sayfa.
/// Hepsi ana iş parçacığında `PDFDocument` üzerinde çalışır; geri alma çağıran tarafta kurulur.
public enum BelgeSayfaIslemleri {

    /// `tasinacak` sayfaları (kendi sıralarıyla) `hedef` konumundan önceye taşıyan yeni sıra.
    /// `hedef`, taşıma öncesi dizideki konumdur (0...sayi). Sonuç: yeni sıradaki eski indeksler.
    public static func siralama(sayi: Int, tasinacak: [Int], hedef: Int) -> [Int] {
        let tasinan = tasinacak.filter { $0 >= 0 && $0 < sayi }
        let tasinanKume = Set(tasinan)
        let kalanlar = (0..<sayi).filter { !tasinanKume.contains($0) }
        // hedefin önündeki, taşınmayan sayfa sayısı = kalanlar içindeki ekleme konumu
        let ekleme = (0..<min(max(hedef, 0), sayi)).filter { !tasinanKume.contains($0) }.count
        var sonuc = kalanlar
        sonuc.insert(contentsOf: tasinan.sorted(), at: min(ekleme, sonuc.count))
        return sonuc
    }

    /// Ters permütasyon: `sira[yeni] = eski` ise sonuç `[eski] = yeni`.
    public static func tersSira(_ sira: [Int]) -> [Int] {
        var ters = [Int](repeating: 0, count: sira.count)
        for (yeni, eski) in sira.enumerated() { ters[eski] = yeni }
        return ters
    }

    /// Belgenin sayfalarını `yeniSira` (yeni sıradaki eski indeksler) düzenine sokar.
    public static func sirala(_ belge: PDFDocument, yeniSira: [Int]) {
        let sayi = belge.pageCount
        guard yeniSira.count == sayi, Set(yeniSira) == Set(0..<sayi) else { return }
        let sayfalar = (0..<sayi).compactMap { belge.page(at: $0) }
        guard sayfalar.count == sayi else { return }
        for i in stride(from: sayi - 1, through: 0, by: -1) { belge.removePage(at: i) }
        for (yeni, eski) in yeniSira.enumerated() { belge.insert(sayfalar[eski], at: yeni) }
    }

    public static func dondur(_ belge: PDFDocument, indeksler: [Int], derece: Int) {
        for i in indeksler {
            guard let s = belge.page(at: i) else { continue }
            s.rotation = ((s.rotation + derece) % 360 + 360) % 360
        }
    }

    /// Verilen indekslerdeki sayfaları siler; (indeks, sayfa) çiftlerini geri almak için döndürür.
    @discardableResult
    public static func sil(_ belge: PDFDocument, indeksler: [Int]) -> [(indeks: Int, sayfa: PDFPage)] {
        var silinen: [(Int, PDFPage)] = []
        for i in Set(indeksler).sorted(by: >) {
            guard let s = belge.page(at: i) else { continue }
            belge.removePage(at: i)
            silinen.append((i, s))
        }
        return silinen.reversed().map { (indeks: $0.0, sayfa: $0.1) }
    }

    /// Silinen sayfaları eski yerlerine koyar (`sil` çıktısıyla).
    public static func geriKoy(_ belge: PDFDocument, _ silinen: [(indeks: Int, sayfa: PDFPage)]) {
        for (i, s) in silinen.sorted(by: { $0.indeks < $1.indeks }) { belge.insert(s, at: min(i, belge.pageCount)) }
    }

    /// Sayfanın kopyasını hemen ardına ekler; eklenen sayfaları döndürür.
    @discardableResult
    public static func cogalt(_ belge: PDFDocument, indeksler: [Int]) -> [PDFPage] {
        var eklenen: [PDFPage] = []
        var kayma = 0
        for i in Set(indeksler).sorted() {
            guard let s = belge.page(at: i + kayma), let kopya = s.copy() as? PDFPage else { continue }
            belge.insert(kopya, at: i + kayma + 1)
            eklenen.append(kopya)
            kayma += 1
        }
        return eklenen
    }

    /// `komsu` sayfanın boyutunda (yoksa A4) boş sayfa.
    public static func bosSayfa(boyut komsu: PDFPage?) -> PDFPage {
        let kutu = komsu?.bounds(for: .mediaBox) ?? CGRect(origin: .zero, size: PDFCizim.Boyut.a4.boyut)
        let s = PDFPage()
        s.setBounds(CGRect(origin: .zero, size: kutu.size), for: .mediaBox)
        s.setBounds(CGRect(origin: .zero, size: kutu.size), for: .cropBox)
        return s
    }

    /// Seçili sayfaları yeni bir PDF verisi olarak çıkarır.
    public static func cikar(_ belge: PDFDocument, indeksler: [Int]) throws -> Data {
        let yeni = PDFDocument()
        for i in Set(indeksler).sorted() {
            guard let s = belge.page(at: i), let kopya = s.copy() as? PDFPage else { continue }
            yeni.insert(kopya, at: yeni.pageCount)
        }
        guard yeni.pageCount > 0 else { throw KagitHata.bosGirdi }
        guard let veri = yeni.dataRepresentation(), !veri.isEmpty else { throw KagitHata.kaydedilemedi("çıkarılan sayfalar") }
        return veri
    }
}
