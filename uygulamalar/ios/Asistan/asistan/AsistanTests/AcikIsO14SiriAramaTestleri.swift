import Foundation
import Testing
@testable import Asistan

/// O14: Siri yanıtında arama işareti. Güncel bilgi (skor, kur, haber, fiyat) istekleri arka plan yarışına hiç girmez;
/// yarış modeli yine de [ARAMA] işareti verirse yanıt söylenmez, istek uygulamada (araçlı yol) sürer.
@MainActor
@Suite("O14 Siri arama işareti")
struct AcikIsO14SiriAramaTestleri {

    @Test func aramaIsaretiUygulamadaSurer() {
        #expect(SiriYanitlayici.yarisSonucu("[ARAMA]") == .uygulamada)
        #expect(SiriYanitlayici.yarisSonucu("  [ARAMA]\n") == .uygulamada)
        #expect(SiriYanitlayici.yarisSonucu(Beyin.yarisAramaIsareti) == .uygulamada)
    }

    @Test func olaganYanitBicimiDuzeltilir() {
        let ham = "Mitoz bölünmedir."
        #expect(SiriYanitlayici.yarisSonucu(ham) == .yanit(YanitBicimi.duzelt(ham)))
        let utmli = "Bkz. https://ornek.com/sayfa?utm_source=x"
        #expect(SiriYanitlayici.yarisSonucu(utmli) == .yanit(YanitBicimi.duzelt(utmli)))
        // İşaret yalnız metnin başındaysa sayılır; içinde geçen "[ARAMA]" yanıttır.
        if case .yanit = SiriYanitlayici.yarisSonucu("Bunu [ARAMA] ile bulurum.") {} else { Issue.record("baştaki işaret değil") }
    }

    @Test func guncelBilgiArkaPlandaYanitlanmaz() {
        for soru in ["dün akşamki maç kaç kaç bitti", "bitcoin fiyatı ne", "Dünkü derbide golleri kim attı",
                     "Bugünkü haberler neler", "Sterlin ne kadar oldu"] {
            #expect(Beyin.guncelBilgiIstegi(soru), "\(soru)")
            #expect(!SiriYanitlayici.arkaPlandaYanitlanir(soru), "\(soru)")
        }
    }

    @Test func olaganSoruMevcutKurallaAyni() {
        for soru in ["mitoz nedir", "Mitoz ile mayoz farkı ne", "Fotosentezi iki cümleyle açıkla"] {
            #expect(!Beyin.guncelBilgiIstegi(soru), "\(soru)")
            let beklenen = CanliHizliIstemci.uygun(soru) && DusunmeSecimi.sec(soru) != .high
            #expect(SiriYanitlayici.arkaPlandaYanitlanir(soru) == beklenen, "\(soru)")
        }
        #expect(SiriYanitlayici.arkaPlandaYanitlanir("Fotosentezi iki cümleyle açıkla"))
    }

    @Test func yarisAdayiKuraliylaUyumlu() {
        // Uygulamadaki yarışa girmeyen güncel bilgi sorusu Siri'de de arka planda yanıtlanmaz.
        for soru in ["Dünkü derbide golleri kim attı", "bitcoin fiyatı ne", "Mitoz ile mayoz farkı ne"] {
            let yaris = Beyin.yarisAdayiMi(soru, kip: .sohbet, caba: DusunmeSecimi.sec(soru), ekVar: false, otomatik: true, yalnizAnahtar: false)
            #expect(SiriYanitlayici.arkaPlandaYanitlanir(soru) == yaris, "\(soru)")
        }
    }
}
