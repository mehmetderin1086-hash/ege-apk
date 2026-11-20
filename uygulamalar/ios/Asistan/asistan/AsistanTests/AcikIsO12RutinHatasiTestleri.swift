import Foundation
import Testing
@testable import Asistan

/// O12: rutin yenileme hatası görev listesi hatasından (`SunucuGorevleri.hata`) ayrı alanda (`rutinHatasi`) tutulur;
/// 'rutinler' aracı 'listele' hata olunca "Kayıtlı rutin yok." demez, hatayı söyler.
@MainActor
@Suite("O12 rutin hatası ayrı alan", .serialized)
struct AcikIsO12RutinHatasiTestleri {

    private func rutin(_ id: String, ad: String, dakika: Int, etkin: Bool) -> SunucuGorevleri.Rutin {
        SunucuGorevleri.Rutin(id: id, name: ad, prompt: "İstem \(ad)", kind: "text", intervalMinutes: dakika,
                              enabled: etkin ? 1 : 0, lastRun: 0, nextRun: 0, created: 0, updated: 0)
    }

    @Test func hataVarsaListeMetniHatayiSoyler() {
        #expect(SunucuRutinAraci.rutinListeMetni([], hata: "Görev sunucusu HTTP 502 döndürdü.") == "Görev sunucusu HTTP 502 döndürdü.")
        // Eski (bayat) liste dolu olsa da hata öndedir.
        #expect(SunucuRutinAraci.rutinListeMetni([rutin("a", ad: "Özet", dakika: 60, etkin: true)], hata: "HTTP 502") == "HTTP 502")
    }

    @Test func hataYokBosListe() {
        #expect(SunucuRutinAraci.rutinListeMetni([], hata: nil) == "Kayıtlı rutin yok.")
    }

    @Test func satirBicimiEtkinVeDuraklatilmis() {
        let metin = SunucuRutinAraci.rutinListeMetni([
            rutin("r1", ad: "Sabah özeti", dakika: 60, etkin: true),
            rutin("r2", ad: "Haftalık", dakika: 10080, etkin: false)
        ], hata: nil)
        #expect(metin == "r1: Sabah özeti — her 60 dakika — etkin\nr2: Haftalık — her 10080 dakika — duraklatıldı")
    }

    @Test func rutinHatasiGorevHatasiniEzmez() {
        let s = SunucuGorevleri.ortak
        let eskiHata = s.hata, eskiRutinHatasi = s.rutinHatasi
        defer { s.hata = eskiHata; s.rutinHatasi = eskiRutinHatasi }
        s.hata = "görev hatası"
        s.rutinHatasi = "rutin hatası"
        #expect(s.hata == "görev hatası")
        s.rutinHatasi = nil
        #expect(s.hata == "görev hatası")
    }

    /// 'Ağ yok' arızası (görev yereli, bu teste özel depo) vekil kökünü kapalı yerel porta (127.0.0.1:9) çevirir: vekil
    /// tanımlı olsun olmasın istek dış ağa çıkmaz. Kimlik yoksa `.baglanti` ağa çıkmadan fırlar; varsa yerel bağlantı reddedilir.
    /// Her iki durumda hata `rutinHatasi`na yazılır, görev hatası korunur.
    @Test func baglantiYokkenRutinYenilemesiGorevHatasinaDokunmaz() async {
        let ad = "asistan.o12.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: ad)!
        defer { d.removePersistentDomain(forName: ad) }
        let arizalar = ArizaDeposu(depo: d)
        arizalar.ac(.agYok, tekrar: -1, sure: 120)
        let s = SunucuGorevleri.ortak
        let eskiHata = s.hata, eskiRutinHatasi = s.rutinHatasi
        defer { s.hata = eskiHata; s.rutinHatasi = eskiRutinHatasi }
        s.hata = "görev hatası"
        s.rutinHatasi = nil
        await ArizaAnahtarlari.$gecerli.withValue(arizalar) { await s.rutinleriYenile() }
        #expect(s.rutinHatasi != nil, "yenileme hatası rutinHatasi alanına yazılmalı")
        if Gizli.vekilToken == nil {
            #expect(s.rutinHatasi == SunucuGorevleri.Hata.baglanti.localizedDescription)
        }
        #expect(s.hata == "görev hatası")
        #expect(SunucuRutinAraci.rutinListeMetni(s.rutinler, hata: s.rutinHatasi) != "Kayıtlı rutin yok.")
    }
}
