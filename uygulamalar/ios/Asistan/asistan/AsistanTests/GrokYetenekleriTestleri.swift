import Testing
import Foundation
@testable import Asistan

@MainActor @Suite("Uzman botlar ve beceriler")
struct GrokYetenekleriTestleri {
    @Test func uzmanSecimiKalirVeIstemeEklenir() throws {
        let alan = "uzman-test-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: alan)); defer { d.removePersistentDomain(forName: alan) }
        let takim = UzmanTakimi(defaults: d)
        let arastirmaci = try #require(takim.uzmanlar.first { $0.ad == "Araştırmacı" })
        takim.sec(arastirmaci.id)
        #expect(takim.baglam(istek: "Konuyu incele")?.contains("Kaynak araştırması") == true)
        #expect(UzmanTakimi(defaults: d).secilenler.contains(arastirmaci.id))
    }

    @Test func etiketSeciliEkibiGecersizKilar() throws {
        let d = try #require(UserDefaults(suiteName: "etiket-test-\(UUID().uuidString)"))
        let takim = UzmanTakimi(defaults: d)
        takim.sec(try #require(takim.uzmanlar.first { $0.ad == "Yazar" }).id)
        let baglam = try #require(takim.baglam(istek: "@Denetçi bunu kontrol et"))
        #expect(baglam.contains("Denetçi")); #expect(!baglam.contains("Yazar ("))
    }

    @Test func ozelUzmanVeBeceriKaliciOlur() throws {
        let alan = "ozel-test-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: alan)); defer { d.removePersistentDomain(forName: alan) }
        UzmanTakimi(defaults: d).ekle(ad: "Biyolog", unvan: "MEB", aciklama: "Kaynağı doğrula")
        BeceriKitapligi(defaults: d).ekle(ad: "Konu özeti", istem: "Özet çıkar")
        #expect(UzmanTakimi(defaults: d).uzmanlar.contains { $0.ad == "Biyolog" })
        #expect(BeceriKitapligi(defaults: d).beceriler.contains { $0.ad == "Konu özeti" })
    }
}
