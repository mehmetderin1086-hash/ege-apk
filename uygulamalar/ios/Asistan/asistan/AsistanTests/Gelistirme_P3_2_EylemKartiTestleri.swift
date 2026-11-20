import Foundation
import Testing
@testable import Asistan

/// P3.2: telefon işlemleri için eylem kartı + 10 dakikalık Geri al (saf mantık; EventKit/AlarmKit'e gidilmez).
@Suite("P3.2 eylem kartı") @MainActor
struct Gelistirme_P3_2_EylemKartiTestleri {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func kayit(_ tur: EylemKaydi.Tur, kimlikler: [String] = ["a"]) -> EylemKaydi {
        EylemKaydi(tur: tur, baslik: "Başlık", ozet: "Özet", kimlikler: kimlikler, acAdresi: "calshow:1", zaman: t0)
    }

    private func bellekDefaults() -> UserDefaults {
        let ad = "p32-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: ad)!
        d.removePersistentDomain(forName: ad)
        return d
    }

    @Test func geriAlmaSuresi599TamamAltiYuzDegil() {
        let k = kayit(.takvim)
        #expect(EylemKaydi.geriAlmaSuresi == 600)
        #expect(k.geriAlinabilir(simdi: t0.addingTimeInterval(599)))
        #expect(!k.geriAlinabilir(simdi: t0.addingTimeInterval(600)))
        #expect(!kayit(.takvim, kimlikler: []).geriAlinabilir(simdi: t0.addingTimeInterval(10)), "boş kimlik")
        for t in [EylemKaydi.Tur.arama, .mesaj, .whatsapp, .harita] {
            #expect(!kayit(t).geriAlinabilir(simdi: t0.addingTimeInterval(10)), "\(t) geri alınamaz")
        }
        for t in [EylemKaydi.Tur.takvim, .hatirlatici, .alarm, .zamanlayici] {
            #expect(kayit(t).geriAlinabilir(simdi: t0.addingTimeInterval(10)), "\(t) geri alınabilir")
        }
    }

    @Test func kalanSureSifirdaDurur() {
        let k = kayit(.alarm)
        #expect(k.kalanSure(simdi: t0.addingTimeInterval(60)) == 540)
        #expect(k.kalanSure(simdi: t0.addingTimeInterval(9_999)) == 0)
    }

    @Test func yalnizAcTablosu() {
        let beklenen: [EylemKaydi.Tur: Bool] = [.takvim: false, .hatirlatici: false, .alarm: false, .zamanlayici: false,
                                                .arama: true, .mesaj: true, .whatsapp: true, .harita: true]
        for t in EylemKaydi.Tur.allCases { #expect(kayit(t).yalnizAc == beklenen[t], "\(t)") }
    }

    @Test func dugmeMetniKimlikSayisina() {
        #expect(EylemKaydi.dugmeMetni(kayit(.takvim, kimlikler: ["a"])) == "Geri al")
        #expect(EylemKaydi.dugmeMetni(kayit(.takvim, kimlikler: ["a", "b", "c"])) == "Tümünü geri al")
    }

    @Test func duzenleYalnizTekKimlikliTakvimde() {
        #expect(kayit(.takvim).duzenlenebilir)
        #expect(!kayit(.takvim, kimlikler: ["a", "b"]).duzenlenebilir)
        #expect(!kayit(.hatirlatici).duzenlenebilir)
    }

    @Test func adresBicimleri() {
        let d = Date(timeIntervalSinceReferenceDate: 812_345_678.9)
        #expect(EylemKaydi.takvimAdresi(d) == "calshow:812345678")
        #expect(EylemKaydi.alarmAdresi == "clock-alarm://", "UygulamaAcAraci'ndaki Saat adresiyle aynı")
        #expect(EylemKaydi.hatirlaticiAdresi == "x-apple-reminderkit://")
        #expect(EylemKaydi.haritaAdresi(enlem: 41.1, boylam: 29.05) == "maps://?daddr=41.1,29.05")
    }

    @Test func kodlaCozGidisDonusuEylemiKorur() throws {
        let k = EylemKaydi(tur: .hatirlatici, baslik: "9B ödev", ozet: "Yarın 08:30", kimlikler: ["x1", "x2"], acAdresi: EylemKaydi.hatirlaticiAdresi, zaman: t0)
        let veri = EkKalici.kodla([MesajEki(tur: .kaynaklar(["https://a.com"])), MesajEki(tur: .eylem(k))])
        let geri = EkKalici.coz(veri)
        #expect(geri.count == 2)
        guard geri.count == 2, case .eylem(let g) = geri[1].tur else { Issue.record("eylem kartı çözülmedi"); return }
        #expect(g == k, "bütün alanlar (id, tür, kimlikler, adres, zaman) korunur")
        #expect(g.geriAlinabilir(simdi: t0.addingTimeInterval(120)), "yeniden açılışta süre kayıttaki zamandan işler")
    }

    @Test func eskiDTOEylemAlanıOlmadanCozulur() {
        // P3.2 öncesi kayıt: 'eylem' anahtarı hiç yok.
        let eski = Data(#"[{"t":"kaynak","adresler":["https://a.com"]},{"t":"indirme","kimlik":"6F1C2E2A-3B5D-4C1E-9A11-2B7C1D8E9F00"}]"#.utf8)
        let geri = EkKalici.coz(eski)
        #expect(geri.count == 2)
        if case .kaynaklar(let a) = geri.first?.tur { #expect(a == ["https://a.com"]) } else { Issue.record("kaynak") }
        // Eylem alanı eksik 'eylem' kaydı sessizce atlanır, öbürleri bozulmaz.
        let eksik = Data(#"[{"t":"eylem"},{"t":"kaynak","adresler":["https://b.com"]}]"#.utf8)
        #expect(EkKalici.coz(eksik).count == 1)
    }

    @Test func geriAlinanlarKalicidirVeIkiYuzdeEnEskisiDuser() {
        let d = bellekDefaults()
        let ilk = UUID()
        #expect(!EylemGeriAlici.geriAlindiMi(ilk, defaults: d))
        EylemGeriAlici.isaretle(ilk, defaults: d)
        #expect(EylemGeriAlici.geriAlindiMi(ilk, defaults: d))
        let digerleri = (0..<EylemGeriAlici.enFazlaKayit).map { _ in UUID() }
        for id in digerleri { EylemGeriAlici.isaretle(id, defaults: d) }
        #expect((d.stringArray(forKey: EylemGeriAlici.geriAlinanAnahtari) ?? []).count == 200)
        #expect(!EylemGeriAlici.geriAlindiMi(ilk, defaults: d), "201. kayıtta en eskisi düşer")
        #expect(EylemGeriAlici.geriAlindiMi(digerleri.last!, defaults: d))
        #expect(EylemGeriAlici.geriAlindiMi(digerleri.first!, defaults: d))
    }

    @Test func sureGecmisKayitEventKiteGitmedenSureDoldu() async {
        let d = bellekDefaults()
        let k = kayit(.takvim, kimlikler: ["gercek-olmayan"])
        let s = await EylemGeriAlici.geriAl(k, simdi: t0.addingTimeInterval(601), defaults: d)
        #expect(s == .sureDoldu)
        #expect(!EylemGeriAlici.geriAlindiMi(k.id, defaults: d))
    }

    @Test func onizlemeKimligiBulunamadiDoner() async {
        let d = bellekDefaults()
        let k = kayit(.takvim, kimlikler: [EylemKaydi.onizlemeKimligi])
        #expect(await EylemGeriAlici.geriAl(k, simdi: t0.addingTimeInterval(5), defaults: d) == .bulunamadi)
        #expect(await EylemGeriAlici.geriAl(kayit(.mesaj, kimlikler: []), simdi: t0, defaults: d) == .bulunamadi, "SMS geri alınmaz")
    }

    @Test func sonucMetinleri() {
        #expect(EylemGeriAlici.metin(.tamam(1), tur: .takvim) == "Geri alındı")
        #expect(EylemGeriAlici.metin(.kismen(2, kalan: 1), tur: .takvim) == "2/3 geri alındı")
        #expect(EylemGeriAlici.metin(.bulunamadi, tur: .alarm) == "Geri alınamadı (kayıt bulunamadı)")
        #expect(EylemGeriAlici.metin(.sureDoldu, tur: .takvim) == "Süre doldu")
        #expect(EylemGeriAlici.metin(.izinYok, tur: .takvim) == "Geri alınamadı (takvim izni yok)")
        #expect(EylemGeriAlici.metin(.izinYok, tur: .hatirlatici) == "Geri alınamadı (hatırlatıcı izni yok)")
    }

    @Test func iletisimKartiYalnizAcVeSorgusuzAdres() throws {
        let sms = try #require(IletisimAraci.adres(islem: "mesaj", hedef: "+905551112233", metin: "Toplantı 15:00"))
        let k = try #require(IletisimAraci.kartKaydi(islem: "mesaj", hedef: "+905551112233", metin: "Toplantı 15:00", url: sms))
        #expect(k.tur == .mesaj && k.yalnizAc && k.kimlikler.isEmpty)
        #expect(k.acAdresi == "sms:+905551112233", "metin yeniden açılışta taslağa ikinci kez dolmaz")
        let wa = try #require(IletisimAraci.adres(islem: "whatsapp", hedef: "+905551112233", metin: "Merhaba"))
        #expect(IletisimAraci.kartKaydi(islem: "whatsapp", hedef: "+905551112233", metin: "Merhaba", url: wa)?.acAdresi == "https://wa.me/905551112233")
        let tel = try #require(IletisimAraci.adres(islem: "ara", hedef: "+905551112233", metin: nil))
        #expect(IletisimAraci.kartKaydi(islem: "ara", hedef: "+905551112233", metin: nil, url: tel)?.tur == .arama)
        #expect(IletisimAraci.kartKaydi(islem: "aramacevapla", hedef: "", metin: nil, url: tel) == nil)
    }

    @Test func ekDefteriEylemKartlariniBirlestirmez() {
        let defter = EkDefteri()   // ortak defter başka testlerle paralel çakışmasın
        defter.ekle(MesajEki(tur: .eylem(kayit(.alarm))))
        defter.ekle(MesajEki(tur: .eylem(kayit(.zamanlayici))))
        #expect(defter.bekleyen.count == 2)
    }

    @Test func mesajTaslagiSonucuGonderildiBilgisiniTasir() {
        let a = MesajTaslagi.Sonuc(metin: "x", gonderildi: true)
        #expect(a.gonderildi && a != MesajTaslagi.Sonuc(metin: "x", gonderildi: false))
    }
}
