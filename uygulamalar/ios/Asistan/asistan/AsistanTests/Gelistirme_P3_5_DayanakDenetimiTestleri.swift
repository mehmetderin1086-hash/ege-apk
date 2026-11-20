import Foundation
import SwiftData
import Testing
@testable import Asistan

/// P3.5 kanıta dayalı yanıt: kaynak dayanağı, teslim edilmeyen işler, kanıt tamponu, denetim notunun kalıcılığı (ağ/izin/model gerekmez).
@Suite("P3.5 dayanak denetimi", .serialized)
@MainActor
struct Gelistirme_P3_5_DayanakDenetimiTestleri {
    // MARK: dayanaksizlar

    @Test func saatAyiriciFarkiDayanakSayilir() {
        #expect(DayanakDenetimi.dayanaksizlar(yanit: "Son otobüs saat 19.45'te kalkıyor.", kanit: "[iett] Kalkış 19:45", soru: "son otobüs kaçta").isEmpty)
    }

    @Test func binlikAyiriciFarkiDayanakSayilir() {
        #expect(DayanakDenetimi.dayanaksizlar(yanit: "Toplam ücret 1.250 TL.", kanit: "[webAra] Fiyat 1250 TL", soru: "fiyat ne").isEmpty)
    }

    @Test func kanittaOlmayanSayiVeAdlarEnCokIkiTane() {
        let b = DayanakDenetimi.dayanaksizlar(yanit: "Listede Ahmet Yılmaz 2.400 TL ödemiş, Ayşe Demir 900 TL.", kanit: "[gelenKutusu] Mehmet 1.200", soru: "kim ne ödedi")
        #expect(b.count == 2)
        #expect(b == ["2.400", "900"])
        // Atıf ve ortak sayı yoksa yanıt model bilgisinden gelmiştir: uydurma sayılmaz.
        #expect(DayanakDenetimi.dayanaksizlar(yanit: "Ahmet Yılmaz 2.400 TL ödemiş.", kanit: "[gelenKutusu] Mehmet 1.200", soru: "").isEmpty)
    }

    @Test func kanitBossaBos() {
        #expect(DayanakDenetimi.dayanaksizlar(yanit: "Listede Ahmet Yılmaz 2.400 TL ödemiş.", kanit: "", soru: "").isEmpty)
        #expect(DayanakDenetimi.dayanaksizlar(yanit: "Listede Ahmet Yılmaz 2.400 TL ödemiş.", kanit: "  \n", soru: "").isEmpty)
    }

    @Test func cumleBasiVeAyAdiAtlanir() {
        let kanit = "[takvim] Toplantı 12 Kasım 14:30, salon B"
        #expect(DayanakDenetimi.dayanaksizlar(yanit: "Toplantı 12 Kasım saat 14.30'da. Salonu hazırladılar.", kanit: kanit, soru: "toplantı ne zaman").isEmpty)
        #expect(DayanakDenetimi.dayanaksizlar(yanit: "Toplantı 12 Kasım 14.30'da, konuşmacı Elif Kaya.", kanit: kanit, soru: "toplantı ne zaman") == ["Elif", "Kaya"])
    }

    @Test func sorudaGecenSayiAtlanir() {
        let yanit = "Sorduğun 34 numaralı hat için sefer 19:45."
        #expect(DayanakDenetimi.dayanaksizlar(yanit: yanit, kanit: "[iett] Sefer 19:45", soru: "34 numaralı otobüs ne zaman").isEmpty)
        #expect(DayanakDenetimi.dayanaksizlar(yanit: yanit, kanit: "[iett] Sefer 19:45", soru: "otobüs ne zaman") == ["34"])
    }

    @Test func listeNumarasiVeTekHaneAtlanir() {
        let yanit = "Kaynakta şunlar var:\n12. madde 19:45\n3) 5 kişi"
        #expect(DayanakDenetimi.dayanaksizlar(yanit: yanit, kanit: "[webAra] 19:45", soru: "").isEmpty)
    }

    @Test func yalnizSaatAraciKanitSayilmaz() {
        let t = KanitTamponu()
        t.ekle(arac: "suankiSaat", cikti: "Şu an 20 Ekim 2026 Salı 14:05")
        #expect(t.metin.isEmpty)
        #expect(!KanitTamponu.veriAraclari.contains("suankiSaat"))
        #expect(DayanakDenetimi.dayanaksizlar(yanit: "Listede 2026 yılında Ahmet Yılmaz 2.400 TL ödemiş.", kanit: t.metin, soru: "").isEmpty)
    }

    // MARK: yapilmayanlar

    @Test func yapilmayanTeslimBulunur() {
        let y = DayanakDenetimi.yapilmayanlar(teslimler: ["PDF dosyası", "takvime ekleme"], plan: [], basariliAraclar: ["ofisBelgesiOlustur"])
        #expect(y == ["takvime ekleme"])
        #expect(DayanakDenetimi.yapilmayanSatiri(y) == "\n\nYapılmayan: takvime ekleme")
        #expect(DayanakDenetimi.yapilmayanSatiri([]) == nil)
    }

    @Test func planMaddesiBittiyseTeslimSayilir() {
        let plan = [PlanMaddesi(metin: "PDF dosyası", durum: .bitti), PlanMaddesi(metin: "takvime ekleme", durum: .bitti)]
        #expect(DayanakDenetimi.yapilmayanlar(teslimler: ["PDF dosyası", "takvime ekleme"], plan: plan, basariliAraclar: []).isEmpty)
        let yarim = [PlanMaddesi(metin: "PDF dosyası", durum: .suruyor)]
        #expect(DayanakDenetimi.yapilmayanlar(teslimler: ["PDF dosyası"], plan: yarim, basariliAraclar: []) == ["PDF dosyası"])
    }

    @Test func veliyeMesajIletisimleTeslim() {
        #expect(DayanakDenetimi.yapilmayanlar(teslimler: ["veliye mesaj"], plan: [], basariliAraclar: ["iletisim"]).isEmpty)
        #expect(DayanakDenetimi.yapilmayanlar(teslimler: ["veliye mesaj"], plan: [], basariliAraclar: ["altAjanlar"]).isEmpty)
        // Yalnız gönderme sözcükleri iletişim sayılır; "veliye mesaj yaz" taslaktır, "Yapılmayan" satırı üretmez.
        #expect(DayanakDenetimi.yapilmayanlar(teslimler: ["veliye mesaj yaz"], plan: [], basariliAraclar: []).isEmpty)
        #expect(DayanakDenetimi.yapilmayanlar(teslimler: ["veliye mesaj gönder"], plan: [], basariliAraclar: ["takvim"]) == ["veliye mesaj gönder"])
        #expect(DayanakDenetimi.yapilmayanlar(teslimler: ["veliye mesaj gönder"], plan: [], basariliAraclar: ["iletisim"]).isEmpty)
    }

    @Test func bilinmeyenTeslimYapilmayanSayilmaz() {
        #expect(DayanakDenetimi.teslimAraclari("sunum") == nil)
        #expect(DayanakDenetimi.yapilmayanlar(teslimler: ["sunum"], plan: [], basariliAraclar: []).isEmpty)
    }

    @Test func teslimAracEslemesi() {
        #expect(DayanakDenetimi.teslimAraclari("Excel tablosu") == ["excelOlustur"])
        #expect(DayanakDenetimi.teslimAraclari("tablo dosyası") == ["excelOlustur"])
        #expect(DayanakDenetimi.teslimAraclari("Word belgesi") == ["ofisBelgesiOlustur"])
        #expect(DayanakDenetimi.teslimAraclari("yarın için hatırlatıcı") == ["hatirlatici", "zamanlayici"])
        // Gönderme sözcüğü olmayan teslim ("e-posta taslağı") iletişim aracı gerektirmez; model metni yazabilir.
        #expect(DayanakDenetimi.teslimAraclari("e-posta") == nil)
        #expect(DayanakDenetimi.teslimAraclari("e-postayı gönder") == ["iletisim"])
        #expect(DayanakDenetimi.teslimAraclari("videoyu indir") == ["indirmeler"])
        #expect(DayanakDenetimi.teslimAraclari("notu kaydet") == ["hafiza", "calismaAlani"])
    }

    // MARK: KanitTamponu

    @Test func uzunCiktiKisalirVeEskiGirdiDuser() {
        let t = KanitTamponu()
        t.ekle(arac: "webAra", cikti: String(repeating: "a", count: 2000))
        #expect(t.girdiler.first?.cikti.count == 1500)
        t.temizle()
        for i in 1...9 { t.ekle(arac: "webAra", cikti: "girdi \(i)") }
        #expect(t.girdiler.count == 8)
        #expect(t.girdiler.first?.cikti == "girdi 2")
        #expect(t.metin.hasPrefix("[webAra] girdi 2"))
    }

    @Test func toplamSinirAsilincaEskilerDuser() {
        let t = KanitTamponu()
        for _ in 1...6 { t.ekle(arac: "webSayfaOku", cikti: String(repeating: "b", count: 1500)) }
        #expect(t.girdiler.reduce(0) { $0 + $1.cikti.count } <= KanitTamponu.toplamSinir)
        #expect(t.girdiler.count == 5)
    }

    // MARK: Kalıcılık

    @Test func kontrolNotuKaliciYazilir() throws {
        let depo = HafizaDeposu(baglam: HafizaTestleri.kap.mainContext)
        let s = depo.sohbetOlustur()
        let m = depo.ekle(.asistan, "Yanıt", sohbet: s)
        #expect(m.kontrol == nil)
        depo.kontrolYaz(m.kimlik, "Denetim: düzeltme")
        let kimlik = m.kimlik
        let bulunan = try depo.baglam.fetch(FetchDescriptor<Mesaj>(predicate: #Predicate { $0.kimlik == kimlik })).first
        #expect(bulunan?.kontrol == "Denetim: düzeltme")
        depo.kontrolYaz(UUID(), "yok")   // olmayan kimlik sessizce geçer
        depo.sohbetSil(s)
    }

    @Test func beyinNotuKaliciYazarVeSonYanittaHaberVerir() {
        let alan = "p35-\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: alan)!
        defer { ud.removePersistentDomain(forName: alan) }
        let k = OnayKapisi(); k.otomatikKarar = false
        let depo = HafizaDeposu(baglam: HafizaTestleri.kap.mainContext)
        let b = Beyin(ayarlar: Ayarlar(defaults: ud), depo: depo, onay: k, modelVitesi: ModelVitesi(defaults: ud))
        let s = depo.sohbetOlustur()
        let ilk = depo.ekle(.asistan, "Birinci", sohbet: s), son = depo.ekle(.asistan, "İkinci", sohbet: s)
        b.mesajlar = [Beyin.Goruntu(rol: .asistan, metin: "Birinci", kayitKimligi: ilk.kimlik),
                      Beyin.Goruntu(rol: .asistan, metin: "İkinci", kayitKimligi: son.kimlik)]
        var gelen: [String] = []
        b.kontrolGeldi = { gelen.append($0) }
        b.kontrolNotuEkle(b.mesajlar[0].id, "Hesap kontrolü: 2 + 2 = 5 yanlış; doğrusu 4")
        #expect(gelen.isEmpty, "son yanıt olmayan mesajda haber verilmez")
        b.kontrolNotuEkle(b.mesajlar[1].id, "Denetim: a")
        b.kontrolNotuEkle(b.mesajlar[1].id, "Kaynakta bulunamadı: 34")
        #expect(gelen == ["Denetim: a", "Kaynakta bulunamadı: 34"])
        #expect(son.kontrol == "Denetim: a\nKaynakta bulunamadı: 34")
        #expect(ilk.kontrol?.hasPrefix("Hesap kontrolü:") == true)
        depo.sohbetSil(s)
    }

    @Test func duzeltilebilirNotYalnizDenetimVeHesapta() {
        #expect(Beyin.duzeltilebilirNot("Denetim: 46 kromozom"))
        #expect(Beyin.duzeltilebilirNot("Kaynakta bulunamadı: 34\nHesap kontrolü: 2 + 2 = 5 yanlış"))
        #expect(!Beyin.duzeltilebilirNot("Oylama: 3 modelin 3'ü B şıkkında uzlaştı."))
        #expect(!Beyin.duzeltilebilirNot("Kaynakta bulunamadı: Elif"))
        #expect(!Beyin.duzeltilebilirNot(nil))
    }

    // MARK: Plan ve süzgeç

    @Test func planUygulamaNesliTemizleIleSifirlanir() {
        let p = PlanDefteri()
        #expect(p.uygulamaPlaniKurabilir)
        p.olustur(["PDF dosyası", "takvime ekleme"], uygulamaNesli: 7)
        #expect(p.uygulamaNesli == 7)
        #expect(p.bekleyenler == ["PDF dosyası", "takvime ekleme"])
        p.temizle()
        #expect(p.uygulamaNesli == nil)
        p.olustur(["a", "b"])   // model kendisi kurdu
        #expect(p.uygulamaNesli == nil)
        #expect(!p.uygulamaPlaniKurabilir, "modelin süren planı ezilmez")
        p.durumVer(sira: 1, durum: .bitti); p.durumVer(sira: 2, durum: .bitti)
        #expect(p.uygulamaPlaniKurabilir)
    }

    @Test func suzgecTeslimListesi() {
        var c = IstemSuzgeci.Cozumleme(duzeltilmisIstek: "x", niyet: "", kisitlar: [], belirsizlikler: [], dogrulama: "", soruGerekli: false)
        #expect(IstemSuzgeci.teslimListesi(c).isEmpty)
        c.teslimler = [" PDF dosyası ", "", "takvime ekleme", "a", "b", "c", "d"]
        #expect(IstemSuzgeci.teslimListesi(c) == ["PDF dosyası", "takvime ekleme", "a", "b", "c"])
    }
}
