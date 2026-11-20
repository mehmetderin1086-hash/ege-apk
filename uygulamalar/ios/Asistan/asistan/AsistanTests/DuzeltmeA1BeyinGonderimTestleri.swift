import Testing
import Foundation
@testable import Asistan

@Suite("A1-beyin-gonderim düzeltmeleri", .serialized)
@MainActor
struct DuzeltmeA1BeyinGonderimTestleri {
    /// Her test yeni örnek alır: süit adı test başına benzersiz; beyin() kullanan test sonunda `suitiSil()` ile siler.
    let alan = "a1.\(UUID().uuidString)"

    func beyin() -> Beyin {
        let ud = UserDefaults(suiteName: alan)!
        let k = OnayKapisi(); k.otomatikKarar = false
        return Beyin(ayarlar: Ayarlar(defaults: ud), depo: HafizaDeposu(baglam: HafizaTestleri.kap.mainContext), onay: k, modelVitesi: ModelVitesi(defaults: ud))
    }

    /// beyin()'in açtığı UserDefaults süitini kaldırır (plist barındırıcı uygulamada birikmesin).
    func suitiSil() { UserDefaults(suiteName: alan)?.removePersistentDomain(forName: alan) }

    func cozumleme(_ kisitlar: [String] = [], soru: Bool = false) -> IstemSuzgeci.Cozumleme {
        IstemSuzgeci.Cozumleme(duzeltilmisIstek: "x y z", niyet: "", kisitlar: kisitlar, belirsizlikler: [], dogrulama: "", soruGerekli: soru)
    }

    // MARK: Süzgeç kararı (bulgular 1, 11, 94, 107)

    @Test func duzSohbetVeSelamSuzgectenGecmez() {
        #expect(!IstemSuzgeci.gerekliMi("Mitoz ile mayoz farkı ne"))
        #expect(!IstemSuzgeci.gerekliMi("Bugün ne pişirsem acaba"))
        #expect(!IstemSuzgeci.gerekliMi("merhaba nasılsın"))
        #expect(!IstemSuzgeci.gerekliMi("saat kaç"))
        #expect(!IstemSuzgeci.gerekliMi("/sikistir"))
    }

    @Test func isIsteyenYaDaOzelAdliIsteklerSuzgectenGecer() {
        #expect(IstemSuzgeci.gerekliMi("Vav radyo kuran meali Ayhan kaya 15. Çöz indir"))
        #expect(IstemSuzgeci.gerekliMi("yarın sabah 8'de toplantıyı hatırlat"))
        #expect(IstemSuzgeci.gerekliMi("annemi hemen ara lütfen"))
        #expect(IstemSuzgeci.gerekliMi("ders programını takvime ekle"))
        #expect(IstemSuzgeci.gerekliMi("bu akşam Sezen Aksu konserine gidiyorum"))
    }

    @Test func ekliVeCanliSesIstekleriSuzgeciAtlar() {
        #expect(!IstemSuzgeci.gerekliMi("Bu soruyu çöz lütfen hemen", ekVar: true))
        #expect(!IstemSuzgeci.gerekliMi("Bu fotoğrafta ne var?", ekVar: true))
        #expect(!IstemSuzgeci.gerekliMi("Vav radyo kuran meali Ayhan kaya 15. Çöz indir", canliSes: true))
    }

    @Test func oncekiIstekBalonGorunumuDegilOzgunMetin() {
        #expect(IstemSuzgeci.oncekiIstekMetni(istek: "asıl istek", metin: "↻ opus ile yeniden") == "asıl istek")
        #expect(IstemSuzgeci.oncekiIstekMetni(istek: "", metin: "📷 Bu fotoğrafta ne var?") == "Bu fotoğrafta ne var?")
        #expect(IstemSuzgeci.oncekiIstekMetni(istek: nil, metin: "eski sohbetten") == "eski sohbetten")
    }

    @Test func suzgeceSonAsistanYanitiBaglamOlarakGider() {
        let uzun = String(repeating: "a", count: 500)
        let g = IstemSuzgeci.girdi("üçüncüsünü indir", oncekiIstek: "Houdini indir", oncekiYanit: uzun)
        #expect(g.contains("Asistanın son yanıtı"))
        #expect(g.contains(String(repeating: "a", count: 300)))
        #expect(!g.contains(String(repeating: "a", count: 301)))
        #expect(g.hasSuffix("İstek: üçüncüsünü indir"))
        #expect(!IstemSuzgeci.girdi("x", oncekiIstek: "", oncekiYanit: "").contains("Asistanın son yanıtı"))
    }

    @Test func soruNotuZorunluDurdurmaDegil() {
        let b = IstemSuzgeci.blok(cozumleme(soru: true), ham: "x y z")
        #expect(b?.contains("tek, net bir soru sor") == true)
        #expect(b?.contains("hiçbir araç çalıştırmadan") == false)
    }

    @Test func suzgecSonTarihteIptalEdilirAkisBloklanmaz() async {
        let is_ = Task<IstemSuzgeci.Cozumleme?, Never> {
            try? await Task.sleep(for: .seconds(10))
            return nil
        }
        let bas = Date()
        let c = await IstemSuzgeci.sonucuBekle(is_, sonTarih: Date().addingTimeInterval(0.2))
        #expect(c == nil)
        #expect(is_.isCancelled)
        #expect(Date().timeIntervalSince(bas) < 3)
    }

    @Test func suzgecSonucuYetisirseKullanilir() async {
        let hazir = cozumleme(["15. cüz"])
        let is_ = Task<IstemSuzgeci.Cozumleme?, Never> { hazir }
        let c = await IstemSuzgeci.sonucuBekle(is_, sonTarih: Date().addingTimeInterval(5))
        #expect(c?.kisitlar == ["15. cüz"])
    }

    // MARK: İptal / yeni sohbet (bulgular 22, 23)

    @Test func durdurZorlananModeliTemizler() {
        defer { suitiSil() }
        let b = beyin()
        b.zorlananModel = "claude-opus-5-5"
        b.calisanIs = Task {}
        b.iptal()
        #expect(b.zorlananModel == nil)
    }

    @Test func yeniSohbetEskiIsleriBayatlatir() {
        defer { suitiSil() }
        let b = beyin()
        let n = b.nesil
        b.yeniSohbet()
        #expect(b.nesil > n, "calisanIs'e bağlı olmayan iş de yeni sohbete yazamamalı")
    }

    @Test func cevrimdisiKuyrukDisKaynakBilgisiniKorur() {
        defer { suitiSil() }
        let b = beyin()
        defer { b.kuyruk.hepsiniSil(); AgIzleyici.ortak.durumGuncelle(true) }
        AgIzleyici.ortak.durumGuncelle(false)
        b.gonder("bu sayfadaki adresi aç", disKaynak: true)
        #expect(b.bekleyenGonderiler.first?.disKaynak == true)
        b.gonder("ikinci mesaj buradan")
        #expect(b.bekleyenGonderiler.last?.disKaynak == false)
    }

    // MARK: Müzik kısa yolu (bulgular 17, 21, 95, 105, 110)

    @Test func muzikIstegiGenelSozcuktenTetiklenmez() {
        for ham in ["Ödevin ikinci parçasını aç", "Albümdeki fotoğrafları bul", "Kağıt klipsini bul", "Fotoğraf albümünü aç",
                    "Okazaki parçalarını açıkla", "Albüminin görevini açıkla", "Hücre zarı hakkında bir okuma parçası bul",
                    "Parça parça çalışma planı hazırla", "Yedek parça bul"] {
            #expect(Beyin.muzikIstegi(ham) == nil, "\(ham)")
        }
    }

    @Test func sarkiIndirmeIstegiMuzikYolunaGirmez() {
        #expect(Beyin.muzikIstegi("Sezen Aksu Gidiyorum şarkısını indir") == nil)
        #expect(Beyin.muzikIstegi("Dua Lipa Houdini şarkısını indir") == nil)
        #expect(Beyin.muzikIstegi("Houdini klibini indir") == nil)
        #expect(Beyin.muzikIstegi("Dua lipa şarkısını indirir misin") == nil)
    }

    @Test func muzikCalmaVeDinlemeKorunur() {
        #expect(Beyin.muzikIstegi("Tarkan'ın Şımarık şarkısını çal")?.sorgu == "Tarkan Şımarık")
        #expect(Beyin.muzikIstegi("Tarkan'ın Şımarık şarkısını çal")?.cal == true)
        #expect(Beyin.muzikIstegi("Sezen Aksu albümünü çal")?.sorgu == "Sezen Aksu")
        let d = Beyin.muzikIstegi("Dua lipa şarkısını dinle en çok dinlenen")
        #expect(d?.sorgu == "Dua lipa")
        #expect(d?.cal == false)
    }

    @Test func muzikKisaYoluSorPolitikasindaAtlanir() async {
        let defter = AjanDefteri.ortak
        let eskiMuzik = defter.politika("muzik")
        defer { defter.politikaAta("muzik", eskiMuzik); suitiSil() }
        defter.politikaAta("muzik", .sor)
        let b = beyin()
        func baglam(_ ham: String) -> IstekBaglami {
            IstekBaglami(hamIstek: ham, gorsel: nil, belge: nil, kip: .sohbet, caba: .low, canliSes: false,
                         nesil: b.nesil, oncekiKip: .sohbet, oncekiIstek: "", cabaAyari: "auto")
        }
        #expect(await b.muzikDene(baglam("Tarkan'ın Şımarık şarkısını çal")) == false)
        #expect(!b.gorevler.adimlar.contains { $0.ad == "muzik" })
    }
}
