import Foundation
import Testing
@testable import Asistan

@Suite("Otomatik düşünme çabası") @MainActor
struct DusunmeTestleri {
    @Test(arguments: ["Saat kaç?", "Beni duyuyor musun?", "YouTube'u aç", "Barış Manço Gülpembe şarkısını aç", "Python nedir?", "2 + 2 kaç?", "Merhaba"])
    func basitIstekler(_ metin: String) { #expect(DusunmeSecimi.sec(metin) == .low) }
    @Test(arguments: ["Bu teoremi kanıtla", "Kodda race condition bul ve düzelt", "Sunucu mimari tasarımını hazırla", "Adım adım çöz", "Bu veri için kapsamlı bir rapor yaz", "1. Araştır\n2. Karşılaştır\n3. Sonuç yaz"])
    func kisaAmaZorIstekler(_ metin: String) { #expect(DusunmeSecimi.sec(metin) == .high) }
    @Test func ortaVeEkler() {
        #expect(DusunmeSecimi.sec("Python ile toplama fonksiyonu yaz", kip: .kod) == .medium)
        #expect(DusunmeSecimi.sec("Bu iki telefonu karşılaştır", kip: .arastirma) == .medium)
        #expect(DusunmeSecimi.sec("Özetle", belgeBoyutu: 2000) == .medium)
        #expect(DusunmeSecimi.sec("Özetle", belgeBoyutu: 15000) == .high)
        #expect(DusunmeSecimi.sec("Ne var?", gorsel: true) == .high)   // fotoğraflı sorular Opus düzeyinde
    }
    @Test func devamVeYeniKonu() {
        #expect(DusunmeSecimi.sec("Devam et", onceki: .high) == .high)
        #expect(DusunmeSecimi.sec("Buna birim testlerini de ekle", onceki: .high) == .high)
        #expect(DusunmeSecimi.sec("Bunu kısalt", onceki: .high) == .low)
        #expect(DusunmeSecimi.sec("Saat kaç?", onceki: .high) == .low)
    }
    @Test func elleSecimVeBozukAyar() {
        #expect(DusunmeSecimi.sec("Kanıtla", ayar: "low") == .low)
        #expect(DusunmeSecimi.sec("Selam", ayar: "high") == .high)
        #expect(DusunmeSecimi.sec("Kanıtla", ayar: "bogus") == .high)
    }
    @Test func otomatikGecisBirKezYapilir() throws {
        let alan = "caba-test.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: alan))
        defer { d.removePersistentDomain(forName: alan) }
        d.set("low", forKey: Ayarlar.Anahtar.caba)
        let a = Ayarlar(defaults: d)
        #expect(a.caba == "auto")
        #expect(a.modelKimligi == "claude-opus-5-5")
        a.caba = "high"
        #expect(Ayarlar(defaults: d).caba == "high")
    }
}

@Suite("Zor soru yönlendirmesi") @MainActor struct ZorSoruTestleri {
    @Test func testSorusuKaliplariYuksek() {
        #expect(DusunmeSecimi.sec("Hangisi doğrudur? A) I B) II C) III D) IV E) V") == .high)
        #expect(DusunmeSecimi.sec("Bu soruyu çöz") == .high)
        #expect(DusunmeSecimi.sec("Doğru cevap hangisi") == .high)
    }
    @Test func gundelikSorularYukselmez() {
        #expect(DusunmeSecimi.sec("Gökyüzü neden mavi?") != .high)
        #expect(DusunmeSecimi.sec("Hangisi daha iyi, çay mı kahve mi?") != .high)
        #expect(DusunmeSecimi.sec("Merhaba") == .low)
    }
    @Test func fotografliZorSoruOpusIleBaslar() throws {
        let alan = "zor-test.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: alan)); defer { d.removePersistentDomain(forName: alan) }
        let v = ModelVitesi(defaults: d)
        let modeller = HizliModelSecimi.adaylar(.high) + HizliModelSecimi.adaylar(.low)
        let s = v.sira(caba: .high, kip: .sohbet, metin: "Bu fotoğrafta ne var?", gorsel: true, modeller: modeller, elle: "x", otomatik: true)
        #expect(s.first == "claude-fable-5-1")   // fotoğraflı zor soru: Fable, ardından Opus
        #expect(s.dropFirst().first == "claude-opus-5-5")
        let m = v.sira(caba: .high, kip: .sohbet, metin: "A) I B) II C) III D) IV soruyu çöz", gorsel: false, modeller: modeller, elle: "x", otomatik: true)
        #expect(m.first == "claude-opus-5-5")
    }
}
