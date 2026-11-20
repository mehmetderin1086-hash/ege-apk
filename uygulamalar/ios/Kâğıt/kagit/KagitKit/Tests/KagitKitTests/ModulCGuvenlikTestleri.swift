import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import KagitKit

@Suite struct ParolaTestleri {
    @Test func kullaniciParolasiKoyVeKaldir() throws {
        let girdi = Ornek.pdf([["Gizli belge"], ["İkinci sayfa"]])
        let sifreli = try Koruma.parolaKoy(veri: girdi, kullaniciParolasi: "abc123", sahipParolasi: "sahip456")
        let d = try #require(PDFDocument(data: sifreli))
        #expect(d.isEncrypted)
        #expect(d.isLocked)
        #expect(!d.unlock(withPassword: "yanlis"))
        #expect(d.unlock(withPassword: "abc123"))
        #expect(d.pageCount == 2)
        #expect(Koruma.durum(veri: sifreli) == Koruma.Durum(sifreli: true, kilitli: true))

        // Parola olmadan / yanlış parolayla kaldırılamaz
        #expect(throws: KagitHata.parolaGerekli) { try Koruma.parolaKaldir(veri: sifreli, parola: nil) }
        #expect(throws: KagitHata.parolaYanlis) { try Koruma.parolaKaldir(veri: sifreli, parola: "yanlis") }

        let acik = try Koruma.parolaKaldir(veri: sifreli, parola: "abc123")
        let a = try #require(PDFDocument(data: acik))
        #expect(!a.isEncrypted)
        #expect(!a.isLocked)
        #expect(a.pageCount == 2)
        #expect(a.string?.contains("Gizli belge") == true)
    }

    @Test func izinlerUygulanir() throws {
        let girdi = Ornek.pdf([["İzin denemesi"]])
        let veri = try Koruma.parolaKoy(veri: girdi, kullaniciParolasi: nil, sahipParolasi: "sahip",
                                        izinler: [.yazdirma])
        let d = try #require(PDFDocument(data: veri))
        #expect(d.isEncrypted)
        #expect(!d.isLocked)             // açılış serbest
        #expect(d.allowsPrinting)
        #expect(!d.allowsCopying)
        #expect(!d.allowsDocumentChanges)
        // Sahip parolası ile izinsiz kopya alınabilir
        let acik = try Koruma.parolaKaldir(veri: veri, parola: "sahip")
        let a = try #require(PDFDocument(data: acik))
        #expect(!a.isEncrypted)
        #expect(a.allowsCopying)
    }

    @Test func izinKisitiSahipParolasiIster() {
        let girdi = Ornek.pdf([["x"]])
        #expect(throws: KagitHata.self) {
            try Koruma.parolaKoy(veri: girdi, kullaniciParolasi: "a", sahipParolasi: nil, izinler: [.yazdirma])
        }
        #expect(throws: KagitHata.self) {
            try Koruma.parolaKoy(veri: girdi, kullaniciParolasi: nil, sahipParolasi: nil)
        }
    }

    @Test func parolasizDosyadaKaldirmaHataVerir() {
        #expect(throws: KagitHata.self) { try Koruma.parolaKaldir(veri: Ornek.pdf([["a"]]), parola: "x") }
    }

    @Test func parolaliBelgeyiYenidenParolalar() throws {
        let ilk = try Koruma.parolaKoy(veri: Ornek.pdf([["Zincir"]]), kullaniciParolasi: "bir", sahipParolasi: nil)
        let ikinci = try Koruma.parolaKoy(veri: ilk, kaynakParola: "bir", kullaniciParolasi: "iki", sahipParolasi: nil)
        let d = try #require(PDFDocument(data: ikinci))
        #expect(!d.unlock(withPassword: "bir"))
        #expect(d.unlock(withPassword: "iki"))
    }
}

@Suite struct KarartmaTestleri {
    static let icerik = """
    BT /F1 24 Tf 72 700 Td (GIZLIKELIME ve herkese acik metin) Tj ET
    BT /F1 24 Tf 72 650 Td (TC 10000000146 nolu kisi) Tj ET
    BT /F1 24 Tf 72 600 Td (Normal satir korunur) Tj ET
    """

    @Test func hazirDesenDogrulayicilari() {
        #expect(HazirDesen.tcGecerli("10000000146"))
        #expect(!HazirDesen.tcGecerli("10000000147"))
        #expect(!HazirDesen.tcGecerli("00000000000"))
        #expect(HazirDesen.ibanGecerli("TR33 0006 1005 1978 6457 8413 26"))
        #expect(!HazirDesen.ibanGecerli("TR34 0006 1005 1978 6457 8413 26"))
        let ep = try! NSRegularExpression(pattern: HazirDesen.eposta.ifade)
        let s = "yaz: ali.veli@okul.k12.tr tamam"
        #expect(ep.numberOfMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length)) == 1)
        let tel = try! NSRegularExpression(pattern: HazirDesen.telefon.ifade)
        for t in ["0532 123 45 67", "+90 532 123 45 67", "(0212) 555 12 34", "05321234567"] {
            #expect(tel.numberOfMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length)) == 1, "\(t)")
        }
        let trh = try! NSRegularExpression(pattern: HazirDesen.tarih.ifade)
        for t in ["12.03.2026", "1/2/99", "31-12-2025"] {
            #expect(trh.numberOfMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length)) == 1, "\(t)")
        }
    }

    @Test func tcNumarasiTelefonSanilmaz() throws {
        let tel = try NSRegularExpression(pattern: HazirDesen.telefon.ifade)
        let s = "10000000146"
        #expect(tel.numberOfMatches(in: s, range: NSRange(location: 0, length: s.count)) == 0)
    }

    @Test func aramaTabanliKarartmaMetniGercektenSiler() async throws {
        let girdi = ModulC.hamPDF(Self.icerik)
        // Fikstür gerçekten ham baytta metin içeriyor (testin anlamlı olması için)
        #expect(ModulC.bayttaVar(girdi, "GIZLIKELIME"))
        #expect(PDFDocument(data: girdi)?.string?.contains("GIZLIKELIME") == true)

        let (cikti, rapor) = try await Karartma.karart(veri: girdi, kurallar: [.ifade("gizlikelime")])
        #expect(rapor.karartilanBolge >= 1)
        #expect(rapor.degisenSayfalar == [0])
        let belge = try #require(PDFDocument(data: cikti))
        #expect(belge.pageCount == 1)
        let metin = belge.string ?? ""
        #expect(!metin.localizedCaseInsensitiveContains("GIZLIKELIME"), "kalan metin: \(metin)")
        // Ham baytlarda da yok (yapı değiştirildi, eski içerik akışı atıldı)
        #expect(!ModulC.bayttaVar(cikti, "GIZLIKELIME"))
        #expect(belge.findString("GIZLIKELIME", withOptions: .caseInsensitive).isEmpty)
        // Kalan metin için OCR katmanı eklendi
        #expect(TurkceMetin.anahtar(metin).contains("normal satir"), "OCR katmanı: \(metin)")
    }

    @Test func sayfaGoruntuOlurVeKutuSiyahtir() async throws {
        let girdi = ModulC.hamPDF(Self.icerik)
        let (cikti, _) = try await Karartma.karart(veri: girdi, kurallar: [.ifade("GIZLIKELIME")])
        let belge = try #require(PDFDocument(data: cikti))
        let g = try #require(PDFCizim.goruntu(belge.page(at: 0)!, dpi: 72))
        // "GIZLIKELIME" yaklaşık x:72-200, y(alttan): 700-718 civarı
        let p = TaramaIslemleriTestleri.piksel(g, 100, 704)
        #expect(p < 30, "kutu içi piksel \(p)")
    }

    @Test func hazirDesenTCKimlikKarartir() async throws {
        let girdi = ModulC.hamPDF(Self.icerik)
        var s = KarartmaSecenekleri()
        s.kalanMetinIcinOCR = false
        let (cikti, rapor) = try await Karartma.karart(veri: girdi, kurallar: [.hazir(.tcKimlik)], secenekler: s)
        #expect(rapor.karartilanBolge >= 1)
        let belge = try #require(PDFDocument(data: cikti))
        #expect(belge.page(at: 0)?.string?.isEmpty ?? true)       // OCR katmanı da kapalı: metin hiç yok
        #expect(!ModulC.bayttaVar(cikti, "10000000146"))
    }

    @Test func eslesmeYoksaBolgeBulunmaz() async throws {
        let b = try await Karartma.bul(veri: ModulC.hamPDF(Self.icerik), kurallar: [.ifade("olmayan kelime")])
        #expect(b.isEmpty)
        await #expect(throws: KagitHata.self) {
            _ = try await Karartma.uygula(veri: ModulC.hamPDF(Self.icerik), bolgeler: [])
        }
    }

    @Test func duzenliIfadeVeGecersizIfade() async throws {
        let b = try await Karartma.bul(veri: ModulC.hamPDF(Self.icerik), kurallar: [.duzenliIfade(#"GIZLI\w+"#)])
        #expect(!b.isEmpty)
        await #expect(throws: KagitHata.self) {
            _ = try await Karartma.bul(veri: ModulC.hamPDF(Self.icerik), kurallar: [.duzenliIfade("(")])
        }
    }

    @Test func elleBolgeKarartir() async throws {
        let girdi = ModulC.hamPDF(Self.icerik)
        var s = KarartmaSecenekleri()
        s.kalanMetinIcinOCR = false
        // Ekran uzayı: sayfa 595x842, "herkese acik metin" satırı y≈700 (alt köken)
        let bolge = KarartmaBolgesi(sayfa: 0, kutu: CGRect(x: 60, y: 690, width: 475, height: 40))
        let (cikti, rapor) = try await Karartma.uygula(veri: girdi, bolgeler: [bolge], secenekler: s)
        #expect(rapor.degisenSayfalar == [0])
        #expect(!ModulC.bayttaVar(cikti, "herkese acik"))
        #expect(PDFDocument(data: cikti)?.string?.contains("herkese") != true)
    }

    @Test func sadeceIlgiliSayfaDegisirDigerleriMetinKalir() async throws {
        let belge = PDFDocument(data: Ornek.pdf([["Birinci SIRKEL sayfa"], ["Ikinci temiz sayfa"]]))!
        let girdi = try #require(belge.dataRepresentation())
        let (cikti, rapor) = try await Karartma.karart(veri: girdi, kurallar: [.ifade("SIRKEL")])
        #expect(rapor.degisenSayfalar == [0])
        let c = try #require(PDFDocument(data: cikti))
        #expect(c.page(at: 1)?.string?.contains("Ikinci temiz sayfa") == true)   // dokunulmadı (vektör metin)
        #expect(c.string?.localizedCaseInsensitiveContains("SIRKEL") == false)
    }

    @Test func aciklamaIcerigiSizdirmaz() async throws {
        let belge = PDFDocument(data: Ornek.pdf([["Sayfa bir SIRKEL"], ["Sayfa iki"]]))!
        let not = PDFAnnotation(bounds: CGRect(x: 50, y: 50, width: 20, height: 20), forType: .text, withProperties: nil)
        not.contents = "gizli not: sirkel hakkında"
        belge.page(at: 1)?.addAnnotation(not)
        let girdi = try #require(belge.dataRepresentation())
        var s = KarartmaSecenekleri()
        s.aciklamalariSil = false      // yine de eşleşen içerik silinmeli
        let (cikti, rapor) = try await Karartma.karart(veri: girdi, kurallar: [.ifade("SIRKEL")], secenekler: s)
        #expect(rapor.silinenAciklama >= 1)
        let c = try #require(PDFDocument(data: cikti))
        #expect(c.page(at: 1)?.annotations.contains { ($0.contents ?? "").localizedCaseInsensitiveContains("sirkel") } != true)
    }

    @Test func taranmisSayfadaOCRIleKarartma() async throws {
        let g = ModulC.taramaGoruntusu(["Sifre: ALTINANAHTAR", "Herkese acik satir"])
        var oc = AranabilirSecenekleri()
        oc.ocr = false
        let girdi = try await AranabilirPDF.gorsellerdenPDF([g], secenekler: oc)
        let (cikti, rapor) = try await Karartma.karart(veri: girdi, kurallar: [.ifade("ALTINANAHTAR")])
        #expect(rapor.karartilanBolge >= 1, "OCR eşleşmesi bulunamadı")
        let metin = PDFDocument(data: cikti)?.string ?? ""
        #expect(!metin.localizedCaseInsensitiveContains("ALTINANAHTAR"))
        #expect(TurkceMetin.anahtar(metin).contains("herkese acik"), "kalan metin: \(metin)")
    }

    @Test func dondurulmusSayfadaKoordinatlar() throws {
        let belge = PDFDocument(data: Ornek.pdf([["x"]]))!
        let s = belge.page(at: 0)!
        let b0 = Karartma.ekranBoyutu(s)
        s.rotation = 90
        let b90 = Karartma.ekranBoyutu(s)
        #expect(b0.width == b90.height && b0.height == b90.width)
        let r = Karartma.ekranKutusu(CGRect(x: 0, y: 0, width: 100, height: 50), sayfa: s)
        // 90° saat yönü: sol alt köşe, ekranda sol üste gider
        #expect(abs(r.minX - 0) < 0.01 && abs(r.width - 50) < 0.01 && abs(r.height - 100) < 0.01)
        #expect(abs(r.maxY - b90.height) < 0.01)
    }

    @Test func ustVeriVeYerImiTemizlenir() async throws {
        let xmp = "<?xpacket begin='' id='W5M0MpCehiHzreSzNTczkc9d'?><x:xmpmeta xmlns:x='adobe:ns:meta/'><rdf:RDF xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#'><rdf:Description><dc:creator>XMPYAZAR</dc:creator></rdf:Description></rdf:RDF></x:xmpmeta><?xpacket end='w'?>"
        let girdi = ModulC.hamPDF(Self.icerik, xmp: xmp, yazar: "INFOYAZAR")
        let (cikti, rapor) = try await Karartma.karart(veri: girdi, kurallar: [.ifade("GIZLIKELIME")])
        #expect(rapor.ustVeri?.xmpTemiz == true)
        #expect(!ModulC.bayttaVar(cikti, "XMPYAZAR"))
        #expect(!ModulC.bayttaVar(cikti, "INFOYAZAR"))
        #expect(!ModulC.bayttaVar(cikti, "Gizli Baslik"))
        #expect(PDFDocument(data: cikti)?.documentAttributes?[PDFDocumentAttribute.authorAttribute] == nil)
    }
}

@Suite struct UstVeriTestleri {
    static let xmp = "<?xpacket begin='' id='W5M0MpCehiHzreSzNTczkc9d'?><x:xmpmeta xmlns:x='adobe:ns:meta/'><rdf:RDF xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#'><rdf:Description xmlns:dc='http://purl.org/dc/elements/1.1/'><dc:creator>XMPYAZAR</dc:creator></rdf:Description></rdf:RDF></x:xmpmeta><?xpacket end='w'?>"

    @Test func okuYazDonguSu() throws {
        let girdi = Ornek.pdf([["Üst veri"]])
        var u = UstVeri()
        u.baslik = "Biyoloji Sınavı"
        u.yazar = "Mehmet Derin"
        u.konu = "Hücre"
        u.anahtarSozcukler = ["biyoloji", "sınav"]
        let (yazilan, _) = try UstVeriIslemleri.yaz(veri: girdi, ustVeri: u)
        let oku = try UstVeriIslemleri.oku(veri: yazilan)
        #expect(oku.baslik == "Biyoloji Sınavı")
        #expect(oku.yazar == "Mehmet Derin")
        #expect(oku.konu == "Hücre")
        #expect(oku.anahtarSozcukler == ["biyoloji", "sınav"])
    }

    @Test func tumunuTemizleXMPDahil() throws {
        let girdi = ModulC.hamPDF("BT /F1 24 Tf 72 700 Td (Metin) Tj ET", xmp: Self.xmp, yazar: "INFOYAZAR")
        #expect(ModulC.bayttaVar(girdi, "XMPYAZAR"))
        // PDFKit tek başına yetmez (ölçüldü): saf attributes temizliği XMP'yi bırakır
        let d = try #require(PDFDocument(data: girdi))
        d.documentAttributes = [:]
        #expect(ModulC.bayttaVar(try #require(d.dataRepresentation()), "XMPYAZAR"))

        let (temiz, rapor) = try UstVeriIslemleri.hepsiniTemizle(veri: girdi)
        #expect(rapor.xmpTemiz)
        #expect(!ModulC.bayttaVar(temiz, "XMPYAZAR"))
        #expect(!ModulC.bayttaVar(temiz, "INFOYAZAR"))
        #expect(!UstVeriIslemleri.xmpVarMi(temiz))
        let a = try #require(PDFDocument(data: temiz))
        #expect(a.pageCount == 1)
        #expect(a.string?.contains("Metin") == true)
        #expect(try UstVeriIslemleri.oku(veri: temiz).yazar.isEmpty)
    }

    @Test func yazmaEskiXMPyiAtar() throws {
        let girdi = ModulC.hamPDF("BT /F1 24 Tf 72 700 Td (Metin) Tj ET", xmp: Self.xmp)
        var u = UstVeri()
        u.baslik = "Yeni"
        let (yazilan, rapor) = try UstVeriIslemleri.yaz(veri: girdi, ustVeri: u)
        #expect(rapor.xmpTemiz)
        #expect(!ModulC.bayttaVar(yazilan, "XMPYAZAR"))
        #expect(try UstVeriIslemleri.oku(veri: yazilan).baslik == "Yeni")
    }

    @Test func xmpsizDosyadaDogrudanTemiz() throws {
        let (c, r) = try UstVeriIslemleri.hepsiniTemizle(veri: Ornek.pdf([["a"]]))
        #expect(r.xmpTemiz)
        #expect(PDFDocument(data: c)?.pageCount == 1)
    }
}
