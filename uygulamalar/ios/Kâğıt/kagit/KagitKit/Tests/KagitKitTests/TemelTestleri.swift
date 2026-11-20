import Foundation
import PDFKit
import Testing
@testable import KagitKit

/// Testlerde kullanılan örnek PDF üreticisi: her sayfaya verilen satırları yazar.
enum Ornek {
    static func pdf(_ sayfalar: [[String]], boyut: CGSize = PDFCizim.Boyut.a4.boyut) -> Data {
        let y = PDFCizim.Yazici(baslik: "Örnek")
        for satirlar in sayfalar {
            y.sayfa(CGRect(origin: .zero, size: boyut)) { ctx in
                for (i, s) in satirlar.enumerated() {
                    PDFCizim.metin(s, ctx, nokta: CGPoint(x: 72, y: boyut.height - 100 - CGFloat(i) * 30), punto: 16)
                }
            }
        }
        return y.bitir()
    }

    static func belge(_ sayfalar: [[String]]) -> PDFDocument { PDFDocument(data: pdf(sayfalar))! }

    static func numarali(_ n: Int) -> PDFDocument { belge((1...n).map { ["Sayfa \($0)"] }) }

    static func gecici(_ ad: String = "test.pdf") -> URL { Gecici.dosya(ad) }
}

@Suite struct SayfaAraligiTestleri {
    @Test func temelAraliklar() throws {
        #expect(try SayfaAraligi.coz("1-3, 5, 8-", sayfaSayisi: 10) == [0, 1, 2, 4, 7, 8, 9])
        #expect(try SayfaAraligi.coz("", sayfaSayisi: 3) == [0, 1, 2])
        #expect(try SayfaAraligi.coz("tek", sayfaSayisi: 5) == [0, 2, 4])
        #expect(try SayfaAraligi.coz("çift", sayfaSayisi: 5) == [1, 3])
        #expect(try SayfaAraligi.coz("-2", sayfaSayisi: 5) == [0, 1])
        #expect(try SayfaAraligi.coz("son", sayfaSayisi: 5) == [4])
        #expect(try SayfaAraligi.coz("son-1", sayfaSayisi: 5) == [3])
        #expect(try SayfaAraligi.coz("HEPSİ", sayfaSayisi: 2) == [0, 1])
    }

    @Test func gecersizAralik() {
        #expect(throws: KagitHata.self) { try SayfaAraligi.coz("0", sayfaSayisi: 5) }
        #expect(throws: KagitHata.self) { try SayfaAraligi.coz("4-2", sayfaSayisi: 5) }
        #expect(throws: KagitHata.self) { try SayfaAraligi.coz("abc", sayfaSayisi: 5) }
        #expect(throws: KagitHata.self) { try SayfaAraligi.coz("9", sayfaSayisi: 5) }
    }

    @Test func metneCevir() {
        #expect(SayfaAraligi.metin([0, 1, 2, 4, 7, 8]) == "1-3, 5, 8-9")
        #expect(SayfaAraligi.metin([3]) == "4")
    }
}

@Suite struct TurkceMetinTestleri {
    @Test func anahtarVeBenzerlik() {
        #expect(TurkceMetin.anahtar("  İSMAİL Çağrı-Öztürk ") == "ismail cagri ozturk")
        #expect(TurkceMetin.benzerlik("Ayşe Yılmaz", "AYSE YILMAZ") == 1)
        #expect(TurkceMetin.benzerlik("Ayşe Yılmaz", "Ayse Yilmas") > 0.85)
    }

    @Test func listedenEslesme() {
        let sinif = ["Ali Veli", "Ayşe Yılmaz", "Mehmet Öztürk", "Zeynep Kaya"]
        #expect(TurkceMetin.enIyiEslesme("Adı Soyadı: Ayse Yilmaz  No: 12", sinif)?.indeks == 1)
        #expect(TurkceMetin.enIyiEslesme("Öztürk Mehmet", sinif)?.indeks == 2)
        #expect(TurkceMetin.enIyiEslesme("Bambaşka Biri", sinif) == nil)
    }

    @Test func dosyaAdiVeOCR() {
        #expect(TurkceMetin.dosyaAdi("a/b:c?.pdf") == "a b c .pdf")
        #expect(TurkceMetin.dosyaAdi("  ") == "Belge")
        #expect(TurkceMetin.ocrDuzelt("Imza: Istanbul") == "İmza: İstanbul")
    }
}

@Suite struct ZipTestleri {
    @Test func gidisDonus() {
        var z = ZipYazici()
        z.ekle("mimetype", metin: "application/epub+zip", sakla: true)
        let uzun = String(repeating: "Merhaba dünya ğüşıöç. ", count: 200)
        z.ekle("klasor/belge.xml", metin: uzun)
        let veri = z.bitir()
        let acilan = ZipOkuyucu.ac(veri)
        #expect(String(data: acilan["mimetype"]!, encoding: .utf8) == "application/epub+zip")
        #expect(String(data: acilan["klasor/belge.xml"]!, encoding: .utf8) == uzun)
        #expect(veri.count < uzun.utf8.count) // sıkıştırıldı
    }

    @Test func crc() {
        #expect(CRC32.hesapla(Data("123456789".utf8)) == 0xCBF4_3926)
    }
}

@Suite struct BelgeTestleri {
    @Test func kaydetVeDogrula() throws {
        let belge = Ornek.numarali(3)
        let hedef = Ornek.gecici()
        try Belge.kaydet(belge, hedef)
        let acilan = try Belge.ac(hedef)
        #expect(acilan.pageCount == 3)
        #expect(acilan.page(at: 1)?.string?.contains("Sayfa 2") == true)
    }

    @Test func parolaliKayit() throws {
        let hedef = Ornek.gecici()
        try Belge.kaydet(Ornek.numarali(2), hedef,
                         secenekler: KayitSecenekleri(kullaniciParolasi: "gizli1", sahipParolasi: "sahip2"))
        #expect(Belge.parolaIstiyorMu(hedef))
        #expect(throws: KagitHata.parolaGerekli) { try Belge.ac(hedef) }
        #expect(throws: KagitHata.parolaYanlis) { try Belge.ac(hedef, parola: "yanlis") }
        #expect(try Belge.ac(hedef, parola: "gizli1").pageCount == 2)
    }

    @Test func anonimlestirmeKagitIsaretiniKorur() throws {
        let belge = Ornek.numarali(1)
        let sayfa = belge.page(at: 0)!
        let a = PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 50, height: 20), forType: .freeText, withProperties: nil)
        a.userName = Isaret.puan(2.5)
        let b = PDFAnnotation(bounds: CGRect(x: 100, y: 10, width: 50, height: 20), forType: .freeText, withProperties: nil)
        b.userName = "Mehmet Bey"
        sayfa.addAnnotation(a); sayfa.addAnnotation(b)
        let acilan = PDFDocument(data: try Belge.veri(belge))!
        let adlar = acilan.page(at: 0)!.annotations.compactMap(\.userName)
        #expect(adlar.contains(Isaret.puan(2.5)))
        #expect(!adlar.contains("Mehmet Bey"))
        #expect(Isaret.puanDegeri(Isaret.puan(2.5)) == 2.5)
    }
}

@Suite struct PdfiumTestleri {
    @Test func metinNesnesiniTurkceDegistir() throws {
        let veri = Ornek.pdf([["Eski satır burada", "Kalacak satır"]])
        let pb = try PdfiumBelge(veri: veri)
        #expect(pb.sayfaSayisi == 1)
        let nesneler = try pb.metinNesneleri(sayfa: 0)
        let eski = try #require(nesneler.first { $0.metin.contains("Eski") })
        #expect(abs(eski.punto - 16) < 0.5)
        try pb.nesneleriSil(sayfa: 0, indeksler: [eski.indeks])
        try pb.metinEkle(sayfa: 0, metin: "Değişti: ĞÜŞİ ığüşöç", taban: CGPoint(x: eski.kutu.minX, y: eski.kutu.minY + 3),
                         punto: eski.punto, yaziTipi: .eslestir(eski.yaziTipiAdi))
        let cikti = try pb.kaydet()
        let metin = PDFDocument(data: cikti)!.page(at: 0)!.string ?? ""
        #expect(!metin.contains("Eski"))
        #expect(metin.contains("Kalacak"))
        #expect(metin.replacingOccurrences(of: "\u{00A0}", with: " ").contains("ĞÜŞİ ığüşöç"))
    }

    @Test func kutudakileriSil() throws {
        let pb = try PdfiumBelge(veri: Ornek.pdf([["Gizli bilgi 12345", "Açık bilgi"]]))
        let gizli = try #require(try pb.metinNesneleri(sayfa: 0).first { $0.metin.contains("Gizli") })
        let silinen = try pb.kutudakileriSil(sayfa: 0, kutular: [gizli.kutu.insetBy(dx: 2, dy: 2)], turler: .metin)
        #expect(silinen == 1)
        let metin = PDFDocument(data: try pb.kaydet())!.page(at: 0)!.string ?? ""
        #expect(!metin.contains("12345"))
        #expect(metin.contains("Açık"))
    }

    @Test func parolaliBelge() throws {
        let belge = Ornek.numarali(1)
        let veri = belge.dataRepresentation(options: [PDFDocumentWriteOption.userPasswordOption: "abc", PDFDocumentWriteOption.ownerPasswordOption: "abc"])!
        #expect(throws: KagitHata.parolaGerekli) { try PdfiumBelge(veri: veri) }
        #expect(try PdfiumBelge(veri: veri, parola: "abc").sayfaSayisi == 1)
    }
}

@Suite struct OCRTestleri {
    @Test func turkceSatirlariTanir() async throws {
        let belge = Ornek.belge([["Sözleşme tarafları: Ayşe Yılmaz", "Öğrenci No: 1234"]])
        let satirlar = try await MetinTanima.tani(sayfa: belge.page(at: 0)!)
        let metin = MetinTanima.metin(satirlar)
        #expect(metin.contains("Ayşe"))
        #expect(metin.contains("1234"))
    }
}
