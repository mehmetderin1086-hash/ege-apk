import Testing
import Foundation
import SwiftData
import UIKit
@testable import Asistan

/// P3.9: performans paketi — güç politikası, yarış genişliği, artımlı zengin metin eşitliği, küçük resim önbelleği,
/// sayfalı sohbet açılışı (sıkıştırma tabanı ve paylaşım metni), artımlı hafıza indeksi, model listesi önbelleği ve
/// açılış ölçeri. Ağ, izin ya da gerçek model gerektirmez.
@Suite("P3.9 performans paketi", .serialized)
@MainActor
struct Gelistirme_P3_9_PerformansTestleri {
    static var kaplar: [ModelContainer] = []
    let temizlik = TestTemizligi()

    func suit() -> UserDefaults { temizlik.suit("p39") }

    func depo() -> HafizaDeposu {
        let k = HafizaDeposu.kapOlustur(bellekte: true); Self.kaplar.append(k)
        return HafizaDeposu(baglam: k.mainContext)
    }

    func beyin(_ d: HafizaDeposu) -> Beyin {
        let ud = suit()
        let k = OnayKapisi(); k.otomatikKarar = false
        return Beyin(ayarlar: Ayarlar(defaults: ud), depo: d, onay: k, modelVitesi: ModelVitesi(defaults: ud))
    }

    /// `adet` mesajlık sohbet; zamanlar 1 sn arayla artar (sıra belirlenimli). `gorselli` sıradaki mesaj fotoğraf adı taşır.
    func uzunSohbet(_ d: HafizaDeposu, adet: Int = 150, gorselli: Int? = nil) -> Sohbet {
        let s = d.sohbetOlustur()
        let taban = Date(timeIntervalSinceNow: -86_400)
        for i in 0..<adet {
            let m = d.ekle(i % 2 == 0 ? .kullanici : .asistan, "Mesaj numarası \(i).", sohbet: s,
                           gorselAdlari: i == gorselli ? ["p39-yok-\(i).jpg"] : [])
            m.zaman = taban.addingTimeInterval(TimeInterval(i))
        }
        try? d.baglam.save()
        return s
    }

    // MARK: (1) güç politikası karar tablosu

    @Test func gucKararTablosu() {
        typealias G = GucPolitikasi
        for t in [ProcessInfo.ThermalState.nominal, .fair] {
            #expect(G.karar(termal: t, dusukGuc: false) == .init(bekciAraligi: .seconds(15), uyandirmaAcik: true))
            #expect(G.karar(termal: t, dusukGuc: true) == .init(bekciAraligi: .seconds(45), uyandirmaAcik: true))
        }
        #expect(G.karar(termal: .serious, dusukGuc: false) == .init(bekciAraligi: .seconds(45), uyandirmaAcik: true))
        #expect(G.karar(termal: .serious, dusukGuc: true) == .init(bekciAraligi: .seconds(45), uyandirmaAcik: false))
        #expect(G.karar(termal: .critical, dusukGuc: false) == .init(bekciAraligi: .seconds(90), uyandirmaAcik: false))
        #expect(G.karar(termal: .critical, dusukGuc: true) == .init(bekciAraligi: .seconds(90), uyandirmaAcik: false))
    }

    @Test func gucDegisimiYalnizKararDegisinceBildirilir() {
        let g = GucPolitikasi(gozle: false)
        g.guncelle(termal: .nominal, dusukGuc: false)
        var gelen: [GucPolitikasi.Karar] = []
        g.degisti = { gelen.append($0) }
        g.guncelle(termal: .fair, dusukGuc: false)          // karar aynı (15 sn, açık)
        #expect(gelen.isEmpty)
        g.guncelle(termal: .critical, dusukGuc: false)
        #expect(gelen == [.init(bekciAraligi: .seconds(90), uyandirmaAcik: false)])
        #expect(g.termalAgir)
        g.guncelle(termal: .critical, dusukGuc: false)      // değer değişmedi
        #expect(gelen.count == 1)
        let o = g.ozet(dusukVeri: false)
        #expect(o.kisitli && o.metin.contains("Hey Asistan") && o.metin.contains("kritik"))
        g.guncelle(termal: .nominal, dusukGuc: false)
        #expect(!g.ozet(dusukVeri: false).kisitli)
        #expect(g.ozet(dusukVeri: true).kisitli, "Düşük Veri yarışı teke indirir")
    }

    // MARK: (2) yarış genişliği termal / düşük güç girdileri

    @Test func yarisGenisligiTermalVeDusukGuc() {
        #expect(ParalelYaris.genislik(ayar: 3, dusukVeri: false, termalAgir: false, dusukGuc: false) == 3)
        #expect(ParalelYaris.genislik(ayar: 3, dusukVeri: false, termalAgir: true, dusukGuc: false) == 1)
        #expect(ParalelYaris.genislik(ayar: 3, dusukVeri: false, termalAgir: false, dusukGuc: true) == 2)
        #expect(ParalelYaris.genislik(ayar: 3, dusukVeri: false, termalAgir: true, dusukGuc: true) == 1)
        #expect(ParalelYaris.genislik(ayar: 1, dusukVeri: false, termalAgir: false, dusukGuc: true) == 1)
        #expect(ParalelYaris.genislik(ayar: 2, dusukVeri: true, termalAgir: false, dusukGuc: false) == 1)
    }

    // MARK: (3) artımlı zengin metin = tam ayrıştırma, her önek uzunluğunda

    @Test func artimliZenginMetinHerOnektekiTamSonucaEsit() {
        var metin = "## Karşılaştırma\nÜç model de Türkçe sohbette iyi; farklar hız ve maliyette:\n\n"
        metin += "| Model | İlk yanıt | Not |\n|---|---|---|\n| Haiku | 1,2 sn | En hızlı |\n| Sonnet | 2,1 sn | Dengeli |\n\n"
        metin += "Önerim:\n1. Günlük sohbet için Haiku\n2. Araçlı işlerde Sonnet\n   ayrıntı satırı\n\n"
        metin += "```swift\nlet model = \"claude-haiku-4-5\"\n\nprint(model)\n```\n\n"
        metin += "- Maliyeti kullanım ekranından izleyebilirsin\n- Ayarlar'dan değiştirebilirsin\n\n---\n\n"
        metin += "Son paragraf: hücre, mitoz ve mayoz arasındaki farkları kısaca özetledim; istersen tabloyu genişletirim."
        let ornek = String(metin.prefix(600))
        #expect(ornek.count >= 400)
        for k in 0...ornek.count {
            let p = String(ornek.prefix(k))
            #expect(ZenginBlokOnbellegi.bloklar(p, akiyor: true) == ZenginAyristirici.ayristir(p), "önek \(k)")
        }
    }

    // MARK: (4) küçük resim önbelleği

    @Test func kucukResimSinirliVeOnbellekten() async throws {
        let klasor = FileManager.default.temporaryDirectory.appending(path: "p39-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: klasor) }
        let url = klasor.appending(path: "buyuk.jpg")
        let bicim = UIGraphicsImageRendererFormat(); bicim.scale = 1
        let veri = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000), format: bicim).jpegData(withCompressionQuality: 0.7) { c in
            UIColor.systemTeal.setFill(); c.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
        }
        try veri.write(to: url)
        let r1 = try #require(await GorselOnbellegi.kucuk(url, kenarPx: 440))
        let cg = try #require(r1.cgImage)
        #expect(max(cg.width, cg.height) <= 440 && max(cg.width, cg.height) >= 400)
        #expect(cg.width > cg.height, "en-boy oranı korunur")
        let r2 = await GorselOnbellegi.kucuk(url, kenarPx: 440)
        #expect(r2 === r1, "ikinci çağrı önbellekten")
        #expect(await GorselOnbellegi.kucuk(klasor.appending(path: "yok.jpg"), kenarPx: 440) == nil)
        let tam = try #require(await GorselOnbellegi.tamBoy(url))
        #expect(tam.size.width * tam.scale >= 2999)
    }

    @Test func gorselAdlariVeGuvenliYol() {
        let veri = EkKalici.kodla([MesajEki(tur: .kaynaklar(["https://a.com"]))], gorselAdlari: ["a.jpg", "b.jpg"])
        #expect(EkKalici.gorselAdlari(veri) == ["a.jpg", "b.jpg"])
        #expect(EkKalici.gorselAdlari(nil).isEmpty && EkKalici.gorselAdlari(Data("bozuk".utf8)).isEmpty)
        let u = EkKalici.gorselURL("../../x.jpg")
        #expect(u.lastPathComponent == "x.jpg" && u.deletingLastPathComponent().standardizedFileURL.path == EkKalici.gorselKlasoru.standardizedFileURL.path)
    }

    @Test func yenidenUretimFotografiKaliciAdlardanBulur() {
        let resim = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20)).image { c in UIColor.red.setFill(); c.fill(CGRect(x: 0, y: 0, width: 40, height: 20)) }
        let adlar = EkKalici.gorselleriKaydet([resim])
        defer { for a in adlar { try? FileManager.default.removeItem(at: EkKalici.gorselURL(a)) } }
        let eski = Beyin.Goruntu(rol: .kullanici, metin: "📷 Bu fotoğrafta ne var?", gorselAdlari: adlar)
        #expect(Beyin.fotoVar(eski), "sayfalı açılışta resimler boş, adlar dolu: yönerge yeniden eklenmeli")
        #expect(Beyin.yenidenGorseller(eski).count == 1)
        let kayip = Beyin.Goruntu(rol: .kullanici, metin: "x", gorselAdlari: ["p39-olmayan.jpg"])
        #expect(Beyin.fotoVar(kayip) && Beyin.yenidenGorseller(kayip).isEmpty)
        #expect(!Beyin.fotoVar(Beyin.Goruntu(rol: .kullanici, metin: "düz")))
    }

    // MARK: (5) sayfalı sohbet açılışı

    @Test func sohbetSayfaliAcilirVeEskilerYuklenir() {
        let d = depo()
        let s = uzunSohbet(d, gorselli: 10)
        let b = beyin(d)
        b.sohbetiAc(s)
        #expect(b.mesajlar.count == Beyin.sohbetSayfasi && b.dahaEskiVar)
        #expect(b.mesajlar.last?.metin == "Mesaj numarası 149." && b.mesajlar.first?.metin == "Mesaj numarası 90.")
        #expect(b.dahaEskiYukle() == 60 && b.mesajlar.count == 120 && b.dahaEskiVar)
        #expect(b.dahaEskiYukle() == 30 && b.mesajlar.count == 150)
        #expect(!b.dahaEskiVar && b.dahaEskiYukle() == 0)
        #expect(b.mesajlar.map(\.metin) == (0..<150).map { "Mesaj numarası \($0)." }, "zamana göre artan sıra")
        #expect(zip(b.mesajlar, b.mesajlar.dropFirst()).allSatisfy { $0.zaman < $1.zaman })
        let g = b.mesajlar[10]
        #expect(g.resimler.isEmpty && g.gorselAdlari == ["p39-yok-10.jpg"], "fotoğraf adla taşınır, dosya okunmaz")
        b.yeniSohbet()
        #expect(!b.dahaEskiVar && b.dahaEskiYukle() == 0)
    }

    @Test func kisaSohbetteDahaEskiYok() {
        let d = depo()
        let s = uzunSohbet(d, adet: 7)
        let b = beyin(d)
        b.sohbetiAc(s)
        #expect(b.mesajlar.count == 7 && !b.dahaEskiVar)
    }

    @Test func hepsiniYuklemeAramaIcinTekSeferde() {
        let d = depo()
        let s = uzunSohbet(d)
        let b = beyin(d)
        b.sohbetiAc(s)
        #expect(b.dahaEskiYukle(hepsi: true) == 90 && b.mesajlar.count == 150 && !b.dahaEskiVar)
    }

    // MARK: (9) sıkıştırma tabanı kayması

    @Test func eskiSayfaSikistirmaTabaniniKaydirir() {
        let d = depo()
        let s = uzunSohbet(d)
        let b = beyin(d)
        b.sohbetiAc(s)
        b.ozet = "Önceki özet"; b.sikistirmaTabani = 20
        let n1 = b.dahaEskiYukle(), n2 = b.dahaEskiYukle()
        #expect(n1 + n2 == 90 && b.sikistirmaTabani == 20 + 90)
        // Taze geçmiş sınırı yüklü pencereyle tutarlı: tabandan sonraki mesajlar aynı kalır.
        #expect(Beyin.tazeGecmisSiniri(mesajSayisi: b.mesajlar.count, sikistirmaTabani: b.sikistirmaTabani, ozetVar: true)
                == Beyin.tazeGecmisSiniri(mesajSayisi: 60, sikistirmaTabani: 20, ozetVar: true))
    }

    // MARK: (10) paylaşım metni bütün sohbet

    @Test func paylasimMetniSayfaliAcilistaBileHepsini() {
        let d = depo()
        let s = uzunSohbet(d)
        let b = beyin(d)
        b.sohbetiAc(s)
        #expect(b.mesajlar.count == 60)
        let metin = d.sohbetMetni(s, gorunenAd: "Asistan")
        #expect(metin.contains("Sen:\nMesaj numarası 0.") && metin.contains("Asistan:\nMesaj numarası 149."))
        #expect(metin.components(separatedBy: "\n\n").count == 150)
    }

    // MARK: (6) artımlı hafıza indeksi

    @Test func indeksTamTaramaKarari() {
        let simdi = Date()
        let dun = simdi.addingTimeInterval(-86_400)
        typealias H = HafizaDeposu
        #expect(H.indeksTamTaramaGerekli(bayrak: false, sonTam: dun, sonZaman: dun, simdi: simdi, mesajSayisi: 100, indeksSayisi: 100) == false)
        #expect(H.indeksTamTaramaGerekli(bayrak: true, sonTam: dun, sonZaman: dun, simdi: simdi, mesajSayisi: 100, indeksSayisi: 100))
        #expect(H.indeksTamTaramaGerekli(bayrak: false, sonTam: nil, sonZaman: dun, simdi: simdi, mesajSayisi: 100, indeksSayisi: 100))
        #expect(H.indeksTamTaramaGerekli(bayrak: false, sonTam: dun, sonZaman: nil, simdi: simdi, mesajSayisi: 100, indeksSayisi: 100))
        #expect(H.indeksTamTaramaGerekli(bayrak: false, sonTam: simdi.addingTimeInterval(-8 * 86_400), sonZaman: dun, simdi: simdi, mesajSayisi: 100, indeksSayisi: 100))
        #expect(H.indeksTamTaramaGerekli(bayrak: false, sonTam: dun, sonZaman: dun, simdi: simdi, mesajSayisi: 5, indeksSayisi: 0), "indeks boşaldı")
        #expect(H.indeksTamTaramaGerekli(bayrak: false, sonTam: dun, sonZaman: dun, simdi: simdi, mesajSayisi: 200, indeksSayisi: 149))
        #expect(!H.indeksTamTaramaGerekli(bayrak: false, sonTam: dun, sonZaman: dun, simdi: simdi, mesajSayisi: 150, indeksSayisi: 100))
        // Tarama sınırını aşan depo her açılışta tam taranmaz.
        #expect(!H.indeksTamTaramaGerekli(bayrak: false, sonTam: dun, sonZaman: dun, simdi: simdi, mesajSayisi: 40_000, indeksSayisi: H.indeksTaramaSiniri - 10))
    }

    @Test func indeksArtimliSenkronYalnizYenileriEkler() async {
        let ix = HafizaIndeksi(bellekte: true)
        let ud = suit()
        let d = depo()
        let s = d.sohbetOlustur()
        for m in ["Fotosentez klorofil", "Hücre zarı seçici", "Mitoz bölünme evreleri"] { d.ekle(.kullanici, m, sohbet: s) }
        #expect(await d.indeksiSenkronla(indeks: ix, defaults: ud) == 3, "ilk senkron tam tarama")
        #expect(ud.object(forKey: HafizaDeposu.indeksSonTamTaramaAnahtari) != nil)
        d.ekle(.asistan, "Mayoz eşey hücresi", sohbet: s)
        #expect(await d.indeksiSenkronla(indeks: ix, defaults: ud) == 1, "artımlı: yalnız yeni mesaj")
        // Eski zamanlı (ör. geri yüklenen) mesaj artımlı yolda görülmez; tam tarama bayrağı onu da ekler ve bayrak silinir.
        let eski = d.ekle(.kullanici, "Eski ribozom notu", sohbet: s)
        eski.zaman = Date(timeIntervalSinceNow: -3 * 86_400); try? d.baglam.save()
        #expect(await d.indeksiSenkronla(indeks: ix, defaults: ud) == 0)
        ud.set(true, forKey: HafizaDeposu.indeksTamTaramaAnahtari)
        #expect(await d.indeksiSenkronla(indeks: ix, defaults: ud) == 1)
        #expect(ud.object(forKey: HafizaDeposu.indeksTamTaramaAnahtari) == nil, "bayrak tam taramadan sonra silinir")
        #expect(ix.kimlikler(tur: .mesaj).count == 5)
    }

    // MARK: (7) model listesi önbelleği tazeliği

    @Test func modelOnbellegiTazelikKenarlari() {
        let simdi = Date()
        let omur = TelefonProxy.modelOnbellekOmru
        #expect(!TelefonProxy.onbellekTaze(zaman: nil, hesapSayisi: 2, mevcutHesap: 2, simdi: simdi, enEski: omur))
        #expect(TelefonProxy.onbellekTaze(zaman: simdi.addingTimeInterval(-5 * 3600), hesapSayisi: 2, mevcutHesap: 2, simdi: simdi, enEski: omur))
        #expect(!TelefonProxy.onbellekTaze(zaman: simdi.addingTimeInterval(-7 * 3600), hesapSayisi: 2, mevcutHesap: 2, simdi: simdi, enEski: omur))
        // (11) hesap eklenip çıkarıldıysa liste bayat sayılır.
        #expect(!TelefonProxy.onbellekTaze(zaman: simdi.addingTimeInterval(-60), hesapSayisi: 2, mevcutHesap: 3, simdi: simdi, enEski: omur))
        #expect(!TelefonProxy.onbellekTaze(zaman: simdi.addingTimeInterval(-60), hesapSayisi: nil, mevcutHesap: 0, simdi: simdi, enEski: omur))
        #expect(!TelefonProxy.onbellekTaze(zaman: simdi.addingTimeInterval(600), hesapSayisi: 2, mevcutHesap: 2, simdi: simdi, enEski: omur), "saat geri alındıysa")
        // Sağlık ekranı açılışı: bir dakikadan eski liste yeniden sınanır.
        #expect(!TelefonProxy.onbellekTaze(zaman: simdi.addingTimeInterval(-90), hesapSayisi: 2, mevcutHesap: 2, simdi: simdi, enEski: 60))
    }

    @Test func modelOnbellegiKaydiCozulur() throws {
        let k = TelefonProxy.ModelOnbellegi(ids: ["claude-haiku-4-5", "gpt-6.1-sol"], zaman: 1_800_000_000, hesapSayisi: 3)
        let geri = try JSONDecoder().decode(TelefonProxy.ModelOnbellegi.self, from: JSONEncoder().encode(k))
        #expect(geri.ids == k.ids && geri.zaman == k.zaman && geri.hesapSayisi == 3)
    }

    // MARK: (8) açılış ölçeri

    @Test func surecBaslangiciMakul() throws {
        let b = AcilisOlcer.surecBaslangici
        #expect(b <= Date())
        // Süreç ömrüne üst sınır konmaz (uzun koşu geçerli); sysctl okunabiliyorsa önbellekteki değerle ±1 sn aynıdır.
        let cekirdek = try #require(AcilisOlcer.cekirdektenBaslangic(), "sysctl kendi sürecimizi okuyabilmeli")
        #expect(abs(b.timeIntervalSince(cekirdek)) <= 1)
        #expect(AcilisOlcer.isaretle("p39_test") == nil, "test barındırıcısında kayıt yapılmaz")
    }
}
