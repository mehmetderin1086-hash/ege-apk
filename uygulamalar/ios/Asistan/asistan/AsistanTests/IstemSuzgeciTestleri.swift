import Testing
import Foundation
@testable import Asistan

@Suite("İstem süzgeci")
struct IstemSuzgeciTestleri {
    @Test func kisaVeSabitMesajlarAtlanir() {
        #expect(!IstemSuzgeci.gerekliMi("selam"))
        #expect(!IstemSuzgeci.gerekliMi("saat kaç"))
        #expect(!IstemSuzgeci.gerekliMi("/yeni"))
        #expect(IstemSuzgeci.gerekliMi("Vav radyo kuran meali Ayhan kaya 15. Çöz indir"))
    }
    @Test func blokDuzeltmeVeKisitlariTasir() {
        let c = IstemSuzgeci.Cozumleme(duzeltilmisIstek: "Vav Radyo Kur'an meali Ayhan Kaya 15. cüz indir", niyet: "15. cüz mealini indirmek",
                                       kisitlar: ["Vav Radyo", "Ayhan Kaya", "15. cüz"], belirsizlikler: ["Çöz → cüz"], dogrulama: "adayda 15. cüz ve okuyucu adı geçmeli", soruGerekli: false)
        let b = IstemSuzgeci.blok(c, ham: "Vav radyo kuran meali Ayhan kaya 15. Çöz indir")
        #expect(b?.contains("Düzeltilmiş istek: Vav Radyo") == true)
        #expect(b?.contains("Zorunlu kısıtlar (hepsi sağlanmalı): Vav Radyo; Ayhan Kaya; 15. cüz") == true)
        #expect(b?.contains("İşlemden önce doğrula") == true)
        #expect(b?.contains("soru sor") == false)
    }
    @Test func bosCozumlemeBlokUretmez() {
        let c = IstemSuzgeci.Cozumleme(duzeltilmisIstek: "Yarın hava nasıl", niyet: "", kisitlar: [], belirsizlikler: [], dogrulama: "", soruGerekli: false)
        #expect(IstemSuzgeci.blok(c, ham: "yarın hava nasıl") == nil)
    }
    @Test func soruGerekliyseUyarir() {
        let c = IstemSuzgeci.Cozumleme(duzeltilmisIstek: "x y z", niyet: "", kisitlar: [], belirsizlikler: [], dogrulama: "", soruGerekli: true)
        #expect(IstemSuzgeci.blok(c, ham: "x y z")?.contains("tek, net bir soru sor") == true)
    }
}

@Suite("İndirme eşleşmesi")
struct IndirmeEslesmeTestleri {
    let istek = "Vav Radyo Kur'an meali Ayhan Kaya 15. cüz"
    @Test func yanlisCuzDusukPuan() {
        let p = IndirmeEslesme.puan(istek: istek, baslik: "Kur'an-ı Kerim Meali 1. Cüz", kanal: "Mazlum Kiper")
        #expect(p <= 0.3)
    }
    @Test func okuyucuEksikseEsigiGecmez() {
        let p = IndirmeEslesme.puan(istek: istek, baslik: "Kur'an-ı Kerim Meali 15. Cüz - Köksal Engür", kanal: "Vav Radyo")
        #expect(p > 0.5 && p < IndirmeEslesme.esik)
    }
    @Test func tamUyumEsigiGecer() {
        let p = IndirmeEslesme.puan(istek: istek, baslik: "Kur'an-ı Kerim Meali 15. Cüz - Ayhan Kaya", kanal: "Vav Radyo")
        #expect(p >= IndirmeEslesme.esik)
    }
    @Test func dolguSozcuklerSayilmaz() {
        let p = IndirmeEslesme.puan(istek: "Dua Lipa Houdini official video", baslik: "Dua Lipa - Houdini (Official Music Video)", kanal: "Dua Lipa")
        #expect(p == 1)
    }
    @Test func secimEnIyiAdayiAlirEsikAltindaBosDoner() {
        let a = IndirmeEslesme.Aday(baslik: "1. Cüz", kanal: "Mazlum Kiper", sure: 100, url: "https://youtube.com/a", puan: 0.3)
        let b = IndirmeEslesme.Aday(baslik: "15. Cüz Ayhan Kaya", kanal: "Vav Radyo", sure: 100, url: "https://youtube.com/b", puan: 0.9)
        let (sec, sirali) = IndirmeEslesme.sec(istek: istek, adaylar: [a, b])
        #expect(sec?.url == b.url && sirali.first?.url == b.url)
        #expect(IndirmeEslesme.sec(istek: istek, adaylar: [a]).secilen == nil)
    }
    @Test func sureMetni() {
        #expect(IndirmeEslesme.sureMetni(65) == "1:05")
        #expect(IndirmeEslesme.sureMetni(3725) == "1:02:05")
        #expect(IndirmeEslesme.sureMetni(nil) == "")
    }
}

/// Gerçek hızlı modelle süzgeç: dikte hatası ("Çöz" → cüz) düzeltilir, kısıtlar çıkar. ASISTAN_CANLI=1 ile.
@Suite("Canlı istem süzgeci", .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1"))
@MainActor
struct CanliIstemSuzgeciTestleri {
    @Test(.timeLimit(.minutes(2)))
    func dikteHatasiVeKisitlar() async throws {
        let ud = UserDefaults(suiteName: "suzgec.\(UUID().uuidString)")!
        let ayarlar = Ayarlar(defaults: ud); ayarlar.caba = "low"; ayarlar.webArama = false
        let depo = HafizaDeposu(baglam: HafizaTestleri.kap.mainContext)
        let beyin = Beyin(ayarlar: ayarlar, depo: depo, onay: OnayKapisi())
        try #require(beyin.hazir, "Secrets.xcconfig dolu olmalı")
        let model = try #require(beyin.yapilandirilmisModel(timeout: 20))
        print("SÜZGEÇ model: \(model.executorConfiguration.model.id) taban: \(model.executorConfiguration.baseURL.absoluteString) telefonHazır: \(TelefonProxy.ortak.hazir)")
        let t0 = Date()
        let c = try #require(await beyin.suzgec.coz("Vav radyo kuran meali Ayhan kaya 15. Çöz indir", oncekiIstek: "", model: model, saniye: 20))
        let sure = Date().timeIntervalSince(t0)
        print("SÜZGEÇ \(Int(sure * 1000)) ms: \(c.duzeltilmisIstek) | kısıtlar: \(c.kisitlar) | belirsiz: \(c.belirsizlikler) | doğrula: \(c.dogrulama) | soru: \(c.soruGerekli)")
        #expect(c.duzeltilmisIstek.lowercased().contains("cüz"))
        let k = c.kisitlar.joined(separator: " ").lowercased()
        #expect(k.contains("15") && k.contains("ayhan") && k.contains("vav"), "kısıtlar: \(c.kisitlar)")
        #expect(IstemSuzgeci.blok(c, ham: "Vav radyo kuran meali Ayhan kaya 15. Çöz indir") != nil)
    }
}

@Suite("Vekil tabanı")
struct VekilTabaniTestleri {
    @Test func sondakiV1VeEgikCizgiSoyulur() {
        #expect(Gizli.vekilKoku("https://a.b/dersdas/claude/v1")?.absoluteString == "https://a.b/dersdas/claude")
        #expect(Gizli.vekilKoku("https://a.b/dersdas/claude/v1/")?.absoluteString == "https://a.b/dersdas/claude")
        #expect(Gizli.vekilKoku("https://a.b/dersdas/claude")?.absoluteString == "https://a.b/dersdas/claude")
    }
    @Test func kokAdresteDonguBiter() {
        // Eski URL bileşen döngüsü bu girdilerde bitmeyebiliyordu.
        #expect(Gizli.vekilKoku("https://a.b/")?.absoluteString == "https://a.b")
        #expect(Gizli.vekilKoku("https://a.b/v1")?.absoluteString == "https://a.b")
        #expect(Gizli.vekilKoku("https://a.b")?.absoluteString == "https://a.b")
        #expect(Gizli.vekilKoku("https://a.b/v1/v1//")?.absoluteString == "https://a.b")
        #expect(Gizli.vekilKoku("") == nil)
        #expect(Gizli.vekilKoku("/v1") == nil)
    }
}

@Suite("Model zinciri yapılandırma hatası")
struct ModelZinciriYapilandirmaTestleri {
    @Test func yapilandirmaHatalariUzunAskiAlir() {
        struct H: Error, CustomStringConvertible { let description: String }
        for m in ["'gemini-pro-account' sağlayıcısı 'tools' yeteneğini desteklemiyor",
                  "You have no credits remaining. Add credits",
                  "sunucu hatası: 'openai-api' için kullanılabilir hesap yok",
                  "native reasoning options require the matching provider"] {
            #expect(ModelZinciri.yapilandirmaHatasi(m.lowercased()), "\(m)")
            let k = ModelZinciri.dusmeKarari(H(description: m))
            #expect(k.gec && k.askiSn == 3600)
        }
        #expect(!ModelZinciri.yapilandirmaHatasi("http 500 internal server error"))
    }
}
