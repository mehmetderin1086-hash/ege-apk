import Testing
import Foundation
@testable import Asistan

@Suite("H1-sohbet-ekrani düzeltmeleri")
@MainActor
struct DuzeltmeH1SohbetEkraniTestleri {

    // MARK: 50 — akış sırasında zorla kaydırma

    @Test("Alt uç yakınlığı: pay içinde ve kısa içerik altta sayılır")
    func altaYakinlik() {
        #expect(SohbetEkrani.alttaYakin(gorunurAlt: 1000, icerikBoyu: 1000))
        #expect(SohbetEkrani.alttaYakin(gorunurAlt: 930, icerikBoyu: 1000))     // 80 pt pay
        #expect(!SohbetEkrani.alttaYakin(gorunurAlt: 900, icerikBoyu: 1000))
        #expect(SohbetEkrani.alttaYakin(gorunurAlt: 800, icerikBoyu: 300))      // içerik ekrandan kısa
    }

    @Test("Takip yalnız kullanıcı kaydırırken bırakılır; alta dönünce yeniden başlar")
    func takipKarari() {
        // Kullanıcı yukarı kaydırdı: takip biter.
        #expect(SohbetEkrani.takipDurumu(onceki: true, altta: false, kullaniciKaydiriyor: true) == false)
        // İçerik büyüdü / yerleşim sıçradı (kullanıcı dokunmuyor): takip sürer.
        #expect(SohbetEkrani.takipDurumu(onceki: true, altta: false, kullaniciKaydiriyor: false) == true)
        // Yukarıda okuyan kullanıcı, yeni parçalar gelirken yukarıda kalır.
        #expect(SohbetEkrani.takipDurumu(onceki: false, altta: false, kullaniciKaydiriyor: false) == false)
        // Alta dönen her zaman takibe girer.
        #expect(SohbetEkrani.takipDurumu(onceki: false, altta: true, kullaniciKaydiriyor: true) == true)
        #expect(SohbetEkrani.takipDurumu(onceki: false, altta: true, kullaniciKaydiriyor: false) == true)
    }

    // MARK: 59 — sessizce düşen fotoğraflar

    @Test("Eksik fotoğraf notu: eksik yoksa önceki uyarı aynen kalır")
    func eksikFotoNotuEksikYok() {
        #expect(SohbetEkrani.eksikFotoNotu(0, onceki: nil) == nil)
        #expect(SohbetEkrani.eksikFotoNotu(0, onceki: "Sınır uyarısı") == "Sınır uyarısı")
    }

    @Test("Eksik fotoğraf notu: sayı yazılır, önceki uyarı korunur")
    func eksikFotoNotuEksikVar() {
        let tek = SohbetEkrani.eksikFotoNotu(1, onceki: nil)
        #expect(tek?.hasPrefix("1 fotoğraf eklenemedi") == true)
        let birlesik = SohbetEkrani.eksikFotoNotu(2, onceki: "Bir mesaja en fazla 8 görsel eklenir; fazlası eklenmedi.")
        #expect(birlesik?.hasPrefix("2 fotoğraf eklenemedi") == true)
        #expect(birlesik?.hasSuffix("fazlası eklenmedi.") == true)
    }

    // MARK: 49 — akışta baştan ayrıştırma (kararlı önek önbelleği)

    nonisolated static let ornekler: [String] = [
        "Merhaba.\n\nİkinci paragraf **kalın**.\n\n- madde 1\n- madde 2\n  devam\n\nSon satır",
        "# Başlık\n\nParagraf\n\n```swift\nlet a = 1\n\nlet b = 2\n```\n\nKod sonrası\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n---\n\n1. bir\n2. iki",
        "```\nkapanmamış çit\n\nhâlâ kod",
        "tek paragraf, boş satır yok",
        "| x | y |\n|---|---|\n| 1 | 2 |\n\nTablodan sonra\n",
        "Önce\r\n\r\nSonra\r\n- liste",
        "a\n\n\n\nb\n\n",
    ]

    @Test("Kararlı önek + kuyruk ayrıştırması tam ayrıştırmayla aynı", arguments: ornekler)
    func kararliBolumEsdeger(_ metin: String) {
        let tam = ZenginAyristirici.ayristir(metin)
        if let b = ZenginAyristirici.kararliBolum(metin) {
            #expect(ZenginAyristirici.ayristir(b.onek) + ZenginAyristirici.ayristir(b.kuyruk) == tam)
        }
        // Akış sırasında her önekte (parça parça) da aynı sonuç.
        for n in stride(from: 1, through: metin.count, by: 3) {
            let parca = String(metin.prefix(n))
            if let b = ZenginAyristirici.kararliBolum(parca) {
                #expect(ZenginAyristirici.ayristir(b.onek) + ZenginAyristirici.ayristir(b.kuyruk) == ZenginAyristirici.ayristir(parca))
            }
        }
    }

    @Test("Kod çiti içindeki boş satır bölme noktası olmaz")
    func citIciBosSatir() {
        let metin = "Giriş\n\n```\nx\n\ny"
        let b = ZenginAyristirici.kararliBolum(metin)
        #expect(b?.onek == "Giriş")
        #expect(b?.kuyruk == "```\nx\n\ny")
        #expect(ZenginAyristirici.kararliBolum("```\na\n\nb") == nil)
    }

    @Test("Önbellekli blok üretimi akışta ve bitmiş metinde doğrudan ayrıştırmayla aynı", arguments: ornekler)
    func onbellekEsdeger(_ metin: String) {
        let tam = ZenginAyristirici.ayristir(metin)
        #expect(ZenginBlokOnbellegi.bloklar(metin, akiyor: true) == tam)
        #expect(ZenginBlokOnbellegi.bloklar(metin, akiyor: false) == tam)
        #expect(ZenginBlokOnbellegi.bloklar(metin, akiyor: false) == tam)   // önbellekten
    }

    // MARK: 60 — çekmece araması

    @Test("Çekmece araması: başlık ya da normalize içerik, Türkçe harf duyarsız")
    func cekmeceEslesme() {
        let a = CekmeceGruplari.Oge(id: UUID(), baslik: "Işık ve fotosentez", son: .now, sabit: false)
        let b = CekmeceGruplari.Oge(id: UUID(), baslik: "Alışveriş", son: .now, sabit: false)
        let c = CekmeceGruplari.Oge(id: UUID(), baslik: "Boş", son: .now, sabit: false)
        let icerik = [b.id: GecmisArama.normalize("Süt, EKMEK ve çay al")]
        let ogeler = [a, b, c]
        #expect(CekmeceGorunumu.eslesenler(ogeler, icerik: icerik, sorgu: "isik") == [a.id])
        #expect(CekmeceGorunumu.eslesenler(ogeler, icerik: icerik, sorgu: "Ekmek") == [b.id])
        #expect(CekmeceGorunumu.eslesenler(ogeler, icerik: icerik, sorgu: "yok-boyle") == [])
        #expect(CekmeceGorunumu.eslesenler(ogeler, icerik: icerik, sorgu: "  ") == Set(ogeler.map(\.id)))
    }

    @Test("Çekmece araması eski eslesir kuralıyla aynı sonucu verir")
    func cekmeceEskiKuralla() {
        let o = CekmeceGruplari.Oge(id: UUID(), baslik: "Genetik çaprazlama", son: .now, sabit: false)
        let ham = "Mendel'in bezelye deneyleri ve ÇEKİNİK özellikler"
        let icerik = [o.id: GecmisArama.normalize(ham)]
        for sorgu in ["çekinik", "CEKINIK", "mendel", "genetik", "bezelye deneyleri", "fasulye"] {
            let yeni = CekmeceGorunumu.eslesenler([o], icerik: icerik, sorgu: sorgu).contains(o.id)
            #expect(yeni == CekmeceGruplari.eslesir(baslik: o.baslik, icerik: ham, sorgu: sorgu), "sorgu: \(sorgu)")
        }
    }

    // MARK: 133 — sohbet arşivi araması

    @Test("Arşiv araması: başlık ya da herhangi bir mesaj; boş sorgu hepsi")
    func arsivEslesme() {
        #expect(GecmisEkrani.eslesir(baslik: "Biyoloji", metinler: [], sorgu: ""))
        #expect(GecmisEkrani.eslesir(baslik: "Biyoloji sınavı", metinler: [], sorgu: "sınav"))
        #expect(GecmisEkrani.eslesir(baslik: "X", metinler: ["ilk", "Mitoz bölünme"], sorgu: "mitoz"))
        #expect(!GecmisEkrani.eslesir(baslik: "X", metinler: ["ilk", "ikinci"], sorgu: "mayoz"))
    }
}
