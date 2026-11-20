import Foundation
import Testing
@testable import Asistan

/// P4.2: kilit ekranında / uygulamayı açmadan sesli asistan. Ağsız, izinsiz saf kararlar: arka plan model rotası,
/// arka planda Live kararı, sessizlik sınırı, bas-konuş sonucu, kipli kontrol bağlantıları, Hey Asistan göçü,
/// ContentState geriye uyumu ve bitiş durumu.
@Suite("P4.2-Arka plan ses") @MainActor
struct Gelistirme_P4_2_ArkaPlanSesTestleri {
    private typealias Adim = ModelZinciri.Adim
    private typealias Durum = AsistanIsNitelikleri.ContentState

    private func suite(_ ad: String) -> UserDefaults {
        let n = "p42-\(ad)-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: n)!
        d.removePersistentDomain(forName: n)
        return d
    }

    // MARK: (a) arka plan rotası

    @Test func arkaPlanSuzTelefonuCikarirSirayiKorur() {
        let girdi = [Adim(yol: .telefon, model: "a"), Adim(yol: .vekil, model: "a"), Adim(yol: .telefon, model: "b"),
                     Adim(yol: .anahtar, model: "a"), Adim(yol: .vekil, model: "b")]
        let sonuc = ModelZinciri.arkaPlanSuz(girdi, arkaPlanda: true)
        #expect(sonuc == [Adim(yol: .vekil, model: "a"), Adim(yol: .anahtar, model: "a"), Adim(yol: .vekil, model: "b")])
    }

    @Test func arkaPlanSuzYalnizTelefonVarsaAynenDoner() {
        let girdi = [Adim(yol: .telefon, model: "a"), Adim(yol: .telefon, model: "b")]
        #expect(ModelZinciri.arkaPlanSuz(girdi, arkaPlanda: true) == girdi)
        #expect(ModelZinciri.arkaPlanSuz([], arkaPlanda: true).isEmpty)
    }

    @Test func arkaPlanSuzOnPlandaDegistirmez() {
        let girdi = [Adim(yol: .telefon, model: "a"), Adim(yol: .vekil, model: "a")]
        #expect(ModelZinciri.arkaPlanSuz(girdi, arkaPlanda: false) == girdi)
    }

    // MARK: (b) arka planda Live kararı

    @Test func arkaPlandaSurdurKararTablosu() {
        #expect(SesOturumu.arkaPlandaSurdur(canliMod: true, ayar: true, gercekZamanli: false))
        #expect(!SesOturumu.arkaPlandaSurdur(canliMod: true, ayar: true, gercekZamanli: true))   // OpenAI/Gemini WebSocket
        #expect(!SesOturumu.arkaPlandaSurdur(canliMod: true, ayar: false, gercekZamanli: false)) // ayar kapalı
        #expect(!SesOturumu.arkaPlandaSurdur(canliMod: false, ayar: true, gercekZamanli: false)) // Live yok
        #expect(!SesOturumu.arkaPlandaSurdur(canliMod: false, ayar: false, gercekZamanli: true))
    }

    // MARK: (c) sessizlik sınırı

    @Test func sessizlikSinirlari() {
        let son = Date(timeIntervalSince1970: 1_000_000)
        #expect(!SesOturumu.sessizlikDoldu(son: son, simdi: son.addingTimeInterval(599)))
        #expect(SesOturumu.sessizlikDoldu(son: son, simdi: son.addingTimeInterval(600)))
        #expect(SesOturumu.sessizlikDoldu(son: son, simdi: son.addingTimeInterval(601)))
        #expect(SesOturumu.canliSessizlikSiniri == 600)
        #expect(!SesOturumu.sessizlikDoldu(son: son, simdi: son.addingTimeInterval(30), sinir: 31))
    }

    // MARK: (d) bas-konuş sonucu

    @Test func basKonusSonucuVazgecVeGonder() {
        #expect(SesOturumu.basKonusSonucu(metin: nil, sureAsildi: false) == .vazgec("Komut duyulmadı"))
        #expect(SesOturumu.basKonusSonucu(metin: "", sureAsildi: true) == .vazgec("Komut duyulmadı"))
        #expect(SesOturumu.basKonusSonucu(metin: "  \n ", sureAsildi: false) == .vazgec("Komut duyulmadı"))
        #expect(SesOturumu.basKonusSonucu(metin: "saat kaç", sureAsildi: true) == .vazgec("Komut tamamlanamadı"))
        #expect(SesOturumu.basKonusSonucu(metin: "  saat kaç ", sureAsildi: false) == .gonder("saat kaç"))
        #expect(SesOturumu.basKonusSuresi == 12)
        #expect(SesOturumu.basKonusEnUzun > SesOturumu.basKonusSuresi)
    }

    // MARK: (e) kipli kontrol bağlantıları

    @Test func kipBaglantilariCozulur() {
        #expect(AsistanBaslatKipi.baglanti(.dinle).absoluteString == "asistan://dinle")
        #expect(AsistanBaslatKipi.baglanti(.canliKamera).absoluteString == "asistan://canli-kamera")
        #expect(AsistanBaslatKipi.baglanti(.sonSohbet).absoluteString == "asistan://devam")
        #expect(AsistanBaslatKipi.baglanti(.sabahOzeti).absoluteString == "asistan://hizli?no=4")
        #expect(AsistanBaglantisi.coz(AsistanBaslatKipi.baglanti(.dinle)) == .dinle)
        #expect(AsistanBaglantisi.coz(AsistanBaslatKipi.baglanti(.canliKamera)) == .canliKamera)
        #expect(AsistanBaglantisi.coz(AsistanBaslatKipi.baglanti(.sonSohbet)) == .devam)
        #expect(AsistanBaglantisi.coz(AsistanBaslatKipi.baglanti(.sabahOzeti)) == .hizli(4))
        // Sabah özeti istemi uygulamaya gömülü sabit metindir (P3.11).
        #expect(DersGunu.hizliIstem(4)?.hasPrefix("Sabah özeti") == true)
        // Var olan `.live` bağlantısı değişmez.
        #expect(AsistanBaglantisi.coz(URL(string: "asistan://live")!) == .live)
    }

    @Test func kipBasliklariVeSimgeleriDolu() {
        for k in AsistanBaslatKipi.allCases {
            #expect(!k.baslik.isEmpty)
            #expect(!k.simge.isEmpty)
        }
        #expect(AsistanBaslatKipi.allCases.count == 4)
    }

    // MARK: (f, h, i) Hey Asistan göçü ve App Group

    @Test func heyAsistanYerelDegerOrtagaTasinir() {
        let yerel = suite("yerel"), ortak = suite("ortak")
        yerel.set(false, forKey: "ayar.heyAsistan")
        let a = Ayarlar(defaults: yerel, ortak: ortak)
        #expect(a.heyAsistan == false)
        #expect(OrtakAyarlar.heyAsistan(ortak) == false)
        // Kontrol Merkezi değeri değiştirdi: öne gelişte eşitlenir ve değişiklik bildirilir.
        OrtakAyarlar.heyAsistanYaz(true, ortak)
        #expect(a.ortaktanEsitle())
        #expect(a.heyAsistan)
        #expect(yerel.bool(forKey: "ayar.heyAsistan"))
        #expect(!a.ortaktanEsitle())   // ikinci çağrıda değişiklik yok
    }

    @Test func heyAsistanOrtakDegerOnceliklidir() {
        let yerel = suite("yerel"), ortak = suite("ortak")
        yerel.set(true, forKey: "ayar.heyAsistan")
        OrtakAyarlar.heyAsistanYaz(false, ortak)
        #expect(Ayarlar(defaults: yerel, ortak: ortak).heyAsistan == false)
    }

    @Test func heyAsistanAnahtarYokkenAcikGelir() {
        let yerel = suite("yerel"), ortak = suite("ortak")
        #expect(Ayarlar(defaults: yerel).heyAsistan)
        #expect(Ayarlar(defaults: suite("yerel2"), ortak: ortak).heyAsistan)
        #expect(OrtakAyarlar.heyAsistan(ortak) == true)
    }

    @Test func ortakVerilmezseAppGroupaYazilmaz() {
        let yerel = suite("yerel"), ortak = suite("ortak")
        let a = Ayarlar(defaults: yerel)
        a.heyAsistan = false
        a.heyAsistan = true
        #expect(OrtakAyarlar.heyAsistan(ortak) == nil)
        #expect(!a.ortaktanEsitle())
    }

    @Test func ayarDegisinceOrtakAlanGuncellenir() {
        let yerel = suite("yerel"), ortak = suite("ortak")
        let a = Ayarlar(defaults: yerel, ortak: ortak)
        a.heyAsistan = false
        #expect(OrtakAyarlar.heyAsistan(ortak) == false)
        #expect(!a.ortaktanEsitle())
    }

    @Test func canliArkaPlanVarsayilanKapali() {
        let yerel = suite("yerel")
        let a = Ayarlar(defaults: yerel)
        #expect(a.canliArkaPlan == false)
        // Live motoru varsayılanı değişmez.
        #expect(a.canliMotor == "claude")
        a.canliArkaPlan = true
        #expect(Ayarlar(defaults: yerel).canliArkaPlan)
    }

    // MARK: (g) ContentState geriye uyumu ve görünüm

    @Test func eskiDurumdaDinliyorYanlis() throws {
        let eski = try JSONDecoder().decode(Durum.self, from: Data(#"{"adim":"Düşünüyor","tamamlanan":1,"toplam":3}"#.utf8))
        #expect(eski.dinliyor == false)
        var yeni = Durum(adim: "Dinliyorum", dinliyor: true)
        yeni.sureSn = 3
        #expect(try JSONDecoder().decode(Durum.self, from: JSONEncoder().encode(yeni)) == yeni)
    }

    @Test func dinlerkenBaslikVeSimge() {
        let dinliyor = Durum(adim: "Dinliyorum", dinliyor: true)
        #expect(IsAktivitesiGorunum.baslik(dinliyor, .calisiyor) == "Dinliyorum")
        #expect(IsAktivitesiGorunum.simge(dinliyor, .calisiyor) == "waveform")
        // Bayatsa ya da bittiyse olağan hâl metinleri.
        #expect(IsAktivitesiGorunum.baslik(dinliyor, .koptu) == IsAktivitesiGorunum.baslik(.koptu))
        let calisiyor = Durum(adim: "Düşünüyor")
        #expect(IsAktivitesiGorunum.baslik(calisiyor, .calisiyor) == IsAktivitesiGorunum.baslik(.calisiyor))
        #expect(IsAktivitesiGorunum.simge(calisiyor, .calisiyor) == IsAktivitesiGorunum.simge(.calisiyor))
    }

    @Test func bitisDurumuAdimliVazgecme() {
        let onceki = Durum(adim: "Dinliyorum", dinliyor: true)
        let s = IsAktivitesi.bitisDurumu(onceki, sureSn: 12, hata: false, durduruldu: true, ozet: nil, sohbetID: nil,
                                         adim: "Komut duyulmadı")
        #expect(s.bitti && s.durduruldu && !s.dinliyor)
        #expect(s.adim == "Komut duyulmadı")
        #expect(s.sureSn == 12)
        #expect(IsAktivitesiGorunum.hal(s, bayat: false) == .durduruldu)
        // Adım verilirse hata yok sayılır.
        let h = IsAktivitesi.bitisDurumu(onceki, sureSn: 0, hata: true, durduruldu: true, ozet: nil, sohbetID: nil, adim: "Durduruldu")
        #expect(h.durduruldu && h.adim == "Durduruldu")
    }

    @Test func bitisDurumuAdimsizEskiDavranis() {
        let onceki = Durum(adim: "Düşünüyor")
        let hazir = IsAktivitesi.bitisDurumu(onceki, sureSn: 5, hata: false, durduruldu: false, ozet: "Özet", sohbetID: nil, adim: nil)
        #expect(hazir.adim == "Yanıt hazır" && !hazir.hata && !hazir.durduruldu && hazir.ozet == "Özet")
        let hatali = IsAktivitesi.bitisDurumu(onceki, sureSn: 5, hata: true, durduruldu: true, ozet: nil, sohbetID: nil, adim: nil)
        #expect(hatali.hata && !hatali.durduruldu)
        #expect(IsAktivitesiGorunum.hal(hatali, bayat: false) == .hata)
    }

    // MARK: (j) Live arka planda sürekli kalır

    @Test func canliSurerKararTablosu() {
        #expect(SesOturumu.canliSurer(onPlanda: true, arkaPlanCanli: false, canliMod: true, kip: .sohbet))
        #expect(SesOturumu.canliSurer(onPlanda: false, arkaPlanCanli: true, canliMod: true, kip: .sohbet))
        #expect(!SesOturumu.canliSurer(onPlanda: false, arkaPlanCanli: false, canliMod: true, kip: .sohbet))
        #expect(!SesOturumu.canliSurer(onPlanda: true, arkaPlanCanli: true, canliMod: false, kip: .sohbet))
        #expect(!SesOturumu.canliSurer(onPlanda: true, arkaPlanCanli: false, canliMod: true, kip: .gorsel))
        #expect(!SesOturumu.canliSurer(onPlanda: false, arkaPlanCanli: true, canliMod: true, kip: .belge))
        #expect(!SesOturumu.canliSurer(onPlanda: true, arkaPlanCanli: false, canliMod: true, kip: .arsiv))
    }
}
