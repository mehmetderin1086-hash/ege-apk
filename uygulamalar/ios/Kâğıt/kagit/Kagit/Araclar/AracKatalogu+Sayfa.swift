import KagitKit
import SwiftUI
import UniformTypeIdentifiers

// Modül A: sayfa, damga, sıkıştırma, dönüştürme, karşılaştırma araçları.
// Dışarıdan çağrılan kimlikler: birlestir, sikistir, gorseldenPDF, belgedenPDF, bosPDF, pdftenWord, filigran.
extension AracKatalogu {
    static var sayfaAraclari: [Arac] {
        [
            Arac(id: "birlestir", ad: "Birleştir", aciklama: "Birden çok PDF'i tek dosyada topla", simge: "doc.on.doc",
                 kategori: .sayfa, girdi: .cokPDF) { BirlestirEkrani(baglam: $0) },
            Arac(id: "bol", ad: "Böl", aciklama: "Aralığa, sayfa sayısına ya da boyuta göre ayır", simge: "scissors",
                 kategori: .sayfa, girdi: .birVeyaCokPDF, topluUygun: true) { BolEkrani(baglam: $0) },
            Arac(id: "sayfaCikar", ad: "Sayfa çıkar", aciklama: "Seçili sayfalardan yeni PDF yap", simge: "square.and.arrow.up.on.square",
                 kategori: .sayfa, girdi: .birVeyaCokPDF, topluUygun: true) { SayfaCikarSilEkrani(baglam: $0, sil: false) },
            Arac(id: "sayfaSil", ad: "Sayfa sil", aciklama: "İstenmeyen sayfaları kaldır", simge: "trash",
                 kategori: .sayfa, girdi: .birVeyaCokPDF, topluUygun: true) { SayfaCikarSilEkrani(baglam: $0, sil: true) },
            Arac(id: "dondur", ad: "Döndür", aciklama: "Sayfaları 90°, 180°, 270° çevir", simge: "rotate.right",
                 kategori: .sayfa, girdi: .birVeyaCokPDF, topluUygun: true) { DondurEkrani(baglam: $0) },
            Arac(id: "sirala", ad: "Sırala", aciklama: "Ters çevir, tek/çift ayır, çift taraflı taramayı birleştir", simge: "arrow.up.arrow.down",
                 kategori: .sayfa, girdi: .birVeyaCokPDF) { SiralaEkrani(baglam: $0) },
            Arac(id: "bosSayfaEkle", ad: "Boş sayfa ekle", aciklama: "Başa, sona ya da araya boş sayfa koy", simge: "doc.badge.plus",
                 kategori: .sayfa, girdi: .birVeyaCokPDF, topluUygun: true) { BosSayfaEkleEkrani(baglam: $0) },
            Arac(id: "kenarKirp", ad: "Kenar kırp", aciklama: "Beyaz kenarları otomatik ya da elle kırp", simge: "crop",
                 kategori: .sayfa, girdi: .birVeyaCokPDF, topluUygun: true) { KenarKirpEkrani(baglam: $0) },
            Arac(id: "nUp", ad: "Kâğıt başına N sayfa", aciklama: "2, 4, 6 ya da 9 sayfayı bir kâğıda sığdır", simge: "square.grid.2x2",
                 kategori: .sayfa, girdi: .birVeyaCokPDF, topluUygun: true) { NUpEkrani(baglam: $0) },
            Arac(id: "kitapcikBaski", ad: "Kitapçık baskı", aciklama: "A4 katlamalı kitapçık sırası, A5 iki yukarı", simge: "book",
                 kategori: .sayfa, girdi: .birVeyaCokPDF, topluUygun: true) { KitapcikBaskiEkrani(baglam: $0) },
            Arac(id: "boyutlandir", ad: "Boyutlandır", aciklama: "A4, A5 ya da Letter'a ölçekle", simge: "arrow.up.left.and.arrow.down.right",
                 kategori: .sayfa, girdi: .birVeyaCokPDF, topluUygun: true) { BoyutlandirEkrani(baglam: $0) },
            Arac(id: "filigran", ad: "Filigran", aciklama: "Metin ya da görsel filigran ekle", simge: "drop.halffull",
                 kategori: .sayfa, girdi: .birVeyaCokPDF, topluUygun: true) { FiligranEkrani(baglam: $0) },
            Arac(id: "sayfaNumarasi", ad: "Sayfa numarası", aciklama: "Konum, biçim ve başlangıç numarası seç", simge: "number",
                 kategori: .sayfa, girdi: .birVeyaCokPDF, topluUygun: true) { SayfaNumarasiEkrani(baglam: $0) },
            Arac(id: "ustAltBilgi", ad: "Üst / alt bilgi", aciklama: "Sol, orta, sağ alanlara yazı, tarih, dosya adı", simge: "text.alignleft",
                 kategori: .sayfa, girdi: .birVeyaCokPDF, topluUygun: true) { UstAltBilgiEkrani(baglam: $0) },
            Arac(id: "sikistir", ad: "Sıkıştır", aciklama: "Dosya boyutunu küçült, e-postaya sığdır", simge: "arrow.down.right.and.arrow.up.left",
                 kategori: .sayfa, girdi: .birVeyaCokPDF, topluUygun: true) { SikistirEkrani(baglam: $0) },
            Arac(id: "karsilastir", ad: "Karşılaştır", aciklama: "İki PDF'in metin ve görsel farkını raporla", simge: "rectangle.split.2x1",
                 kategori: .sayfa, girdi: .cokPDF) { KarsilastirEkrani(baglam: $0) },
            Arac(id: "onar", ad: "Onar", aciklama: "Bozuk PDF'i yeniden yaz ve doğrula", simge: "wrench.and.screwdriver",
                 kategori: .sayfa, girdi: .birVeyaCokPDF, topluUygun: true) { OnarEkrani(baglam: $0) },
        ]
    }

    static var donusturAraclari: [Arac] {
        let metinTurleri: [UTType] = [.plainText, .rtf, .html, UTType(filenameExtension: "md"), UTType(filenameExtension: "markdown"),
                                      UTType(filenameExtension: "docx"), UTType(filenameExtension: "xlsx"),
                                      UTType(filenameExtension: "pptx"), UTType(filenameExtension: "odt"),
                                      UTType(filenameExtension: "doc")].compactMap { $0 }
        return [
            Arac(id: "gorseldenPDF", ad: "Görselden PDF", aciklama: "Fotoğraf ve resimlerden PDF yap", simge: "photo.on.rectangle",
                 kategori: .donustur, girdi: .gorseller) { GorseldenPDFEkrani(baglam: $0) },
            Arac(id: "belgedenPDF", ad: "Belgeden PDF", aciklama: "TXT, RTF, HTML, Markdown, Word, Excel, PowerPoint", simge: "doc.text",
                 kategori: .donustur, girdi: .dosyalar(metinTurleri)) { BelgedenPDFEkrani(baglam: $0) },
            Arac(id: "bosPDF", ad: "Boş PDF", aciklama: "Çizgili, kareli, noktalı, milimetrik sayfalar", simge: "doc",
                 kategori: .donustur, girdi: .yok) { BosPDFEkrani(baglam: $0) },
            Arac(id: "pdftenGorsele", ad: "PDF'ten görsele", aciklama: "Sayfaları PNG/JPEG yap, ZIP ya da Fotoğraflar'a", simge: "photo",
                 kategori: .donustur, girdi: .birVeyaCokPDF, topluUygun: true) { PDFtenGorseleEkrani(baglam: $0) },
            Arac(id: "pdftenGorselleriCikar", ad: "Gömülü görselleri çıkar", aciklama: "PDF içindeki resimleri özgün boyutta al", simge: "photo.stack",
                 kategori: .donustur, girdi: .birVeyaCokPDF, topluUygun: true) { PDFtenGorselleriCikarEkrani(baglam: $0) },
            Arac(id: "pdftenWord", ad: "PDF'ten Word", aciklama: "DOCX'e çevir (cihazda ya da sunucuda)", simge: "doc.richtext",
                 kategori: .donustur, girdi: .birVeyaCokPDF, topluUygun: true) { PDFtenOfficeEkrani(baglam: $0, tur: .word) },
            Arac(id: "pdftenExcel", ad: "PDF'ten Excel", aciklama: "Tabloları XLSX'e aktar (cihazda ya da sunucuda)", simge: "tablecells",
                 kategori: .donustur, girdi: .birVeyaCokPDF, topluUygun: true) { PDFtenOfficeEkrani(baglam: $0, tur: .excel) },
            Arac(id: "pdftenPowerPoint", ad: "PDF'ten PowerPoint", aciklama: "Her sayfa bir slayt", simge: "rectangle.on.rectangle",
                 kategori: .donustur, girdi: .birVeyaCokPDF, topluUygun: true) { PDFtenPowerPointEkrani(baglam: $0) },
            Arac(id: "pdftenMetin", ad: "PDF'ten metin", aciklama: "Düz metin (TXT) olarak al", simge: "text.justify.left",
                 kategori: .donustur, girdi: .birVeyaCokPDF, topluUygun: true) { b in
                KisaDonusumEkrani(aracId: "pdftenMetin", baglam: b) { [try PDFYapisi.pdftenMetin($0, aralik: $1)] }
            },
            Arac(id: "pdftenMarkdown", ad: "PDF'ten Markdown", aciklama: "Başlık ve listeleri koruyarak MD yap", simge: "number.square",
                 kategori: .donustur, girdi: .birVeyaCokPDF, topluUygun: true) { b in
                KisaDonusumEkrani(aracId: "pdftenMarkdown", baglam: b) { [try PDFYapisi.pdftenMarkdown($0, aralik: $1)] }
            },
            Arac(id: "pdftenHTML", ad: "PDF'ten HTML", aciklama: "Web sayfası olarak al", simge: "chevron.left.forwardslash.chevron.right",
                 kategori: .donustur, girdi: .birVeyaCokPDF, topluUygun: true) { b in
                KisaDonusumEkrani(aracId: "pdftenHTML", baglam: b) { [try PDFYapisi.pdftenHTML($0, aralik: $1)] }
            },
            Arac(id: "pdftenEPUB", ad: "PDF'ten EPUB", aciklama: "E-kitap okuyucular için", simge: "books.vertical",
                 kategori: .donustur, girdi: .birVeyaCokPDF, topluUygun: true) { b in
                KisaDonusumEkrani(aracId: "pdftenEPUB", baglam: b) { [try PDFYapisi.pdftenEPUB($0, aralik: $1)] }
            },
        ]
    }
}
