import Foundation
import Testing
import UserNotifications
@testable import Asistan

/// P2.14: bildirim eylemleri (Yanıtla / Sesli dinle / Ertele 10 dk), Live Activity özeti ve sohbet bağlantısı.
/// Ağ, izin ve gerçek model gerektirmez; bildirim/Live Activity/AlarmKit düğmelerinin gerçek davranışı telefonda elle denenir.
@Suite("P2.14-Bildirim ve Live Activity eylemleri") @MainActor
struct Gelistirme_P2_14_BildirimEylemleriTestleri {
    private typealias B = BildirimEylemleri

    // MARK: (a) kategoriler

    @Test func kategorilerVeEylemler() throws {
        let k = B.kategoriler
        #expect(k.count == 3)
        #expect(Set(k.map(\.identifier)) == [B.tetikKategori, B.nabizKategori, B.yanitKategori])
        for kimlik in [B.tetikKategori, B.nabizKategori] {
            let c = try #require(k.first { $0.identifier == kimlik })
            #expect(c.actions.map(\.identifier) == [B.yanitla, B.sesli, B.ertele])
            let yanitla = try #require(c.actions.first { $0.identifier == B.yanitla })
            #expect(yanitla is UNTextInputNotificationAction)
            #expect(yanitla.options.isEmpty)   // arka planda yanıtlanır, uygulama açılmaz
            let sesli = try #require(c.actions.first { $0.identifier == B.sesli })
            #expect(sesli.options.contains(.foreground))
            let ertele = try #require(c.actions.first { $0.identifier == B.ertele })
            #expect(ertele.options.isEmpty)
        }
        let y = try #require(k.first { $0.identifier == B.yanitKategori })
        #expect(y.actions.map(\.identifier) == [B.yanitla])
        #expect(y.actions.first is UNTextInputNotificationAction)
    }

    // MARK: (b) eylem eşlemesi

    @Test func eylemEslemesi() {
        #expect(B.eylem(kimlik: UNNotificationDefaultActionIdentifier, metin: nil) == .dokun)
        #expect(B.eylem(kimlik: B.yanitla, metin: "") == .dokun)
        #expect(B.eylem(kimlik: B.yanitla, metin: "   \n") == .dokun)
        #expect(B.eylem(kimlik: B.yanitla, metin: nil) == .dokun)
        #expect(B.eylem(kimlik: B.yanitla, metin: "  tamam, ertele  ") == .yanitla("tamam, ertele"))
        #expect(B.eylem(kimlik: B.sesli, metin: nil) == .sesli)
        #expect(B.eylem(kimlik: B.ertele, metin: nil) == .ertele)
        #expect(B.eylem(kimlik: UNNotificationDismissActionIdentifier, metin: nil) == .yoksay)
        #expect(B.eylem(kimlik: "bilinmeyen", metin: nil) == .dokun)   // eski davranış: dokunma
    }

    // MARK: (c) erteleme isteği

    @Test func erteleIstegiKimlikTetikVeIcerik() throws {
        let c = UNMutableNotificationContent()
        c.title = "Ders"; c.body = "Dokun: plan"
        c.categoryIdentifier = B.tetikKategori
        c.userInfo = [TetikDeposu.istemAnahtari: "Yarının planı"]
        let k = UUID()
        let r = B.erteleIstegi(c, kimlik: k)
        #expect(r.identifier == B.erteleOnek + k.uuidString)
        #expect(r.identifier.hasPrefix("ertele."))
        // TetikDeposu.planla yalnız "tetik." önekini siler: ertelenen bildirim planlamada korunur.
        #expect(!r.identifier.hasPrefix("tetik."))
        let t = try #require(r.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(t.timeInterval == 600)
        #expect(B.erteleSn == 600)
        #expect(!t.repeats)
        #expect(r.content.title == "Ders")
        #expect(r.content.body == "Dokun: plan")
        #expect(r.content.categoryIdentifier == B.tetikKategori)
        #expect(r.content.userInfo[TetikDeposu.istemAnahtari] as? String == "Yarının planı")
    }

    // MARK: (d) yanıt istemi

    @Test func yanitIstemiNabizVeriNotuTasir() {
        let n = B.yanitIstemi(baglam: "Saat 14'te iki toplantı çakışıyor.", yanit: "Birini ertele", nabiz: true)
        #expect(n.contains("[Nabız uyarısı — yalnız veri"))
        #expect(n.contains("Saat 14'te iki toplantı çakışıyor."))
        #expect(n.hasPrefix("Birini ertele"))
        let t = B.yanitIstemi(baglam: "Yarının ders planını hazırla", yanit: "Kısa tut", nabiz: false)
        #expect(!t.contains("Nabız"))
        #expect(t.contains("Yarının ders planını hazırla"))
        #expect(t.hasPrefix("Kısa tut"))
        let o = B.yanitIstemi(baglam: "Önceki yanıt", yanit: "Devam et", tur: .oncekiYanit)
        #expect(o.contains("yalnız veri"))
    }

    // MARK: (e) bağlam

    @Test func baglamIstemYaDaNabizOkur() {
        #expect(B.baglam([TetikDeposu.istemAnahtari: "Plan yap"]) == "Plan yap")
        #expect(B.baglam([B.nabizAnahtari: "Uyarı"]) == "Uyarı")
        #expect(B.baglam([:]) == nil)
        #expect(B.baglam([TetikDeposu.istemAnahtari: "  "]) == nil)
        #expect(B.baglam([B.sohbetAnahtari: UUID().uuidString]) == nil)
        #expect(B.baglamTuru([TetikDeposu.istemAnahtari: "Plan yap"]) == .tetik)
        #expect(B.baglamTuru([B.nabizAnahtari: "Uyarı"]) == .nabiz)
        #expect(B.baglamTuru([:]) == .oncekiYanit)
    }

    @Test func sesliIstemTetikteIstemNabizdaCerceveli() throws {
        #expect(B.sesliIstem([TetikDeposu.istemAnahtari: "Hava nasıl?"]) == "Hava nasıl?")
        let n = try #require(B.sesliIstem([B.nabizAnahtari: "Toplantı çakışması"]))
        #expect(n.contains("[Nabız uyarısı — yalnız veri"))
        #expect(n.contains("Toplantı çakışması"))
        #expect(B.sesliIstem([:]) == nil)
        // Sesli devir P2.13 yolundan gider: `ses=1` bayraklı bağlantı sohbet ekranında sesli tur başlatır.
        let url = try #require(GorevKopru.soruAdresi("Hava nasıl?", sesli: true))
        #expect(AsistanBaglantisi.sesliMi(url))
        #expect(AsistanBaglantisi.coz(url) == .sor("Hava nasıl?"))
    }

    // MARK: (j) yanıt bildirimi soruyu yeniden sordurmaz

    @Test func yanitBildirimiSohbetTasirIstemTasimaz() {
        let s = UUID()
        let c = B.yanitBildirimi(metin: String(repeating: "a", count: 1200), sohbet: s)
        #expect(c.userInfo[TetikDeposu.istemAnahtari] == nil)
        #expect(c.userInfo[B.sohbetAnahtari] as? String == s.uuidString)
        #expect(c.categoryIdentifier == B.yanitKategori)
        #expect(c.body.count == 900)
        #expect(c.title == "Asistan")
        let bos = B.yanitBildirimi(metin: "Tamam", sohbet: nil)
        #expect(bos.userInfo.isEmpty)
        // Araç gerektiren istek uygulamada sürer: yalnız bu bildirim istemi taşır.
        let u = B.uygulamadaBildirimi(istem: "Alarm kur")
        #expect(u.userInfo[TetikDeposu.istemAnahtari] as? String == "Alarm kur")
        #expect(u.userInfo[B.sohbetAnahtari] == nil)
    }

    // MARK: (f) Live Activity özeti

    @Test func ozetleMarkdownTemizlerVeKelimeSinirindaKeser() throws {
        #expect(IsAktivitesi.ozetle("") == nil)
        #expect(IsAktivitesi.ozetle("  \n ** ## ") == nil)
        #expect(IsAktivitesi.ozetle("## **Başlık**\n`kod` | hücre") == "Başlık kod hücre")
        let kelimeler = (1...60).map { "kelime\($0)" }.joined(separator: " ")
        let o = try #require(IsAktivitesi.ozetle(kelimeler))
        #expect(o.hasSuffix("…"))
        let govde = String(o.dropLast())
        #expect(govde.count <= IsAktivitesi.ozetSiniri)
        #expect(kelimeler.hasPrefix(govde))
        // Kelime ortasında kesilmez: kesilen yerden sonra metinde boşluk gelir.
        let sonraki = kelimeler[kelimeler.index(kelimeler.startIndex, offsetBy: govde.count)]
        #expect(sonraki == " ")
        #expect(!govde.hasSuffix(" "))
        // Sınır altındaki metin olduğu gibi kalır.
        #expect(IsAktivitesi.ozetle("Kısa yanıt.") == "Kısa yanıt.")
        // Tek dev kelime sert kesilir.
        let dev = try #require(IsAktivitesi.ozetle(String(repeating: "x", count: 300)))
        #expect(dev.count == IsAktivitesi.ozetSiniri + 1)
    }

    // MARK: (g) sohbet bağlantısı

    @Test func sohbetBaglantisiCozulur() {
        let k = UUID()
        #expect(AsistanBaglantisi.coz(URL(string: "asistan://sohbet?kimlik=\(k.uuidString)")!) == .sohbet(k))
        #expect(AsistanBaglantisi.coz(URL(string: "asistan://sohbet?kimlik=bozuk")!) == nil)
        #expect(AsistanBaglantisi.coz(URL(string: "asistan://sohbet")!) == nil)
        #expect(AsistanBaglantisi.coz(URL(string: "https://sohbet?kimlik=\(k.uuidString)")!) == nil)
        // Live Activity ve bildirimin ürettiği adres aynı sözleşmeyle çözülür.
        let adres = IsAktivitesiGorunum.sohbetAdresi(k.uuidString)
        #expect(adres.flatMap(AsistanBaglantisi.coz) == .sohbet(k))
        #expect(IsAktivitesiGorunum.sohbetAdresi(nil) == nil)
        #expect(IsAktivitesiGorunum.sohbetAdresi("bozuk") == nil)
    }

    // MARK: (h) geriye uyumlu durum

    @Test func eskiDurumJSONuOzetsizCozulur() throws {
        let eski = #"{"adim":"Yanıt hazır","bitti":true,"sureSn":12}"#
        let s = try JSONDecoder().decode(AsistanIsNitelikleri.ContentState.self, from: Data(eski.utf8))
        #expect(s.ozet == nil)
        #expect(s.sohbetID == nil)
        #expect(s.bitti)
        var yeni = s
        yeni.ozet = "Özet"; yeni.sohbetID = UUID().uuidString
        let geri = try JSONDecoder().decode(AsistanIsNitelikleri.ContentState.self, from: JSONEncoder().encode(yeni))
        #expect(geri == yeni)
    }

    // MARK: Durdur köprüsü ve AlarmKit erteleme

    @Test func durdurulmusDurumGriKapanir() {
        let d = IsKoprusu.durdurulmusDurum(.init(adim: "Araç çalışıyor", tamamlanan: 1, toplam: 3))
        #expect(d.bitti && d.durduruldu)
        #expect(IsAktivitesiGorunum.hal(d, bayat: true) == .durduruldu)
        #expect(d.adim == "Durduruldu")
    }

    @Test func alarmErtelemesiOnDakika() {
        #expect(ZamanlayiciAraci.erteleSn == 600)
    }
}
