import Foundation
import Testing
@testable import Asistan

@Suite("A2-beyin-zincir düzeltmeleri") @MainActor
struct DuzeltmeA2BeyinZincirTestleri {
    // MARK: Paralel yarış (bulgu 0, 15)

    @Test func kazananKoparsaYarisHemenHataylaBiter() async {
        let son = ParalelYaris.Sonlandirici(adet: 3)
        await #expect(throws: ParalelYaris.Hata.self) {
            _ = try await withCheckedThrowingContinuation { (d: CheckedContinuation<ParalelYaris.Sonuc, Error>) in
                son.baslat(d)
                son.kazandi("a")                       // b ve c iptal edildi, sayaca dokunmadan çıkarlar
                son.sonuc("a", nil, hata: "a: akış tamamlanmadan koptu")
            }
        }
    }

    @Test func kazananBelliykenKaybedeninSonucuYarisiBitirmez() async throws {
        let son = ParalelYaris.Sonlandirici(adet: 3)
        let r = try await withCheckedThrowingContinuation { (d: CheckedContinuation<ParalelYaris.Sonuc, Error>) in
            son.baslat(d)
            son.kazandi("a")
            son.sonuc("b", nil, hata: "b: yanıt vermedi")
            son.sonuc("c", nil, hata: "c: HTTP 429")
            son.sonuc("a", .init(model: "a", metin: "tamam", ilkSn: 0.5), hata: nil)
        }
        #expect(r.model == "a")
        #expect(r.metin == "tamam")
    }

    @Test func kazanansizHepsiBasarisizsaHataVerir() async {
        let son = ParalelYaris.Sonlandirici(adet: 2)
        await #expect(throws: ParalelYaris.Hata.self) {
            _ = try await withCheckedThrowingContinuation { (d: CheckedContinuation<ParalelYaris.Sonuc, Error>) in
                son.baslat(d)
                son.sonuc("a", nil, hata: "a: HTTP 500")
                son.sonuc("b", nil, hata: "b: HTTP 503")
            }
        }
    }

    // MARK: Zincir bekçisi (bulgu 18) ve taze oturum geçmişi (bulgu 19)

    @Test func bekciYalnizBuDenemedekiAraclariSayar() {
        #expect(Beyin.denemeAracSayisi(toplam: 57, taban: 57) == 0)
        #expect(Beyin.denemeAracSayisi(toplam: 59, taban: 57) == 2)
        #expect(Beyin.denemeAracSayisi(toplam: 0, taban: 5) == 0)
        #expect(Beyin.bekciMutlakSiniri(aracSayisi: 0) == 90)
        #expect(Beyin.bekciMutlakSiniri(aracSayisi: 1) == 240)
        // Gün içinde önceden araç çalışmış olsa da ilk metin bütçesi (8 sn) korunur, 30 sn'ye çıkmaz.
        var bekci = AkisBekcisi(ilkMetinButcesi: 8)
        var asti = false
        for _ in 0..<16 where !asti {
            asti = bekci.adim(uzunluk: 0, aracSayisi: Beyin.denemeAracSayisi(toplam: 57, taban: 57), aracCalisiyor: false)
        }
        #expect(asti)
    }

    @Test func tazeOturumGecmisiOzetlenenleriTekrarTasimaz() {
        #expect(Beyin.tazeGecmisSiniri(mesajSayisi: 10, sikistirmaTabani: 0, ozetVar: false) == 16)
        #expect(Beyin.tazeGecmisSiniri(mesajSayisi: 40, sikistirmaTabani: 30, ozetVar: true) == 9)
        #expect(Beyin.tazeGecmisSiniri(mesajSayisi: 80, sikistirmaTabani: 20, ozetVar: true) == 16)
        #expect(Beyin.tazeGecmisSiniri(mesajSayisi: 5, sikistirmaTabani: 10, ozetVar: true) == 0)
    }

    // MARK: Emoji temizliği (bulgu 24)

    @Test func bilimselIsaretlerKorunurGercekEmojiSilinir() {
        let capraz = YanitBicimi.duzelt("♀ AaBb × ♂ aabb", zengin: true)
        #expect(capraz.contains("♀") && capraz.contains("♂"))
        #expect(YanitBicimi.duzelt("A ↔ B") == "A ↔ B")
        #expect(YanitBicimi.duzelt("Marka™").contains("™"))
        #expect(YanitBicimi.duzelt("🏃‍♀️ koştu ⚽", zengin: true) == "koştu")
    }

    // MARK: Atölye yönlendirme (bulgu 2, 20)

    @Test func ogretmenIstekleriKodVeGorselKipineDusmez() {
        #expect(AtolyeYonlendirme.yerel("Mitoz için sınıf içi uygulama hazırla") != .kod)
        #expect(AtolyeYonlendirme.yerel("Takvime yarın için program ekle") != .kod)
        #expect(AtolyeYonlendirme.yerel("Resmî tatiller için takvim oluştur") != .gorsel)
        #expect(AtolyeYonlendirme.yerel("Müdürlüğe resmi dilekçe oluştur") != .gorsel)
        #expect(AtolyeYonlendirme.yerel("Bir kedi resmi çiz") == .gorsel)
        #expect(AtolyeYonlendirme.yerel("Beyaz bir kedi resmi çiz") == .gorsel)
        #expect(AtolyeYonlendirme.yerel("Swift ile bir uygulama yaz") == .kod)
        #expect(AtolyeYonlendirme.yerel("iOS uygulama kodu yaz") == .kod)
    }

    @Test func icindeYazGecenSorularSohbetKalir() {
        for soru in ["Nutuk'u kim yazdı?", "Beyaz kan hücreleri ne işe yarar?", "Bu yazın en sıcak günü ne zamandı?",
                     "Yazılı ne zaman?", "Düzenleyici gen nedir?", "DNA'nın kısaltması ne?"] {
            #expect(AtolyeYonlendirme.yerel(soru) == .sohbet, "\(soru)")
        }
        #expect(AtolyeYonlendirme.yerel("Bunu İngilizceye çevir") == .yazi)
        #expect(AtolyeYonlendirme.yerel("Bana dilekçe yazar mısın") == .yazi)
        #expect(AtolyeYonlendirme.yerel("Bana doğum günü mesajı hazırla") == .yazi)
    }

    // MARK: Uzman seçimi (bulgu 112)

    @Test func uzmanSecimiSozcukBasinaBaglidir() {
        let test = UzmanTakimi.otomatikAdlar("10. sınıf hücre testi hazırla, PDF olsun")
        #expect(!test.contains("Kodcu"))
        #expect(test.contains("Ofis Uzmanı"))
        #expect(!UzmanTakimi.otomatikAdlar("Kodon tablosu nedir").contains("Kodcu"))
        #expect(!UzmanTakimi.otomatikAdlar("Protestan reformu nedir").contains("Kodcu"))
        #expect(UzmanTakimi.otomatikAdlar("Python kodunu yaz").contains("Kodcu"))
        #expect(UzmanTakimi.otomatikAdlar("Mitoz konusunu araştır").contains("Araştırmacı"))
        #expect(UzmanTakimi.otomatikAdlar("PDF ve Excel raporunu doğrula") == ["Ofis Uzmanı", "Denetçi"])
    }

    // MARK: Adım bütçesi (bulgu 113)

    @Test func kayitliAdimButcesiGoclaEzilmez() throws {
        let alan = "a2-butce.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: alan)); defer { d.removePersistentDomain(forName: alan) }
        let dosya = FileManager.default.temporaryDirectory.appending(path: "a2-ajan-\(UUID().uuidString).json")
        #expect(AjanDefteri(defaults: d, dosya: dosya).adimButcesi == 30)
        d.set(0, forKey: "ajan.adimButcesi")
        #expect(AjanDefteri(defaults: d, dosya: dosya).adimButcesi == 0)
        d.set(10, forKey: "ajan.adimButcesi")
        #expect(AjanDefteri(defaults: d, dosya: dosya).adimButcesi == 10)
    }

    // MARK: Live Activity bitişi (bulgu 27)

    @Test func durdurulanIsYanitHazirGostermez() {
        let normal = IsAktivitesi.bitisMetni(hata: false, durduruldu: false)
        #expect(normal.adim == "Yanıt hazır" && !normal.hata)
        let durdu = IsAktivitesi.bitisMetni(hata: false, durduruldu: true)
        #expect(durdu.adim == "Durduruldu" && durdu.hata)
        #expect(IsAktivitesi.bitisMetni(hata: true, durduruldu: true).adim.hasPrefix("Bir sorun oluştu"))
    }

    // MARK: Tanı günlüğü (bulgu 116)

    nonisolated private static func esZamanliYaz(_ adet: Int, klasor: URL) {
        DispatchQueue.concurrentPerform(iterations: adet) { i in TaniGunlugu.yaz("satır \(i)", klasor: klasor) }
    }

    @Test func taniGunluguDondurulurVeEsZamanliSatirKaybolmaz() throws {
        let klasor = FileManager.default.temporaryDirectory.appending(path: "a2-tani-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: klasor) }
        Self.esZamanliYaz(300, klasor: klasor)
        let metin = try String(contentsOf: klasor.appending(path: "tani.log"), encoding: .utf8)
        #expect(metin.split(separator: "\n").count == 300)
        // Sınır aşılınca eski günlük silinmez, tani.1.log olur; yeni dosya yeni satırla başlar.
        TaniGunlugu.yaz("son satır", klasor: klasor, sinir: 100)
        #expect(FileManager.default.fileExists(atPath: klasor.appending(path: "tani.1.log").path))
        let yeni = try String(contentsOf: klasor.appending(path: "tani.log"), encoding: .utf8)
        #expect(yeni.hasSuffix("son satır\n") && yeni.split(separator: "\n").count == 1)
    }
}
