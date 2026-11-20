import Testing
import Foundation
import SwiftData
@testable import Asistan

@Suite("K3-hafiza-tetik-dosya düzeltmeleri") @MainActor
struct Duzeltme2K3hafizatetikdosyaTestleri {
    nonisolated(unsafe) private static var kaplar: [ModelContainer] = []   // context'ten uzun yaşamalı (yoksa SwiftData çöker)
    private func depo() -> HafizaDeposu {
        let k = HafizaDeposu.kapOlustur(bellekte: true); Self.kaplar.append(k)
        return HafizaDeposu(baglam: k.mainContext)
    }
    private func klasor() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appending(path: "k3-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // MARK: hafıza değer güncellemesi (bulgu 14, 49)

    @Test func degisenAdresEskisininYerineGecer() {
        let d = depo()
        let ilk = d.hatirlaZengin("Kullanıcının adresi Kadıköy", kaynak: "cikarim")
        let ikinci = d.hatirlaZengin("Kullanıcının adresi Üsküdar", kaynak: "cikarim")
        #expect(d.olgular().count == 1 && ikinci?.kimlik == ilk?.kimlik, "aynı konu, yeni değer: güncellenir")
        #expect(d.olgular().first?.metin == "Kullanıcının adresi Üsküdar")
    }

    @Test func farkliKisilerAyriKalir() {
        let d = depo()
        _ = d.hatirlaZengin("Kullanıcının kızı Ela 5 yaşında", kaynak: "cikarim")
        _ = d.hatirlaZengin("Kullanıcının oğlu Ali 8 yaşında", kaynak: "cikarim")
        #expect(d.olgular().count == 2)
        _ = d.hatirlaZengin("Kullanıcının kızı Zeynep 8 yaşında", kaynak: "cikarim")
        #expect(d.olgular().count == 3, "iki kız: ad kişinin kimliğidir, değer değil")
    }

    @Test func yalnizSayiDegisinceGuncellenir() {
        let d = depo()
        _ = d.hatirlaZengin("Kullanıcının kızı Elif 9 yaşında", kaynak: "cikarim")
        _ = d.hatirlaZengin("Kullanıcının kızı Elif 10 yaşında", kaynak: "cikarim")
        #expect(d.olgular().count == 1 && d.olgular().first?.metin.contains("10") == true)
    }

    @Test func degerGuncellemesiKurali() {
        // Güncellenir: yer adı, sayı, ayrıntı eklenen yer, tek değerli tercih.
        #expect(OlguBicimi.degerGuncellemesi("Kullanıcının adresi Kadıköy", "Kullanıcının adresi Üsküdar"))
        #expect(OlguBicimi.degerGuncellemesi("Kullanıcı Ankara'da yaşıyor", "Kullanıcı Ankara Çankaya'da yaşıyor"))
        #expect(OlguBicimi.degerGuncellemesi("Kullanıcının annesi Ankara'da yaşıyor", "Kullanıcının annesi İzmir'de yaşıyor"))
        #expect(OlguBicimi.degerGuncellemesi("Kullanıcının en sevdiği içecek kahve", "Kullanıcının en sevdiği içecek çay"))
        #expect(OlguBicimi.degerGuncellemesi("Kullanıcının kızı Elif 9 yaşında", "Kullanıcının kızı Elif 10 yaşında"))
        // Ayrı kalır: konu sözcüğü, kişi, sınıf kodu, sıra sayısı, yer bağlamı dışındaki özel ad.
        #expect(!OlguBicimi.degerGuncellemesi("Kullanıcının kızı Ela 5 yaşında", "Kullanıcının oğlu Ali 8 yaşında"))
        #expect(!OlguBicimi.degerGuncellemesi("Kullanıcı kahveyi şekersiz sever", "Kullanıcı çayı şekersiz sever"))
        #expect(!OlguBicimi.degerGuncellemesi("Kullanıcı 9-A sınıfına biyoloji dersi veriyor", "Kullanıcı 10-B sınıfına biyoloji dersi veriyor"))
        #expect(!OlguBicimi.degerGuncellemesi("Kullanıcının eşinin adı Ayşe", "Kullanıcının annesinin adı Ayşe"))
        #expect(!OlguBicimi.degerGuncellemesi("Kullanıcı 9. sınıflara biyoloji dersi veriyor", "Kullanıcı 10. sınıflara biyoloji dersi veriyor"))
        #expect(!OlguBicimi.degerGuncellemesi("Kullanıcının kızı Ela İzmir'de yaşıyor", "Kullanıcının kızı Zeynep İzmir'de yaşıyor"))
        #expect(!OlguBicimi.degerGuncellemesi("Kullanıcı Python'u sever", "Kullanıcı Swift'i sever"))
        #expect(!OlguBicimi.degerGuncellemesi("Kullanıcının en sevdiği içecek kahve", "Kullanıcının en sevdiği yemek mantı"))
        #expect(!OlguBicimi.degerGuncellemesi("Kullanıcının adresi Kadıköy", "Kullanıcının adresi Kadıköy"), "fark yoksa güncelleme değil")
    }

    @Test func belirsizDegerGuncellemesiYeniEklenir() {
        let d = depo()
        _ = d.hatirla("Kullanıcının kızı Elif 9 yaşında", kaynak: "cikarim")
        _ = d.hatirla("Kullanıcının kızı Elif 11 yaşında", kaynak: "cikarim")
        _ = d.hatirlaZengin("Kullanıcının kızı Elif 10 yaşında", kaynak: "cikarim")
        #expect(d.olgular().count == 3, "iki aday uyuyorsa hiçbiri ezilmez")
    }

    @Test func degerGuncellemesiKorumalariAsmaz() throws {
        let d = depo()
        _ = d.hatirlaZengin("Kullanıcının adresi Kadıköy", kaynak: "kullanici")
        _ = d.hatirlaZengin("Kullanıcının adresi Üsküdar", kaynak: "cikarim")
        #expect(d.olgular().count == 2, "çıkarım kullanıcının elle eklediği olguyu ezmez")
        let d2 = depo()
        let s = try #require(d2.hatirlaZengin("Kullanıcının adresi Kadıköy", kaynak: "cikarim"))
        d2.olguAyarla(s.kimlik, sabit: true)
        _ = d2.hatirlaZengin("Kullanıcının adresi Üsküdar", kaynak: "cikarim")
        #expect(d2.olgular().count == 2 && d2.olgular().contains { $0.sabit == true && $0.metin.contains("Kadıköy") })
    }

    @Test func oncekiAyrimlarKorunur() {
        let d = depo()
        let ciftler = [("Kullanıcı kahveyi şekersiz sever", "Kullanıcı çayı şekersiz sever"),
                       ("Kullanıcı 9-A sınıfına biyoloji dersi veriyor", "Kullanıcı 10-B sınıfına biyoloji dersi veriyor"),
                       ("Kullanıcının eşinin adı Ayşe", "Kullanıcının annesinin adı Ayşe")]
        for (a, b) in ciftler { _ = d.hatirlaZengin(a, kaynak: "cikarim"); _ = d.hatirlaZengin(b, kaynak: "cikarim") }
        #expect(d.olgular().count == 6)
        #expect(d.yinelenenleriBirlestir() == 0)
    }

    // MARK: geçmiş arama (bulgu 24, 71, 75)

    @Test func ftsBulgusuKesitBaslikVeRolTasir() {
        let uzun = String(repeating: "önsöz ", count: 80) + "Fotosentez ışık tepkimeleri tilakoitte olur."
        let r = HafizaIndeksi.Sonuc(tur: .mesaj, kimlik: "k1", sohbet: "s1", zaman: .now, metin: uzun, puan: 2)
        let b = GecmisArama.ftsBulgulari([r], sorgu: "fotosentez", etiketler: ["k1": .init(baslik: "Biyoloji", rol: "Asistan")])
        #expect(b.first?.sohbet == "Biyoloji" && b.first?.rol == "Asistan")
        #expect(b.first?.parca.contains("Fotosentez") == true, "kesit terimin çevresinden")
        let e = GecmisArama.ftsBulgulari([r], sorgu: "fotosentez", etiketler: [:])
        #expect(e.first?.sohbet == "Sohbet" && e.first?.rol == "")
    }

    @Test func altDizeYedegiBitisikAdiBulurVeEtiketlerCozulur() throws {
        let d = depo()
        let s = d.sohbetOlustur()
        d.ekle(.kullanici, "KitapKatalog raf haritası nasıl olmalı", sohbet: s)
        let b = d.gecmisAra("katalog", adet: 5)
        #expect(b.count == 1 && b.first?.rol == "Kullanıcı", "sözcük ortası eşleşme alt dize taramasıyla bulunur")
        let m = try #require(try d.baglam.fetch(FetchDescriptor<Mesaj>()).first)
        let e = d.mesajEtiketleri([m.kimlik.uuidString, "gecersiz"])
        #expect(e[m.kimlik.uuidString] == GecmisArama.Etiket(baslik: s.baslik, rol: "Kullanıcı"))
        #expect(e.count == 1 && d.mesajEtiketleri([]).isEmpty)
    }

    // MARK: Kestirme teslimi (bulgu 51)

    @Test func tekSeferlikYayinTeslimeKadarYinelenir() {
        #expect(GorevKopru.yayinlanmali(tekSefer: false, yayinlandi: true, teslimBildirilir: false, alindi: true), "yinelenebilir istek her turda")
        #expect(GorevKopru.yayinlanmali(tekSefer: true, yayinlandi: false, teslimBildirilir: false, alindi: false), "ilk yayın")
        #expect(!GorevKopru.yayinlanmali(tekSefer: true, yayinlandi: true, teslimBildirilir: false, alindi: false), "teslim bildirilmiyorsa tek yayın")
        #expect(GorevKopru.yayinlanmali(tekSefer: true, yayinlandi: true, teslimBildirilir: true, alindi: false), "teslim alınana kadar yinelenir")
        #expect(!GorevKopru.yayinlanmali(tekSefer: true, yayinlandi: true, teslimBildirilir: true, alindi: true), "teslimden sonra çift iş yok")
    }

    @Test func bekletiliyorYalnizKuyruktaysa() {
        #expect(GorevKopru.teslimEdilemediMetni(kuyrukta: true, cevrimdisi: true).contains("bekletiliyor"))
        #expect(!GorevKopru.teslimEdilemediMetni(kuyrukta: false, cevrimdisi: true).contains("bekletiliyor"))
        #expect(GorevKopru.teslimEdilemediMetni(kuyrukta: false, cevrimdisi: false).contains("alamadı"))
    }

    // MARK: takvim tetiği notu (bulgu 56)

    @Test func takvimNotuGorunenMetindenAyiklanir() {
        let istem = "Toplantıyı özetle (Etkinlik: Zümre)"
        #expect(Tetik.notsuz(istem + "\n" + Tetik.etkinlikNotu) == istem)
        #expect(Tetik.notsuz(istem) == nil, "notsuz istemde değişiklik yok")
        #expect(Tetik.notsuz("\n" + Tetik.etkinlikNotu) == nil)
    }

    // MARK: bozuk depo yedeği (bulgu 53)

    @Test func ayniBozukIcerikIkinciKezYedeklenmez() throws {
        let dir = try klasor(); defer { try? FileManager.default.removeItem(at: dir) }
        let p = dir.appending(path: "projeler.json")
        try Data("{bozuk".utf8).write(to: p)
        BozukDosya.sakla(p, zaman: Date(timeIntervalSince1970: 1_000))
        BozukDosya.sakla(p, zaman: Date(timeIntervalSince1970: 2_000))   // sonraki soğuk açılış
        func yedekler() throws -> Int { try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("projeler.bozuk-") }.count }
        #expect(try yedekler() == 1)
        try Data("{baska bozuk".utf8).write(to: p)
        BozukDosya.sakla(p, zaman: Date(timeIntervalSince1970: 3_000))
        #expect(try yedekler() == 2, "farklı bozuk içerik ayrıca yedeklenir")
    }

    // MARK: dosya kitaplığı yer imi tazeleme (bulgu 54, 58)

    @Test func tazelerKaldirilaniVeYenidenBaglananiEzmez() {
        let a = BagliKlasor(ad: "A", yerImi: Data([1])), b = BagliKlasor(ad: "B", yerImi: Data([2])), c = BagliKlasor(ad: "C", yerImi: Data([3]))
        let eski = [a, b, c]
        var aTaze = a; aTaze.yerImi = Data([9]); aTaze.ad = "A2"
        var bTaze = b; bTaze.yerImi = Data([8])
        var cTaze = c; cTaze.yerImi = Data([7])
        var bYeniden = b; bYeniden.yerImi = Data([5])   // arada kullanıcı yeniden bağladı
        let mevcut = [a, bYeniden]                       // arada C kaldırıldı
        let sonuc = DosyaKitapligi.tazeleriBirlestir(mevcut, taze: [aTaze, bTaze, cTaze], eski: eski)
        #expect(sonuc?.count == 2, "kaldırılan klasör geri gelmez")
        #expect(sonuc?.first { $0.id == a.id }?.yerImi == Data([9]) && sonuc?.first { $0.id == a.id }?.ad == "A2")
        #expect(sonuc?.first { $0.id == b.id }?.yerImi == Data([5]), "yeniden bağlanan ezilmez")
        #expect(DosyaKitapligi.tazeleriBirlestir(eski, taze: eski, eski: eski) == nil, "değişiklik yoksa yazım yok")
    }

    @Test func cozulemeyenYerImiTazelenmez() {
        #expect(DosyaTarayici.tazele([BagliKlasor(ad: "X", yerImi: Data([0, 1, 2]))]) == nil)
    }
}
