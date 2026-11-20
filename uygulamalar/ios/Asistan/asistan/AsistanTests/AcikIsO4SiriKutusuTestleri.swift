import Foundation
import Testing
@testable import Asistan

/// O4: Siri / tetik devri için kalıcı kutu (`SiriSoruKutusu`). Geçici dosyalarla çalışır; ağ, izin ve gerçek model gerekmez.
@Suite("O4 Siri soru kutusu", .serialized)
@MainActor
struct AcikIsO4SiriKutusuTestleri {
    let taban = Date(timeIntervalSince1970: 1_800_000_000)

    func geciciDosya() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "o4-siri-\(UUID().uuidString).json")
    }

    func kayit(_ metin: String, yas: TimeInterval, surec: String = SiriSoruKutusu.surec) -> SiriSoruKaydi {
        SiriSoruKaydi(metin: metin, zaman: taban.addingTimeInterval(-yas), surec: surec)
    }

    // MARK: (a) ayıklama

    @Test func ayiklaOmruDolaniAtarYineleneniTeklerSonBesiTutar() {
        let eski = kayit("eski", yas: SiriSoruKutusu.omur + 1)
        let k = [eski, kayit("a", yas: 60), kayit("b", yas: 50), kayit("a", yas: 40)]
        let sonuc = SiriSoruKutusu.ayikla(k, simdi: taban)
        #expect(sonuc.map(\.metin) == ["b", "a"], "ömrü dolan atılır, yinelenenin en yenisi kalır")
        #expect(sonuc.last?.zaman == taban.addingTimeInterval(-40))

        let yedi = (1...7).map { kayit("s\($0)", yas: TimeInterval(100 - $0)) }
        #expect(SiriSoruKutusu.ayikla(yedi, simdi: taban).map(\.metin) == ["s3", "s4", "s5", "s6", "s7"])
    }

    // MARK: (b) süreçlere ayırma

    @Test func ayirBaskaSurectenTazeyiGonderirEskiyiDusurur() {
        let taze = kayit("taze", yas: 120, surec: "onceki")
        let eski = kayit("eski", yas: SiriSoruKutusu.omur + 60, surec: "onceki")
        let ayni = kayit("ayni", yas: 10, surec: "bu")
        let (g, d) = SiriSoruKutusu.ayir([taze, eski, ayni], simdi: taban, surec: "bu")
        #expect(g.map(\.metin) == ["taze"])
        #expect(d.map(\.metin) == ["eski"])
    }

    // MARK: (c) kalıcılık

    @Test func ekleVeCikarDiskeKalir() {
        let dosya = geciciDosya(); defer { try? FileManager.default.removeItem(at: dosya) }
        let ilk = SiriSoruKutusu(dosya: dosya)
        ilk.ekle("  Yarınki derslerim ne?  ")
        ilk.ekle("Yarınki derslerim ne?")   // yinelenen eklenmez
        #expect(ilk.kayitlar.map(\.metin) == ["Yarınki derslerim ne?"])
        #expect(SiriSoruKutusu(dosya: dosya).kayitlar.map(\.metin) == ["Yarınki derslerim ne?"])
        ilk.cikar(metin: "Yarınki derslerim ne?\n")
        #expect(ilk.kayitlar.isEmpty)
        #expect(SiriSoruKutusu(dosya: dosya).kayitlar.isEmpty)
    }

    @Test func bosMetinEklenmez() {
        let dosya = geciciDosya(); defer { try? FileManager.default.removeItem(at: dosya) }
        let k = SiriSoruKutusu(dosya: dosya)
        k.ekle("   \n")
        #expect(k.kayitlar.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dosya.path))
    }

    // MARK: (d) bozuk dosya

    @Test func bozukJsonBosListeVerirDosyaSilinmez() throws {
        let dosya = geciciDosya(); defer { try? FileManager.default.removeItem(at: dosya) }
        try Data("{bozuk".utf8).write(to: dosya)
        let k = SiriSoruKutusu(dosya: dosya)
        #expect(k.kayitlar.isEmpty)
        #expect(FileManager.default.fileExists(atPath: dosya.path))
    }

    // MARK: önceki süreçten kalanlar

    @Test func eskilerOncekiSurectenKalanlariAyirirVeDusenleriSiler() throws {
        let dosya = geciciDosya(); defer { try? FileManager.default.removeItem(at: dosya) }
        let simdi = Date()
        let kayitlar = [
            SiriSoruKaydi(metin: "taze soru", zaman: simdi.addingTimeInterval(-300), surec: "onceki-surec"),
            SiriSoruKaydi(metin: "bayat soru", zaman: simdi.addingTimeInterval(-(SiriSoruKutusu.omur + 300)), surec: "onceki-surec"),
            SiriSoruKaydi(metin: "bu sürecin sorusu", zaman: simdi.addingTimeInterval(-5), surec: SiriSoruKutusu.surec),
        ]
        try JSONEncoder().encode(kayitlar).write(to: dosya)
        let k = SiriSoruKutusu(dosya: dosya)
        let (g, d) = k.eskiler(simdi: simdi)
        #expect(g == ["taze soru"])
        #expect(d == ["bayat soru"])
        // Gönderilecek kayıt kabul edilene kadar kutuda kalır; düşen silinir; ikinci çağrı aynı kaydı yeniden vermez.
        #expect(Set(SiriSoruKutusu(dosya: dosya).kayitlar.map(\.metin)) == ["taze soru", "bu sürecin sorusu"])
        let ikinci = k.eskiler(simdi: simdi)
        #expect(ikinci.gonderilecek.isEmpty && ikinci.dusen.isEmpty)
    }

    @Test func dusmeNotuTekVeCokluIstek() {
        #expect(SiriSoruKutusu.dusmeNotu([]) == nil)
        #expect(SiriSoruKutusu.dusmeNotu(["Mitoz nedir?"])?.contains("“Mitoz nedir?”") == true)
        #expect(SiriSoruKutusu.dusmeNotu(["a", "b"])?.contains("2 isteğin") == true)
    }

    // MARK: (e) GorevKopru entegrasyonu

    @Test func teslimEdilenSoruKabulEdilinceKutudanCikar() {
        let dosya = geciciDosya(); defer { try? FileManager.default.removeItem(at: dosya) }
        let gecici = SiriSoruKutusu(dosya: dosya)
        let k = GorevKopru.ortak
        k.kutu = gecici
        defer { k.kutu = .ortak }
        let s = "o4-siri-\(UUID())"
        k.teslimEt(s)
        #expect(gecici.kayitlar.map(\.metin) == [s])
        #expect(SiriSoruKutusu(dosya: dosya).kayitlar.map(\.metin) == [s], "uygulama kapanırsa soru diskte kalır")
        k.kabul(s, nesil: 88_888)   // ilk yayından (300 ms) önce kabul: hiç yayın yapılmaz
        #expect(gecici.kayitlar.isEmpty)
        #expect(k.bekleyenSoru == nil)
    }

    @Test func cevrimdisiKuyrugaAlinanSoruKutudanCikar() {
        let dosya = geciciDosya(); defer { try? FileManager.default.removeItem(at: dosya) }
        let gecici = SiriSoruKutusu(dosya: dosya)
        let k = GorevKopru.ortak
        k.kutu = gecici
        defer { k.kutu = .ortak }
        let s = "o4-cevrimdisi-\(UUID())"
        k.teslimEt(s)
        #expect(gecici.kayitlar.count == 1)
        k.kuyrugaAlindi(s)   // kalıcı çevrimdışı kuyruk devraldı: açılışta ikinci kez gönderilmesin
        #expect(gecici.kayitlar.isEmpty)
        k.kabul(s, nesil: -1)   // yayın döngüsünü durdur
    }

    // MARK: (f) kabulü eşleşmeyen istekler kutuya girmez

    @Test func egikCizgiVeUzunMetinKutuyaGirmez() {
        let dosya = geciciDosya(); defer { try? FileManager.default.removeItem(at: dosya) }
        let gecici = SiriSoruKutusu(dosya: dosya)
        let k = GorevKopru.ortak
        k.kutu = gecici
        defer { k.kutu = .ortak }
        let uzun = String(repeating: "a", count: 4_001)
        k.teslimEt("/yeni")
        k.kabul("/yeni", nesil: -1)   // ilk yayından önce döngüyü durdur: test sunucusunda komut çalışmasın
        k.teslimEt(uzun)
        k.kabul(uzun, nesil: -1)
        #expect(gecici.kayitlar.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dosya.path))
    }

    // MARK: (g) kutuda olmayan metin diske yazmaz

    @Test func olmayanMetinCikarilincaDosyaDegismez() throws {
        let dosya = geciciDosya(); defer { try? FileManager.default.removeItem(at: dosya) }
        let k = SiriSoruKutusu(dosya: dosya)
        k.ekle("kalan soru")
        let once = try #require(try FileManager.default.attributesOfItem(atPath: dosya.path)[.modificationDate] as? Date)
        let veriOnce = try Data(contentsOf: dosya)
        k.cikar(metin: "kutuda olmayan")
        let sonra = try #require(try FileManager.default.attributesOfItem(atPath: dosya.path)[.modificationDate] as? Date)
        #expect(once == sonra)
        #expect(try Data(contentsOf: dosya) == veriOnce)
        #expect(k.kayitlar.map(\.metin) == ["kalan soru"])
    }

    // MARK: varsayılan kutu yalıtımı

    @Test func testteVarsayilanDosyaGecicidir() {
        #expect(CevrimdisiKuyruk.yalitilmis)
        #expect(SiriSoruKutusu.varsayilanDosya().path.hasPrefix(FileManager.default.temporaryDirectory.path))
    }
}
