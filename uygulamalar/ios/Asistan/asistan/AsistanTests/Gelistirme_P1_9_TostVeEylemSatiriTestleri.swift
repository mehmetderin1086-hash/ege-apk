import Foundation
import Testing
import SwiftData
@testable import Asistan

/// P1.9: son yanıtın eylem satırı, kısa bildirim (tost), sohbet bazında taslak ve model zorlamasız yeniden üretim.
@Suite("P1.9 tost ve eylem satırı") @MainActor
struct Gelistirme_P1_9_TostVeEylemSatiriTestleri {

    // MARK: Tost

    @Test func tostSuresiIkiIleAltiArasinda() {
        #expect(TostDefteri.sure("") == 2)
        #expect(TostDefteri.sure("Kopyalandı") == 2 + 10.0 / 40)
        #expect(TostDefteri.sure(String(repeating: "a", count: 40)) == 3)
        #expect(TostDefteri.sure(String(repeating: "a", count: 1_000)) == 6)
        for n in [0, 1, 39, 80, 159, 160, 161, 5_000] {
            let s = TostDefteri.sure(String(repeating: "ş", count: n))
            #expect(s >= 2 && s <= 6, "n=\(n) süre \(s)")
        }
    }

    @Test func ikinciTostIlkininYeriniAlir() {
        let d = TostDefteri()
        d.goster("Kopyalandı", simge: "doc.on.doc")
        let ilk = d.gorunen
        #expect(ilk?.metin == "Kopyalandı")
        #expect(ilk?.simge == "doc.on.doc")
        d.goster("Beceri kaydedildi", simge: "sparkles")
        #expect(d.gorunen?.metin == "Beceri kaydedildi")
        #expect(d.gorunen?.simge == "sparkles")
        #expect(d.gorunen?.id != ilk?.id)
        d.kapat()
        #expect(d.gorunen == nil)
    }

    @Test func bosTostGosterilmezVarsayilanSimgeKullanilir() {
        let d = TostDefteri()
        d.goster("   \n")
        #expect(d.gorunen == nil)
        d.goster("  Tamam  ")
        #expect(d.gorunen?.metin == "Tamam")
        #expect(d.gorunen?.simge == "checkmark.circle")
        d.kapat()
    }

    /// Eski tostun zamanlayıcısı yenisini silmez; yeni tost kendi süresi dolunca kapanır.
    @Test(.timeLimit(.minutes(1))) func eskiTostunKapanisiYenisiniSilmez() async throws {
        let d = TostDefteri()
        d.goster("a")                                           // ~2 sn
        try await Task.sleep(for: .milliseconds(1_200))
        let uzun = String(repeating: "b", count: 240)           // 6 sn
        d.goster(uzun)
        try await Task.sleep(for: .milliseconds(1_500))         // ilk tostun süresi geçti
        #expect(d.gorunen?.metin == uzun, "ilk tostun gecikmeli kapanışı ikinciyi silmemeli")
        d.kapat()
        #expect(d.gorunen == nil)
    }

    @Test(.timeLimit(.minutes(1))) func tostSuresiDoluncaKapanir() async throws {
        let d = TostDefteri()
        d.goster("Kopyalandı")
        #expect(d.gorunen != nil)
        let son = ContinuousClock.now + .seconds(10)
        while d.gorunen != nil, ContinuousClock.now < son { try await Task.sleep(for: .milliseconds(50)) }
        #expect(d.gorunen == nil)
    }

    // MARK: Sohbet bazında taslak

    @Test func taslakSohbettenCikincaSaklanirDonunceGelir() {
        let x = UUID()
        // X'ten yeni sohbete (nil): X'in metni saklanır, yeni sohbetin taslağı (yok) boş gelir.
        let a = SohbetEkrani.taslakGecisi([:], eski: x, yeni: nil, metin: "yarım kalan soru")
        #expect(a.taslaklar[x] == "yarım kalan soru")
        #expect(a.metin == "")
        // Yeni sohbette yazıp X'e dönünce: yeni sohbetin taslağı saklanır, X'inki geri gelir ve sözlükten düşer.
        let b = SohbetEkrani.taslakGecisi(a.taslaklar, eski: nil, yeni: x, metin: "yeni sohbet taslağı")
        #expect(b.metin == "yarım kalan soru")
        #expect(b.taslaklar[nil] == "yeni sohbet taslağı")
        #expect(b.taslaklar[x] == nil)
        // Yeniden yeni sohbete: onun taslağı geri gelir.
        let c = SohbetEkrani.taslakGecisi(b.taslaklar, eski: x, yeni: nil, metin: "")
        #expect(c.metin == "yeni sohbet taslağı")
        #expect(c.taslaklar[x] == nil, "boş metin anahtarı siler")
    }

    @Test func bosMetinAnahtariSiler() {
        let x = UUID(), y = UUID()
        let r = SohbetEkrani.taslakGecisi([x: "eski", y: "öbürü"], eski: x, yeni: y, metin: "  \n ")
        #expect(r.taslaklar[x] == nil)
        #expect(r.metin == "öbürü")
        #expect(r.taslaklar[y] == nil)
    }

    /// Yeni sohbet ilk mesajla (ya da indirme iletisiyle) kayda dönüşür: aynı sohbettir, yazılan metin kutuda kalır.
    @Test func yeniSohbetKaydaDonusuncMetinKalir() {
        let y = UUID()
        let r = SohbetEkrani.taslakGecisi([nil: "eski yeni-sohbet taslağı"], eski: nil, yeni: y, metin: "şu an yazılan")
        #expect(r.metin == "şu an yazılan")
        #expect(r.taslaklar[nil] == nil)
        #expect(r.taslaklar[y] == nil)
    }

    @Test func ayniSohbetteDegisiklikYok() {
        let x = UUID()
        let r = SohbetEkrani.taslakGecisi([x: "a"], eski: x, yeni: x, metin: "b")
        #expect(r.metin == "b")
        #expect(r.taslaklar == [x: "a"])
    }

    // MARK: Tema alanı (geriye uyum)

    private func alaniSil(_ veri: Data, yol: [String]) throws -> Data {
        var kok = try #require(try JSONSerialization.jsonObject(with: veri) as? [String: Any])
        if yol.isEmpty {
            kok.removeValue(forKey: "eylemSatiriAcik")
        } else {
            var ic = try #require(kok[yol[0]] as? [String: Any])
            ic.removeValue(forKey: "eylemSatiriAcik")
            kok[yol[0]] = ic
        }
        return try JSONSerialization.data(withJSONObject: kok)
    }

    @Test func eskiTemaJSONuCozulurEylemSatiriAcik() throws {
        var t = SohbetTemasi.claude
        t.eylemSatiri = false   // alan yazılsın; sonra eski profil gibi silinir
        let eski = try alaniSil(JSONEncoder().encode(t), yol: [])
        #expect(String(decoding: eski, as: UTF8.self).contains("eylemSatiriAcik") == false)
        let cozulen = try JSONDecoder().decode(SohbetTemasi.self, from: eski)
        #expect(cozulen.eylemSatiriAcik == nil)
        #expect(cozulen.eylemSatiri == true)
        #expect(cozulen.gecerli())
        #expect(SohbetTemasi.claude.eylemSatiri, "hazır temalarda varsayılan açık")
    }

    @Test func eylemSatiriKapaliGidipGelir() throws {
        var t = SohbetTemasi.telegram
        t.eylemSatiri = false
        let c = try JSONDecoder().decode(SohbetTemasi.self, from: JSONEncoder().encode(t))
        #expect(c.eylemSatiri == false)
        #expect(c == t)
    }

    @Test func eskiGorunumProfiliGecerliKalir() throws {
        var p = GorunumTercihleri()
        var t = SohbetTemasi.gece
        t.eylemSatiri = false
        p.sohbet = t
        let eski = try alaniSil(p.veri(), yol: ["sohbet"])
        let c = try GorunumTercihleri.coz(eski)
        #expect(c.sohbetTemasi.eylemSatiri == true)
        #expect(c.sohbetTemasi.ad == "Gece")
        // Alan yazılıysa korunur.
        let yeni = try GorunumTercihleri.coz(p.veri())
        #expect(yeni.sohbetTemasi.eylemSatiri == false)
    }

    // MARK: Yeniden üret (model zorlamasız)

    private func beyin(_ alan: String) throws -> Beyin {
        let d = try #require(UserDefaults(suiteName: alan))
        // İstem süzgeci ve otomatik hafıza kapalı: test ağa çıkmasın.
        let a = Ayarlar(defaults: d); a.otomatikHafiza = false; a.istemSuzgeci = false
        let k = OnayKapisi(); k.otomatikKarar = false
        // SwiftData aynı şemada eşzamanlı birden çok kapta çöker: ortak test kabı kullanılır.
        return Beyin(ayarlar: a, depo: HafizaDeposu(baglam: HafizaTestleri.kap.mainContext), onay: k)
    }

    // Yeniden üretimde model zorlandığı için yerel kısa yollar atlanır ve istek zincire (gerçek ağ) gider. Bu yüzden iş,
    // MainActor'da hiç askıya girmeden (görev daha başlamadan) iptal edilir ve bitmesi beklenir: ağa çıkan satır koşmaz.
    @Test func modelsizYenidenUretModelZorlamaz() async throws {
        let alan = "p19-yeniden.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: alan)?.removePersistentDomain(forName: alan) }
        let b = try beyin(alan)
        let soru = Beyin.Goruntu(rol: .kullanici, metin: "saat kaç", istek: "saat kaç")
        let yanit = Beyin.Goruntu(rol: .asistan, metin: "Saat 10.00.", sure: 0.4, model: "claude-haiku-4-5")
        b.mesajlar = [soru, yanit]
        AgIzleyici.ortak.durumGuncelle(true)   // çevrimdışıysa istek kuyruğa düşer, balon eklenmez
        b.yenidenUret(yanit.id, model: nil)
        let is_ = b.calisanIs
        #expect(b.zorlananModel == nil)
        #expect(b.durum != .bosta, "yeniden üretim gönderildi")
        #expect(b.mesajlar.last?.rol == .kullanici)
        #expect(b.mesajlar.last?.metin == "↻ Yeniden üretiliyor")
        #expect(b.mesajlar.last?.istek == "saat kaç", "modele özgün istek gider")
        b.iptal()
        await is_?.value
    }

    @Test func modelliYenidenUretModeliZorlarEtiketiYazar() async throws {
        let alan = "p19-yeniden-model.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: alan)?.removePersistentDomain(forName: alan) }
        let b = try beyin(alan)
        let soru = Beyin.Goruntu(rol: .kullanici, metin: "saat kaç", istek: "saat kaç")
        let yanit = Beyin.Goruntu(rol: .asistan, metin: "Saat 10.00.", sure: 0.4)
        b.mesajlar = [soru, yanit]
        AgIzleyici.ortak.durumGuncelle(true)
        b.yenidenUret(yanit.id, model: "claude-opus-5-5")
        #expect(b.zorlananModel == "claude-opus-5-5")
        #expect(b.mesajlar.last?.metin == "↻ claude-opus-5-5 ile yeniden")
        let is_ = b.calisanIs
        b.iptal()
        await is_?.value
        #expect(b.zorlananModel == nil, "iptal zorlanan modeli bırakır")
    }

    @Test func bilinmeyenMesajdaYenidenUretHicbirSeyYapmaz() throws {
        let alan = "p19-yeniden-yok.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: alan)?.removePersistentDomain(forName: alan) }
        let b = try beyin(alan)
        b.yenidenUret(UUID(), model: nil)
        #expect(b.durum == .bosta)
        #expect(b.mesajlar.isEmpty)
        #expect(b.zorlananModel == nil)
    }
}
