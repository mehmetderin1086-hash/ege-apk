import Testing
import Foundation
import SwiftData
@testable import _01

/// 50.000 kitaplık katalogda arama, filtre, sıralama ve bölümleme süre sınırları içinde kalmalı.
@MainActor
struct BuyukKatalogPerformansTestleri {
    private static let adet = 50_000

    private func buyukKatalog() throws -> (ModelContext, [CatalogBook]) {
        let ctx = ModelContext(try KitapVeritabani.makeContainer(inMemory: true))
        let kategoriler = KitapKategorileri.liste
        var kitaplar: [CatalogBook] = []
        kitaplar.reserveCapacity(Self.adet)
        for i in 0..<Self.adet {
            let kitap = CatalogBook(book: Book(
                title: "Kitap \(i) \(i % 7 == 0 ? "Şeker Portakalı" : "Macera")",
                author: "Yazar \(i % 900)",
                isbn: i % 3 == 0 ? String(format: "978975%07d", i) : nil,
                category: kategoriler[i % kategoriler.count],
                quantity: 1 + i % 3,
                shelf: "\(i % 12)",
                cabinet: ["A", "B", "C", "D"][i % 4],
                tags: i % 5 == 0 ? "macera, dostluk" : nil,
                readingLevel: OkumaDuzeyi.liste[i % OkumaDuzeyi.liste.count]
            ))
            ctx.insert(kitap)
            kitaplar.append(kitap)
        }
        try ctx.save()
        return (ctx, kitaplar)
    }

    private func sure(_ blok: () throws -> Void) rethrows -> Double {
        let bas = ContinuousClock.now
        try blok()
        let gecen = ContinuousClock.now - bas
        return Double(gecen.components.seconds) + Double(gecen.components.attoseconds) / 1e18
    }

    @Test(.tags(.performans), .timeLimit(.minutes(3))) func ellibinKitaptaAramaVeFiltre() throws {
        let (ctx, kitaplar) = try buyukKatalog()

        // Veritabanı araması (searchKey üzerinde SQL)
        var bulunan = 0
        let aramaSuresi = try sure {
            let kosul = try #require(KitapAramaKosulu.predicate(for: "seker portakali"))
            bulunan = try ctx.fetchCount(FetchDescriptor<CatalogBook>(predicate: kosul))
        }
        #expect(bulunan == Self.adet / 7 + 1)
        #expect(aramaSuresi < PerformansTabani.sinir(2.0), "Arama \(aramaSuresi) sn sürdü")

        // Bellekteki filtre + sıralama (Kitaplar sekmesinin her çizimde yaptığı iş)
        var filtre = KitapFiltresi()
        filtre.kategori = "Roman"
        filtre.etiket = "macera"
        var sonuc: [CatalogBook] = []
        let filtreSuresi = sure { sonuc = filtre.uygula(kitaplar, oduncSayilari: [:], siralama: .ad) }
        #expect(!sonuc.isEmpty)
        #expect(filtreSuresi < PerformansTabani.sinir(2.0), "Filtre \(filtreSuresi) sn sürdü")

        // Tüm katalogda yer sıralaması ve A–Z bölümleri
        let siralamaSuresi = sure { _ = KitapFiltresi().uygula(kitaplar, oduncSayilari: [:], siralama: .yer) }
        #expect(siralamaSuresi < PerformansTabani.sinir(4.0), "Yer sıralaması \(siralamaSuresi) sn sürdü")
        let bolumSuresi = sure { _ = AlfabeBolumleri.grupla(kitaplar) { $0.title } }
        #expect(bolumSuresi < PerformansTabani.sinir(2.0), "Bölümleme \(bolumSuresi) sn sürdü")
    }

    @Test(.tags(.performans), .timeLimit(.minutes(3))) func ellibinKitaptaRaporVeDenetim() throws {
        let (ctx, kitaplar) = try buyukKatalog()
        let raporSuresi = sure { _ = RaporMotoru.kategoriDagilimi(kitaplar) }
        #expect(raporSuresi < PerformansTabani.sinir(1.0), "Kategori dağılımı \(raporSuresi) sn sürdü")

        let csvSuresi = sure { _ = KitapCSV.olustur(Array(kitaplar.prefix(10_000)), sutunlar: KitapSutunu.varsayilan) }
        #expect(csvSuresi < PerformansTabani.sinir(3.0), "10 bin satır CSV \(csvSuresi) sn sürdü")

        var rapor = IntegrityReport()
        let denetimSuresi = sure { rapor = IntegrityCheck.run(context: ctx) }
        #expect(rapor.bookCount == Self.adet)
        #expect(denetimSuresi < PerformansTabani.sinir(5.0), "Bütünlük denetimi \(denetimSuresi) sn sürdü")

        // Mükerrer uyarısı düzenleyicide her yazışta çalışır: hızlı olmalı
        let mukerrerSuresi = sure {
            _ = MukerrerDenetimi.eslesmeler(title: "Kitap 700 Şeker Portakalı", isbn: "9789750000000", haric: nil, context: ctx)
        }
        #expect(mukerrerSuresi < PerformansTabani.sinir(1.5), "Mükerrer denetimi \(mukerrerSuresi) sn sürdü")
    }
}
