import Testing
import Foundation
import CoreGraphics
@testable import Asistan

/// P2.2: önce yerel yol (YerelKomut), sonra kalıcı çevrimdışı kuyruk (CevrimdisiKuyruk).
/// Ağ, izin ve gerçek model gerektirmez; Beyin akışı testleri ortak AgIzleyici'yi çevrimdışına alır ve geri açar.
@Suite("P2.2 çevrimdışı kuyruk ve yerel komut", .serialized)
@MainActor
struct Gelistirme_P2_2_CevrimdisiKuyrukTestleri {
    let alan = "p22.\(UUID().uuidString)"

    func geciciKlasor() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "p22-kuyruk-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    func sahteGorsel(_ renk: CGFloat = 0.5) -> CGImage {
        let c = CGContext(data: nil, width: 8, height: 6, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(red: renk, green: 0.2, blue: 0.8, alpha: 1))
        c.fill(CGRect(x: 0, y: 0, width: 8, height: 6))
        return c.makeImage()!
    }

    func beyin(kuyruk: CevrimdisiKuyruk? = nil) -> Beyin {
        let ud = UserDefaults(suiteName: alan)!
        let k = OnayKapisi(); k.otomatikKarar = false
        return Beyin(ayarlar: Ayarlar(defaults: ud), depo: HafizaDeposu(baglam: HafizaTestleri.kap.mainContext), onay: k,
                     modelVitesi: ModelVitesi(defaults: ud), kuyruk: kuyruk)
    }

    func suitiSil() { UserDefaults(suiteName: alan)?.removePersistentDomain(forName: alan) }

    func bekle(_ kosul: () -> Bool, sinir: Int = 60) async {
        for _ in 0..<sinir where !kosul() { try? await Task.sleep(for: .milliseconds(50)) }
    }

    // MARK: YerelKomut çözücü

    @Test func yerelKomutTablosu() {
        #expect(YerelKomut.coz("feneri aç") == .fener(true))
        #expect(YerelKomut.coz("Feneri kapat.") == .fener(false))
        #expect(YerelKomut.coz("el fenerini yak") == .fener(true))
        #expect(YerelKomut.coz("10 dakikalık zamanlayıcı kur") == .zamanlayici(saniye: 600, etiket: nil))
        #expect(YerelKomut.coz("on beş dakikalık zamanlayıcı") == .zamanlayici(saniye: 900, etiket: nil))
        #expect(YerelKomut.coz("30 saniyelik sayaç") == .zamanlayici(saniye: 30, etiket: nil))
        #expect(YerelKomut.coz("yarım saatlik zamanlayıcı kur") == .zamanlayici(saniye: 1800, etiket: nil))
        #expect(YerelKomut.coz("10 dakika sonra haber ver") == .zamanlayici(saniye: 600, etiket: nil))
        #expect(YerelKomut.coz("Çay için 5 dakikalık zamanlayıcı kur") == .zamanlayici(saniye: 300, etiket: "Çay"))
        #expect(YerelKomut.coz("saat 7:30 alarm kur") == .alarm(saat: 7, dakika: 30))
        #expect(YerelKomut.coz("sabah 6'da alarm kur") == .alarm(saat: 6, dakika: 0))
        #expect(YerelKomut.coz("akşam 8'e alarm kur") == .alarm(saat: 20, dakika: 0))
        #expect(YerelKomut.coz("yarın ne var") == .takvim(gun: 1))
        #expect(YerelKomut.coz("Bugün ne var?") == .takvim(gun: 0))
        #expect(YerelKomut.coz("bugünkü programım") == .takvim(gun: 0))
        #expect(YerelKomut.coz("bugün ayın kaçı") == .tarih)
        #expect(YerelKomut.coz("tarih ne") == .tarih)
    }

    @Test func yerelKomutYalnizTamEslesme() {
        #expect(YerelKomut.coz("feneri aç ve annemi ara") == nil)
        #expect(YerelKomut.coz("alarm hakkında bilgi ver") == nil)
        #expect(YerelKomut.coz("saat 25:00 alarm kur") == nil)
        #expect(YerelKomut.coz("yarın ne var ne yok anlat bakalım") == nil)
        #expect(YerelKomut.coz("mitoz bölünmeyi anlat") == nil)
        #expect(YerelKomut.coz("") == nil)
        #expect(YerelKomut.coz("yetmiş dakikalık zamanlayıcı") == nil, "yazıyla sayı yalnız 1-60")
    }

    @Test func cevrimdisiYanitlanirKarari() {
        #expect(YerelKomut.cevrimdisiYanitlanir("saat kaç"))
        #expect(YerelKomut.cevrimdisiYanitlanir("merhaba"))
        #expect(YerelKomut.cevrimdisiYanitlanir("feneri aç"))
        #expect(!YerelKomut.cevrimdisiYanitlanir("Merhaba kuyruk"))
        #expect(!YerelKomut.cevrimdisiYanitlanir("bugün hava nasıl"))
    }

    @Test func yerelKomutAracVeYanEtki() {
        #expect(YerelKomut.aracAdi(.fener(true)) == "cihaz")
        #expect(YerelKomut.aracAdi(.alarm(saat: 7, dakika: 0)) == "zamanlayici")
        #expect(YerelKomut.aracAdi(.takvim(gun: 0)) == "takvim")
        #expect(YerelKomut.aracAdi(.tarih) == nil)
        #expect(YerelKomut.yanEtkili(.zamanlayici(saniye: 60, etiket: nil)))
        #expect(!YerelKomut.yanEtkili(.takvim(gun: 1)))
    }

    @Test func alarmZamaniGecmisseYarina() throws {
        var t = Calendar(identifier: .gregorian); t.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let simdi = try #require(t.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9, minute: 0)))
        let gecmis = try #require(YerelKomut.alarmZamani(saat: 7, dakika: 30, simdi: simdi, takvim: t))
        #expect(gecmis.iso == "2026-10-21T07:30")
        let gelecek = try #require(YerelKomut.alarmZamani(saat: 18, dakika: 5, simdi: simdi, takvim: t))
        #expect(gelecek.iso == "2026-10-20T18:05")
        let a = YerelKomut.gunAraligi(gun: 1, simdi: simdi, takvim: t)
        #expect(a.baslangic == "2026-10-21T00:00")
        #expect(a.bitis == "2026-10-21T23:59")
    }

    // MARK: Kalıcı kuyruk

    @Test func kuyrukYenidenAcilistaKorunurVeSilinceGorsellerGider() throws {
        let k = geciciKlasor(); defer { try? FileManager.default.removeItem(at: k) }
        let q = CevrimdisiKuyruk(klasor: k)
        let o = q.ekle(metin: "iki fotoğraflı", gorseller: [sahteGorsel(0.1), sahteGorsel(0.9)], belge: "belge metni", canliSes: true, disKaynak: true)
        #expect(o.gorselAdlari == ["\(o.id.uuidString)-0.jpg", "\(o.id.uuidString)-1.jpg"])
        let q2 = CevrimdisiKuyruk(klasor: k)
        let y = try #require(q2.ogeler.first)
        #expect(q2.ogeler.count == 1)
        #expect(y.id == o.id && y.metin == o.metin && y.gorselAdlari == o.gorselAdlari && y.belge == "belge metni")
        #expect(y.canliSes && y.disKaynak && !y.askida)
        #expect(abs(y.zaman.timeIntervalSince(o.zaman)) < 0.01)
        #expect(q2.gorseller(y).count == 2)
        for ad in o.gorselAdlari { #expect(FileManager.default.fileExists(atPath: k.appending(path: ad).path)) }
        q2.sil(o.id)
        #expect(q2.ogeler.isEmpty)
        for ad in o.gorselAdlari { #expect(!FileManager.default.fileExists(atPath: k.appending(path: ad).path)) }
        #expect(CevrimdisiKuyruk(klasor: k).ogeler.isEmpty)
    }

    @Test func bozukKuyrukDosyasiYedeklenirKuyrukBosAcilir() throws {
        let k = geciciKlasor(); defer { try? FileManager.default.removeItem(at: k) }
        try FileManager.default.createDirectory(at: k, withIntermediateDirectories: true)
        try Data("{bozuk json".utf8).write(to: k.appending(path: "kuyruk.json"))
        let q = CevrimdisiKuyruk(klasor: k)
        #expect(q.ogeler.isEmpty)
        let adlar = try FileManager.default.contentsOfDirectory(atPath: k.path)
        #expect(adlar.contains { $0.hasPrefix("kuyruk.bozuk-") && $0.hasSuffix(".json") }, "bozuk dosya sessizce silinmemeli")
        #expect(!adlar.contains("kuyruk.json"))
    }

    @Test func eskiOgeAcilistaAskidaYuklenir() {
        let k = geciciKlasor(); defer { try? FileManager.default.removeItem(at: k) }
        let q = CevrimdisiKuyruk(klasor: k)
        q.ekle(metin: "dünden kalan", gorseller: [], belge: nil, canliSes: false, disKaynak: false, zaman: Date().addingTimeInterval(-25 * 3600))
        q.ekle(metin: "az önce", gorseller: [], belge: nil, canliSes: false, disKaynak: false)
        let q2 = CevrimdisiKuyruk(klasor: k)
        #expect(q2.ogeler.map(\.askida) == [true, false])
        #expect(q2.siradaki?.metin == "az önce")
    }

    @Test func askiyaAlVeAskidanCikar() {
        let k = geciciKlasor(); defer { try? FileManager.default.removeItem(at: k) }
        let q = CevrimdisiKuyruk(klasor: k)
        let a = q.ekle(metin: "a", gorseller: [], belge: nil, canliSes: false, disKaynak: false)
        q.ekle(metin: "b", gorseller: [], belge: nil, canliSes: false, disKaynak: false)
        q.askiyaAl()
        #expect(q.siradaki == nil)
        #expect(q.askidakiSayisi == 2)
        q.askidanCikar(a.id)
        #expect(q.siradaki?.id == a.id)
        #expect(CevrimdisiKuyruk(klasor: k).siradaki?.id == a.id, "askı durumu da kalıcı")
        q.hepsiniSil()
        #expect(CevrimdisiKuyruk(klasor: k).ogeler.isEmpty)
    }

    // MARK: Beyin akışı

    @Test func beyinTestteKendiGeciciKuyrugunuAlir() {
        defer { suitiSil() }
        let b1 = beyin(), b2 = beyin()
        #expect(b1.kuyruk !== b2.kuyruk)
        #expect(b1.kuyruk !== CevrimdisiKuyruk.ortak)
    }

    @Test func cevrimdisiYerelYolKuyrugaGirmezDigerleriGirer() async {
        defer { suitiSil() }
        let b = beyin()
        defer { b.kuyruk.hepsiniSil(); AgIzleyici.ortak.durumGuncelle(true) }
        AgIzleyici.ortak.durumGuncelle(false)
        b.gonder("saat kaç")
        #expect(b.bekleyenGonderiler.isEmpty, "yerel yanıtlanan istek kuyruğa girmemeli")
        await bekle { b.mesajlar.count >= 2 && b.durum == .bosta }
        #expect(b.mesajlar.last?.metin.hasPrefix("Saat") == true)
        b.gonder("Merhaba kuyruk")
        #expect(b.kuyruk.ogeler.count == 1)
        #expect(b.cevrimdisiNotu?.contains("Merhaba kuyruk") == true)
        b.yeniSohbet()
        #expect(b.kuyruk.ogeler.count == 1, "yeni sohbet kuyruğu silmez")
        #expect(b.bekleyenGonderiler.first?.askida == true)
        b.bekleyeniIptalEt(b.bekleyenGonderiler[0].id)
        #expect(b.bekleyenGonderiler.isEmpty)
        #expect(b.cevrimdisiNotu == nil)
    }

    @Test func yereldeYanitlanirKarari() {
        defer { suitiSil() }
        let b = beyin()
        #expect(b.yereldeYanitlanir("saat kaç", ekVar: false, disKaynak: false))
        #expect(b.yereldeYanitlanir("bugün ayın kaçı", ekVar: false, disKaynak: true), "salt okunur komut dış kaynakta da yerel")
        #expect(!b.yereldeYanitlanir("saat kaç", ekVar: true, disKaynak: false), "ekli istek kuyruğa")
        #expect(!b.yereldeYanitlanir("feneri aç", ekVar: false, disKaynak: true), "dış kaynaklı yan etkili komut kısa yoldan çalışmaz")
        #expect(!b.yereldeYanitlanir("Merhaba kuyruk", ekVar: false, disKaynak: false))
    }

    @Test func baglantiYokkenBekleyeniGonderYinelemez() {
        defer { suitiSil() }
        let b = beyin()
        defer { b.kuyruk.hepsiniSil(); AgIzleyici.ortak.durumGuncelle(true) }
        AgIzleyici.ortak.durumGuncelle(false)
        b.gonder("Bağlantı gidip gelirken")
        #expect(b.kuyruk.ogeler.count == 1)
        b.bekleyeniGonder()
        b.bekleyeniSimdiGonder(b.kuyruk.ogeler[0].id)
        #expect(b.kuyruk.ogeler.count == 1, "çevrimdışıyken gönderim denenmez, öğe yinelenmez")
        #expect(b.mesajlar.isEmpty)
    }

    @Test func kuyrugaAlKestirmeyiBekletiliyorIsaretler() async {
        await GorevKopruTestKilidi.ortak.al()   // GorevKopru.ortak tek görev izler: başka süit görevi devralmasın
        defer { GorevKopruTestKilidi.ortak.birak() }
        defer { suitiSil() }
        let b = beyin()
        defer { b.kuyruk.hepsiniSil(); AgIzleyici.ortak.durumGuncelle(true) }
        AgIzleyici.ortak.durumGuncelle(false)
        let istek = "P2.2 köprü kuyruk denemesi \(UUID().uuidString.prefix(6))"
        let gorev = Task { await GorevKopru.ortak.calistir(istek, sinir: 5) }
        await bekle { GorevKopru.ortak.beklenen == istek }
        b.gonder(istek)
        #expect(GorevKopru.ortak.kuyrukta, "Kestirmenin beklediği istek kuyruğa girince işaretlenmeli")
        let yanit = await gorev.value
        #expect(yanit == GorevKopru.teslimEdilemediMetni(kuyrukta: true, cevrimdisi: true))
    }

    @Test func kuyruktakiOgeBaglantiGelinceGiderVeSilinir() async {
        defer { suitiSil() }
        let k = geciciKlasor(); defer { try? FileManager.default.removeItem(at: k) }
        let q = CevrimdisiKuyruk(klasor: k)
        let b = beyin(kuyruk: q)
        defer { b.iptal(); AgIzleyici.ortak.durumGuncelle(true) }
        AgIzleyici.ortak.durumGuncelle(false)
        b.gonder("Merhaba kalıcı kuyruk")
        #expect(q.ogeler.count == 1)
        AgIzleyici.ortak.durumGuncelle(true)
        b.bekleyeniGonder()
        #expect(q.ogeler.isEmpty, "gönderim kabul edilince öğe silinir")
        #expect(b.mesajlar.first?.metin == "Merhaba kalıcı kuyruk")
        #expect(b.kuyruktanNesil == b.nesil)
        #expect(CevrimdisiKuyruk(klasor: k).ogeler.isEmpty)
    }

    // MARK: Şerit metni ve Siri

    @Test func seritBasligi() {
        let simdi = Date()
        func o(_ askida: Bool) -> BekleyenGonderi {
            BekleyenGonderi(id: UUID(), metin: "x", gorselAdlari: [], belge: nil, canliSes: false, disKaynak: false, zaman: simdi, askida: askida)
        }
        #expect(BekleyenlerSeridi.baslik(ogeler: [], cevrimici: false, not: nil) == "Çevrimdışı: bağlantı gelince devam edilir")
        #expect(BekleyenlerSeridi.baslik(ogeler: [o(true), o(true)], cevrimici: true, not: nil) == "Önceki sohbetten 2 mesaj bekliyor")
        #expect(BekleyenlerSeridi.baslik(ogeler: [o(false)], cevrimici: false, not: "Bağlantı yok.") == "Bağlantı yok.")
        #expect(BekleyenlerSeridi.baslik(ogeler: [o(false), o(true)], cevrimici: true, not: nil) == "2 mesaj bekliyor (1 tanesi askıda)")
        let uzun = BekleyenGonderi(id: UUID(), metin: String(repeating: "a", count: 80), gorselAdlari: [], belge: nil, canliSes: false, disKaynak: false, zaman: simdi, askida: false)
        #expect(BekleyenlerSeridi.ozet(uzun).count == 61)
    }

    @Test func siriCevrimdisiSaatiYereldeYanitlar() async {
        let ud = UserDefaults(suiteName: alan)!
        defer { suitiSil(); AgIzleyici.ortak.durumGuncelle(true) }
        AgIzleyici.ortak.durumGuncelle(false)
        let depo = HafizaDeposu(baglam: HafizaTestleri.kap.mainContext)
        let s = await SiriYanitlayici.yanitla("saat kaç", depo: depo, ayarlar: Ayarlar(defaults: ud))
        guard case .yanit(let metin) = s else { Issue.record("çevrimdışı 'saat kaç' yerelde yanıtlanmalı: \(s)"); return }
        #expect(metin.hasPrefix("Saat "))
        #expect(await SiriYanitlayici.yanitla("Merhaba kalıcı kuyruk", depo: depo, ayarlar: Ayarlar(defaults: ud)) == .uygulamada)
    }
}
