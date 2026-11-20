import Testing
import Foundation
import AVFoundation
import UIKit
@testable import _01

/// Ekle-Tarama paketi (21 Eki 2026): seri tarama kuyruğu ve durum makinesi, kalıcı onay kuyruğu,
/// dosya içe aktarma özeti, künye kaynağı sağlamlığı, tarama oturumu depolaması, iptal.
/// Kamera ve ağ gerektirmez; ağ davranışları `URLProtocol` ile taklit edilir.
@MainActor
@Suite(.serialized)
struct EkleGelistirmeTests {
    // MARK: - Yardımcılar

    private func geciciKlasor(_ ad: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ekle-gelistirme-\(ad)-" + UUID().uuidString, isDirectory: true)
    }

    private func oturumKlasorunde(_ islem: (URL) async throws -> Void) async throws {
        let onceki = ScanSessionStore.directoryOverride
        let klasor = geciciKlasor("oturum")
        ScanSessionStore.directoryOverride = klasor
        defer { ScanSessionStore.directoryOverride = onceki; try? FileManager.default.removeItem(at: klasor) }
        try await islem(klasor)
    }

    private func kuyrukKlasorunde(_ islem: (URL) throws -> Void) throws {
        let onceki = PendingQueueStore.directoryOverride
        let klasor = geciciKlasor("kuyruk")
        try FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        PendingQueueStore.directoryOverride = klasor
        defer { PendingQueueStore.directoryOverride = onceki; try? FileManager.default.removeItem(at: klasor) }
        try islem(klasor)
    }

    private func png(_ boyut: CGSize = CGSize(width: 64, height: 64)) throws -> Data {
        let resim = UIGraphicsImageRenderer(size: boyut).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: boyut))
        }
        return try #require(resim.pngData())
    }

    // MARK: - TekrarBastirici

    @Test func tekrarBastiriciPencereIcindeYutarDisindaGecirir() {
        let kod = "9789750718434"
        let t0 = Date(timeIntervalSince1970: 1_000)
        var bastirici = TekrarBastirici(pencere: 1.5)
        let ilk = bastirici.yutulsunMu(kod, simdi: t0)
        let yinelenen = bastirici.yutulsunMu(kod, simdi: t0.addingTimeInterval(1.4))
        let farkliKod = bastirici.yutulsunMu("9786053607021", simdi: t0.addingTimeInterval(1.4))
        #expect(!ilk, "İlk okutma geçer")
        #expect(yinelenen, "1,4 sn sonra aynı kod yutulur")
        #expect(!farkliKod, "Farklı kod geçer")

        var ikinci = TekrarBastirici(pencere: 1.5)
        _ = ikinci.yutulsunMu(kod, simdi: t0)
        let gec = ikinci.yutulsunMu(kod, simdi: t0.addingTimeInterval(1.6))
        #expect(!gec, "1,6 sn sonra aynı kod yeni nüshadır")
    }

    @Test func yutulanOkutmaPenceregiUzatmaz() {
        let kod = "9789750718434"
        let t0 = Date(timeIntervalSince1970: 5_000)
        var bastirici = TekrarBastirici(pencere: 1.5)
        _ = bastirici.yutulsunMu(kod, simdi: t0)
        _ = bastirici.yutulsunMu(kod, simdi: t0.addingTimeInterval(1.0))
        let gec = bastirici.yutulsunMu(kod, simdi: t0.addingTimeInterval(1.6))
        #expect(!gec, "Ölçü son KABUL edilen okutmadır")
    }

    // MARK: - Tarama kipi ve denetleyici

    @Test func taramaKipiSurekliVePanelKurallari() {
        #expect(!TaramaKipi.tekli.surekli && !TaramaKipi.arama.surekli)
        #expect(TaramaKipi.seri(BulkAssignment(), otoKayit: true).surekli)
        #expect(TaramaKipi.depo.surekli && TaramaKipi.rafAtama.surekli)
        #expect(TaramaKipi.seri(BulkAssignment(), otoKayit: false).seri)
        #expect(TaramaKipi.depo.panelGerekli && !TaramaKipi.tekli.panelGerekli)
    }

    @Test func gunlukSonDortSatiriTutar() {
        let denetleyici = BarkodTaramaDenetleyicisi()
        for sira in 1...7 { denetleyici.gunlugeEkle("satır \(sira)") }
        #expect(denetleyici.gunluk == ["satır 4", "satır 5", "satır 6", "satır 7"])
    }

    @Test func kaliciKuyrukIslenenISBNiDeBekleyenSayar() {
        let denetleyici = BarkodTaramaDenetleyicisi()
        #expect(denetleyici.bekleyenISBNler == nil, "Boş kuyrukta alan yazılmaz")
        ["9789750718434", "9786053607021", "9789755705859"].forEach(denetleyici.isbnEkle)
        #expect(denetleyici.siradakiniAl() == "9789750718434")
        #expect(denetleyici.bekleyenISBNler == ["9789750718434", "9786053607021", "9789755705859"],
                "İşlenen ISBN bitene dek diskteki listede kalır")
        denetleyici.islemBitti()
        #expect(denetleyici.bekleyenISBNler == ["9786053607021", "9789755705859"])
        #expect(denetleyici.bekleyenSayisi == 2)
    }

    @Test func kilitKaybindaISBNKuyrukBasinaDoner() {
        let denetleyici = BarkodTaramaDenetleyicisi()
        ["9789750718434", "9786053607021"].forEach(denetleyici.isbnEkle)
        let alinan = denetleyici.siradakiniAl()
        denetleyici.islenenigeriVer()
        #expect(denetleyici.siradakiniAl() == alinan, "Yarım kalan ISBN yeniden ilk sırada")
    }

    @Test func nushaSayaciOturumdaKumulatifArtar() {
        let denetleyici = BarkodTaramaDenetleyicisi()
        #expect(denetleyici.nushaEklendi(isbn: "9789750718434", adet: 1) == 1)
        #expect(denetleyici.nushaEklendi(isbn: "9789750718434", adet: 2) == 3)
        #expect(denetleyici.nushaEklendi(isbn: "9786053607021", adet: 1) == 1)
    }

    // MARK: - Kalıcı ISBN kuyruğu (oturum)

    @Test func pendingISBNsKaydedilirYuklenirIsciKaldigiYerdenSurer() async throws {
        try await oturumKlasorunde { _ in
            let ilk = BarkodTaramaDenetleyicisi()
            ["9789750718434", "9786053607021", "9789755705859"].forEach(ilk.isbnEkle)
            _ = ilk.siradakiniAl()   // künyesi alınırken uygulama kapanır

            var oturum = ScanSession(kind: .photo, title: "Kitap ekleme")
            oturum.pendingISBNs = ilk.bekleyenISBNler
            oturum.seriAtama = SeriAtama(location: "Kütüphane", cabinet: "A", shelf: "3", category: "Roman", otoKayit: false)
            try ScanSessionStore.save(oturum)

            let yuklenen = try #require(try ScanSessionStore.allVerified().first)
            #expect(yuklenen.pendingISBNs == ["9789750718434", "9786053607021", "9789755705859"])
            #expect(yuklenen.seriAtama?.shelf == "3" && yuklenen.seriAtama?.otoKayit == false)

            let ikinci = BarkodTaramaDenetleyicisi()
            ikinci.devral(bekleyen: try #require(yuklenen.pendingISBNs))
            #expect(ikinci.siradakiniAl() == "9789750718434", "Yarım kalan ISBN yeniden denenir")
            #expect(ikinci.siradakiniAl() == "9786053607021")
        }
    }

    @Test func eskiOturumJSONindaPendingISBNsYoktur() throws {
        // pendingISBNs / seriAtama / sourceImageFiles eklenmeden önce yazılmış oturum okunabilmeli
        let eski = ScanSession(kind: .barcode, title: "Eski")
        var veri = try JSONEncoder().encode(eski)
        var sozluk = try #require(try JSONSerialization.jsonObject(with: veri) as? [String: Any])
        sozluk.removeValue(forKey: "pendingISBNs")
        sozluk.removeValue(forKey: "seriAtama")
        sozluk.removeValue(forKey: "sourceImageFiles")
        veri = try JSONSerialization.data(withJSONObject: sozluk)
        let cozulen = try JSONDecoder().decode(ScanSession.self, from: veri)
        #expect(cozulen.pendingISBNs == nil && cozulen.seriAtama == nil && cozulen.sourceImageFiles == nil)
    }

    // MARK: - KuyrukTaslagi / PendingQueueStore

    @Test func kuyrukTaslagiAlanlariGidisDonusteKorur() throws {
        try kuyrukKlasorunde { _ in
            var taslak = BookDraft()
            taslak.title = "Şüpheli Ad"
            taslak.isbn = "9789750718434"
            taslak.lowConfidenceFields = ["title", "author"]
            taslak.recognizedByGemini = true
            taslak.recognitionSource = "gemini"
            taslak.bilgiNotu = "ISBN kaynaklarda bulunamadı"
            taslak.konumFarki = "Konum farklı: A-3 → B-1"
            let kayit = KuyrukTaslagi(draft: taslak, book: taslak.snapshot)
            try PendingQueueStore.save([kayit])

            let yuklenen = try #require(PendingQueueStore.load().first)
            let geri = yuklenen.draft
            #expect(geri.lowConfidenceFields == ["title", "author"])
            #expect(geri.recognizedByGemini)
            #expect(geri.recognitionSource == "gemini")
            #expect(geri.bilgiNotu == "ISBN kaynaklarda bulunamadı")
            #expect(geri.konumFarki == "Konum farklı: A-3 → B-1")
            #expect(geri.title == "Şüpheli Ad")
        }
    }

    @Test func eskiBookDizisiDosyasiOkunur() throws {
        try kuyrukKlasorunde { klasor in
            let kitaplar = [Book(title: "Nutuk", author: "Atatürk", isbn: "9789750718434"), Book(title: "Çalıkuşu", author: "Reşat Nuri")]
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(kitaplar).write(to: klasor.appendingPathComponent("BekleyenKuyruk.json"))

            let yuklenen = PendingQueueStore.load()
            #expect(yuklenen.map(\.book.title) == ["Nutuk", "Çalıkuşu"])
            #expect(yuklenen.allSatisfy { $0.lowConfidenceFields.isEmpty && !$0.recognizedByGemini })
        }
    }

    @Test func bozukKuyrukDosyasiBozukYedegineTasinirVeBosDoner() throws {
        try kuyrukKlasorunde { klasor in
            let dosya = klasor.appendingPathComponent("BekleyenKuyruk.json")
            try Data("{ bozuk json".utf8).write(to: dosya)

            let sonuc = PendingQueueStore.loadResult()
            #expect(sonuc.taslaklar.isEmpty)
            let yedek = try #require(sonuc.bozukYedek)
            #expect(FileManager.default.fileExists(atPath: yedek.path))
            #expect(yedek.pathExtension == "bozuk")
            #expect(!FileManager.default.fileExists(atPath: dosya.path), "Bozuk dosya sonraki kayıtta ezilmez, yanına taşınmıştır")
            #expect(try Data(contentsOf: yedek) == Data("{ bozuk json".utf8))
        }
    }

    @Test func kuyrukYazmaHatasiYuzeyeCikar() throws {
        let onceki = PendingQueueStore.directoryOverride
        let engel = geciciKlasor("engel")
        try Data("dosya".utf8).write(to: engel)   // klasör yerine düz dosya
        PendingQueueStore.directoryOverride = engel
        defer { PendingQueueStore.directoryOverride = onceki; try? FileManager.default.removeItem(at: engel) }

        #expect(throws: (any Error).self) {
            try PendingQueueStore.save([KuyrukTaslagi(book: Book(title: "A", author: "B"))])
        }
    }

    @Test func bosKuyrukDosyayiSiler() throws {
        try kuyrukKlasorunde { klasor in
            try PendingQueueStore.save([KuyrukTaslagi(book: Book(title: "A", author: "B"))])
            #expect(FileManager.default.fileExists(atPath: klasor.appendingPathComponent("BekleyenKuyruk.json").path))
            try PendingQueueStore.save([])
            #expect(!FileManager.default.fileExists(atPath: klasor.appendingPathComponent("BekleyenKuyruk.json").path))
        }
    }

    // MARK: - Dosya içe aktarma özeti

    @Test func dosyaOzetiBozukDosyayiAdiylaSoyler() async {
        let urller = ["a.pdf", "b.jpg", "c.pdf"].map { URL(fileURLWithPath: "/tmp/\($0)") }
        var ilerleme: [Int] = []
        let ozet = await DosyaIceAktarma.calistir(urls: urller, ilerleme: { ilerleme.append($0) }) { url in
            if url.lastPathComponent == "a.pdf" { throw DosyaOkumaHatasi(neden: "bozuk PDF") }
        }
        #expect(ozet.okunan == 2 && ozet.okunamayan == 1 && ozet.toplam == 3)
        #expect(ozet.mesaj == "2 dosya okundu, 1 okunamadı: a.pdf (bozuk PDF)")
        #expect(ilerleme == [1, 2, 3], "Başarısız dosya ilerlemeyi durdurmaz")
    }

    @Test func dosyaOzetiHataYoksaMesajYoktur() async {
        let ozet = await DosyaIceAktarma.calistir(urls: [URL(fileURLWithPath: "/tmp/x.pdf")]) { _ in }
        #expect(ozet.mesaj == nil && ozet.okunan == 1)
    }

    @Test func dosyaOzetiCokHatadaListeyiKisaltir() async {
        let urller = (1...8).map { URL(fileURLWithPath: "/tmp/\($0).pdf") }
        let ozet = await DosyaIceAktarma.calistir(urls: urller) { _ in throw DosyaOkumaHatasi(neden: "indirilemedi") }
        let mesaj = ozet.mesaj ?? ""
        #expect(ozet.okunamayan == 8)
        #expect(mesaj.contains("ve 3 dosya daha"))
        #expect(mesaj.contains("1.pdf (indirilemedi)") && !mesaj.contains("8.pdf"))
    }

    @Test func dosyaOzetiBilinmeyenHatayiGenelNedenleSoyler() async {
        struct Garip: Error { }
        let ozet = await DosyaIceAktarma.calistir(urls: [URL(fileURLWithPath: "/tmp/z.jpg")]) { _ in throw Garip() }
        #expect(ozet.mesaj == "0 dosya okundu, 1 okunamadı: z.jpg (okunamadı)")
    }

    @Test func koordineliOkumaVarOlanDosyayiOkurVeYoksaHataVerir() async throws {
        let klasor = geciciKlasor("okuma")
        try FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: klasor) }
        let dosya = klasor.appendingPathComponent("a.bin")
        try Data([1, 2, 3]).write(to: dosya)
        #expect(try await KoordineliDosyaOkuma.oku(dosya) == Data([1, 2, 3]))
        await #expect(throws: DosyaOkumaHatasi.self) {
            _ = try await KoordineliDosyaOkuma.oku(klasor.appendingPathComponent("yok.bin"))
        }
    }

    // MARK: - Kamera izni

    @Test func kameraIzniKarari() async {
        let desteklenmiyor = await KameraIzni.karar(durum: .authorized, destekleniyor: false, kullanilabilir: false, izinIste: { true })
        #expect(desteklenmiyor == .desteklenmiyor)
        let reddedilmis = await KameraIzni.karar(durum: .denied, destekleniyor: true, kullanilabilir: false, izinIste: { true })
        #expect(reddedilmis == .reddedildi, "Reddedilmiş izin 'desteklenmiyor' diye gösterilmez")
        let kisitli = await KameraIzni.karar(durum: .restricted, destekleniyor: true, kullanilabilir: false, izinIste: { true })
        #expect(kisitli == .reddedildi)
        let verildi = await KameraIzni.karar(durum: .notDetermined, destekleniyor: true, kullanilabilir: true, izinIste: { true })
        #expect(verildi == .izinli)
        let istenenRed = await KameraIzni.karar(durum: .notDetermined, destekleniyor: true, kullanilabilir: true, izinIste: { false })
        #expect(istenenRed == .reddedildi)
        let hazir = await KameraIzni.karar(durum: .authorized, destekleniyor: true, kullanilabilir: true, izinIste: { false })
        #expect(hazir == .izinli)
    }

    // MARK: - Künye kaynağı sağlamlığı

    @Test func kitapyurduSunucuKodlariSonucYokuAyirir() {
        #expect(KitapyurduHata.sunucu(404).sonucYok)
        #expect(KitapyurduHata.sunucu(500).sonucYok)
        for kod in [429, 502, 503, 504, 403] { #expect(!KitapyurduHata.sunucu(kod).sonucYok, "\(kod) 'kitap yok' değildir") }
    }

    @Test func yenidenDenemeGeciciSunucuKodlarindaOlur() {
        for kod in [429, 502, 503, 504] { #expect(BookMetadataService.isRetriable(KitapyurduHata.sunucu(kod))) }
        for kod in [403, 404, 500] { #expect(!BookMetadataService.isRetriable(KitapyurduHata.sunucu(kod))) }
        #expect(BookMetadataService.isRetriable(URLError(.timedOut)))
        #expect(!BookMetadataService.isRetriable(URLError(.badServerResponse)))
        #expect(!BookMetadataService.isRetriable(URLError(.resourceUnavailable)), "Bot engeli beklemekle geçmez")
    }

    @Test func botDogrulamaSayfasiTaninir() {
        #expect(KitapyurduScraper.isBotChallenge(html: "<title>Just a moment...</title>"))
        #expect(KitapyurduScraper.isBotChallenge(html: "<div class=\"cf-challenge\"></div>"))
        #expect(!KitapyurduScraper.isBotChallenge(html: "<html><h1 class=\"ky-pd-title\">Kitap</h1></html>"))
    }

    @Test func kitapyurdu503HataFirlatir404SonucYokDer() async throws {
        let durum = YanitDurumu()
        MockKitapyurduProtokolu.durum = durum
        URLProtocol.registerClass(MockKitapyurduProtokolu.self)
        defer { URLProtocol.unregisterClass(MockKitapyurduProtokolu.self); MockKitapyurduProtokolu.durum = nil }

        durum.kod = 503
        do {
            _ = try await KitapyurduScraper.searchResults(title: "Kürk Mantolu Madonna")
            Issue.record("503 'sonuç yok' sanılmamalı")
        } catch let hata as KitapyurduHata {
            #expect(hata == .sunucu(503))
        }

        durum.kod = 404
        let yok = try await KitapyurduScraper.searchResults(title: "Kürk Mantolu Madonna")
        #expect(yok.isEmpty, "404 gerçek 'sonuç yok'tur")

        durum.kod = 500
        let bos = try await KitapyurduScraper.searchResults(title: "Kürk Mantolu Madonna")
        #expect(bos.isEmpty, "Kitapyurdu boş aramada 500 döndürür")
    }

    @Test func butceDolarsaCancellationErrorFirlar() async {
        await #expect(throws: CancellationError.self) {
            _ = try await ButceliCalistir.calistir(butce: .milliseconds(60)) { () async throws -> Int in
                try await Task.sleep(for: .seconds(10))
                return 1
            }
        }
        let hizli = try? await ButceliCalistir.calistir(butce: .seconds(5)) { () async throws -> Int in 42 }
        #expect(hizli == 42)
    }

    @Test func disaridanIptalCancellationErrorOlarakYayilir() async {
        let gorev = Task { () async throws -> Int in
            try await ButceliCalistir.calistir(butce: .seconds(30)) { () async throws -> Int in
                try await Task.sleep(for: .seconds(10))
                return 1
            }
        }
        gorev.cancel()
        await #expect(throws: CancellationError.self) { _ = try await gorev.value }
    }

    @Test func kunyeHataMetniNedeniSoyler() {
        #expect(KunyeHataMetni.metin(KitapyurduHata.sunucu(429), kaynak: "Kitapyurdu").contains("çok sık"))
        #expect(KunyeHataMetni.metin(KitapyurduHata.sunucu(503), kaynak: "Kitapyurdu").contains("yanıt vermiyor"))
        #expect(KunyeHataMetni.metin(URLError(.resourceUnavailable), kaynak: "Kitapyurdu").contains("bot"))
        #expect(KunyeHataMetni.metin(URLError(.notConnectedToInternet), kaynak: "Kitapyurdu").contains("bağlantı"))
    }

    // MARK: - Kazıyıcı performansı

    @Test func amazonParseProduct2MBSayfadaHizliVeDogru() {
        var html = "<html><head>"
        html += String(repeating: "<script>window.ue_t0=ue_t0||+new Date();var a={\"k\":\"v\"};</script>\n", count: 30_000)
        html += "</head><body><span id=\"productTitle\">Derin Sayfa Kitabı</span>"
        html += "<span class=\"author notFaded\"><a class=\"a-link-normal\" href=\"#\">Yazar Adı</a></span>"
        html += "<div id=\"detailBullets_feature_div\"><ul>"
        html += "<li><span class=\"a-list-item\">Yayıncı : Deneme Yayınları</span></li>"
        html += "<li><span class=\"a-list-item\">Baskı uzunluğu : 352 sayfa</span></li></ul></div>"
        html += String(repeating: "<div class=\"x\"><tr><td>dolgu</td></tr></div>\n", count: 20_000)
        #expect(html.utf8.count > 2_000_000)

        let baslangic = ContinuousClock.now
        let meta = AmazonBookScraper.parseProduct(html: html, fallbackISBN: "")
        let sure = ContinuousClock.now - baslangic
        #expect(meta.title == "Derin Sayfa Kitabı")
        #expect(meta.author == "Yazar Adı")
        #expect(meta.publisher == "Deneme Yayınları" && meta.pageCount == "352")
        #expect(sure < .seconds(3), "2 MB sayfa bölümlere kesilerek taranır (ölçülen: \(sure))")
    }

    @Test func regexOnbellegiAyniNesneyiDondurur() throws {
        let a = try #require(KunyeRegex.derle("a(b+)c"))
        let b = try #require(KunyeRegex.derle("a(b+)c"))
        #expect(a === b)
        #expect(KunyeRegex.etiketleriTemizle("<b>Merhaba</b> <i>dünya</i>").contains("Merhaba"))
        #expect(!KunyeRegex.etiketleriTemizle("<b>Merhaba</b>").contains("<"))
    }

    // MARK: - Tarama oturumu depolama

    @Test func fotografliOturumJSONBoyutuFotografSayisindanBagimsizdir() async throws {
        try await oturumKlasorunde { klasor in
            let foto = Data(repeating: 7, count: 300_000)
            var bir = ScanSession(kind: .photo, title: "Bir")
            bir.sourceImages = [foto]
            var bes = ScanSession(kind: .photo, title: "Bes")
            bes.sourceImages = Array(repeating: foto, count: 5)
            try ScanSessionStore.save(bir)
            try ScanSessionStore.save(bes)

            func jsonBoyutu(_ oturum: ScanSession) throws -> Int {
                try Data(contentsOf: klasor.appendingPathComponent(oturum.id.uuidString + ".json")).count
            }
            let farki = try abs(jsonBoyutu(bes) - jsonBoyutu(bir))
            #expect(try jsonBoyutu(bes) < 20_000, "Fotoğraflar JSON'a gömülmez")
            #expect(farki < 500, "Boyut fotoğraf sayısıyla büyümez (fark \(farki))")

            let yuklenen = try #require(try ScanSessionStore.allVerified().first { $0.id == bes.id })
            #expect(yuklenen.sourceImages == Array(repeating: foto, count: 5), "Yüklerken fotoğraflar geri doldurulur")
            #expect(yuklenen.sourceImageFiles == nil)
            let dizin = try #require(ScanSessionStore.photoDirectory(for: bes.id))
            #expect(((try? FileManager.default.contentsOfDirectory(atPath: dizin.path)) ?? []).sorted()
                    == (0..<5).map { "foto-\($0).jpg" }.sorted())
        }
    }

    @Test func fotografsizYuklemeDosyaAdlariniTasirVeKaydiBozmaz() async throws {
        try await oturumKlasorunde { _ in
            var oturum = ScanSession(kind: .photo, title: "Foto")
            oturum.sourceImages = [Data([1, 2, 3]), Data([4, 5])]
            try ScanSessionStore.save(oturum)

            let hafif = try #require(try ScanSessionStore.allVerified(hydratePhotos: false).first)
            #expect((hafif.sourceImages ?? []).isEmpty)
            #expect(hafif.sourceImageFiles == ["foto-0.jpg", "foto-1.jpg"] && hafif.hasSourceImages)

            // Fotoğrafsız yüklenen oturumun yeniden kaydı fotoğrafları silmez
            try ScanSessionStore.save(hafif, updateTimestamp: false)
            let tam = try #require(try ScanSessionStore.allVerified().first)
            #expect(tam.sourceImages == [Data([1, 2, 3]), Data([4, 5])])
            #expect(ScanSessionStore.hydrated(hafif).sourceImages == [Data([1, 2, 3]), Data([4, 5])])
        }
    }

    @Test func fotografKalmayincaKlasorSilinir() async throws {
        try await oturumKlasorunde { _ in
            var oturum = ScanSession(kind: .photo, title: "Foto")
            oturum.sourceImages = [Data([1])]
            try ScanSessionStore.save(oturum)
            let dizin = try #require(ScanSessionStore.photoDirectory(for: oturum.id))
            #expect(FileManager.default.fileExists(atPath: dizin.path))

            var temiz = try #require(try ScanSessionStore.allVerified().first)
            temiz.sourceImages = []
            try ScanSessionStore.save(temiz)
            #expect(!FileManager.default.fileExists(atPath: dizin.path))
            try ScanSessionStore.remove(oturum.id)
            #expect(try ScanSessionStore.allVerified().isEmpty)
        }
    }

    @Test func eskiGomuluFotografliOturumAcilistaDosyalaraDokulur() async throws {
        try await oturumKlasorunde { klasor in
            try FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
            var eski = ScanSession(kind: .photo, title: "Eski")
            eski.sourceImages = [Data(repeating: 9, count: 100_000)]
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let dosya = klasor.appendingPathComponent(eski.id.uuidString + ".json")
            try encoder.encode(eski).write(to: dosya)   // eski biçim: fotoğraf JSON'un içinde
            #expect(try Data(contentsOf: dosya).count > 100_000)

            let sonuc = ScanSessionStore.maintenanceNow()
            #expect(sonuc.migrated == 1 && sonuc.orphansRemoved == 0)
            #expect(try Data(contentsOf: dosya).count < 20_000)
            let yuklenen = try #require(try ScanSessionStore.allVerified().first)
            #expect(yuklenen.sourceImages == [Data(repeating: 9, count: 100_000)])
        }
    }

    @Test func bakimHicbirOturumuKendiliginenSilmez() async throws {
        try await oturumKlasorunde { _ in
            let eskiTarih = Date().addingTimeInterval(-90 * 24 * 3600)
            var eski = ScanSession(kind: .barcode, title: "Eski bitmiş"); eski.updatedAt = eskiTarih
            try ScanSessionStore.save(eski, updateTimestamp: false)
            _ = ScanSessionStore.maintenanceNow()
            #expect(try ScanSessionStore.allVerified().map(\.title) == ["Eski bitmiş"], "Otomatik silme yok")
        }
    }

    @Test func bitmisOturumlarYalnizElleVeBekleyenlerHaricTemizlenir() async throws {
        try await oturumKlasorunde { _ in
            let simdi = Date()
            let eskiTarih = simdi.addingTimeInterval(-31 * 24 * 3600)
            var bitmis = ScanSession(kind: .photo, title: "Bitmiş"); bitmis.updatedAt = eskiTarih
            bitmis.sourceImages = [Data(repeating: 1, count: 10_000)]
            var bekleyenKitap = ScanSession(kind: .barcode, title: "Kitap bekliyor"); bekleyenKitap.updatedAt = eskiTarih
            bekleyenKitap.pendingBooks = [Book(title: "A", author: "B")]
            var bekleyenISBN = ScanSession(kind: .barcode, title: "ISBN bekliyor"); bekleyenISBN.updatedAt = eskiTarih
            bekleyenISBN.pendingISBNs = ["9789750718434"]
            var taze = ScanSession(kind: .barcode, title: "Taze"); taze.updatedAt = simdi
            for oturum in [bitmis, bekleyenKitap, bekleyenISBN, taze] { try ScanSessionStore.save(oturum, updateTimestamp: false) }

            let ozet = ScanSessionStore.finishedUsage(now: simdi)
            #expect(ozet.sessions == 1 && ozet.bytes >= 10_000)
            #expect(ScanSessionStore.purgeFinished(now: simdi) == 1)
            let kalan = Set(try ScanSessionStore.allVerified().map(\.title))
            #expect(kalan == ["Kitap bekliyor", "ISBN bekliyor", "Taze"])
            let klasor = try #require(ScanSessionStore.photoDirectory(for: bitmis.id))
            #expect(!FileManager.default.fileExists(atPath: klasor.path), "Fotoğraflar da silinir")
        }
    }

    @Test func ayniBoyutluFarkliFotografEskiDosyadaKalmaz() async throws {
        try await oturumKlasorunde { _ in
            var oturum = ScanSession(kind: .photo, title: "Foto")
            oturum.sourceImages = [Data([1, 2, 3])]
            try ScanSessionStore.save(oturum)
            oturum.sourceImages = [Data([9, 9, 9])]
            try ScanSessionStore.save(oturum)
            let yuklenen = try #require(try ScanSessionStore.allVerified().first)
            #expect(yuklenen.sourceImages == [Data([9, 9, 9])])
        }
    }

    @Test func sahipsizFotografKlasoruBakimdaSilinir() async throws {
        try await oturumKlasorunde { klasor in
            let sahipsiz = klasor.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: sahipsiz, withIntermediateDirectories: true)
            try Data([1]).write(to: sahipsiz.appendingPathComponent("foto-0.jpg"))
            var canli = ScanSession(kind: .photo, title: "Canlı")
            canli.sourceImages = [Data([2])]
            try ScanSessionStore.save(canli)
            let canliKlasor = try #require(ScanSessionStore.photoDirectory(for: canli.id))

            _ = ScanSessionStore.maintenanceNow()
            #expect(!FileManager.default.fileExists(atPath: sahipsiz.path), "JSON'u olmayan klasör silinir")
            #expect(FileManager.default.fileExists(atPath: canliKlasor.path), "Oturumu olan klasöre dokunulmaz")
        }
    }

    @Test func diskKullanimiJSONveFotografKlasorlerinitoplar() async throws {
        try await oturumKlasorunde { _ in
            #expect(ScanSessionStore.diskUsage().sessions == 0 && ScanSessionStore.diskUsage().bytes == 0)
            var oturum = ScanSession(kind: .photo, title: "Foto")
            oturum.sourceImages = [Data(repeating: 1, count: 50_000), Data(repeating: 2, count: 50_000)]
            try ScanSessionStore.save(oturum)
            let kullanim = ScanSessionStore.diskUsage()
            #expect(kullanim.sessions == 1)
            #expect(kullanim.bytes >= 100_000 && kullanim.bytes < 130_000)
        }
    }

    @Test func arkaPlanKaydiTamamlanincaDiskteGorunur() async throws {
        try await oturumKlasorunde { _ in
            var oturum = ScanSession(kind: .photo, title: "Arka plan")
            oturum.sourceImages = [Data([1, 2, 3])]
            ScanSessionStore.saveInBackground(oturum, onFailure: { _ in })
            ScanSessionStore.flush()
            let yuklenen = try ScanSessionStore.allVerified().first
            #expect(yuklenen?.sourceImages == [Data([1, 2, 3])])
        }
    }

    // MARK: - Depo ve şüpheli alan yardımcıları

    @Test func depoIndeksiDusulmusKaydiDislarVeEtkinKayitKazanir() {
        let dusulmus = CatalogBook(book: Book(title: "Düşülmüş", author: "A", isbn: "9789750718434", isWithdrawn: true))
        let etkin = CatalogBook(book: Book(title: "Etkin", author: "A", isbn: "9789750718434"))
        let indeks = DepoIndeksi.kur([dusulmus, etkin])
        #expect(indeks["9789750718434"]?.title == "Etkin")
        #expect(DepoIndeksi.kur([dusulmus]).isEmpty, "Yalnız düşülmüş kayıt varsa nüsha eklenmez")
    }

    @Test func konumFarkiEtiketi() {
        #expect(KonumFarki.metin(eskiDolap: "A", eskiRaf: "3", yeniDolap: "B", yeniRaf: "1") == "Konum farklı: A-3 → B-1")
        #expect(KonumFarki.metin(eskiDolap: "A", eskiRaf: "3", yeniDolap: "A", yeniRaf: "3") == nil)
        #expect(KonumFarki.metin(eskiDolap: nil, eskiRaf: nil, yeniDolap: "B", yeniRaf: "1") == nil, "Yeri olmayan kitapta fark yoktur")
    }

    @Test func depoEslesmeKarariVarsayilanNushaDir() {
        let onceki = UserDefaults.standard.object(forKey: DepoEslesmeKarari.anahtar)
        defer { UserDefaults.standard.set(onceki, forKey: DepoEslesmeKarari.anahtar) }
        UserDefaults.standard.removeObject(forKey: DepoEslesmeKarari.anahtar)
        #expect(DepoEslesmeKarari.mevcut == .nusha)
        DepoEslesmeKarari.mevcut = .konumTasi
        #expect(DepoEslesmeKarari.mevcut == .konumTasi)
    }

    @Test func supheliAlanOnarimiYalnizSupheliVeBosAlanlariDegistirir() {
        var taslak = BookDraft()
        taslak.isbn = "9789750718434"
        taslak.title = "Kurk Mantolu Madona"
        taslak.author = "Sabahattin Ali"
        taslak.lowConfidenceFields = ["title"]
        var meta = AmazonBookMetadata()
        meta.title = "Kürk Mantolu Madonna"
        meta.author = "S. Ali"
        meta.publisher = "YKY"

        let degisti = SupheliAlanOnarimi.uygula(meta, to: &taslak)
        #expect(degisti)
        #expect(taslak.title == "Kürk Mantolu Madonna", "Şüpheli işaretli alan kaynaktaki değerle düzelir")
        #expect(taslak.author == "Sabahattin Ali", "Şüphesiz dolu alana dokunulmaz")
        #expect(taslak.publisher == "YKY", "Boş alan doldurulur")
        #expect(taslak.lowConfidenceFields.isEmpty)
    }

    @Test func supheliAlanOnarimiKaynakDuzeltmediyseIsaretiKorur() {
        var taslak = BookDraft()
        taslak.isbn = "9789750718434"
        taslak.title = "Belirsiz Ad"
        taslak.lowConfidenceFields = ["title", "author"]
        var meta = AmazonBookMetadata()
        meta.title = "Belirsiz Ad Düzeltilmiş"   // yazar kaynakta yok
        SupheliAlanOnarimi.uygula(meta, to: &taslak)
        #expect(taslak.title == "Belirsiz Ad Düzeltilmiş")
        #expect(taslak.lowConfidenceFields == ["author"], "Düzelmeyen şüpheli alan işaretli kalır")
        #expect(SupheliAlanOnarimi.aranabilir([taslak]).count == 1)
        var isbnsiz = taslak; isbnsiz.isbn = ""
        #expect(SupheliAlanOnarimi.aranabilir([isbnsiz]).isEmpty, "ISBN'siz taslak yeniden aranamaz")
    }

    // MARK: - İptal

    @Test func iptalEdilenOCRSonucYazmaz() async throws {
        let veri = try png(CGSize(width: 200, height: 200))
        let gorev = Task { () -> BookOCRResult? in await BookOCREngine.recognize(imageData: veri) }
        gorev.cancel()
        #expect(await gorev.value == nil, "İptalden sonra OCR sonucu üretilmez")

        let taslakGorevi = Task { () -> BookDraft? in await BookOCREngine.recognizeBook(imageData: veri) }
        taslakGorevi.cancel()
        #expect(await taslakGorevi.value == nil)
    }

    @Test func iptalEdilenBarkodAramasiBosDoner() async throws {
        let veri = try png(CGSize(width: 300, height: 300))
        let gorev = Task { () -> [BarkodBulgusu] in await CokluKitapAlgilayici.barkodlar(veri) }
        gorev.cancel()
        #expect(await gorev.value.isEmpty)
    }

    @Test func iptalEdilenKapakDuzeltmeNilDoner() async throws {
        let veri = try png(CGSize(width: 300, height: 300))
        let gorev = Task { () -> Data? in await KapakDuzeltici.duzelt(veri) }
        gorev.cancel()
        #expect(await gorev.value == nil)
    }
}

// MARK: - URLProtocol taklidi

/// Her isteğe `durum.kod` ile yanıt verir (boş gövde). `URLSession.shared` kayıtlı protokolleri kullanır.
final class YanitDurumu: @unchecked Sendable {
    var kod = 200
}

final class MockKitapyurduProtokolu: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var durum: YanitDurumu?

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.contains("kitapyurdu") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let kod = Self.durum?.kod ?? 200
        let yanit = HTTPURLResponse(url: request.url!, statusCode: kod, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: yanit, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { }
}
