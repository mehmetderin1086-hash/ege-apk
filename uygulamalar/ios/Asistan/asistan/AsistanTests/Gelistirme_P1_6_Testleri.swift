import Foundation
import Testing
@testable import Asistan

/// P1.6: Görünüm stüdyosunda işe yaramayan denetimler kalktı; eski profil alanları yalnız çözülsün diye duruyor.
@Suite("P1.6 görünüm sadeleştirme") @MainActor
struct Gelistirme_P1_6_Testleri {
    /// Hazır görünümler ve "Ana ekran" bölümü dönemindeki bir profil (duzen/balon/zemin/baslik/durum/hizliKomutlar dolu, sohbet yok).
    private static let eskiProfil = """
    {"surum":1,"tema":"Sistem","duzen":"Yazı odaklı","gosterge":"Halkalar","balon":"Kart","zemin":"Işıltı",
     "renk":"2588C9","yaziOlcegi":1.1,"kureOlcegi":0.9,"hareket":true,"sik":true,
     "baslik":true,"durum":true,"hizliKomutlar":true}
    """

    @Test func eskiProfilAlanlariylaCozulur() throws {
        let p = try GorunumTercihleri.coz(Data(Self.eskiProfil.utf8))
        #expect(p.sohbet == nil)
        #expect(p.sohbetTemasi == .karma)   // 20 Eki 2026: varsayılan Karma
        #expect(p.renk == "2588C9" && p.sik && p.gosterge == .halkalar)
        // Okunmayan alanlar da kaybolmaz: profil dışa aktarılıp yeniden yüklenince aynı kalır.
        #expect(p.duzen == .odak && p.balon == .kart && p.zemin == .isilti && p.baslik && p.durum && p.hizliKomutlar)
        #expect(try GorunumTercihleri.coz(p.veri()) == p)
    }

    @Test func varsayilanVurguPalettedirVeIlktir() {
        #expect(GorunumTercihleri.paletler.first?.0 == "Claude")
        #expect(GorunumTercihleri.paletler.first?.1 == "D97757")
        #expect(GorunumTercihleri.paletler.first?.1 == SohbetTemaAyarlari.vurgu("Claude"))
        // Şerit `id: \.1` ile çizilir: renkler tekil olmalı.
        let renkler = GorunumTercihleri.paletler.map(\.1)
        #expect(Set(renkler).count == renkler.count)
        #expect(renkler.allSatisfy { $0.range(of: "^[0-9A-F]{6}$", options: .regularExpression) != nil })
    }

    @Test func hazirSohbetTemalariVurgusuylaKayipsizTasinir() throws {
        for h in SohbetTemasi.hazirlar {
            var p = GorunumTercihleri(); p.sohbet = h; p.renk = SohbetTemaAyarlari.vurgu(h.ad)
            let geri = try GorunumTercihleri.coz(p.veri())
            #expect(geri == p, "\(h.ad)")
            #expect(geri.sohbetTemasi.ad == h.ad)
        }
    }

    /// `--gece` / `--calisma` önizleme bayraklarının kurduğu profiller (AsistanApp ile aynı atama) geçerlidir.
    @Test func onizlemeBayragiProfilleriGecerli() throws {
        var gece = GorunumTercihleri(); gece.sohbet = .gece; gece.renk = SohbetTemaAyarlari.vurgu("Gece")
        var sade = GorunumTercihleri(); sade.sohbet = .sade; sade.renk = SohbetTemaAyarlari.vurgu("Sade")
        try gece.dogrula(); try sade.dogrula()
        #expect(gece.renk == "9164E8" && sade.renk == "007AFF")
        #expect(gece.sohbetTemasi == .gece && sade.sohbetTemasi == .sade)
    }
}
