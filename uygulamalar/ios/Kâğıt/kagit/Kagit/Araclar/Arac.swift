import KagitKit
import SwiftUI
import UniformTypeIdentifiers

/// Araç kategorileri (Araçlar sekmesindeki bölümler).
enum AracKategorisi: String, CaseIterable, Identifiable {
    case duzenle, sayfa, donustur, guvenlik, tarama, ogretmen, yapay
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .duzenle: "Düzenle ve İşaretle"
        case .sayfa: "Sayfa İşlemleri"
        case .donustur: "Dönüştür"
        case .guvenlik: "Güvenlik"
        case .tarama: "Tarama ve OCR"
        case .ogretmen: "Öğretmen"
        case .yapay: "Yapay Zekâ"
        }
    }
}

/// Aracın beklediği girdi.
enum GirdiTuru: Equatable {
    case yok
    case tekPDF
    case cokPDF          // en az iki (birleştirme, karşılaştırma)
    case birVeyaCokPDF   // toplu işleme uygun
    case gorseller
    case dosyalar([UTType])

    var pdfMi: Bool { self == .tekPDF || self == .cokPDF || self == .birVeyaCokPDF }
}

/// Araç ekranına verilen bağlam.
struct AracBaglami {
    var girdiler: [URL]
}

/// Bir araç: kimlik, ad, simge ve ekranı. Ekranlar çoğunlukla `AracSablonu` ile kurulur.
struct Arac: Identifiable {
    let id: String
    let ad: String
    let aciklama: String
    let simge: String
    let kategori: AracKategorisi
    let girdi: GirdiTuru
    /// Toplu işlemde kullanılabilir mi (her dosyaya aynı işlem).
    var topluUygun = false
    let ekran: @MainActor (AracBaglami) -> AnyView

    init(id: String, ad: String, aciklama: String, simge: String, kategori: AracKategorisi,
         girdi: GirdiTuru, topluUygun: Bool = false,
         @ViewBuilder ekran: @escaping @MainActor (AracBaglami) -> some View) {
        self.id = id
        self.ad = ad
        self.aciklama = aciklama
        self.simge = simge
        self.kategori = kategori
        self.girdi = girdi
        self.topluUygun = topluUygun
        self.ekran = { AnyView(ekran($0)) }
    }
}

/// Bütün araçların listesi. Her modül kendi listesini ayrı dosyada tanımlar
/// (`AracKatalogu+Sayfa.swift` vb.) ve burada birleştirilir.
enum AracKatalogu {
    static var hepsi: [Arac] {
        sayfaAraclari + donusturAraclari + guvenlikAraclari + taramaAraclari
            + duzenleAraclari + ogretmenAraclari + yapayAraclari
    }

    static func bul(_ id: String) -> Arac? { hepsi.first { $0.id == id } }

    static func kategoride(_ k: AracKategorisi) -> [Arac] { hepsi.filter { $0.kategori == k } }

    /// Tek bir PDF üzerinde çalışabilen araçlar ("Araçla aç" menüsü).
    static var pdfAraclari: [Arac] { hepsi.filter { $0.girdi == .tekPDF || $0.girdi == .birVeyaCokPDF } }

    static var topluAraclar: [Arac] { hepsi.filter(\.topluUygun) }
}
