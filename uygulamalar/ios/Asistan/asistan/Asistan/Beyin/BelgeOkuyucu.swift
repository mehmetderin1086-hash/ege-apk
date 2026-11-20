import Foundation
import PDFKit
import UniformTypeIdentifiers
import ZIPFoundation

nonisolated struct OkunanBelge: Sendable {
    let ad: String
    let metin: String
    let not: String
    /// P2.12: Saklanan PDF kopyasının kimliği ("ek:<uuid>"); `oku(_:ekKopyasi: true)` doldurur.
    var ekKimligi: String? = nil
}

nonisolated enum BelgeOkuyucu {
    static var desteklenenTurler: [UTType] {
        var turler: [UTType] = [.pdf, .plainText, .sourceCode, .json, .commaSeparatedText]
        for uzanti in ["docx", "xlsx", "pptx"] { if let t = UTType(filenameExtension: uzanti) { turler.append(t) } }
        return turler
    }
    enum Hata: LocalizedError {
        case buyuk, okunamadi, kilitli, acilmisBuyuk
        var errorDescription: String? {
            switch self {
            case .buyuk: "Belge 20 MB sınırını aşıyor. Daha küçük bir dosya seç."
            case .okunamadi: "Belgeden metin okunamadı. DOCX, XLSX, PPTX, PDF, metin, CSV veya kod dosyası seç."
            case .kilitli: "PDF parola ile kilitli. Kilidi açılmış bir kopyasını seç."
            case .acilmisBuyuk: "Ofis belgesinin açılmış içeriği işleme sınırını aşıyor (bölüm başına 8 MB, toplam 32 MB). Daha küçük bir bölüm seç veya dosyayı Dosya kasası’na yükle."
            }
        }
    }
    /// P2.12: Eklenen PDF'lerin kopyaları (pdfIslem aracı 'ek:<uuid>' ile adresler): Application Support/EkDosyalari/<uuid>-<ad>.
    static var ekKlasoru: URL {
        let k = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return k.appendingPathComponent("EkDosyalari", isDirectory: true)
    }
    /// Ek kopyasının kimlik öneki.
    static let ekOneki = "ek:"

    static func oku(_ url: URL) throws -> OkunanBelge { try oku(url, ekKopyasi: false) }

    /// Ofis arşivinde bölüm başına ve toplam açılan bayt sınırları.
    static let bolumSiniri = 2_000_000
    static let toplamSiniri = 32_000_000
    private struct BolumSiniri: Error {}

    /// Sohbet eki için OCR: en çok 20 sayfa (okunan sınırla aynı), 90 sn bütçe (kullanıcı ekleme ekranında bekliyor).
    static let sohbetOcrAyari: PdfOcr.Ayar = { var a = PdfOcr.Ayar.varsayilan; a.azamiSayfa = 20; a.sureButcesi = 90; return a }()

    static func ocrNotuGerekli(_ s: PdfOcr.Sonuc) -> Bool {
        !s.metinliSayfalar.isEmpty || !s.hataliSayfalar.isEmpty || s.sinirYuzundenAtlanan > 0 || s.sureYuzundenAtlanan > 0
    }

    /// Sayfanın seçilebilir metni yok sayılır mı (taranmış sayfa ya da yalnız sayfa numarası).
    static func metinKatmaniYok(_ yazi: String) -> Bool {
        yazi.trimmingCharacters(in: .whitespacesAndNewlines).count < 20
    }

    /// `ekKopyasi`: PDF ise dosyanın kopyası `ekKlasoru`na yazılır, not'a kimliği eklenir (öbür türlerde yok sayılır).
    static func oku(_ url: URL, ekKopyasi: Bool) throws -> OkunanBelge {
        try Task.checkCancellation()
        let erisim = url.startAccessingSecurityScopedResource()
        defer { if erisim { url.stopAccessingSecurityScopedResource() } }
        let boyut = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard boyut <= 20 * 1024 * 1024 else { throw Hata.buyuk }
        var metin = ""
        var notlar: [String] = []
        let uzanti = url.pathExtension.lowercased()
        if uzanti == "pdf" {
            guard let belge = PDFDocument(url: url) else { throw Hata.okunamadi }
            guard !belge.isLocked else { throw Hata.kilitli }
            let sayfaSayisi = min(belge.pageCount, 20)
            // Önce metin katmanı; metni olmayan (taranmış) sayfalar tek seferde PdfOcr'a gider (okuma sırası, güven notu,
            // sayfa başına hata yalıtımı, süre bütçesi). Sayfa numarası etiketi iki yolda da korunur.
            var yazilar = [String](repeating: "", count: sayfaSayisi)
            var bosSayfalar: [Int] = []
            for i in 0..<sayfaSayisi {
                try Task.checkCancellation()
                let yazi = belge.page(at: i)?.string ?? ""
                if Self.metinKatmaniYok(yazi) { bosSayfalar.append(i) } else { yazilar[i] = yazi }
            }
            // Metin katmanı sınırı zaten dolduruyorsa taranmış sayfalar için 250 dpi OCR'a girilmez.
            if !bosSayfalar.isEmpty, yazilar.reduce(0, { $0 + $1.count }) < 50_000 {
                let sonuc = try PdfOcr.oku(belge, sayfalar: bosSayfalar, ayar: Self.sohbetOcrAyari)
                for s in sonuc.metinliSayfalar where s.indeks < sayfaSayisi { yazilar[s.indeks] = s.metin }
                // Boş ayırıcı/kapak sayfası "0 sayfa OCR ile okundu" diye güven düşüren not bırakmasın.
                if Self.ocrNotuGerekli(sonuc) { notlar.append(PdfOcr.not(sonuc)) }
            }
            for (i, yazi) in yazilar.enumerated() where !yazi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metin += "\n[Sayfa \(i + 1)]\n\(yazi)\n"
                if metin.count >= 50_000 { notlar.append("Metin 50.000 karakterle sınırlandı."); break }
            }
            if belge.pageCount > 20 { notlar.append("İlk 20 / \(belge.pageCount) sayfa okundu.") }
        } else if ["docx", "xlsx", "pptx"].contains(uzanti) {
            let archive = try Archive(url: url, accessMode: .read)
            let adlar: [String]
            switch uzanti {
            case "docx": adlar = archive.compactMap { $0.path == "word/document.xml" ? $0.path : nil }
            case "pptx": adlar = archive.compactMap { $0.path.hasPrefix("ppt/slides/slide") && $0.path.hasSuffix(".xml") && !$0.path.contains("/_rels/") ? $0.path : nil }.sorted(by: dogalSirala)
            default: adlar = archive.compactMap { ($0.path == "xl/sharedStrings.xml" || ($0.path.hasPrefix("xl/worksheets/sheet") && $0.path.hasSuffix(".xml"))) ? $0.path : nil }.sorted(by: dogalSirala)
            }
            var acilanToplam = 0
            var kesilen = 0
            for ad in adlar.prefix(80) {
                try Task.checkCancellation()
                guard let entry = archive[ad] else { continue }
                // Bölüm başına en çok 2 MB açılır, sınırda açma durdurulur (sıkıştırma bombası açılıp atılmaz);
                // kısmi XML'in okunabilen metni kullanılır. Büyük e-Okul xlsx'i reddedilmez, kısaltılmış okunur.
                var data = Data(); data.reserveCapacity(min(Int(entry.uncompressedSize), Self.bolumSiniri))
                do {
                    _ = try archive.extract(entry) { parca in
                        try Task.checkCancellation()
                        let al = min(parca.count, Self.bolumSiniri - data.count)
                        data.append(parca.prefix(al)); acilanToplam += al
                        if data.count >= Self.bolumSiniri { throw BolumSiniri() }
                    }
                } catch is BolumSiniri { kesilen += 1 }
                let bolum = OfisXMLMetni.cikar(data)
                if !bolum.isEmpty { metin += "\n[\(ad)]\n\(bolum)\n" }
                if metin.count >= 50_000 { notlar.append("Metin 50.000 karakterle sınırlandı."); break }
                if acilanToplam >= Self.toplamSiniri { notlar.append("Belgenin yalnız bir bölümü okundu (açılmış boyut sınırı)."); break }
            }
            if kesilen > 0 { notlar.append("\(kesilen) büyük bölüm kısaltılarak okundu.") }
            if uzanti == "xlsx" { notlar.append("Hesap tablosundaki biçimler ve formüller değil, görülebilen hücre metinleri aktarıldı.") }
        } else {
            let veri = try Data(contentsOf: url)
            guard let yazi = String(data: veri, encoding: .utf8) ?? String(data: veri, encoding: .utf16) else { throw Hata.okunamadi }
            metin = yazi
            if metin.count > 50_000 { notlar.append("İlk 50.000 karakter okundu.") }
        }
        guard !metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Hata.okunamadi }
        var kimlik: String?
        if ekKopyasi, uzanti == "pdf", let k = ekKopyala(url) {
            kimlik = ekOneki + k
            notlar.append("Dosya kimliği (pdfIslem için): \(ekOneki)\(k)")
        }
        return OkunanBelge(ad: url.lastPathComponent, metin: String(metin.prefix(50_000)), not: notlar.joined(separator: " "), ekKimligi: kimlik)
    }

    /// Dosyayı (güvenlik kapsamı açıkken) `ekKlasoru/<uuid>-<ad>`'a kopyalar; dönen değer uuid. Önce 7 günden eski kopyalar budanır.
    private static func ekKopyala(_ url: URL) -> String? {
        eskiEkleriBuda()
        let fm = FileManager.default
        try? fm.createDirectory(at: ekKlasoru, withIntermediateDirectories: true)
        let kimlik = UUID().uuidString
        let hedef = ekKlasoru.appendingPathComponent(kimlik + "-" + IndirmeYoneticisi.dosyaAdi(url.lastPathComponent))
        do {
            try fm.copyItem(at: url, to: hedef)
            // Kopya kaynağın değişiklik tarihini taşır: budama kopyanın yaşına baksın.
            try? fm.setAttributes([.modificationDate: Date.now, .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: hedef.path)
            return kimlik
        } catch { return nil }
    }

    /// `gun` günden eski ek kopyalarını siler.
    static func eskiEkleriBuda(gun: Int = 7, simdi: Date = .now) {
        let fm = FileManager.default
        guard let ogeler = try? fm.contentsOfDirectory(at: ekKlasoru, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let sinir = simdi.addingTimeInterval(-Double(gun) * 86_400)
        for u in ogeler {
            let tarih = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if tarih < sinir { try? fm.removeItem(at: u) }
        }
    }

    /// "ek:<uuid>" kimliğini kopyanın yoluna çözer (klasör dışına çıkan ya da bulunmayan kimlik nil).
    static func ekDosyasi(_ uuid: String) -> URL? {
        let temiz = uuid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: temiz) != nil,
              let ad = (try? FileManager.default.contentsOfDirectory(atPath: ekKlasoru.path))?.first(where: { $0.lowercased().hasPrefix(temiz.lowercased() + "-") })
        else { return nil }
        let u = ekKlasoru.appendingPathComponent(ad).standardizedFileURL
        guard u.deletingLastPathComponent().path == ekKlasoru.standardizedFileURL.path else { return nil }
        return u
    }

    private static func dogalSirala(_ a: String, _ b: String) -> Bool { a.localizedStandardCompare(b) == .orderedAscending }
}

nonisolated private final class OfisXMLMetni: NSObject, XMLParserDelegate {
    private var metinler: [String] = []
    private var tampon = ""
    private var okunuyor = false

    static func cikar(_ data: Data) -> String {
        let alici = OfisXMLMetni(), parser = XMLParser(data: data)
        parser.delegate = alici
        parser.parse()
        return alici.metinler.joined(separator: " ").replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let ad = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if ["t", "v"].contains(ad) { okunuyor = true; tampon = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if okunuyor { tampon += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let ad = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if ["t", "v"].contains(ad) {
            let s = tampon.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { metinler.append(s) }
            okunuyor = false; tampon = ""
        }
        if ["p", "row", "tr"].contains(ad), metinler.last != "\n" { metinler.append("\n") }
    }
}
