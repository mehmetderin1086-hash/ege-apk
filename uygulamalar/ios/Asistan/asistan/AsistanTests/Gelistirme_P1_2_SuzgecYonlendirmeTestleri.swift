import Testing
import Foundation
@testable import Asistan

/// P1.2: istem süzgeci hızlı yolu yavaşlatmaz (yarış adayında başlamaz), ölçülü düzeltmesi yönlendirmeye girer.
@Suite("P1.2 süzgeç yönlendirmesi")
@MainActor
struct Gelistirme_P1_2_SuzgecYonlendirmeTestleri {
    let ham = "Vav radyo kuran meali Ayhan kaya 15. Çöz indir"
    let duz = "Vav Radyo Kur'an meali Ayhan Kaya 15. cüz indir"

    // MARK: Süzgeç kararı

    @Test func yarisAdayindaSuzgecBaslamaz() {
        #expect(IstemSuzgeci.gerekliMi("bu akşam Sezen Aksu konserine gidiyorum"))
        #expect(!IstemSuzgeci.gerekliMi("bu akşam Sezen Aksu konserine gidiyorum", yarisAdayi: true))
        #expect(!IstemSuzgeci.gerekliMi(ham, yarisAdayi: true))
        // Varsayılan parametre eski davranışı korur.
        #expect(IstemSuzgeci.gerekliMi(ham))
        #expect(!IstemSuzgeci.gerekliMi("Mitoz ile mayoz farkı ne"))
    }

    // MARK: Ölçülü düzeltme

    @Test func dikteDuzeltmesiKabulEdilir() {
        #expect(IstemSuzgeci.olculuDuzeltme(ham: ham, duz: duz) == duz)
        #expect(IstemSuzgeci.olculuDuzeltme(ham: ham, duz: "  \(duz)\n") == duz)
    }

    @Test func yenidenYazilmisMetinReddedilir() {
        let uzatilmis = "Bana Kur'an mealinin on beşinci cüzünü Vav Radyo sitesinden Ayhan Kaya sesiyle bulup indirir misin lütfen"
        #expect(IstemSuzgeci.olculuDuzeltme(ham: ham, duz: uzatilmis) == nil)
        // Sözcük sayısı aynı ama içerik tümüyle başka: düzenleme uzaklığı sınırı aşılır.
        #expect(IstemSuzgeci.olculuDuzeltme(ham: ham, duz: "Yarın sabah dokuzda okul müdürüyle toplantı hatırlatması kur lütfen") == nil)
    }

    @Test func ayniVeBosMetinNilDoner() {
        #expect(IstemSuzgeci.olculuDuzeltme(ham: ham, duz: ham) == nil)
        // Yalnız büyük/küçük harf farkı düzeltme sayılmaz.
        #expect(IstemSuzgeci.olculuDuzeltme(ham: "yarın hava nasıl olacak", duz: "Yarın hava nasıl olacak") == nil)
        #expect(IstemSuzgeci.olculuDuzeltme(ham: ham, duz: "   ") == nil)
    }

    @Test func duzenlemeUzakligi() {
        #expect(IstemSuzgeci.duzenlemeUzakligi("", "abc") == 3)
        #expect(IstemSuzgeci.duzenlemeUzakligi("kitten", "sitting") == 3)
        #expect(IstemSuzgeci.duzenlemeUzakligi("coz", "cuz") == 1)
        #expect(IstemSuzgeci.duzenlemeUzakligi("ayni", "ayni") == 0)
    }

    // MARK: Yarış adayı (tek karar kopyası)

    @Test func yarisAdayiKarari() {
        #expect(Beyin.yarisAdayiMi("Mitoz ile mayoz farkı ne", kip: .sohbet, caba: .low, ekVar: false, otomatik: true, yalnizAnahtar: false))
        #expect(!Beyin.yarisAdayiMi("Dolar kaç", kip: .sohbet, caba: .low, ekVar: false, otomatik: true, yalnizAnahtar: false))
        #expect(!Beyin.yarisAdayiMi("Mitoz ile mayoz farkı ne", kip: .sohbet, caba: .low, ekVar: true, otomatik: true, yalnizAnahtar: false))
        #expect(!Beyin.yarisAdayiMi("Mitoz ile mayoz farkı ne", kip: .sohbet, caba: .high, ekVar: false, otomatik: true, yalnizAnahtar: false))
        #expect(!Beyin.yarisAdayiMi("Mitoz ile mayoz farkı ne", kip: .arastirma, caba: .low, ekVar: false, otomatik: true, yalnizAnahtar: false))
        #expect(!Beyin.yarisAdayiMi("Mitoz ile mayoz farkı ne", kip: .sohbet, caba: .low, ekVar: false, otomatik: false, yalnizAnahtar: false))
        #expect(!Beyin.yarisAdayiMi("Mitoz ile mayoz farkı ne", kip: .sohbet, caba: .low, ekVar: false, otomatik: true, yalnizAnahtar: true))
    }

    @Test func yonlendirmeKipiAtolyeyeGecmez() {
        #expect(Beyin.yonlendirmeKipi(eski: .sohbet, aday: .arastirma) == .arastirma)
        #expect(Beyin.yonlendirmeKipi(eski: .kod, aday: .sohbet) == .sohbet)
        // Atölye/kod kiplerine yeni geçiş yok; atölye kipi değişmez.
        #expect(Beyin.yonlendirmeKipi(eski: .sohbet, aday: .gorsel) == .sohbet)
        #expect(Beyin.yonlendirmeKipi(eski: .sohbet, aday: .kod) == .sohbet)
        #expect(Beyin.yonlendirmeKipi(eski: .belge, aday: .sohbet) == .belge)
    }

    // MARK: Yararın belgesi

    @Test func duzeltmeCabayiDusurur() {
        // "Çöz" sözcüğü yüksek çabaya çıkarıyordu; düzeltilmiş "cüz" çıkarmaz.
        #expect(DusunmeSecimi.sec(ham) == .high)
        #expect(DusunmeSecimi.sec(duz) != .high)
    }

    // MARK: İstek bağlamı

    @Test func istekBaglamiYonMetni() {
        let b = IstekBaglami(hamIstek: ham, gorsel: nil, belge: nil, kip: .sohbet, caba: .high, canliSes: false,
                             nesil: 1, oncekiKip: .sohbet, oncekiIstek: "", cabaAyari: "auto")
        #expect(b.yonlendirmeMetni == nil)
        #expect(b.yonMetni == ham)
        var b2 = b
        b2.yonlendirmeMetni = duz
        b2.kip = .arastirma
        b2.caba = .medium
        #expect(b2.yonMetni == duz)
        #expect(b2.kip == .arastirma && b2.caba == .medium)
        #expect(b2.hamIstek == ham)
        // Özgün bağlam değişmez.
        #expect(b.kip == .sohbet && b.caba == .high && b.yonMetni == ham)
    }
}
