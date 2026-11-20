import Foundation
import Testing
import ZIPFoundation
@testable import Asistan

@Suite("İndirme girişleri") @MainActor struct IndirmeTestleri {
    @Test func guvensizAdreslerReddedilir() throws {
        for s in ["file:///etc/passwd", "http://example.com", "https://user:secret@example.com", "javascript:alert(1)"] {
            #expect(throws: (any Error).self) { try IndirmeYoneticisi.dogrula(s) }
        }
        #expect(try IndirmeYoneticisi.dogrula("https://example.com/a.mp3").host == "example.com")
    }
    @Test func dosyaAdiKlasorDisinaCikamaz() {
        let ad = IndirmeYoneticisi.dosyaAdi("../../kayıt/ses.mp3")
        #expect(!ad.contains("/")); #expect(!ad.hasPrefix(".")); #expect(ad.hasSuffix(".mp3"))
        #expect(IndirmeYoneticisi.dosyaAdi("...") == "Dosya")
    }
    @Test func kepceBaglantisiAdresVeSesSeciminiKorur() throws {
        let kaynak = try #require(URL(string: "https://www.youtube.com/watch?v=abc&list=xyz"))
        let url = try #require(KepceBaglantisi.adres(kaynak, tur: "audio"))
        let q = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(q.first { $0.name == "url" }?.value == kaynak.absoluteString)
        #expect(q.first { $0.name == "tur" }?.value == "ses")
        #expect(KepceBaglantisi.adres(kaynak, tur: "file") == nil)
    }
    @Test func durumlar() {
        var k = IndirmeKaydi(adres: "https://example.com", tur: "video")
        #expect(k.etkin)
        k.durum = "done"; #expect(!k.etkin)
        k.durum = "cancelled"; #expect(!k.etkin)
    }
    @Test func httpsYonlendirmeleriDosyaIndirmesiniKorur() {
        var genel = URLRequest(url: URL(string: "https://site.example/dosya")!)
        let cdn = URLRequest(url: URL(string: "https://cdn.example/dosya.zip")!)
        #expect(IndirmeTemsilcisi.yonlendirmeyeIzinVer(orijinal: genel, yeni: cdn))
        #expect(!IndirmeTemsilcisi.yonlendirmeyeIzinVer(orijinal: genel, yeni: URLRequest(url: URL(string: "http://cdn.example/dosya.zip")!)))
        genel.setValue("kişisel", forHTTPHeaderField: "X-Personal-Token")
        #expect(!IndirmeTemsilcisi.yonlendirmeyeIzinVer(orijinal: genel, yeni: cdn))
        #expect(IndirmeTemsilcisi.yonlendirmeyeIzinVer(orijinal: genel, yeni: URLRequest(url: URL(string: "https://site.example/indir")!)))
    }
    @Test func kazimaRaporuTumVeriTurleriniCozuyor() throws {
        let json = #"{"kaynak":"https://example.com","baslik":"Örnek","aciklama":"Açıklama","dil":"tr","taramaTarihi":"2026-10-18T12:00:00.000Z","ogeler":[{"id":"1","tur":"metin","ad":"P 1","deger":"Merhaba","url":null},{"id":"2","tur":"gorsel","ad":"Kapak","deger":"https://example.com/a.jpg","url":"https://example.com/a.jpg"},{"id":"3","tur":"tablo","ad":"Tablo 1 · satır 1","deger":"[\"A\",\"B\"]","url":null}]}"#
        let rapor = try JSONDecoder().decode(KazimaRaporu.self, from: Data(json.utf8))
        #expect(rapor.baslik == "Örnek")
        #expect(rapor.ogeler.map(\.tur) == ["metin", "gorsel", "tablo"])
        #expect(rapor.ogeler[1].url == "https://example.com/a.jpg")
        let csv = String(decoding: try KazimaDisaAktarici.veri(rapor, csv: true), as: UTF8.self)
        #expect(csv.contains("\"gorsel\",\"Kapak\""))
        #expect(csv.contains("[\"\"A\"\",\"\"B\"\"]"))
        let yeniden = try JSONDecoder().decode(KazimaRaporu.self, from: KazimaDisaAktarici.veri(rapor, csv: false))
        #expect(yeniden.ogeler == rapor.ogeler)
    }
    @Test func hizliKazimaHTMLMetinBaglantiMedyaVeTabloyuCikarir() {
        let html = """
        <html lang="tr"><head><title>Örnek Sayfa</title><meta name="description" content="Kısa açıklama"></head>
        <body><p>Merhaba dünya</p><a href="/dosya.pdf">PDF dosyası</a><img src="/kapak.jpg" title="Kapak"><audio src="/ses.mp3"></audio>
        <table><tr><th>Ad</th><th>Değer</th></tr><tr><td>Renk</td><td>Mercan</td></tr></table>
        <script type="application/ld+json">{"@type":"Article"}</script></body></html>
        """
        let rapor = WebKazimaHizli.rapor(html: html, kaynak: URL(string: "https://example.com/yol/")!)
        #expect(rapor.baslik == "Örnek Sayfa")
        #expect(rapor.aciklama == "Kısa açıklama")
        #expect(rapor.dil == "tr")
        #expect(rapor.ogeler.contains { $0.tur == "dosya" && $0.url == "https://example.com/dosya.pdf" })
        #expect(rapor.ogeler.contains { $0.tur == "gorsel" && $0.url == "https://example.com/kapak.jpg" })
        #expect(rapor.ogeler.contains { $0.tur == "ses" && $0.url == "https://example.com/ses.mp3" })
        #expect(rapor.ogeler.contains { $0.tur == "tablo" && $0.deger.contains("Mercan") })
        #expect(rapor.ogeler.contains { $0.tur == "yapisal-veri" })
    }
    @Test func gercekExcelPaketiOlusturulurVeHucrelerMetindir() throws {
        let json = #"{"columns":["Başlık","Fiyat","URL"],"rows":[["Simyacı & Dünya","=1+1","https://example.com/a"],["İkinci",42,null]]}"#
        let tablo = try ExcelOlusturucu.tablo(json)
        #expect(tablo.satirlar.count == 2)
        #expect(tablo.satirlar[1] == ["İkinci", "42", ""])
        let xlsx = ExcelOlusturucu.xlsx(tablo)
        #expect(xlsx.starts(with: Data([0x50, 0x4b, 0x03, 0x04])))
        let ham = String(decoding: xlsx, as: UTF8.self)
        #expect(ham.contains("xl/worksheets/sheet1.xml"))
        #expect(ham.contains("Simyacı &amp; Dünya"))
        #expect(ham.contains("<t xml:space=\"preserve\">=1+1</t>"))
    }
    @Test func excelSinirlariUygulanir() {
        #expect(throws: (any Error).self) { try ExcelOlusturucu.tablo(#"{"columns":[],"rows":[]}"#) }
        #expect(throws: (any Error).self) { try ExcelOlusturucu.tablo(#"{"columns":["A"],"rows":"yanlış"}"#) }
    }
    @Test func ofisPaketleriVePdfGercekDosyadir() throws {
        let json = #"{"title":"Proje Raporu","paragraphs":["Birinci paragraf","İkinci paragraf"],"table":{"columns":["Ad","Değer"],"rows":[["Hız",42]]},"slides":[{"title":"Başlangıç","body":["Madde bir","Madde iki"]}]}"#
        let i = try OfisOlusturucu.icerik(json)
        let docx = OfisOlusturucu.docx(i), pptx = OfisOlusturucu.pptx(i), pdf = OfisOlusturucu.pdf(i)
        #expect(docx.starts(with: Data([0x50, 0x4b, 0x03, 0x04])))
        #expect(pptx.starts(with: Data([0x50, 0x4b, 0x03, 0x04])))
        #expect(pdf.starts(with: Data("%PDF".utf8)))
        let kok = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: kok, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: kok) }
        let d = kok.appending(path: "rapor.docx"), p = kok.appending(path: "sunum.pptx")
        try docx.write(to: d); try pptx.write(to: p)
        let da = try Archive(url: d, accessMode: .read), pa = try Archive(url: p, accessMode: .read)
        #expect(da["word/document.xml"] != nil)
        #expect(pa["ppt/presentation.xml"] != nil)
        #expect(pa["ppt/slides/slide1.xml"] != nil)
    }
    @Test func wordIcerigiExcelVeSunumYapisinaDonusur() throws {
        let belge = OkunanBelge(ad: "Rapor.docx", metin: "[word/document.xml]\nBirinci paragraf\nİkinci paragraf\nÜçüncü paragraf", not: "")
        let i = OfisDonusturucu.icerik(belge)
        #expect(i.baslik == "Rapor")
        #expect(i.tablo?.sutunlar == ["Sıra", "İçerik"])
        #expect(i.tablo?.satirlar == [["1", "Birinci paragraf"], ["2", "İkinci paragraf"], ["3", "Üçüncü paragraf"]])
        #expect(i.slaytlar.count == 1)
        let xlsx = ExcelOlusturucu.xlsx(try #require(i.tablo))
        #expect(String(decoding: xlsx, as: UTF8.self).contains("Birinci paragraf"))
    }
    @Test func zipOlusturulurVeGuvenleAcilir() throws {
        let kok = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: kok, withIntermediateDirectories: true)
        let a = kok.appending(path: "Bir.txt"), b = kok.appending(path: "İki.csv")
        try "Merhaba ZIP".write(to: a, atomically: true, encoding: .utf8)
        try "A,B\n1,2".write(to: b, atomically: true, encoding: .utf8)
        let zip = try ArsivIslemleri.zipOlustur([a, b], ad: "Sinama")
        let acilan = try ArsivIslemleri.ac(zip, parola: nil)
        defer { try? FileManager.default.removeItem(at: kok); try? FileManager.default.removeItem(at: zip); try? FileManager.default.removeItem(at: acilan.0) }
        #expect(zip.pathExtension == "zip")
        #expect(acilan.1.count == 2)
        #expect(acilan.1.contains { $0.lastPathComponent == "Bir.txt" })
        #expect(acilan.1.contains { $0.pathExtension == "csv" })
        #expect(try String(contentsOf: acilan.1.first { $0.lastPathComponent == "Bir.txt" }!, encoding: .utf8) == "Merhaba ZIP")
        #expect(!ArsivIslemleri.guvenli("../gizli.txt"))
        #expect(ArsivIslemleri.guvenli("klasor/dosya.txt"))
    }
    @Test func gercekRar5ArsiviAcilir() throws {
        let baytlar: [UInt8] = [
            0x52,0x61,0x72,0x21,0x1a,0x07,0x01,0x00,0x33,0x92,0xb5,0xe5,0x0a,0x01,0x05,0x06,0x00,0x05,0x01,0x01,0x80,0x80,0x00,0xf7,
            0x12,0xa7,0xe5,0x1f,0x02,0x02,0xa8,0x00,0x06,0xa8,0x00,0xa4,0x83,0x02,0x16,0x3b,0xf1,0x5f,0x57,0xb5,0x06,0x7a,0x80,0x00,
            0x01,0x09,0x52,0x45,0x41,0x44,0x4d,0x45,0x2e,0x6d,0x64,0x23,0x20,0x55,0x6e,0x72,0x61,0x72,0x0a,0x0a,0x41,0x20,0x64,0x65,
            0x73,0x63,0x72,0x69,0x70,0x74,0x69,0x6f,0x6e,0x20,0x6f,0x66,0x20,0x74,0x68,0x69,0x73,0x20,0x70,0x61,0x63,0x6b,0x61,0x67,
            0x65,0x2e,0x0a,0x1d,0x77,0x56,0x51,0x03,0x05,0x04,0x00
        ]
        let rar = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".rar")
        try Data(baytlar).write(to: rar)
        let acilan = try ArsivIslemleri.ac(rar, parola: nil)
        defer { try? FileManager.default.removeItem(at: rar); try? FileManager.default.removeItem(at: acilan.0) }
        #expect(acilan.1.map(\.lastPathComponent) == ["README.md"])
        #expect(try Data(contentsOf: acilan.1[0]).count == 40)
    }
}
