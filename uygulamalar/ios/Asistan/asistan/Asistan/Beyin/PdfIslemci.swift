import Foundation
import PDFKit
import UIKit

/// P2.12: Var olan PDF'ler üzerinde saf işlemler (birleştir, böl, döndür, sıkıştır, form doldur, imzala).
/// Ana aktöre bağlı değil: PDFKit belge/sayfa nesneleri yerel kalır, çağıranlar ağır işi `Task.detached` içinde yapar.
/// Hiçbir işlem özgün dosyayı değiştirmez; sonuç her zaman yeni veridir.
nonisolated enum PdfIslemci {
    nonisolated enum Hata: LocalizedError, Equatable {
        case parolali, okunamadi, aralik(String), cokSayfa, alanYok([String]), imzaYok, derece
        var errorDescription: String? {
            switch self {
            case .parolali: "PDF parola ile korunuyor; parolalı PDF işlenmez. Kilidi açılmış bir kopyasını ekle."
            case .okunamadi: "PDF açılamadı ya da bozuk."
            case .aralik(let s): "Sayfa aralığı geçersiz: \(s). Örnek: 1-3,5 (tek dosya) ya da 1-2;3-4 (ayrı dosyalar)."
            case .cokSayfa: "Sonuç en çok \(PdfIslemci.enFazlaSayfa) sayfa olabilir."
            case .alanYok(let a): a.isEmpty ? "Bu PDF'de doldurulabilir form alanı yok." : "Form alanı bulunamadı: \(a.joined(separator: ", "))."
            case .imzaYok: "Kayıtlı imza yok. Ayarlar → İmzam'dan imzanı bir kez çiz."
            case .derece: "Döndürme açısı 90, 180, 270 ya da -90 olmalı."
            }
        }
    }

    /// Birleştirme kaynağı: PDF dosyası ya da A4 sayfaya yerleştirilecek görsel.
    nonisolated enum Kaynak: Equatable, Sendable {
        case pdf(URL), gorsel(URL)
    }

    /// Form alanı (widget notu).
    nonisolated struct Alan: Equatable, Sendable {
        let sayfa: Int
        let ad: String
        let tur: String
        let deger: String
    }

    nonisolated enum ImzaKonumu: String, CaseIterable, Sendable {
        case sagAlt, solAlt, ortaAlt, sagUst
        var gorunenAd: String {
            switch self { case .sagAlt: "sağ alt"; case .solAlt: "sol alt"; case .ortaAlt: "orta alt"; case .sagUst: "sağ üst" }
        }
        /// Model "sağ alt", "sag_alt", "sagAlt" yazabilir; bilinmeyen değer sağ alt sayılır.
        static func coz(_ s: String?) -> ImzaKonumu {
            let t = (s ?? "").lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "tr_TR"))
                .filter { $0.isLetter }
            return allCases.first { $0.rawValue.lowercased() == t } ?? .sagAlt
        }
    }

    static let enFazlaSayfa = 300
    /// A4 (pt).
    static let a4 = CGRect(x: 0, y: 0, width: 595, height: 842)

    // MARK: Açma ve aralık

    /// Parolalı PDF açılmaz (boş parolayla açılabilen kilit dışında).
    static func ac(_ url: URL) throws -> PDFDocument {
        guard let d = PDFDocument(url: url) else { throw Hata.okunamadi }
        return try kilitDenetle(d)
    }
    static func ac(_ veri: Data) throws -> PDFDocument {
        guard let d = PDFDocument(data: veri) else { throw Hata.okunamadi }
        return try kilitDenetle(d)
    }
    private static func kilitDenetle(_ d: PDFDocument) throws -> PDFDocument {
        if d.isLocked || d.isEncrypted, !d.unlock(withPassword: "") { throw Hata.parolali }
        if d.isLocked { throw Hata.parolali }
        return d
    }

    /// "1-3,5;7-9" → 0 tabanlı gruplar ([[0,1,2,4],[6,7,8]]); ';' ayrı dosya demektir. Saf.
    static func araliklar(_ s: String, sayfaSayisi: Int) throws -> [[Int]] {
        let temiz = s.replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: " ", with: "")
        guard !temiz.isEmpty else { throw Hata.aralik("boş") }
        var gruplar: [[Int]] = []
        for grup in temiz.split(separator: ";", omittingEmptySubsequences: false) {
            var sayfalar: [Int] = []
            let parcalar = grup.split(separator: ",", omittingEmptySubsequences: false)
            guard !grup.isEmpty else { throw Hata.aralik("boş grup") }
            for p in parcalar {
                let uclar = p.split(separator: "-", omittingEmptySubsequences: false)
                guard (1...2).contains(uclar.count), let a = Int(uclar[0]), let b = Int(uclar.last!) else { throw Hata.aralik(String(p)) }
                guard a >= 1, b >= 1, a <= sayfaSayisi, b <= sayfaSayisi else { throw Hata.aralik("\(p) (PDF \(sayfaSayisi) sayfa)") }
                guard a <= b else { throw Hata.aralik("\(p) ters") }
                sayfalar.append(contentsOf: (a - 1)...(b - 1))
            }
            guard !sayfalar.isEmpty else { throw Hata.aralik(String(grup)) }
            gruplar.append(sayfalar)
        }
        return gruplar
    }

    // MARK: Birleştir / böl / döndür

    /// PDF'lerin sayfaları ve görseller (A4'e en-boy oranı korunarak sığdırılır) tek belgede toplanır.
    static func birlestir(_ kaynaklar: [Kaynak]) throws -> PDFDocument {
        let sonuc = PDFDocument()
        for k in kaynaklar {
            switch k {
            case .pdf(let url):
                let d = try ac(url)
                guard sonuc.pageCount + d.pageCount <= enFazlaSayfa else { throw Hata.cokSayfa }
                for i in 0..<d.pageCount {
                    guard let p = d.page(at: i)?.copy() as? PDFPage else { continue }
                    sonuc.insert(p, at: sonuc.pageCount)
                }
            case .gorsel(let url):
                guard sonuc.pageCount < enFazlaSayfa else { throw Hata.cokSayfa }
                guard let r = UIImage(contentsOfFile: url.path), let p = gorselSayfasi(r) else { throw Hata.okunamadi }
                sonuc.insert(p, at: sonuc.pageCount)
            }
        }
        guard sonuc.pageCount > 0 else { throw Hata.okunamadi }
        return sonuc
    }

    /// Görseli A4 sayfaya sığdırır (küçükse büyütür, en-boy oranı korunur).
    static func gorselSayfasi(_ r: UIImage, kalite: Double? = nil) -> PDFPage? {
        var secenek: [PDFPage.ImageInitializationOption: Any] = [.mediaBox: NSValue(cgRect: a4), .upscaleIfSmaller: true]
        if let kalite { secenek[.compressionQuality] = kalite }
        return PDFPage(image: r, options: secenek)
    }

    static func bol(_ d: PDFDocument, gruplar: [[Int]]) -> [PDFDocument] {
        gruplar.map { g in
            let yeni = PDFDocument()
            for i in g { if let p = d.page(at: i)?.copy() as? PDFPage { yeni.insert(p, at: yeni.pageCount) } }
            return yeni
        }
    }

    /// `sayfalar` nil ise bütün sayfalar döner. Derece 90/180/270/-90.
    static func dondur(_ d: PDFDocument, sayfalar: [Int]?, derece: Int) throws {
        guard [90, 180, 270, -90].contains(derece) else { throw Hata.derece }
        for i in sayfalar ?? Array(0..<d.pageCount) {
            guard let p = d.page(at: i) else { continue }
            p.rotation = (((p.rotation + derece) % 360) + 360) % 360
        }
    }

    // MARK: Sıkıştır

    /// Önce PDFKit'in JPEG seçenekleri denenir; küçülme %10'dan azsa ya da hedef aşılıyorsa sayfalar 150 dpi'da
    /// JPEG'e rasterleştirilir (kalite 0.6 → 0.45 → 0.3). Rasterleştirmede metin katmanı kaybolur; `not` bunu söyler.
    static func sikistir(_ url: URL, hedefMB: Double?) throws -> (veri: Data, not: String) {
        let ozgun = (try? Data(contentsOf: url)) ?? Data()
        let d = try ac(url)
        let hedef = hedefMB.flatMap { $0 > 0 ? Int($0 * 1_048_576) : nil }
        let ilk = d.dataRepresentation(options: [PDFDocumentWriteOption.saveImagesAsJPEGOption: true,
                                                 PDFDocumentWriteOption.optimizeImagesForScreenOption: true]) ?? ozgun
        let yeterli = Double(ilk.count) <= Double(ozgun.count) * 0.9 && (hedef == nil || ilk.count <= hedef!)
        let metinli = ilk.count < ozgun.count || ozgun.isEmpty ? ilk : ozgun
        var en = (veri: metinli, raster: false)
        if !yeterli {
            // Hedef yoksa amaç en az %10 küçülmedir; kalite ancak gerektiği kadar düşürülür.
            for kalite in [0.6, 0.45, 0.3] {
                guard let r = rasterlestir(d, kalite: kalite) else { break }
                if r.count < en.veri.count { en = (r, true) }
                let ulasti = hedef.map { en.veri.count <= $0 } ?? (ozgun.isEmpty || Double(en.veri.count) <= Double(ozgun.count) * 0.9)
                if ulasti { break }
            }
            // Hedefsiz istekte metin katmanı küçük kazanç için feda edilmez.
            if en.raster, hedef == nil, !ozgun.isEmpty, Double(en.veri.count) > Double(ozgun.count) * 0.9 { en = (metinli, false) }
        }
        var notlar: [String] = []
        if en.raster { notlar.append("Sayfalar görüntüye çevrildi; metin katmanı kayboldu (metin seçilemez/aranamaz).") }
        if en.veri.count >= ozgun.count, !ozgun.isEmpty { notlar.append("Belirgin küçülme olmadı; dosya zaten sıkıştırılmış olabilir.") }
        if let hedef, en.veri.count > hedef { notlar.append("Hedef boyuta inilemedi.") }
        return (en.veri, notlar.joined(separator: " "))
    }

    /// Her sayfayı 150 dpi'da çizip JPEG sayfası yapar.
    static func rasterlestir(_ d: PDFDocument, kalite: Double, dpi: CGFloat = 150) -> Data? {
        let yeni = PDFDocument()
        for i in 0..<d.pageCount {
            guard let p = d.page(at: i) else { continue }
            let boy = gorunenBoyut(p)
            let olcek = dpi / 72
            let bicim = UIGraphicsImageRendererFormat()
            bicim.scale = 1; bicim.opaque = true
            let piksel = CGSize(width: (boy.width * olcek).rounded(), height: (boy.height * olcek).rounded())
            let resim = UIGraphicsImageRenderer(size: piksel, format: bicim).image { c in
                UIColor.white.setFill(); c.fill(CGRect(origin: .zero, size: piksel))
                ciz(p, c.cgContext, olcek: olcek)
            }
            var secenek: [PDFPage.ImageInitializationOption: Any] = [.mediaBox: NSValue(cgRect: CGRect(origin: .zero, size: boy)), .compressionQuality: kalite]
            secenek[.upscaleIfSmaller] = true
            guard let sayfa = PDFPage(image: resim, options: secenek) else { return nil }
            yeni.insert(sayfa, at: yeni.pageCount)
        }
        return yeni.pageCount > 0 ? yeni.dataRepresentation() : nil
    }

    // MARK: Form

    static func alanlar(_ d: PDFDocument) -> [Alan] {
        var sonuc: [Alan] = []
        for i in 0..<d.pageCount {
            guard let p = d.page(at: i) else { continue }
            for a in p.annotations where widgetMi(a) {
                guard let ad = a.fieldName, !ad.isEmpty else { continue }
                let tur: String, deger: String
                switch a.widgetFieldType {
                case .text: tur = "metin"; deger = a.widgetStringValue ?? ""
                case .button:
                    switch a.widgetControlType {
                    case .checkBoxControl: tur = "onay kutusu"
                    case .radioButtonControl: tur = "seçenek düğmesi (\(a.buttonWidgetStateString))"
                    default: tur = "düğme"
                    }
                    deger = a.buttonWidgetState == .onState ? "işaretli" : "boş"
                case .choice: tur = "seçim (\((a.choices ?? []).joined(separator: " / ")))"; deger = a.widgetStringValue ?? ""
                case .signature: tur = "imza alanı"; deger = ""
                default: tur = "diğer"; deger = a.widgetStringValue ?? ""
                }
                // Aynı adlı birden çok widget (seçenek düğmeleri) tek satır olur.
                if !sonuc.contains(where: { $0.ad == ad && $0.sayfa == i + 1 && $0.tur == tur }) {
                    sonuc.append(Alan(sayfa: i + 1, ad: ad, tur: tur, deger: deger))
                }
            }
        }
        return sonuc
    }

    nonisolated static let evetDegerleri: Set<String> = ["evet", "true", "x", "1", "yes", "on", "işaretli", "isaretli", "✓", "✔"]

    /// Metin alanı → widgetStringValue; onay kutusu ('evet/true/x/1') işaretlenir; seçenek düğmesi durum adıyla;
    /// seçim alanı yalnız seçenekler içindeyse yazılır. Alan adı büyük/küçük harf duyarsız eşleşir.
    static func doldur(_ d: PDFDocument, _ degerler: [String: String]) -> (doldurulan: Int, bulunamayan: [String]) {
        var dolan = Set<String>()
        for i in 0..<d.pageCount {
            guard let p = d.page(at: i) else { continue }
            for a in p.annotations where widgetMi(a) {
                guard let ad = a.fieldName,
                      let es = degerler.first(where: { $0.key.lowercased() == ad.lowercased() }) else { continue }
                let anahtar = es.key
                let v = es.value.trimmingCharacters(in: .whitespacesAndNewlines)
                switch a.widgetFieldType {
                case .text: a.widgetStringValue = v; dolan.insert(anahtar)
                case .button:
                    if a.widgetControlType == .radioButtonControl {
                        a.buttonWidgetState = a.buttonWidgetStateString.lowercased() == v.lowercased() ? .onState : .offState
                    } else {
                        a.buttonWidgetState = evetDegerleri.contains(v.lowercased()) ? .onState : .offState
                    }
                    dolan.insert(anahtar)
                case .choice:
                    if let s = (a.choices ?? []).first(where: { $0.lowercased() == v.lowercased() }) { a.widgetStringValue = s; dolan.insert(anahtar) }
                default: break
                }
            }
        }
        let bulunamayan = degerler.keys.filter { !dolan.contains($0) }.sorted()
        return (dolan.count, bulunamayan)
    }

    private static func widgetMi(_ a: PDFAnnotation) -> Bool {
        (a.type ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased() == "widget"
    }

    // MARK: İmza

    /// İmza çerçevesi (sol üst köşe orijinli, sayfanın görünen koordinatı). Saf.
    static func cerceve(_ k: ImzaKonumu, sayfa: CGRect, imza: CGSize, genislik: CGFloat = 140, kenar: CGFloat = 36) -> CGRect {
        let w = min(genislik, max(1, sayfa.width - 2 * kenar))
        let oran = imza.width > 0 ? imza.height / imza.width : 0.4
        let h = min(w * oran, max(1, sayfa.height / 3))
        let x: CGFloat, y: CGFloat
        switch k {
        case .sagAlt: x = sayfa.maxX - kenar - w; y = sayfa.maxY - kenar - h
        case .solAlt: x = sayfa.minX + kenar; y = sayfa.maxY - kenar - h
        case .ortaAlt: x = sayfa.midX - w / 2; y = sayfa.maxY - kenar - h
        case .sagUst: x = sayfa.maxX - kenar - w; y = sayfa.minY + kenar
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// İmza düzleştirilir (sonradan çıkarılamaz): her sayfa vektör olarak yeniden çizilir, hedef sayfaya imza görüntüsü eklenir.
    /// `sayfa` 0 tabanlı. Form alanları ve bağlantılar görünüm olarak korunur, etkileşimli kalmaz.
    static func imzala(_ d: PDFDocument, imza: CGImage, sayfa: Int, konum: ImzaKonumu) throws -> Data {
        guard d.pageCount > 0 else { throw Hata.okunamadi }
        guard (0..<d.pageCount).contains(sayfa) else { throw Hata.aralik("sayfa \(sayfa + 1) (PDF \(d.pageCount) sayfa)") }
        guard d.pageCount <= enFazlaSayfa else { throw Hata.cokSayfa }
        let ilkBoy = d.page(at: 0).map(gorunenBoyut) ?? a4.size
        let resim = UIImage(cgImage: imza)
        return UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: ilkBoy)).pdfData { ctx in
            for i in 0..<d.pageCount {
                guard let p = d.page(at: i) else { continue }
                let boy = gorunenBoyut(p)
                ctx.beginPage(withBounds: CGRect(origin: .zero, size: boy), pageInfo: [:])
                ciz(p, ctx.cgContext, olcek: 1)
                if i == sayfa {
                    resim.draw(in: cerceve(konum, sayfa: CGRect(origin: .zero, size: boy), imza: CGSize(width: imza.width, height: imza.height)))
                }
            }
        }
    }

    /// İmzalı sayfanın küçük resmi (uzun kenar 900 px).
    static func onizleme(_ veri: Data, sayfa: Int) -> CGImage? {
        guard let d = PDFDocument(data: veri), let p = d.page(at: min(max(0, sayfa), d.pageCount - 1)) else { return nil }
        let boy = gorunenBoyut(p)
        let olcek = 900 / max(boy.width, boy.height, 1)
        return p.thumbnail(of: CGSize(width: boy.width * olcek, height: boy.height * olcek), for: .mediaBox).cgImage
    }

    // MARK: Yardımcılar

    /// Döndürme sonrası görünen sayfa boyutu.
    static func gorunenBoyut(_ p: PDFPage) -> CGSize {
        let b = p.bounds(for: .mediaBox)
        let r = ((p.rotation % 360) + 360) % 360
        return r == 90 || r == 270 ? CGSize(width: b.height, height: b.width) : b.size
    }

    /// Sayfayı sol üst orijinli (UIKit) bağlama çizer. `draw(with:to:)` döndürmeyi ve kutu orijinini kendisi uygular
    /// (macOS'ta küçük resimle karşılaştırılarak ölçüldü); yalnız y ekseni çevrilir.
    static func ciz(_ p: PDFPage, _ cg: CGContext, olcek: CGFloat) {
        let boy = gorunenBoyut(p)
        cg.saveGState()
        cg.scaleBy(x: olcek, y: olcek)
        cg.translateBy(x: 0, y: boy.height)
        cg.scaleBy(x: 1, y: -1)
        p.draw(with: .mediaBox, to: cg)
        cg.restoreGState()
    }
}
