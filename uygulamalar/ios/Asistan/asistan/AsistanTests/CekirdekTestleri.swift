import Testing
import Foundation
import AVFoundation
@testable import Asistan

@Suite("Model zinciri")
@MainActor
struct ModelZinciriTestleri {
    @Test func vekilOnceAnahtarSonra() {
        let z = ModelZinciri(vekilVar: true, anahtarVar: true, yalnizAnahtar: false)
        #expect(z.adimlar(model: "m").map(\.yol) == [.vekil, .anahtar])
    }
    @Test func yalnizAnahtarVekiliAtlar() {
        let z = ModelZinciri(vekilVar: true, anahtarVar: true, yalnizAnahtar: true)
        #expect(z.adimlar(model: "m").map(\.yol) == [.anahtar])
    }
    @Test func askidakiYolSonaDuser() {
        let simdi = Date()
        var z = ModelZinciri(vekilVar: true, anahtarVar: true, yalnizAnahtar: false)
        z.askiBitis[.vekil] = simdi.addingTimeInterval(600)
        #expect(z.adimlar(model: "m", simdi: simdi).map(\.yol) == [.anahtar])
        // Askı bitince geri gelir.
        #expect(z.adimlar(model: "m", simdi: simdi.addingTimeInterval(601)).map(\.yol) == [.vekil, .anahtar])
    }
    @Test func hepsiAskidaysaYineDenenir() {
        let simdi = Date()
        var z = ModelZinciri(vekilVar: true, anahtarVar: true, yalnizAnahtar: false)
        z.askiBitis[.vekil] = simdi.addingTimeInterval(600)
        z.askiBitis[.anahtar] = simdi.addingTimeInterval(600)
        #expect(z.adimlar(model: "m", simdi: simdi).count == 2)
    }
    @Test func kimlikYoksaBos() {
        let z = ModelZinciri(vekilVar: false, anahtarVar: false, yalnizAnahtar: false)
        #expect(z.adimlar(model: "m").isEmpty)
    }
    @Test func dusmeKarariIptaldeGecmez() {
        #expect(ModelZinciri.dusmeKarari(CancellationError()).gec == false)
    }
    @Test func dusmeKarariBaglantidaGecer() {
        let h = URLError(.notConnectedToInternet)
        let k = ModelZinciri.dusmeKarari(h)
        #expect(k.gec && k.askiSn <= 60)
    }
    @Test func dusmeKarariSinirdaUzunAski() {
        struct H: Error, CustomStringConvertible { var description: String { "rateLimited(resetDate: nil)" } }
        let k = ModelZinciri.dusmeKarari(H())
        #expect(k.gec && k.askiSn >= 600)
    }
}

@Suite("Cümle bölücü")
@MainActor
struct CumleBolucuTestleri {
    @Test func akanMetindenCumleler() {
        var b = CumleBolucu()
        #expect(b.yeniCumleler("Merhaba, bugün hava") == [])
        #expect(b.yeniCumleler("Merhaba, bugün hava güzel. Sıcaklık 2") == ["Merhaba, bugün hava güzel."])
        #expect(b.yeniCumleler("Merhaba, bugün hava güzel. Sıcaklık 21.5 derece. Ya") == ["Sıcaklık 21.5 derece."])
        #expect(b.kalan("Merhaba, bugün hava güzel. Sıcaklık 21.5 derece. Yağmur yok") == "Yağmur yok")
        #expect(b.kalan("Merhaba, bugün hava güzel. Sıcaklık 21.5 derece. Yağmur yok") == nil)
    }
    @Test func ondalikSayiCumleyiBolmez() {
        var b = CumleBolucu()
        #expect(b.yeniCumleler("Fiyat 12.50 lira. ") == ["Fiyat 12.50 lira."])
    }
    @Test func ondalikNoktasindaBolunenAkisSayiyiBirlikteOkur() {
        var b = CumleBolucu()
        #expect(b.yeniCumleler("Fiyat 12.") == [])
        #expect(b.yeniCumleler("Fiyat 12.50 lira. Sonraki") == ["Fiyat 12.50 lira."])
        #expect(b.kalan("Fiyat 12.50 lira. Sonraki") == "Sonraki")
    }
    @Test func sayiylaBitenCumleAkisBitinceKaybolmaz() {
        var b = CumleBolucu()
        #expect(b.yeniCumleler("Sonuç 12.") == [])
        #expect(b.kalan("Sonuç 12.") == "Sonuç 12.")
        #expect(b.kalan("Sonuç 12.") == nil)
    }
    @Test func sayidanSonraBoslukGelinceCumleOkunur() {
        var b = CumleBolucu()
        #expect(b.yeniCumleler("Sonuç 12.") == [])
        #expect(b.yeniCumleler("Sonuç 12. Devam") == ["Sonuç 12."])
    }
    @Test func okunabilirTemizler() {
        #expect(Konusmaci.okunabilir("**Kalın** ve `kod` — tamam") == "Kalın ve kod , tamam")
    }
}

@Suite("Araç yardımcıları")
@MainActor
struct AracYardimTestleri {
    @Test func isoBicimleriCozulur() {
        #expect(AracYardim.tarih("2026-10-15T18:30") != nil)
        #expect(AracYardim.tarih("2026-10-15T18:30:00") != nil)
        #expect(AracYardim.tarih("2026-10-15T18:30:00+03:00") != nil)
        #expect(AracYardim.tarih("2026-10-15") != nil)
        #expect(AracYardim.tarih("yarın") == nil)
    }
    @Test func saatsizTarihYerelGunBaslangici() {
        let d = AracYardim.tarih("2026-10-15")!
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour], from: d)
        #expect(c.year == 2026 && c.month == 10 && c.day == 15 && c.hour == 0)
    }
    @Test func aracAdlariBenzersiz() {
        let adlar = AracKaydi.adlar
        #expect(Set(adlar).count == adlar.count)
        #expect(adlar.allSatisfy { $0.range(of: "^[a-zA-Z0-9_]+$", options: .regularExpression) != nil })
    }
    @Test func havaMetniTurkce() {
        let y = HavaAraci.Yanit(
            current: .init(temperature_2m: 21.4, apparent_temperature: 20.1, relative_humidity_2m: 55, weather_code: 2, wind_speed_10m: 12.3),
            daily: .init(time: ["a", "b", "c"], temperature_2m_max: [24, 25, 23], temperature_2m_min: [14, 15, 13], weather_code: [2, 61, 0], precipitation_probability_max: [10, 70, nil]))
        let m = HavaAraci.metin(y, ad: "Ankara")
        #expect(m.contains("Ankara: şu an 21°C"))
        #expect(m.contains("Yarın: 15–25°C, yağmurlu, yağış olasılığı %70."))
        #expect(m.contains("Öbür gün"))
    }
}

@Suite("Talimatlar")
@MainActor
struct TalimatTestleri {
    @Test func sabitOnceOlgularSonda() {
        let t = Talimatlar.olustur(olgular: ["Kahveyi şekersiz içer"], simdi: Date(timeIntervalSince1970: 1_760_000_000))
        #expect(t.hasPrefix(Talimatlar.sabit))
        #expect(t.contains("- Kahveyi şekersiz içer"))
    }
    @Test func olguYoksaBelirtir() {
        #expect(Talimatlar.olustur(olgular: []).contains("henüz yok"))
    }
}

@Suite("Hafıza deposu", .serialized)
@MainActor
struct HafizaTestleri {
    /// SwiftData aynı şema için eşzamanlı birden çok kap kurulurken çöker (EXC_BREAKPOINT); tek kap paylaşılır.
    static let kap = HafizaDeposu.kapOlustur(bellekte: true)
    func depo() -> HafizaDeposu {
        let d = HafizaDeposu(baglam: Self.kap.mainContext)
        // Sohbet silinince mesajlar cascade ile gider; Mesaj'ı ayrıca toplu silmek zorunlu inverse yüzünden hata basar.
        for s in d.sonSohbetler(1000) { d.baglam.delete(s) }
        for o in d.olgular() { d.baglam.delete(o) }
        try? d.baglam.save()
        return d
    }
    @Test func hatirlaUnutListele() {
        let d = depo()
        #expect(d.hatirla("Eşinin adı Ayşe") != nil)
        #expect(d.hatirla("eşinin adı ayşe") != nil)  // kopya eklenmez
        #expect(d.olgular().count == 1)
        #expect(d.hatirla("   ") == nil)
        #expect(d.unut(iceren: "AYŞE") == 1)
        #expect(d.olgular().isEmpty)
    }
    @Test func cokUzunOlguReddedilir() {
        let d = depo()
        #expect(d.hatirla(String(repeating: "a", count: 301)) == nil)
    }
    @Test func sohbetBasligiIlkMesajdan() {
        let d = depo()
        let s = d.sohbetOlustur()
        d.ekle(.kullanici, "Yarın hava nasıl olacak İstanbul'da acaba söyler misin lütfen", sohbet: s)
        #expect(s.baslik.count <= 40)
        #expect(s.mesajlar.count == 1)
        #expect(d.sonSohbetler().first?.kimlik == s.kimlik)
    }
}

@Suite("Ayarlar")
@MainActor
struct AyarlarTestleri {
    @Test func varsayilanlarVeKalicilik() {
        let ud = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let a = Ayarlar(defaults: ud)
        #expect(a.modelKimligi == "claude-opus-5-5")
        #expect(a.sesKimligi == "azure:Elif")
        #expect(a.model == .opus55 && a.caba == "auto" && a.sesliYanit && a.webArama)
        a.modelKimligi = ModelSecimi.haiku55.rawValue
        a.caba = "high"
        let b = Ayarlar(defaults: ud)
        #expect(b.model == .haiku55 && b.caba == "high")
        #expect(ModelSecimi.haiku55.rawValue == "claude-haiku-4-5")
    }
}

@Suite("Onay kapısı")
@MainActor
struct OnayTestleri {
    @Test func otomatikKararDiyalogAcmaz() async {
        let o = OnayKapisi(); o.otomatikKarar = false
        #expect(await o.iste(baslik: "x", ayrinti: "") == false)
        #expect(o.bekleyen == nil)
    }
    @Test func yanitlaBekleyeniCozer() async {
        let o = OnayKapisi()
        let gorev = Task { await o.iste(baslik: "Kısayol?", ayrinti: "Ev modu") }
        while o.bekleyen == nil { await Task.yield() }
        #expect(o.bekleyen?.baslik == "Kısayol?")
        o.yanitla(true)
        #expect(await gorev.value == true)
        #expect(o.bekleyen == nil)
    }
    // 20 Eki 2026: ikinci onay isteği artık ilkini reddetmez, sıraya girer (FIFO).
    // Yeni davranış Duzeltme2K1onayliveTestleri.ikinciIstekIlkiniReddetmezSirayaGirer'de sınanıyor.
}

@Suite("Gömlemci ve çıkarıcı")
@MainActor
struct GomlemciTestleri {
    @Test func kosinusVeBirim() {
        let a = Gomlemci.birim([3, 4])
        #expect(abs(a[0] - 0.6) < 1e-6 && abs(a[1] - 0.8) < 1e-6)
        #expect(abs(Gomlemci.kosinus(a, a) - 1) < 1e-6)
        #expect(Gomlemci.kosinus([1, 0], [0, 1]) == 0)
        #expect(Gomlemci.kosinus([1, 0], [1]) == 0)  // boyut uyuşmazlığı güvenli
    }
    @Test func veriGidisDonus() {
        let v: [Float] = [0.1, -2, 3.5]
        #expect(Gomlemci.vektor(Gomlemci.veri(v)) == v)
    }
    @Test func cikariciDegerSuzgeci() {
        #expect(OlguCikarici.degerMi(kullanici: "Saat kaç?", asistan: "19:00") == false)
        #expect(OlguCikarici.degerMi(kullanici: "Ben kahveyi şekersiz severim, not al", asistan: "Tamam."))
        #expect(OlguCikarici.degerMi(kullanici: "Yarın hava nasıl olacak?", asistan: "Güneşli.") == false)
    }
    @Test func ilgiliVektorsuzSonOlgular() {
        let d = HafizaTestleri().depo()
        for i in 1...5 { _ = d.hatirla("Olgu \(i)") }
        let l = d.ilgili("herhangi", k: 2)
        let adlar = Set(l.map(\.metin))
        #expect((1...2).contains(l.count), "k sınırı aşılmamalı, boş dönmemeli")
        #expect(adlar.isSubset(of: Set((1...5).map { "Olgu \($0)" })))
        // Anlamsal arama kapalıyken olgulara vektör yazılmaz: her iki dalda da en yeni iki olgu döner.
        if !HafizaDeposu.anlamsalAramaAcik { #expect(adlar == ["Olgu 4", "Olgu 5"]) }
    }
    @Test func sureMetni() {
        #expect(ZamanlayiciAraci.sure(300) == "5 dakikalık")
        #expect(ZamanlayiciAraci.sure(3600) == "1 saatlik")
        #expect(ZamanlayiciAraci.sure(90) == "1 dakika 30 saniyelik")
        #expect(ZamanlayiciAraci.sure(45) == "45 saniyelik")
    }
}

@Suite("Whisper istemcisi")
@MainActor
struct WhisperTestleri {
    @Test func wavBasligiDogru() {
        let d = WhisperIstemcisi.wav([0, 0.5, -0.5, 1, -1], oran: 16000)
        #expect(d.count == 44 + 10)
        #expect(String(data: d[0..<4], encoding: .ascii) == "RIFF")
        #expect(String(data: d[8..<12], encoding: .ascii) == "WAVE")
        let oran = d[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        #expect(oran == 16000)
        let sonOrnek = d[52..<54].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) }
        #expect(sonOrnek == -32767)
    }
    @Test func yenidenOrneklemeUzunlukVeEnerjiKorur() {
        let n = 48000  // 1 sn, 48 kHz, 440 Hz sinüs
        let o = (0..<n).map { 0.3 * sin(Float($0) * 2 * .pi * 440 / 48000) }
        let y = SesTamponu.yenidenOrnekle(o, kaynakOran: 48000, hedefOran: 16000)
        #expect(abs(y.count - 16000) < 200, "uzunluk \(y.count)")
        let e1 = SesTamponu.enerji(o).rms, e2 = SesTamponu.enerji(y).rms
        #expect(abs(e1 - e2) < 0.03, "rms \(e1) → \(e2)")
        #expect(SesTamponu.yenidenOrnekle(o, kaynakOran: 16000, hedefOran: 16000).count == n)
    }
    @Test func tamponBiriktirirVeBosaltir() {
        let t = SesTamponu()
        t.ayarla(oran: 16000)
        let v: [Float] = Array(repeating: 0.1, count: 8000)
        v.withUnsafeBufferPointer { t.ekle($0) }
        #expect(abs(t.sure - 0.5) < 1e-6)
        #expect(t.al().count == 8000)
        #expect(t.sure == 0)
    }
}

@Suite("Ses enerji kapısı")
@MainActor
struct EnerjiKapisiTestleri {
    func sinyal(sn: Double, genlik: Float) -> [Float] {
        (0..<Int(sn * 16000)).map { genlik * sin(Float($0) * 2 * .pi * 220 / 16000) }
    }
    @Test func sessizlikteEvetElenir() {
        let sessiz = sinyal(sn: 1.0, genlik: 0.003)
        #expect(SesTamponu.konusmaVar(sessiz, oran: 16000, metin: "Evet") == false)
        #expect(SesTamponu.konusmaVar(sessiz, oran: 16000, metin: "Yarın hava nasıl") == false)
    }
    @Test func bosTamponKapiyiAcikBirakir() {
        #expect(SesTamponu.konusmaVar([], oran: 16000, metin: "Evet"))
    }
    @Test func int16TamponFloataCevrilir() {
        let f = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)!
        let b = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: 4)!
        b.frameLength = 4
        let p = b.int16ChannelData![0]; p[0] = 0; p[1] = 16384; p[2] = -32768; p[3] = 32767
        let t = SesTamponu(); t.ayarla(oran: 16000); t.ekle(b)
        let v = t.al()
        #expect(v.count == 4 && abs(v[1] - 0.5) < 1e-6 && v[2] == -1 && v[3] > 0.99)
    }
    @Test func kisaSureElenir() {
        #expect(SesTamponu.konusmaVar(sinyal(sn: 0.3, genlik: 0.5), oran: 16000, metin: "Yarın hava nasıl") == false)
    }
    @Test func gercekKonusmaGecer() {
        #expect(SesTamponu.konusmaVar(sinyal(sn: 1.2, genlik: 0.2), oran: 16000, metin: "Yarın hava nasıl"))
        #expect(SesTamponu.konusmaVar(sinyal(sn: 0.8, genlik: 0.2), oran: 16000, metin: "Evet"))
    }
    @Test func kisaOnayDahaYuksekEsikIster() {
        let orta = sinyal(sn: 1.0, genlik: 0.02)  // rms ≈ 0.014
        #expect(SesTamponu.konusmaVar(orta, oran: 16000, metin: "Yarın hava nasıl"))
        #expect(SesTamponu.konusmaVar(orta, oran: 16000, metin: "Evet") == false)
    }
}

@Suite("Yerel Whisper yardımcıları")
@MainActor
struct YerelWhisperTestleri {
    @Test func temizleUydurmalariEler() {
        #expect(YerelWhisper.temizle("<|tr|> Yarın hava nasıl <|endoftext|>") == "Yarın hava nasıl")
        #expect(YerelWhisper.temizle("Altyazı M.K.") == "")
        #expect(YerelWhisper.temizle("İzlediğiniz için teşekkürler.") == "")
        #expect(YerelWhisper.temizle("Teşekkürler. Yarın saat üçte toplantı var, hatırlatıcı koy lütfen, bir de hava nasıl?").count > 20)
    }
    @Test func seceneklerBenzersiz() {
        let ids = YerelWhisper.secenekler.map(\.id)
        #expect(Set(ids).count == ids.count && ids.contains(YerelWhisper.varsayilanModel))
    }
}
