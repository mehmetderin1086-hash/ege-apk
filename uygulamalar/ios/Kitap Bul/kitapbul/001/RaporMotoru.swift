import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText

// MARK: - Rapor hesapları

/// Rapor ve grafiklerin hesapları (görünümden bağımsız, test edilebilir).
enum RaporMotoru {
    struct AySayisi: Identifiable, Equatable {
        var id: Date { ay }
        let ay: Date
        let verilen: Int
        let iade: Int
        let eklenen: Int
        /// Dilimin uzunluğu: 1 ay, çok uzun aralıklarda 3 ay (çeyrek)
        var ayAdedi = 1
    }

    /// Son `aySayisi` ayın ödünç/iade/ekleme sayıları (en eski önce).
    static func aylikSayilar(events: [LoanEvent], eklenmeTarihleri: [Date], aySayisi: Int = 12, now: Date = .now) -> [AySayisi] {
        let takvim = Calendar.current
        guard let buAy = takvim.dateInterval(of: .month, for: now)?.start else { return [] }
        return (0..<aySayisi).reversed().compactMap { geri -> AySayisi? in
            guard let bas = takvim.date(byAdding: .month, value: -geri, to: buAy),
                  let bit = takvim.date(byAdding: .month, value: 1, to: bas) else { return nil }
            let araliktaki = events.filter { $0.date >= bas && $0.date < bit }
            return AySayisi(
                ay: bas,
                verilen: araliktaki.filter { $0.kind == .lent }.count,
                iade: araliktaki.filter { $0.kind == .returned }.count,
                eklenen: eklenmeTarihleri.filter { $0 >= bas && $0 < bit }.count
            )
        }
    }

    /// Seçili tarih aralığındaki aylık (36 aydan uzunsa üç aylık) ödünç/iade/ekleme sayıları, en eski önce.
    /// Aralığın ilk ve son ayı dâhil tüm dilimler üretilir; bu yüzden aralıktaki hareketlerin toplamı dilim
    /// toplamına eşittir. Her dilim `ayAdedi` ay uzunluğundadır.
    static func aylikSayilar(events: [LoanEvent], eklenmeTarihleri: [Date], baslangic: Date, now: Date = .now,
                             takvim: Calendar = .current) -> [AySayisi] {
        guard let ilkAy = takvim.dateInterval(of: .month, for: min(baslangic, now))?.start,
              let sonAy = takvim.dateInterval(of: .month, for: max(baslangic, now))?.start else { return [] }
        let ayFarki = takvim.dateComponents([.month], from: ilkAy, to: sonAy).month ?? 0
        let ayAdedi = ayFarki + 1
        let uc = ayAdedi > 36
        let adim = uc ? 3 : 1
        var baslangicAyi = ilkAy
        if uc {
            // Dilimler takvim çeyreğine hizalanır (Ocak, Nisan, Temmuz, Ekim).
            let ay = takvim.component(.month, from: ilkAy)
            baslangicAyi = takvim.date(byAdding: .month, value: -((ay - 1) % 3), to: ilkAy) ?? ilkAy
        }
        var sonuc: [AySayisi] = []
        var bas = baslangicAyi
        let sinir = takvim.date(byAdding: .month, value: 1, to: sonAy) ?? sonAy
        while bas < sinir, let bit = takvim.date(byAdding: .month, value: adim, to: bas) {
            let araliktaki = events.filter { $0.date >= bas && $0.date < bit }
            sonuc.append(AySayisi(
                ay: bas,
                verilen: araliktaki.filter { $0.kind == .lent }.count,
                iade: araliktaki.filter { $0.kind == .returned }.count,
                eklenen: eklenmeTarihleri.filter { $0 >= bas && $0 < bit }.count,
                ayAdedi: adim
            ))
            bas = bit
        }
        return sonuc
    }

    /// Okuma serisi: bugünden (bugün hareket yoksa dünden) geriye, en az bir ödünç verilen
    /// ardışık okul günü sayısı. Hafta sonları seriyi bozmaz.
    static func okumaSerisi(events: [LoanEvent], now: Date = .now, takvim: Calendar = .current) -> Int {
        let gunler = Set(events.filter { $0.kind == .lent && $0.loanKind != "textbook" }.map { takvim.startOfDay(for: $0.date) })
        guard !gunler.isEmpty else { return 0 }
        var gun = takvim.startOfDay(for: now)
        if !gunler.contains(gun) {
            gun = takvim.date(byAdding: .day, value: -1, to: gun) ?? gun
        }
        var seri = 0
        var bosHaftaSonu = 0
        for _ in 0..<400 {
            if gunler.contains(gun) {
                seri += 1
                bosHaftaSonu = 0
            } else if takvim.isDateInWeekend(gun), bosHaftaSonu < 2 {
                bosHaftaSonu += 1
            } else {
                break
            }
            gun = takvim.date(byAdding: .day, value: -1, to: gun) ?? gun
        }
        return seri
    }

    /// En çok ödünç verilen kitap kimlikleri (son `gun` gün).
    static func enCokOkunanlar(events: [LoanEvent], gun: Int = 365, limit: Int = 15, now: Date = .now) -> [UUID] {
        let sinir = Calendar.current.date(byAdding: .day, value: -gun, to: now) ?? now
        var sayilar: [UUID: Int] = [:]
        for olay in events where olay.kind == .lent && olay.loanKind != "textbook" && olay.date >= sinir { sayilar[olay.bookID, default: 0] += 1 }
        return sayilar.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.uuidString < $1.key.uuidString }
            .prefix(limit).map(\.key)
    }

    /// Kategori → nüsha sayısı (düşülenler hariç), büyükten küçüğe.
    static func kategoriDagilimi(_ kitaplar: [CatalogBook]) -> [(ad: String, sayi: Int)] {
        var sayilar: [String: Int] = [:]
        for kitap in kitaplar where !kitap.isWithdrawn {
            let ad = kitap.kategoriAdi
            sayilar[ad, default: 0] += max(1, kitap.quantity ?? 1)
        }
        return sayilar.map { (ad: $0.key, sayi: $0.value) }.sorted { $0.sayi != $1.sayi ? $0.sayi > $1.sayi : $0.ad < $1.ad }
    }

    /// Hiç ödünç verilmemiş kitaplar (geçmişte ve şu an), en eski eklenen önce.
    static func okunmayanlar(_ kitaplar: [CatalogBook], events: [LoanEvent], loans: [ActiveLoan], enAzGun: Int = 0, now: Date = .now) -> [CatalogBook] {
        let verilen = Set(events.filter { $0.kind == .lent }.map(\.bookID)).union(loans.map(\.bookID))
        // Eşik `KitapFiltresi.yakinOduncler` ile aynı: şimdiden geriye N gün (anlık, gün başına yuvarlanmaz).
        let sinir = Calendar.current.date(byAdding: .day, value: -enAzGun, to: now) ?? now
        return kitaplar
            .filter { !$0.isWithdrawn && !verilen.contains($0.id) && ($0.loanedTo ?? "").isEmpty && $0.addedAt <= sinir }
            .sorted { $0.addedAt < $1.addedAt }
    }

    /// Dönem raporu (resmî yazışmaya eklenecek PDF bölümleri).
    static func donemBolumleri(kitaplar: [CatalogBook], events: [LoanEvent], loans: [ActiveLoan],
                               baslangic: Date, bitis: Date, now: Date = .now,
                               copies: [BookCopy] = [], reservations: [Reservation] = [], className: String = "",
                               stockLoans: [ActiveLoan]? = nil, includeLegacyLoans: Bool = true) -> [PDFReportBuilder.Section] {
        let donem = events.filter { $0.date >= baslangic && $0.date <= bitis && (className.isEmpty || $0.classSnapshot == className) }
        let active = loans.filter { className.isEmpty || $0.studentClass == className }
        let states = SchoolLibraryService.stockByBook(books: kitaplar, loans: stockLoans ?? loans, copies: copies, reservations: reservations, now: now)
        let verilen = donem.filter { $0.kind == .lent }
        let iade = donem.filter { $0.kind == .returned }
        let kayip = donem.filter { $0.kind == .lost }
        let eklenen = kitaplar.filter { $0.addedAt >= baslangic && $0.addedAt <= bitis }
        let dusulen = kitaplar.filter { $0.isWithdrawn && ($0.withdrawnDate ?? .distantPast) >= baslangic && ($0.withdrawnDate ?? .distantFuture) <= bitis }
        let toplamNusha = kitaplar.filter { !$0.isWithdrawn }.reduce(0) { $0 + (states[$1.id]?.total ?? 0) }
        let okuyan = Set(verilen.map { event in
            if let id = event.studentID { return "student:" + id.uuidString }
            if let id = event.memberID { return "member:" + id.uuidString }
            return "legacy:" + CatalogMatcher.normalize(event.person) + "|" + (event.classSnapshot ?? "")
        }).count

        var enCok: [String: Int] = [:]
        for olay in verilen where olay.loanKind != "textbook" { enCok[olay.bookTitle, default: 0] += 1 }
        let populer = enCok.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(10)
        let okurlar = OkumaPuani.siralama(donem).prefix(10)

        return [
            PDFReportBuilder.Section(title: "Genel Durum", rows: [
                ("Kayıtlı eser (düşülenler hariç)", "\(kitaplar.filter { !$0.isWithdrawn }.count)"),
                ("Toplam nüsha", "\(toplamNusha)"),
                ("Dönemde eklenen eser", "\(eklenen.count)"),
                ("Dönemde düşülen eser", "\(dusulen.count)"),
                (className.isEmpty ? "Şu an ödünçte" : "Seçilen sınıfta şu an ödünçte", "\(active.count + (className.isEmpty && includeLegacyLoans ? kitaplar.filter { !($0.loanedTo ?? "").isEmpty }.count : 0))"),
                ("Şu an gecikmiş", "\(active.filter { $0.dueDate < Calendar.current.startOfDay(for: now) }.count + (className.isEmpty && includeLegacyLoans ? kitaplar.filter { !($0.loanedTo ?? "").isEmpty && ($0.loanDueDate ?? .distantFuture) < Calendar.current.startOfDay(for: now) }.count : 0))"),
                ("Şu an verilebilir nüsha (seçili koleksiyon)", "\(states.values.reduce(0) { $0 + $1.available })"),
                ("Kayıp / onarımda nüsha", "\(states.values.reduce(0) { $0 + $1.lost }) / \(states.values.reduce(0) { $0 + $1.repair })")
            ]),
            PDFReportBuilder.Section(title: "Dönem Ödünç Hareketleri", rows: [
                ("Ödünç verilen", "\(verilen.count)"),
                ("İade alınan", "\(iade.count)"),
                ("Tamamlanan okuma (bildirilmiş, ders kitabı hariç)", "\(iade.filter { $0.readingCompleted == true && $0.loanKind != "textbook" }.count)"),
                ("Tamamlanmadan iade (bildirilmiş, ders kitabı hariç)", "\(iade.filter { $0.readingCompleted == false && $0.loanKind != "textbook" }.count)"),
                ("Okuma bilgisi olmayan iade (ders kitabı hariç)", "\(iade.filter { $0.readingCompleted == nil && $0.loanKind != "textbook" }.count)"),
                ("Gecikmeli iade", "\(iade.filter(\.wasLate).count)"),
                ("Kayıp bildirilen", "\(kayip.count)"),
                ("Süre uzatılan", "\(donem.filter { $0.kind == .extended }.count)"),
                ("Ders kitabı verilen (okuma sıralamasından ayrı)", "\(verilen.filter { $0.loanKind == "textbook" }.count)"),
                ("Kitap alan farklı okur", "\(okuyan)"),
                ("Sınıf kimliği eksik eski hareket (tüm dönem)", "\(events.filter { $0.date >= baslangic && $0.date <= bitis && ($0.classSnapshot ?? "").isEmpty }.count)")
            ]),
            PDFReportBuilder.Section(title: "En Çok Ödünç Verilen 10 Eser", rows: populer.map { ($0.key, "\($0.value) kez") }),
            PDFReportBuilder.Section(title: "En Çok Okuyan 10 Öğrenci", rows: okurlar.map { ([$0.ad, $0.classSnapshot ?? "", $0.studentID?.uuidString ?? "Eski kimlik"].filter { !$0.isEmpty }.joined(separator: " · "), "\($0.kitapSayisi) kitap · \($0.puan) puan") }),
            PDFReportBuilder.Section(title: "Koleksiyon Dağılımı", rows: kategoriDagilimi(kitaplar).prefix(15).map { ($0.ad, "\($0.sayi) nüsha") })
        ]
    }
}

// MARK: - Sütun seçmeli CSV

enum KitapSutunu: String, CaseIterable, Identifiable, Codable {
    case ad = "Kitap Adı", yazar = "Yazar", yayinevi = "Yayınevi", isbn = "ISBN", yil = "Yıl"
    case kategori = "Kategori", dil = "Dil", adet = "Adet", dolap = "Dolap", raf = "Raf", yerNo = "Yer No"
    case demirbas = "Demirbaş", seri = "Seri", cilt = "Cilt", etiketler = "Etiketler", duzey = "Okuma Düzeyi"
    case sayfa = "Sayfa", durum = "Okuma Durumu", eklenme = "Eklenme", dusulen = "Düşüldü", notlar = "Notlar"

    var id: String { rawValue }

    static let varsayilan: [KitapSutunu] = [.ad, .yazar, .yayinevi, .isbn, .kategori, .adet, .dolap, .raf]

    func deger(_ kitap: CatalogBook) -> String {
        switch self {
        case .ad: kitap.title
        case .yazar: kitap.author
        case .yayinevi: kitap.publisher ?? ""
        case .isbn: kitap.isbn ?? ""
        case .yil: kitap.publicationYear ?? ""
        case .kategori: kitap.category ?? ""
        case .dil: kitap.language ?? ""
        case .adet: "\(kitap.quantity ?? 1)"
        case .dolap: kitap.cabinet ?? ""
        case .raf: kitap.shelf ?? ""
        case .yerNo: kitap.location ?? ""
        case .demirbas: kitap.accessionCode ?? ""
        case .seri: kitap.series ?? ""
        case .cilt: kitap.volume.map(String.init) ?? ""
        case .etiketler: kitap.tags ?? ""
        case .duzey: kitap.readingLevel ?? ""
        case .sayfa: kitap.pageCount ?? ""
        case .durum: kitap.readingStatus ?? ""
        case .eklenme: kitap.addedAt.formatted(.iso8601.year().month().day())
        case .dusulen: kitap.isWithdrawn ? "Evet" : ""
        case .notlar: kitap.notes
        }
    }
}

enum KitapCSV {
    /// Excel'in Türkçe karakterleri doğru açması için UTF-8 BOM + ";" ayırıcı.
    static func olustur(_ kitaplar: [CatalogBook], sutunlar: [KitapSutunu]) -> String {
        func kacis(_ metin: String) -> String {
            let tek = metin.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            guard tek.contains(";") || tek.contains("\"") || tek.hasPrefix("=") || tek.hasPrefix("+") || tek.hasPrefix("-") || tek.hasPrefix("@") else {
                return tek
            }
            // Formül enjeksiyonuna karşı: =,+,-,@ ile başlayan hücre metin olarak kalır
            let guvenli = (tek.hasPrefix("=") || tek.hasPrefix("+") || tek.hasPrefix("-") || tek.hasPrefix("@")) ? "'" + tek : tek
            return "\"" + guvenli.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var satirlar = [sutunlar.map { kacis($0.rawValue) }.joined(separator: ";")]
        for kitap in kitaplar {
            satirlar.append(sutunlar.map { kacis($0.deger(kitap)) }.joined(separator: ";"))
        }
        return "\u{FEFF}" + satirlar.joined(separator: "\r\n") + "\r\n"
    }

    /// Paylaşım klasörüne (her çağrıda ayrı, rastgele adlı alt klasör) yazar; öğrenci/kitap listeleri sabit adla
    /// geçici klasörde birikmez. Dosyalar ekran kapanınca ve uygulama açılışında temizlenir (`GeciciDosya`).
    static func dosya(_ metin: String, ad: String = "KitapListesi") -> URL? {
        GeciciDosya.yaz(Data(metin.utf8), ad: "\(ad).csv")
    }
}

// MARK: - QR ve derin bağlantı

nonisolated enum KitapQR {
    static let sema = "kitapbul"

    static func url(for id: UUID) -> URL {
        URL(string: "\(sema)://kitap/\(id.uuidString)")!
    }

    /// kitapbul://kitap/<uuid> → uuid
    static func kitapID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == sema, url.host?.lowercased() == "kitap" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }

    /// Widget/kontrol bağlantıları: kitapbul://ekle/barkod|seri|ses|kapak|kamera|elle, kitapbul://asistan
    enum Hedef: Equatable {
        case kitap(UUID)
        case ekle(String)
        case asistan
    }

    static func hedef(from url: URL) -> Hedef? {
        guard url.scheme?.lowercased() == sema else { return nil }
        switch url.host?.lowercased() {
        case "kitap": return kitapID(from: url).map { .kitap($0) }
        case "ekle": return .ekle(url.lastPathComponent.lowercased())
        case "asistan": return .asistan
        default: return nil
        }
    }

    /// Her kart için yeni bağlam kurmak binlerce kartta dakikalar sürer; tek bağlam paylaşılır.
    private static let cizimBaglami = CIContext()

    static func goruntu(_ metin: String, olcek: CGFloat = 8) -> CGImage? {
        let filtre = CIFilter.qrCodeGenerator()
        filtre.message = Data(metin.utf8)
        filtre.correctionLevel = "M"
        guard let cikti = filtre.outputImage?.transformed(by: CGAffineTransform(scaleX: olcek, y: olcek)) else { return nil }
        return cizimBaglami.createCGImage(cikti, from: cikti.extent)
    }
}

/// QR'li kitap kartları (A4'te 2×4): başlık, yazar, yer, QR. Kart okutulunca uygulama kitabı açar.
nonisolated enum KitapKartiPDF {
    struct Kart: Sendable {
        let id: UUID
        let baslik: String
        let yazar: String
        let yer: String
    }

    static func olustur(_ kartlar: [Kart]) -> Data {
        let genislik: CGFloat = 595, yukseklik: CGFloat = 842, kenar: CGFloat = 30
        let sutun = 2, satir = 4
        let data = NSMutableData()
        var kutu = CGRect(x: 0, y: 0, width: genislik, height: yukseklik)
        guard let tuketici = CGDataConsumer(data: data), let ctx = CGContext(consumer: tuketici, mediaBox: &kutu, nil) else { return Data() }
        let hucreG = (genislik - kenar * 2) / CGFloat(sutun)
        let hucreY = (yukseklik - kenar * 2) / CGFloat(satir)
        var i = 0
        while i < kartlar.count {
            ctx.beginPDFPage(nil)
            for yuva in 0..<(sutun * satir) where i < kartlar.count {
                let x = kenar + CGFloat(yuva % sutun) * hucreG
                let y = yukseklik - kenar - CGFloat(yuva / sutun + 1) * hucreY
                ciz(kartlar[i], CGRect(x: x, y: y, width: hucreG, height: hucreY).insetBy(dx: 6, dy: 6), ctx)
                i += 1
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    private static func ciz(_ kart: Kart, _ alan: CGRect, _ ctx: CGContext) {
        ctx.setStrokeColor(CGColor(gray: 0.6, alpha: 1))
        ctx.setLineWidth(0.6)
        ctx.stroke(alan)
        let qrBoyut = min(alan.height - 20, alan.width * 0.45)
        if let qr = KitapQR.goruntu(KitapQR.url(for: kart.id).absoluteString) {
            ctx.interpolationQuality = .none
            ctx.draw(qr, in: CGRect(x: alan.maxX - qrBoyut - 10, y: alan.minY + (alan.height - qrBoyut) / 2, width: qrBoyut, height: qrBoyut))
        }
        let metinG = alan.width - qrBoyut - 30
        var imlec = alan.maxY - 16
        imlec = yaz(kart.baslik, 13, kalin: true, x: alan.minX + 10, y: imlec, g: metinG, satir: 3, ctx)
        imlec = yaz(kart.yazar, 10, kalin: false, x: alan.minX + 10, y: imlec - 4, g: metinG, satir: 2, ctx)
        if !kart.yer.isEmpty { _ = yaz(kart.yer, 10, kalin: true, x: alan.minX + 10, y: imlec - 6, g: metinG, satir: 1, ctx) }
        _ = yaz("Okut: kitabı Kitap Bul'da aç", 7, kalin: false, x: alan.minX + 10, y: alan.minY + 16, g: metinG, satir: 1, ctx)
    }

    private static func yaz(_ metin: String, _ boyut: CGFloat, kalin: Bool, x: CGFloat, y: CGFloat, g: CGFloat, satir: Int, _ ctx: CGContext) -> CGFloat {
        let font = CTFontCreateWithName((kalin ? "HelveticaNeue-Bold" : "HelveticaNeue") as CFString, boyut, nil)
        let nitelik = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1)] as CFDictionary
        guard let dizgi = CFAttributedStringCreate(nil, metin as CFString, nitelik) else { return y - boyut }
        let kurucu = CTFramesetterCreateWithAttributedString(dizgi)
        let yol = CGPath(rect: CGRect(x: x, y: 0, width: g, height: boyut * CGFloat(satir) * 1.3), transform: nil)
        let cerceve = CTFramesetterCreateFrame(kurucu, CFRange(location: 0, length: 0), yol, nil)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: y - boyut * 1.3 * CGFloat(satir))
        CTFrameDraw(cerceve, ctx)
        ctx.restoreGState()
        return y - boyut * 1.3 * CGFloat(satir)
    }
}

// MARK: - Etiket şablonları ve renk bandı

nonisolated enum EtiketSablonu: String, CaseIterable, Identifiable, Sendable {
    case standart = "Standart (3×8)"
    case sirt = "Sırt etiketi (4×12, renk bandı)"
    case buyuk = "Büyük (2×6, barkod + QR)"

    static let anahtar = "spineLabelTemplate"
    var id: String { rawValue }

    static var kayitli: EtiketSablonu {
        EtiketSablonu(rawValue: UserDefaults.standard.string(forKey: anahtar) ?? "") ?? .standart
    }

    var izgara: (sutun: Int, satir: Int) {
        switch self {
        case .standart: (3, 8)
        case .sirt: (4, 12)
        case .buyuk: (2, 6)
        }
    }
}

nonisolated enum EtiketRengi {
    /// Kategoriye sabit renk (raflarda renk kodlu dizim için); aynı kategori hep aynı renk.
    static let palet: [(CGFloat, CGFloat, CGFloat)] = [
        (0.85, 0.23, 0.23), (0.95, 0.55, 0.13), (0.93, 0.78, 0.15), (0.30, 0.69, 0.31), (0.13, 0.59, 0.95),
        (0.40, 0.23, 0.72), (0.91, 0.12, 0.39), (0.47, 0.33, 0.28), (0.00, 0.59, 0.53), (0.38, 0.49, 0.55)
    ]

    static func renk(for kategori: String?) -> CGColor {
        // Anahtar bilerek değiştirilmez: değişirse yeni basılan etiketin rengi raftaki eski etiketle tutmaz
        let anahtar = (kategori ?? "").lowercased()
        guard !anahtar.isEmpty else { return CGColor(gray: 0.6, alpha: 1) }
        // Kararlı özet (Swift hashValue her açılışta değişir)
        let toplam = anahtar.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
        let (r, g, b) = palet[Int(toplam % UInt32(palet.count))]
        return CGColor(red: r, green: g, blue: b, alpha: 1)
    }

    /// Yer numarası alanı Dewey biçimindeyse ("813", "894.35") döner.
    static func dewey(_ yer: String?) -> String? {
        guard let yer = yer?.trimmingCharacters(in: .whitespaces), !yer.isEmpty else { return nil }
        let parcalar = yer.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parcalar.count), parcalar[0].count == 3, parcalar.allSatisfy({ $0.allSatisfy(\.isNumber) && !$0.isEmpty }) else { return nil }
        return yer
    }
}
