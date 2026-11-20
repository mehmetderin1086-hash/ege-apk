import Testing
import Foundation
@testable import Asistan

/// P1.5: telefona kurulan derlemenin sürüm kimliği (Info.plist → SurumBilgisi → Ayarlar/`/durum`/tani.log).
@Suite("P1.5 sürüm bilgisi")
@MainActor
struct Gelistirme_P1_5_SurumBilgisiTestleri {
    let tam: [String: Any] = [
        "CFBundleShortVersionString": "0.21.0",
        "CFBundleVersion": "202610201530",
        "AsistanGitHash": "7f2747a",
        "AsistanDegisikDosya": "3",
        "AsistanDerlemeTuru": "Release",
    ]

    @Test func tamSozlukKisaVeUzun() {
        let s = SurumBilgisi.oku(tam, derleyiciTuru: "Release")
        #expect(s.kisa == "0.21.0 (202610201530)")
        #expect(s.uzun.contains("git 7f2747a"))
        #expect(s.uzun.contains("+3"))
        #expect(s.uzun.contains("Release"))
        #expect(s.uzun == "0.21.0 (202610201530) · git 7f2747a +3 · Release")
        #expect(s.degisik == 3)
    }

    @Test func degisikSifirkenArtiYazilmaz() {
        var s = tam; s["AsistanDegisikDosya"] = "0"
        let b = SurumBilgisi.oku(s, derleyiciTuru: "Release")
        #expect(!b.uzun.contains("+"))
        #expect(b.uzun == "0.21.0 (202610201530) · git 7f2747a · Release")
    }

    @Test func sayiOlarakGelenDegerlerOkunur() {
        var s = tam; s["AsistanDegisikDosya"] = 5; s["CFBundleVersion"] = NSNumber(value: 38)
        let b = SurumBilgisi.oku(s, derleyiciTuru: "Release")
        #expect(b.degisik == 5)
        #expect(b.derleme == "38")
    }

    @Test func bosSozlukBilinmiyorDoner() {
        let b = SurumBilgisi.oku([:], derleyiciTuru: "Debug")
        #expect(b.pazarlama == "bilinmiyor")
        #expect(b.derleme == "bilinmiyor")
        #expect(b.git == "bilinmiyor")
        #expect(b.degisik == 0)
        #expect(b.tur == "Debug")
        #expect(b.kisa == "bilinmiyor (bilinmiyor)")
        #expect(b.derlemeTarihi == nil)
    }

    @Test func derlemeTuruCaprazDenetlenir() {
        // Plist Release dese de ikili Debug derlenmişse ikisi birden görünür.
        let b = SurumBilgisi.oku(tam, derleyiciTuru: "Debug")
        #expect(b.tur == "Debug (plist: Release)")
        var s = tam; s.removeValue(forKey: "AsistanDerlemeTuru")
        #expect(SurumBilgisi.oku(s, derleyiciTuru: "Release").tur == "Release")
    }

    @Test func derlemeTarihiOn2HaneliNumaradan() throws {
        let b = SurumBilgisi.oku(tam, derleyiciTuru: "Release")
        let tarih = try #require(b.derlemeTarihi)
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute], from: tarih)
        #expect(c.year == 2026 && c.month == 10 && c.day == 20 && c.hour == 15 && c.minute == 30)
    }

    @Test func derlemeTarihiGecersizNumaradaNil() {
        for numara in ["38", "20261020153", "2026102015300", "202613201530", "202610321530", "20261020153a", "bilinmiyor"] {
            var s = tam; s["CFBundleVersion"] = numara
            #expect(SurumBilgisi.oku(s, derleyiciTuru: "Release").derlemeTarihi == nil, "\(numara)")
        }
    }

    @Test func simdikiCokmeden() {
        let s = SurumBilgisi.simdiki
        #expect(!s.kisa.isEmpty)
        #expect(s.uzun.hasPrefix(s.kisa))
    }

    @Test func slashDurumSurumSatiriniIcerir() {
        let alan = "p15.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: alan)?.removePersistentDomain(forName: alan) }
        let ud = UserDefaults(suiteName: alan)!
        let k = OnayKapisi(); k.otomatikKarar = false
        let beyin = Beyin(ayarlar: Ayarlar(defaults: ud), depo: HafizaDeposu(baglam: HafizaTestleri.kap.mainContext), onay: k, modelVitesi: ModelVitesi(defaults: ud))
        let metin = beyin.slashDurum()
        #expect(metin.hasPrefix("Sürüm: "))
        #expect(metin.contains("Sürüm: \(SurumBilgisi.simdiki.uzun)"))
    }
}
