import Foundation
import Testing
@testable import Asistan

@Suite("Hey Asistan") struct UyandirmaTestleri {
    @Test func yalnizUyandirma() {
        #expect(Uyandirma.komut("Hey Asistan") == "")
        #expect(Uyandirma.komut(" HEY, ASISTAN!") == "")
    }
    @Test func tekNefesteKomut() {
        #expect(Uyandirma.komut("Hey Asistan, saat kaç?") == "saat kaç?")
        #expect(Uyandirma.komut("hey asistan Barış Manço aç") == "Barış Manço aç")
    }
    @Test func dikteIngIlizceYazimlaGelseDeUyanir() {
        #expect(Uyandirma.komut("Hey Assistant, saat kaç?") == "saat kaç?")
        #expect(Uyandirma.komut("HEY assistant!") == "")
    }
    @Test func turkceDikteIlkHarfiniDuserseDeUyanir() {
        #expect(Uyandirma.komut("Ey Asistan, saat kaç?") == "saat kaç?")
        #expect(Uyandirma.komut("EY ASİSTAN") == "")
    }
    @Test func yanlisUyanmalariReddet() {
        #expect(Uyandirma.komut("asistan saat kaç") == nil)
        #expect(Uyandirma.komut("Bugün hey asistan demiştim") == nil)
        #expect(Uyandirma.komut("Hey asistanlık") == nil)
        #expect(Uyandirma.komut("Hey assistantship") == nil)
        #expect(Uyandirma.komut("heyasistan") == nil)
        #expect(Uyandirma.komut("Ey asistanlık") == nil)
    }
}

@Suite("Tek komut kapısı") struct UyandirmaAkisiTestleri {
    @Test func beklerkenOrtamKonusmasiGonderilmez() {
        var akis = UyandirmaAkisi(); akis.bekle()
        let sonuc24 = !akis.araSonuc("Yarın alışveriş yapacağız")
        #expect(sonuc24)
        let sonuc25 = akis.kesinSonuc("Saat kaç?") == nil
        #expect(sonuc25)
        #expect(akis.durum == .bekliyor)
    }
    @Test func UyandirmaSonraTekKomutVeYenidenCagri() {
        var akis = UyandirmaAkisi(); akis.bekle()
        let sonuc30 = akis.araSonuc("Hey Asistan")
        #expect(sonuc30)
        let sonuc31 = akis.kesinSonuc("Hey Asistan") == nil
        #expect(sonuc31)
        let sonuc32 = akis.kesinSonuc("Saat kaç?") == "Saat kaç?"
        #expect(sonuc32)
        let sonuc33 = akis.kesinSonuc("Yarın hava nasıl?") == nil
        #expect(sonuc33)
        let sonuc34 = !akis.yanitBitti(surekli: true)
        #expect(sonuc34) // Eski sürekli konuşma tercihi uyandırmayı etkilemez.
        akis.bekle()
        let sonuc36 = akis.kesinSonuc("Yarın hava nasıl?") == nil
        #expect(sonuc36)
        let sonuc37 = akis.kesinSonuc("Hey Asistan yarın hava nasıl?") == "yarın hava nasıl?"
        #expect(sonuc37)
    }
    @Test func tekNefesVeGecikmisTekrar() {
        var akis = UyandirmaAkisi(); akis.bekle()
        let sonuc41 = akis.kesinSonuc("Hey Asistan, müziği aç") == "müziği aç"
        #expect(sonuc41)
        #expect(akis.uyandirmaIleAcildi)
        let sonuc43 = akis.kesinSonuc("Hey Asistan, müziği aç") == nil
        #expect(sonuc43)
    }
    @Test func IptalHataVeyaZamanAsimiSonrasiGecikmisSonucReddedilir() {
        var akis = UyandirmaAkisi(); akis.bekle()
        akis.araSonuc("Hey Asistan")
        akis.kapat()
        #expect(!akis.etkin)
        let sonuc50 = akis.kesinSonuc("Mesaj gönder") == nil
        #expect(sonuc50)
        akis.bekle()
        let sonuc52 = akis.kesinSonuc("Mesaj gönder") == nil
        #expect(sonuc52)
    }
    @Test func elleBaslatmaAcikTercihleSurekliOlabilir() {
        var akis = UyandirmaAkisi(); akis.elleDinle()
        let sonuc56 = akis.kesinSonuc("Merhaba") == "Merhaba"
        #expect(sonuc56)
        let sonuc57 = akis.yanitBitti(surekli: true)
        #expect(sonuc57)
        let sonuc58 = akis.kesinSonuc("Saat kaç?") == "Saat kaç?"
        #expect(sonuc58)
        let sonuc59 = !akis.yanitBitti(surekli: false)
        #expect(sonuc59)
        let sonuc60 = akis.kesinSonuc("Devam") == nil
        #expect(sonuc60)
    }
    /// Ölü 'sürekli konuşma' ayarı kaldırıldı; eski kayıt ve göç işareti açılışta silinir.
    @Test @MainActor func eskiSurekliAnahtariTemizlenir() throws {
        let alan = "tek-komut.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: alan))
        defer { d.removePersistentDomain(forName: alan) }
        d.set(true, forKey: "ayar.surekliKonusma")
        d.set(true, forKey: "ayar.tekKomutV1")
        _ = Ayarlar(defaults: d)
        #expect(d.object(forKey: "ayar.surekliKonusma") == nil)
        #expect(d.object(forKey: "ayar.tekKomutV1") == nil)
    }
}

@Suite("Uyandırma ses gizliliği") struct UyandirmaTamponTestleri {
    @Test func beklemeSesiSinirliVeKapatincaBos() {
        let tampon = SesTamponu()
        tampon.ayarla(oran: 10, azamiSure: 3)
        let ses = (0..<100).map { Float($0) }
        ses.withUnsafeBufferPointer { tampon.ekle($0) }
        #expect(tampon.sure == 3)
        #expect(tampon.al() == Array(ses.suffix(30)))
        #expect(tampon.sure == 0)
    }
}
