import Foundation
import SwiftData

/// Barkod masasında okutulan kodun ne olduğunu çözer. Sıra: öğrenci kartı (OGR/OGRID) →
/// nüsha demirbaşı → ISBN → kurum içi barkod. Görünümden bağımsızdır; kurallar
/// `OkutCozumleyiciTestleri`nde sınanır.
enum OkutCozumleyici {
    /// Kitabın hangi koddan bulunduğu.
    enum Kaynak: Equatable { case demirbas, isbn, icBarkod }

    enum Sonuc {
        case ogrenci(Student)
        /// Tek katalog kaydı; demirbaş okutulduysa nüsha da gelir.
        case kitap(CatalogBook, nusha: BookCopy?, kaynak: Kaynak)
        case hata(String)
    }

    /// Bir barkod için katalogdan okunan en çok kayıt: tam tablo okunmaz.
    static let adayLimiti = 20

    static func coz(_ ham: String, context: ModelContext,
                    ogrenciKarti: @MainActor (String) throws -> Student = SchoolLibraryService.student(forCard:)) -> Sonuc {
        let kod = ham.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kod.isEmpty else { return .hata("Kod okunamadı; tekrar okutun.") }
        if kod.uppercased().hasPrefix("OGR") {
            do { return .ogrenci(try ogrenciKarti(kod)) } catch { return .hata(error.localizedDescription) }
        }
        do {
            let nushalar = try demirbasNushalari(kod, context: context)
            if nushalar.count > 1 { return .hata("“\(kod)” demirbaş kodu birden çok nüshada kayıtlı. Demirbaş defterinden düzeltin.") }
            if let nusha = nushalar.first {
                let kitapID = nusha.bookID
                guard let kitap = try context.fetch(FetchDescriptor<CatalogBook>(predicate: #Predicate { $0.id == kitapID })).first else {
                    return .hata("Bu nüshanın kitap kaydı katalogda bulunamadı.")
                }
                guard !kitap.isWithdrawn else { return .hata("“\(kitap.title)” koleksiyondan düşülmüş; ödünç ve iade yapılamaz.") }
                return .kitap(kitap, nusha: nusha, kaynak: .demirbas)
            }
            let isbn = ISBNFormatter.repair(kod)
            if ISBNFormatter.isValidISBN13(isbn), !InternalBarcode.isInternal(isbn) {
                return try tekKitap(barkod: isbn, kaynak: .isbn, context: context)
            }
            let ic = ISBNFormatter.normalize(kod)
            if InternalBarcode.isInternal(ic) {
                return try tekKitap(barkod: ic, kaynak: .icBarkod, context: context)
            }
            return .hata("Kod tanınmadı. Öğrenci kartı, demirbaş, ISBN ya da kitap barkodu okutun.")
        } catch { return .hata(error.localizedDescription) }
    }

    /// Kitabın nüsha sayısı: adet ile kayıtlı nüsha sayısının büyüğü (stok hesabıyla aynı).
    static func nushaSayisi(_ kitap: CatalogBook, context: ModelContext) -> Int {
        let id = kitap.id
        let kayitli = (try? context.fetchCount(FetchDescriptor<BookCopy>(predicate: #Predicate { $0.bookID == id }))) ?? 0
        return max(max(1, kitap.quantity ?? 1), kayitli)
    }

    /// Demirbaşı koda uyan nüshalar; barkod masası ve Kitaplar/Ana Sayfa araması aynı kuralı kullanır.
    /// Karşılaştırma `CatalogMatcher.normalize` iledir: büyük/küçük harf ve ayraç farkı sayılmaz ("d-12" = "D12").
    static func demirbasNushalari(_ kod: String, context: ModelContext) throws -> [BookCopy] {
        let anahtar = CatalogMatcher.normalize(kod)
        guard !anahtar.isEmpty else { return [] }
        let istek: FetchDescriptor<BookCopy>
        if let r = demirbasRakamlari(anahtar) {
            // Normalize eşit bir kod bu rakamların her birini aynen taşır: SQL onlarla daraltılır, tüm tablo okunmaz.
            let (a, b, c, d) = (r[0], r[1], r[2], r[3])
            istek = FetchDescriptor(predicate: #Predicate {
                $0.accessionCode.contains(a) && $0.accessionCode.contains(b)
                    && $0.accessionCode.contains(c) && $0.accessionCode.contains(d)
            })
        } else {
            istek = FetchDescriptor(predicate: #Predicate { !$0.accessionCode.isEmpty })
        }
        return try context.fetch(istek).filter { CatalogMatcher.normalize($0.accessionCode) == anahtar }
    }

    /// SQL daraltması için normalize anahtarın sondan en çok dört ayrı ASCII rakamı; eksik yerler ilk
    /// rakamla dolar (her zaman dört öğe). Rakamsız anahtarda `nil`.
    static func demirbasRakamlari(_ anahtar: String) -> [String]? {
        var rakamlar: [String] = []
        for karakter in anahtar.reversed() where karakter.isASCII && karakter.isNumber {
            let rakam = String(karakter)
            if !rakamlar.contains(rakam) { rakamlar.append(rakam) }
            if rakamlar.count == 4 { break }
        }
        guard let ilk = rakamlar.first else { return nil }
        return rakamlar + Array(repeating: ilk, count: 4 - rakamlar.count)
    }

    private static func tekKitap(barkod: String, kaynak: Kaynak, context: ModelContext) throws -> Sonuc {
        let adaylar = try isbnAdaylari(barkod, context: context)
        guard adaylar.count == 1, let kitap = adaylar.first else {
            return .hata(adaylar.isEmpty ? "Katalogda kitap veya nüsha bulunamadı." : "Birden fazla katalog kaydı eşleşti. Kitaplar’dan doğru kaydı açın.")
        }
        return .kitap(kitap, nusha: nil, kaynak: kaynak)
    }

    /// Barkoda (ISBN-13 ya da iç barkod) birebir uyan katalog kayıtları. Ödünç ve iade düşülmüş
    /// kitabı saymaz; Kitaplar'daki barkodla arama `dusulenlerDahil` ile onları da bulur.
    static func isbnAdaylari(_ barkod: String, dusulenlerDahil: Bool = false, context: ModelContext) throws -> [CatalogBook] {
        // ISBN-10 olarak saklanan kayıt da bulunsun: 978'li kodun ortadaki 9 hanesi iki yazımda da geçer.
        let arama = barkod.hasPrefix("978") ? String(barkod.dropFirst(3).prefix(9)) : barkod
        guard let kosul = KitapAramaKosulu.predicate(for: arama) else { return [] }
        var istek = FetchDescriptor<CatalogBook>(predicate: kosul)
        istek.fetchLimit = adayLimiti
        let eslesir = { (kitap: CatalogBook) in
            (dusulenlerDahil || !kitap.isWithdrawn) && ISBNFormatter.normalize(kitap.isbn ?? "") == barkod
        }
        let adaylar = try context.fetch(istek).filter(eslesir)
        guard adaylar.isEmpty else { return adaylar }
        // Eski arşivden ya da düzenlenmemiş kayıttan gelen ISBN tire veya boşlukla saklanmış olabilir
        // ("978-605-360-702-1", "0-8044-2957-X"): yalnız ayraçlı kayıtlar okunup normalize edilerek karşılaştırılır.
        let ayracli = #Predicate<CatalogBook> { ($0.isbn?.contains("-") ?? false) || ($0.isbn?.contains(" ") ?? false) }
        return try context.fetch(FetchDescriptor<CatalogBook>(predicate: ayracli)).filter(eslesir)
    }
}

/// Sürekli taramada aynı barkod art arda okunabilir. Aynı kod son kabulden sonraki 3 saniye
/// içinde yeniden gelirse yok sayılır; araya başka bir kod girerse yeniden kabul edilir.
struct TekrarSuzgeci {
    var sure: TimeInterval = 3
    private var sonKod: String?
    private var sonAn = Date.distantPast

    mutating func kabulEt(_ kod: String, an: Date = .now) -> Bool {
        let anahtar = kod.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if anahtar == sonKod, an.timeIntervalSince(sonAn) < sure { return false }
        sonKod = anahtar
        sonAn = an
        return true
    }
}
