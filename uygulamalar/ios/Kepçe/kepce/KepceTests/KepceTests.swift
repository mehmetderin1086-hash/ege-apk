import Foundation
import Testing
@testable import Kepce

@MainActor struct BicimSeciciTests {
    private func bilgi(_ bicimler: [Bicim], sure: Double = 600) -> MedyaBilgisi {
        var json: [String: Any] = ["kind": "video", "title": "Deneme", "duration": sure]
        json["formats"] = []
        var b = try! JSONDecoder().decode(MedyaBilgisi.self, from: JSONSerialization.data(withJSONObject: json))
        b.formats = bicimler
        return b
    }

    private var youtube: [Bicim] {[
        Bicim(formatID: "sb0", ext: "mhtml", vcodec: "none", acodec: "none", protokol: "mhtml"),
        Bicim(formatID: "139", ext: "m4a", vcodec: "none", acodec: "mp4a.40.5", abr: 48, filesize: 3_000_000),
        Bicim(formatID: "140-drc", ext: "m4a", vcodec: "none", acodec: "mp4a.40.2", abr: 129, filesize: 10_000_000),
        Bicim(formatID: "140", ext: "m4a", vcodec: "none", acodec: "mp4a.40.2", abr: 129, filesize: 10_000_000),
        Bicim(formatID: "251", ext: "webm", vcodec: "none", acodec: "opus", abr: 135, filesize: 10_100_000),
        Bicim(formatID: "18", ext: "mp4", vcodec: "avc1.42001E", acodec: "mp4a.40.2", height: 360, fps: 30, filesize: 28_000_000),
        Bicim(formatID: "134", ext: "mp4", vcodec: "avc1.4D401E", acodec: "none", height: 360, fps: 30, filesize: 18_000_000),
        Bicim(formatID: "230", ext: "mp4", vcodec: "avc1.4D401E", acodec: "none", height: 360, fps: 30, protokol: "m3u8_native"),
        Bicim(formatID: "298", ext: "mp4", vcodec: "avc1.4D4020", acodec: "none", height: 720, fps: 60, filesize: 150_000_000),
        Bicim(formatID: "299", ext: "mp4", vcodec: "avc1.64002A", acodec: "none", height: 1080, fps: 60, filesize: 257_000_000),
        Bicim(formatID: "399", ext: "mp4", vcodec: "av01.0.09M.08", acodec: "none", height: 1080, fps: 60, filesize: 124_000_000),
        Bicim(formatID: "303", ext: "webm", vcodec: "vp9", acodec: "none", height: 1080, fps: 60, filesize: 168_000_000),
        Bicim(formatID: "401", ext: "mp4", vcodec: "av01.0.13M.08", acodec: "none", height: 2160, fps: 60, filesize: 712_000_000),
        Bicim(formatID: "315", ext: "webm", vcodec: "vp9", acodec: "none", height: 2160, fps: 60, filesize: 1_362_000_000),
    ]}

    @Test func videoPlanH264VeAACSecer() throws {
        let b = bilgi(youtube)
        let plan = try #require(BicimSecici.plan(b, tur: .video, enFazla: 1080, av1: false))
        #expect(plan.video?.formatID == "299" && plan.ses?.formatID == "140" && plan.uzanti == "mp4")
        #expect(plan.tahminiBoyut == 267_000_000)
        #expect(plan.etiket.hasPrefix("1080p60"))
        // AV1 donanımı yoksa 2160p listelenmez; varsa listelenir.
        #expect(BicimSecici.kaliteler(b, av1: false).map(\.id) == ["1080p60", "720p60", "360p"])
        #expect(BicimSecici.kaliteler(b, av1: true).first?.id == "2160p60")
        // 1080p'de H.264 AV1'den önce gelir.
        #expect(BicimSecici.kaliteler(b, av1: true).first { $0.id == "1080p60" }?.video.formatID == "299")
        // 360p'de ayrı (sessiz) DASH akışı HLS'den ve tek dosyadan önce gelir.
        #expect(BicimSecici.kaliteler(b, av1: false).last?.video.formatID == "134")
    }

    @Test func dusukSinirVeSecilenKalite() throws {
        let b = bilgi(youtube)
        #expect(BicimSecici.plan(b, tur: .video, enFazla: 480, av1: false)?.video?.formatID == "134")
        #expect(BicimSecici.plan(b, tur: .video, enFazla: 144, av1: false)?.video?.formatID == "134")   // sınırın altında kalite yoksa en düşüğü
        #expect(BicimSecici.plan(b, tur: .video, kaliteID: "720p60", av1: false)?.video?.formatID == "298")
    }

    @Test func sesPlaniAACveDRCsiz() throws {
        let plan = try #require(BicimSecici.plan(bilgi(youtube), tur: .ses))
        #expect(plan.ses?.formatID == "140" && plan.video == nil && plan.uzanti == "m4a")
        #expect(BicimSecici.sesler(bilgi(youtube)).map(\.formatID) == ["140", "140-drc", "139"])
    }

    @Test func cokDilliSes() {
        let bicimler = [
            Bicim(formatID: "140-0", ext: "m4a", vcodec: "none", acodec: "mp4a.40.2", abr: 129, language: "en", languagePreference: 10),
            Bicim(formatID: "140-1", ext: "m4a", vcodec: "none", acodec: "mp4a.40.2", abr: 129, language: "tr", languagePreference: -1),
        ]
        let b = bilgi(bicimler)
        #expect(BicimSecici.diller(b) == ["en", "tr"])
        #expect(BicimSecici.plan(b, tur: .ses)?.ses?.formatID == "140-0")
        #expect(BicimSecici.plan(b, tur: .ses, dil: "tr")?.ses?.formatID == "140-1")
    }

    @Test func hamVeKodeksizSiteler() throws {
        let ham = try #require(BicimSecici.plan(bilgi(youtube), tur: .ham))
        #expect(ham.video?.formatID == "18")   // yt-dlp sırasında en iyi sesli tek dosya
        // Kodek bilgisi vermeyen bir site: MP4 sesli tek dosya varsayılır.
        let site = bilgi([Bicim(formatID: "hd", ext: "mp4", vcodec: nil, acodec: nil, height: 720)])
        let plan = try #require(BicimSecici.plan(site, tur: .video))
        #expect(plan.video?.formatID == "hd" && plan.ses == nil)
        #expect(BicimSecici.plan(site, tur: .ses)?.video?.formatID == "hd")   // ses videodan ayrılır
        // Yalnız WebM sunan site: video planı yok, özgün dosya var.
        let webm = bilgi([Bicim(formatID: "w", ext: "webm", vcodec: "vp9", acodec: "opus", height: 720)])
        #expect(BicimSecici.plan(webm, tur: .video) == nil && BicimSecici.plan(webm, tur: .ham)?.uzanti == "webm")
    }

    @Test func boyutVeSureMetinleri() {
        #expect(BicimSecici.sureMetni(3725) == "1:02:05" && BicimSecici.sureMetni(65) == "1:05")
        #expect(BicimSecici.boyutMetni(nil) == "—")
    }
}

@MainActor struct AyristirmaTests {
    @Test func motorJSONunuOkur() throws {
        let json = """
        {"kind":"video","id":"x","title":"Başlık","duration":12.5,"view_count":1000,"chapters":[{"start_time":0,"end_time":5,"title":"Giriş"}],
         "formats":[{"format_id":"140","ext":"m4a","vcodec":"none","acodec":"mp4a.40.2","abr":129.5,"filesize":1234,"url":"https://a/b",
                     "protocol":"https","http_headers":{"User-Agent":"UA","Accept-Language":"en-us,en;q=0.5"},"downloader_options":{"http_chunk_size":10485760}}],
         "subtitles":{"tr":[{"ext":"vtt","url":"https://s"}]},"automatic_captions":{},"log":[]}
        """
        let b = try PythonMotoru.ayristir(json)
        #expect(b.title == "Başlık" && b.duration == 12.5 && b.viewCount == 1000 && b.chapters?.first?.title == "Giriş")
        let f = try #require(b.formats?.first)
        #expect(f.chunkSize == 10_485_760 && f.httpHeaders?["User-Agent"] == "UA" && f.protokol == "https" && f.abr == 129.5)
        #expect(f.sesVar && !f.videoVar && f.dogrudan)
        let geri = try JSONDecoder().decode(Bicim.self, from: JSONEncoder().encode(f))
        #expect(geri == f)
        #expect(throws: PythonMotoru.Hata.self) { try PythonMotoru.ayristir(#"{"kind":"error","error":"ERROR: Private video"}"#) }
        #expect(PythonMotoru.anlasilir("Sign in to confirm you're not a bot").contains("oturum doğrulaması"))
    }

    @Test func aralikBasligiVeParcaDurumu() {
        #expect(AralikBasligi("bytes 0-1023/4096") == AralikBasligi("bytes 0-1023/4096"))
        let a = AralikBasligi("bytes 100-199/*")
        #expect(a?.baslangic == 100 && a?.bitis == 199 && a?.toplam == nil)
        #expect(AralikBasligi("çöp") == nil)
        var d = ParcaDurumu(toplam: 25, parca: 10, tamam: [])
        #expect(d.sayi == 3 && d.aralik(2) == 20...24 && d.kalan == [0, 1, 2])
        d.tamam = [0, 2]
        #expect(d.alinan == 15 && d.kalan == [1])
    }

    @Test func hlsListesi() throws {
        let taban = URL(string: "https://cdn.ornek.com/v/liste.m3u8")!
        let medya = """
        #EXTM3U
        #EXT-X-MEDIA-SEQUENCE:7
        #EXT-X-MAP:URI="init.mp4"
        #EXT-X-KEY:METHOD=AES-128,URI="https://k/anahtar",IV=0x000102030405060708090a0b0c0d0e0f
        #EXTINF:4.0,
        seg1.m4s
        #EXT-X-KEY:METHOD=NONE
        #EXT-X-BYTERANGE:1000@0
        #EXTINF:4.0,
        tek.mp4
        #EXT-X-BYTERANGE:500
        #EXTINF:4.0,
        tek.mp4
        """
        let l = HLSListesi(metin: medya, taban: taban)
        #expect(l.baslangic?.adres.absoluteString == "https://cdn.ornek.com/v/init.mp4")
        #expect(l.bolutler.count == 3 && l.sifreleme == .aes128)
        #expect(l.bolutler[0].anahtar?.absoluteString == "https://k/anahtar" && l.bolutler[0].iv?.count == 16)
        #expect(l.bolutler[1].anahtar == nil && l.bolutler[1].aralik == 0...999 && l.bolutler[2].aralik == 1000...1499)
        let ana = HLSListesi(metin: "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=800000\nlow.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=3000000\nhigh.m3u8\n", taban: taban)
        #expect(ana.enIyiVaryant?.lastPathComponent == "high.m3u8" && ana.bolutler.isEmpty)
        #expect(AkisIndirici.sira(1) == Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]))
    }

    @Test func aesCozumu() throws {
        // CommonCrypto ile şifrele, aynı anahtar/IV ile çöz.
        let anahtar = Data(repeating: 7, count: 16), iv = Data(repeating: 1, count: 16)
        let metin = Data("Kepçe HLS bölütü".utf8)
        var sifreli = Data(count: metin.count + 16)
        var uzunluk = 0
        _ = sifreli.withUnsafeMutableBytes { c in metin.withUnsafeBytes { m in anahtar.withUnsafeBytes { a in iv.withUnsafeBytes { i in
            CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), a.baseAddress, 16, i.baseAddress, m.baseAddress, metin.count, c.baseAddress, c.count, &uzunluk)
        } } } }
        #expect(try AkisIndirici.aesCoz(sifreli.prefix(uzunluk), anahtar: anahtar, iv: iv) == metin)
    }

    @Test func altyaziTemizligi() {
        let vtt = """
        WEBVTT
        Kind: captions

        00:00:00.000 --> 00:00:02.000 align:start position:0%
        merhaba<00:00:00.500><c> dünya</c>

        00:00:02.000 --> 00:00:02.010 align:start position:0%
        merhaba dünya

        00:00:02.010 --> 00:00:04.000 align:start position:0%
        merhaba dünya
        bugün &amp; yarın
        """
        let satirlar = Altyazi.vtt(vtt)
        #expect(satirlar.map(\.metin) == ["merhaba dünya", "bugün & yarın"])
        let srt = Altyazi.srtMetni(satirlar)
        #expect(srt.hasPrefix("1\n00:00:00,000 --> 00:00:02,010\nmerhaba dünya"))
        #expect(Altyazi.srt(srt).map(\.metin) == satirlar.map(\.metin))
        #expect(Altyazi.zaman("01:02:03.500") == 3723.5 && Altyazi.zaman("00:01,250") == 1.25)
    }

    @Test func dosyaAdlariVeBaglantilar() throws {
        #expect(Kutuphane.temizAd("  Ders 1: Hücre / Zar?  ") == "Ders 1 Hücre Zar")
        #expect(Kutuphane.temizAd("...") == "Kepçe")
        let klasor = FileManager.default.temporaryDirectory.appending(path: "kepce-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: klasor) }
        let ilk = Kutuphane.benzersiz("Ad", uzanti: "mp4", klasor: klasor)
        FileManager.default.createFile(atPath: ilk.path, contents: Data())
        #expect(Kutuphane.benzersiz("Ad", uzanti: "mp4", klasor: klasor).lastPathComponent == "Ad (2).mp4")
        #expect(PaylasimKutusu.adresBul("Şuna bak https://youtu.be/abc?si=1 harika") == "https://youtu.be/abc?si=1")
        #expect(PaylasimKutusu.adresBul("bağlantı yok") == nil)
        #expect(ListeOgesi(id: "aqz-KE-bpKQ", title: nil, url: nil).adres == "https://www.youtube.com/watch?v=aqz-KE-bpKQ")
    }
}

@MainActor struct TopluTests {
    @Test func videoAnahtariAyniVideoyuTanir() {
        let a = IndirmeKuyrugu.anahtar("https://www.youtube.com/watch?v=aqz-KE-bpKQ&t=10")
        #expect(a == "yt:aqz-KE-bpKQ")
        #expect(IndirmeKuyrugu.anahtar("https://youtu.be/aqz-KE-bpKQ?si=x") == a)
        #expect(IndirmeKuyrugu.anahtar("https://m.youtube.com/shorts/aqz-KE-bpKQ") == a)
        #expect(IndirmeKuyrugu.anahtar("https://vimeo.com/123?x=1") == "vimeo.com/123")
    }

    @Test func listeAdresleri() {
        #expect(ListeAdresi.listeMi("https://www.youtube.com/playlist?list=PL1"))
        #expect(ListeAdresi.listeMi("https://www.youtube.com/@BlenderOfficial"))
        #expect(!ListeAdresi.listeMi("https://www.youtube.com/watch?v=x&list=PL1"))   // listedeki tek video
        #expect(!ListeAdresi.listeMi("https://youtu.be/abc"))
        #expect(ListeAdresi.duzelt("https://www.youtube.com/@Blender") == "https://www.youtube.com/@Blender/videos")
        #expect(ListeAdresi.duzelt("https://www.youtube.com/@Blender/shorts") == "https://www.youtube.com/@Blender/shorts")
        #expect(ListeAdresi.duzelt("https://www.youtube.com/channel/UC123") == "https://www.youtube.com/channel/UC123/videos")
        let metin = "bir https://youtu.be/a\nhttps://youtu.be/b iki https://youtu.be/a"
        #expect(ListeAdresi.hepsi(metin) == ["https://youtu.be/a", "https://youtu.be/b"])
    }

    @Test func topluEklemeYinelenenleriAtlar() {
        let dosya = FileManager.default.temporaryDirectory.appending(path: "kuyruk-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: dosya) }
        let kuyruk = IndirmeKuyrugu(dosya: dosya, kutuphane: Kutuphane(dosyasiz: true))
        kuyruk.hepsiniDuraklat()
        let ogeler = ["https://youtu.be/aaaaaaaaaaa", "https://www.youtube.com/watch?v=aaaaaaaaaaa", "https://youtu.be/bbbbbbbbbbb"].map { IndirmeKuyrugu.TopluOge(adres: $0) }
        let sonuc = kuyruk.topluEkle(ogeler, secim: IndirmeSecimi(tur: .ses), numarala: true)
        #expect(sonuc.eklenen == 2 && sonuc.atlanan == 1)
        #expect(kuyruk.isler.map(\.secim.siraNo) == [1, 3])
        #expect(kuyruk.topluEkle(ogeler, secim: IndirmeSecimi(tur: .ses)).eklenen == 0)
        for is_ in kuyruk.isler { kuyruk.kaldir(is_.id) }
    }

    @Test func hizSiniriVeGeciciHatalar() {
        #expect(IndirmeKuyrugu.hizSiniri(PythonMotoru.Hata.cozum(PythonMotoru.anlasilir("Sign in to confirm you're not a bot"))))
        #expect(IndirmeKuyrugu.gecici(URLError(.timedOut)) && IndirmeKuyrugu.gecici(IndirmeHatasi.http(503)))
        #expect(!IndirmeKuyrugu.gecici(IndirmeHatasi.mpegTS))
    }
}

/// Gömülü Python'un simülatörde/cihazda gerçekten açıldığını denetler (ağ gerektirmez).
@MainActor struct MotorTests {
    @Test func pythonVeYtDlpYuklenir() async throws {
        let surum = try await PythonMotoru.shared.surum()
        #expect(surum.python.hasPrefix("3.14"))
        #expect(!surum.yt_dlp.isEmpty && surum.ejs != "?")
    }

    @Test func jsDegerlendiricisiCalisir() {
        let sonuc = kepceJSDegerlendir("var x = [1,2,3].map(function(n){return n*2}); x.join('-')")
        let metin = sonuc.map { String(cString: $0.assumingMemoryBound(to: CChar.self)) }
        free(sonuc)
        #expect(metin == "2-4-6")
        let hata = kepceJSDegerlendir("throw new Error('olmadı')")
        let hataMetni = hata.map { String(cString: $0.assumingMemoryBound(to: CChar.self)) } ?? ""
        free(hata)
        #expect(hataMetni.contains("\"type\":\"error\"") && hataMetni.contains("olmadı"))
    }
}

/// Ağ gerektiren uçtan uca deneme: KEPCE_CANLI=1 ile çalışır.
@MainActor struct CanliTests {
    nonisolated static let acik = ProcessInfo.processInfo.environment["KEPCE_CANLI"] == "1"

    @Test(.enabled(if: CanliTests.acik)) func youtubeSesiniIndirirVeEtiketler() async throws {
        let bilgi = try await PythonMotoru.shared.coz("https://www.youtube.com/watch?v=aqz-KE-bpKQ")
        #expect(bilgi.title?.contains("Big Buck Bunny") == true)
        let kaliteler = BicimSecici.kaliteler(bilgi)
        #expect(kaliteler.contains { $0.yukseklik >= 1080 })
        // En küçük ses akışını indir, M4A'ya etiketleyerek koy.
        let ses = try #require(BicimSecici.sesler(bilgi).last)
        let klasor = FileManager.default.temporaryDirectory.appending(path: "kepce-canli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: klasor) }
        let sayac = IlerlemeSayaci()
        let baslangic = Date()
        try await AkisIndirici.indir(ses, hedef: klasor.appending(path: "ses.m4a"), baglanti: 4, sayac: sayac, sure: bilgi.duration)
        let boyut = try #require(try klasor.appending(path: "ses.m4a").resourceValues(forKeys: [.fileSizeKey]).fileSize)
        print("Kepçe canlı: \(boyut) bayt, \(Date().timeIntervalSince(baslangic)) sn")
        #expect(Int64(boyut) == sayac.toplam && sayac.alinan == Int64(boyut))
        let cikis = klasor.appending(path: "cikis.m4a")
        try await Birlestirici.birlestir(video: nil, ses: klasor.appending(path: "ses.m4a"), cikis: cikis, yalnizSes: true,
                                         etiket: MedyaEtiketi(baslik: "Deneme", sanatci: "Blender"), kesit: 10...20)
        let varlik = AVURLAsset(url: cikis)
        let sure = try await varlik.load(.duration).seconds
        #expect(abs(sure - 10) < 0.5)
        let etiketler = try await varlik.load(.commonMetadata)
        #expect(try await etiketler.first { $0.commonKey == .commonKeyTitle }?.load(.stringValue) == "Deneme")
    }

    @Test(.enabled(if: CanliTests.acik)) func videoVeSesiBirlestirir() async throws {
        let bilgi = try await PythonMotoru.shared.coz("https://www.youtube.com/watch?v=aqz-KE-bpKQ")
        let plan = try #require(BicimSecici.plan(bilgi, tur: .video, enFazla: 240))
        let klasor = FileManager.default.temporaryDirectory.appending(path: "kepce-canli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: klasor) }
        try await AkisIndirici.indir(try #require(plan.video), hedef: klasor.appending(path: "video.mp4"), baglanti: 4, sayac: IlerlemeSayaci(), sure: bilgi.duration)
        try await AkisIndirici.indir(try #require(plan.ses), hedef: klasor.appending(path: "ses.m4a"), baglanti: 2, sayac: IlerlemeSayaci(), sure: bilgi.duration)
        let cikis = klasor.appending(path: "cikis.mp4")
        try await Birlestirici.birlestir(video: klasor.appending(path: "video.mp4"), ses: klasor.appending(path: "ses.m4a"), cikis: cikis, yalnizSes: false,
                                         etiket: MedyaEtiketi(baslik: "BBB"), kesit: nil)
        let varlik = AVURLAsset(url: cikis)
        #expect(try await varlik.loadTracks(withMediaType: .video).count == 1)
        #expect(try await varlik.loadTracks(withMediaType: .audio).count == 1)
        #expect(abs(try await varlik.load(.duration).seconds - (bilgi.duration ?? 0)) < 2)
    }
}

import AVFoundation
import CommonCrypto
