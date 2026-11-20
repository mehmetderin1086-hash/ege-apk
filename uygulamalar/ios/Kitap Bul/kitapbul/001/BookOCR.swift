import Foundation
import CoreGraphics
import CoreImage
import CoreText
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import Vision

#if DEBUG
/// Geliştirme sınaması: OCR hattını cihaz üstünde, gerçek uygulama sürecinde dener
/// ve sonucu konsola yazar. Yalnızca DEBUG derlemede vardır.
enum BookOCRSelfTest {
    static func run() async {
        guard let image = makeCover() else {
            print("📖 SELFTEST: görüntü oluşturulamadı")
            return
        }
        do {
            let result = try await BookOCREngine.recognize(cgImage: image)
            let draft = BookOCRExtractor.draft(from: result)
            let expected = draft.title == "Kürk Mantolu Madonna"
                && draft.author == "SABAHATTİN ALİ"
                && draft.isbn == "9789750718533"
                && draft.publisher == "Yapı Kredi Yayınları"
            print("📖 SELFTEST \(expected ? "BAŞARILI" : "SAPMA") → ad=\(draft.title) | yazar=\(draft.author) | isbn=\(draft.isbn) | yayınevi=\(draft.publisher)")
        } catch {
            print("📖 SELFTEST HATA: \(error)")
        }
    }

    private static func makeCover() -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: 1000, height: 1400, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1000, height: 1400))

        func draw(_ text: String, size: CGFloat, y: CGFloat) {
            let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, size, nil)
            let attributes = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1)
            ] as CFDictionary
            guard let string = CFAttributedStringCreate(nil, text as CFString, attributes) else { return }
            context.textPosition = CGPoint(x: 60, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(string), context)
        }

        draw("SABAHATTİN ALİ", size: 44, y: 1220)
        draw("Kürk Mantolu", size: 96, y: 1000)
        draw("Madonna", size: 96, y: 880)
        draw("ISBN: 978-975-07-1853-3", size: 22, y: 300)
        draw("Yapı Kredi Yayınları", size: 28, y: 160)
        return context.makeImage()
    }
}
#endif

/// OCR ile okunan tek bir metin satırı.
nonisolated struct OCRLine {
    var text: String
    /// Görüntüye oranla normalize yazı yüksekliği (0 = bilinmiyor).
    /// Kapaktaki en büyük yazıyı (kitap adını) bulmak için kullanılır.
    var height: CGFloat
    var confidence: Float
}

/// Bir görüntünün tüm OCR çıktısı: satırlar + varsa barkoddan okunan ISBN.
nonisolated struct BookOCRResult {
    var lines: [OCRLine]
    var barcodeISBN: String?

    var averageConfidence: Float {
        lines.isEmpty ? 0 : lines.map(\.confidence).reduce(0, +) / Float(lines.count)
    }
}

/// Kitap kapağı/künye görüntülerinden metin ve barkod okuyan OCR motoru.
/// Türkçe için cihaz üstündeki en iyi ÜÇ tanıma motorunu birlikte çalıştırır
/// ve sonuçları tek listede birleştirir:
/// 1. Klasik Vision hassas tanıma (VNRecognizeTextRequest, tr-TR) + EAN-13 barkod okuma
/// 2. Yeni nesil Vision metin tanıma (RecognizeTextRequest, güncel model revizyonu)
/// 3. Yapısal belge tanıma (RecognizeDocumentsRequest, iOS 26+) — künye sayfaları ve barkod
/// Ek olarak sonuç zayıfsa kontrast artırılmış görüntüyle ikinci bir geçiş yapılır.
enum BookOCREngine {
    /// Fotoğraf verisinden tek adımda taslak üretir. Görüntü çözme, OCR ve kapak
    /// kodlama dahil TÜM ağır işler arka plan görevinde koşar — arayüz asla donmaz.
    ///
    /// ANA OCR = Gemini: cihaz Vision motorları ve Gemini AYNI ANDA çalışır. Gemini
    /// alanları (ad, yazar, yayınevi, yıl, kategori…) esas alınır; Vision'dan yalnızca
    /// barkod ISBN'i ve Gemini'nin boş bıraktığı alanlar gelir. Gemini kapalı/çevrimdışı/
    /// hatalıysa Vision sonucu tek başına kullanılır — tarama hiç aksamaz.
    /// Görev iptal edilirse (ör. kullanıcı "Durdur"a bastı, ekran kapandı) `nil` döner ve hiçbir sonuç üretilmez.
    static func recognizeBook(imageData: Data) async -> BookDraft? {
        async let geminiFields = GeminiBookRecognizer.fieldsIfEnabled(images: [imageData])

        let visionDraft = await visionTaslagi(imageData: imageData)
        let fields = await geminiFields
        guard !Task.isCancelled else { return nil }

        switch (visionDraft, fields) {
        case (var draft?, let fields?):
            GeminiBookRecognizer.merge(fields, into: &draft)
            return draft
        case (let draft?, nil):
            return draft
        case (nil, let fields?) where fields.isBook != false:
            // Vision görüntüyü çözemedi ama Gemini okudu: kapak ham veriden küçültülür
            let cover = GeminiImagePreparer.jpegData(from: imageData, maxPixel: 1400)
            return GeminiBookRecognizer.draft(from: fields, cover: cover)
        default:
            return nil
        }
    }

    /// Cihaz Vision motorlarıyla taslak; ana aktörün dışında ve çağıranın görev ağacı içinde koşar.
    @concurrent private static func visionTaslagi(imageData: Data) async -> BookDraft? {
        guard !Task.isCancelled, let image = decodeImage(from: imageData) else { return nil }
        guard let result = try? await recognize(cgImage: image), !Task.isCancelled else { return nil }
        var draft = await BookOCRExtractor.draft(from: result)
        draft.coverData = coverData(from: imageData) ?? encodePNG(image)
        return draft
    }

    /// Görüntü verisinden yalnızca OCR sonucu (kamera çok sayfa akışı için) — arka planda.
    /// İptal edilen görev sonuç döndürmez.
    @concurrent static func recognize(imageData: Data) async -> BookOCRResult? {
        guard !Task.isCancelled, let image = decodeImage(from: imageData) else { return nil }
        let sonuc = try? await recognize(cgImage: image)
        return Task.isCancelled ? nil : sonuc
    }

    nonisolated static func decodeImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2600,
            kCGImageSourceShouldCacheImmediately: false
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Katalogda saklanacak kapak: en çok 1600 px JPEG. 2600 px PNG kapak başına birkaç MB
    /// tutar; kataloğu, yedekleri ve bekleyen tarama kuyruğunu şişirir.
    nonisolated static func coverData(from data: Data) -> Data? {
        GeminiImagePreparer.jpegData(from: data, maxPixel: 1600, quality: 0.85)
    }

    nonisolated static func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Aşamalar arasında iptal denetlenir: iptal edilen görev kalan motorları çalıştırmaz ve `CancellationError` fırlatır.
    @concurrent static func recognize(cgImage: CGImage) async throws -> BookOCRResult {
        // Motorlar birbirinden bağımsızdır: biri hata verirse diğerleri devam eder.
        var result = BookOCRResult(lines: [], barcodeISBN: nil)
        var firstError: Error?
        try Task.checkCancellation()

        // Motor 1: Klasik hassas tanıma + barkod
        do {
            result = merge(result, try await classicPass(on: cgImage))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            firstError = error
        }
        try Task.checkCancellation()
        debugLog("motor 1 bitti: \(result.lines.count) satır")

        // Motor 2: Yeni nesil Vision metin tanıma
        do {
            result = merge(result, try await modernPass(on: cgImage))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            firstError = firstError ?? error
        }
        try Task.checkCancellation()
        debugLog("motor 2 bitti: \(result.lines.count) satır")

        // Sonuç hâlâ zayıfsa kontrast artırılmış görüntüyle ek geçiş
        // (görüntü iyileştirme ağırdır; bu işlev zaten ana aktörün dışında koşar)
        if result.averageConfidence < 0.9 || result.lines.count < 8 {
            if let enhanced = enhancedImage(from: cgImage),
               let secondPass = try? await classicPass(on: enhanced) {
                result = merge(result, secondPass)
            }
        }
        try Task.checkCancellation()
        debugLog("iyileştirilmiş geçiş bitti: \(result.lines.count) satır")

        // Motor 3: Yapısal belge tanıma
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            if let documentResult = try? await documentPass(on: cgImage) {
                result = merge(result, documentResult)
            }
        }
        try Task.checkCancellation()
        debugLog("motor 3 bitti: \(result.lines.count) satır")

        // Hiçbir motor tek satır bile okuyamadıysa hatayı yükselt
        if result.lines.isEmpty, result.barcodeISBN == nil, let firstError {
            throw firstError
        }
        return result
    }

    nonisolated private static func debugLog(_ message: String) {
#if DEBUG
        print("📖 OCR: \(message)")
#endif
    }

    /// Motor 2: Yeni nesil Vision API'si (iOS 18+). Klasik motordan farklı model
    /// revizyonu kullandığı için onun kaçırdığı satırları yakalayabilir.
    private static func modernPass(on cgImage: CGImage) async throws -> BookOCRResult {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [
            Locale.Language(identifier: "tr-TR"),
            Locale.Language(identifier: "en-US")
        ]
        request.usesLanguageCorrection = true
        request.minimumTextHeightFraction = 0.005
        request.automaticallyDetectsLanguage = false

        let observations = try await request.perform(on: cgImage)
        let sorted = observations.sorted { lhs, rhs in
            let left = lhs.boundingBox.cgRect
            let right = rhs.boundingBox.cgRect
            let verticalDifference = abs(left.midY - right.midY)
            if verticalDifference > 0.02 {
                return left.midY > right.midY
            }
            return left.minX < right.minX
        }

        var lines: [OCRLine] = []
        for observation in sorted {
            guard let candidate = observation.topCandidates(3).first else { continue }
            lines.append(
                OCRLine(
                    text: candidate.string,
                    height: observation.boundingBox.cgRect.height,
                    confidence: candidate.confidence
                )
            )
        }
        return BookOCRResult(lines: lines, barcodeISBN: nil)
    }

    // MARK: - Tanıma geçişleri

    /// Klasik motor. Vision'ın eşzamanlı `perform` çağrısı `@concurrent` bağlamda koşar (ana akışı kilitlemez);
    /// görev iptal edilince devam eden istekler `cancel()` ile durdurulur.
    @concurrent private static func classicPass(on cgImage: CGImage) async throws -> BookOCRResult {
        try Task.checkCancellation()
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.recognitionLanguages = ["tr-TR", "en-US"]
        textRequest.usesLanguageCorrection = true
        textRequest.minimumTextHeight = 0.005
        textRequest.customWords = [
            "ISBN", "yayınevi", "yayıncılık", "baskı", "sayfa", "çeviren",
            "Doğan", "İş Bankası", "Can Yayınları", "Yapı Kredi", "İletişim"
        ]
        let barcodeRequest = VNDetectBarcodesRequest()
        barcodeRequest.symbologies = [.ean13]
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)

        nonisolated(unsafe) let metinIstegi = textRequest
        nonisolated(unsafe) let barkodIstegi = barcodeRequest
        try await withTaskCancellationHandler {
            try handler.perform([textRequest])
            // Barkod okuma ayrı koşar: hata verirse metin sonuçlarını götürmesin
            try? handler.perform([barcodeRequest])
        } onCancel: {
            metinIstegi.cancel()
            barkodIstegi.cancel()
        }
        try Task.checkCancellation()

        // Satırları görsel sıraya koy: üstten alta, aynı hizada soldan sağa
        let sorted = (textRequest.results ?? []).sorted { lhs, rhs in
            let verticalDifference = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
            if verticalDifference > 0.02 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        var lines: [OCRLine] = []
        for observation in sorted {
            guard let candidate = observation.topCandidates(3).first else { continue }
            lines.append(
                OCRLine(
                    text: candidate.string,
                    height: observation.boundingBox.height,
                    confidence: candidate.confidence
                )
            )
        }

        let barcodeISBN = barcodeRequest.results?
            .compactMap(\.payloadStringValue)
            .map(ISBNFormatter.repair)
            .first(where: ISBNFormatter.isValidISBN13)

        return BookOCRResult(lines: lines, barcodeISBN: barcodeISBN)
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private static func documentPass(on cgImage: CGImage) async throws -> BookOCRResult {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.recognitionLanguages = [
            Locale.Language(identifier: "tr-TR"),
            Locale.Language(identifier: "en-US")
        ]
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        request.textRecognitionOptions.useLanguageCorrection = true
        request.textRecognitionOptions.customWords = [
            "ISBN", "yayınevi", "yayıncılık", "baskı", "sayfa", "çeviren"
        ]

        let observations = try await request.perform(on: cgImage, orientation: .up)
        guard let observation = observations.first else {
            return BookOCRResult(lines: [], barcodeISBN: nil)
        }

        let lines = observation.document.text.lines.compactMap { line -> OCRLine? in
            guard let candidate = line.topCandidates(3).first else { return nil }
            return OCRLine(text: candidate.string, height: 0, confidence: candidate.confidence)
        }
        let barcodeISBN = observation.document.barcodes
            .compactMap(\.payloadString)
            .map(ISBNFormatter.repair)
            .first(where: ISBNFormatter.isValidISBN13)

        return BookOCRResult(lines: lines, barcodeISBN: barcodeISBN)
    }

    // MARK: - Yardımcılar

    /// İki geçişin satırlarını, tekrarları eleyerek birleştirir. Aynı satır iki geçişte de
    /// okunduysa yüksekliği ve güveni yüksek olan korunur.
    nonisolated private static func merge(_ first: BookOCRResult, _ second: BookOCRResult) -> BookOCRResult {
        var seen: [String: Int] = [:]
        var merged: [OCRLine] = []

        for line in first.lines + second.lines {
            let key = line.text
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }

            if let index = seen[key] {
                merged[index].height = max(merged[index].height, line.height)
                merged[index].confidence = max(merged[index].confidence, line.confidence)
            } else {
                seen[key] = merged.count
                merged.append(line)
            }
        }

        return BookOCRResult(
            lines: merged,
            barcodeISBN: first.barcodeISBN ?? second.barcodeISBN
        )
    }

    /// Zayıf kontrastlı/stilize yazılar için gri tonlama + kontrast + netleştirme uygular.
    nonisolated private static func enhancedImage(from image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let controls = input.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputSaturationKey: 0,
                kCIInputContrastKey: 1.45,
                kCIInputBrightnessKey: 0.03
            ]
        )
        let sharpened = controls.applyingFilter(
            "CISharpenLuminance",
            parameters: [kCIInputSharpnessKey: 0.7]
        )
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(
            sharpened,
            from: sharpened.extent
        )
    }
}

/// OCR çıktısından kitap alanlarını (ad, yazar, yayınevi, ISBN, yıl, baskı, sayfa) çıkarır.
enum BookOCRExtractor {
    static func draft(from result: BookOCRResult) -> BookDraft {
        // Satırları hazırla: "Ad | Yazar" gibi üstbilgi satırlarını böl, temizle ve aksan
        // farkı dışında aynı olan satırları Türkçe karakteri çok olan lehine tekilleştir
        // ("Yüzbasının Kızı" yerine "Yüzbaşının Kızı" kazanır).
        var seen: [String: Int] = [:]
        var entries: [OCRLine] = []
        for line in result.lines {
            for part in line.text.components(separatedBy: "|") {
                let cleaned = clean(part)
                guard !cleaned.isEmpty else { continue }
                let key = foldKey(cleaned)
                if let index = seen[key] {
                    if turkishScore(cleaned) > turkishScore(entries[index].text) {
                        entries[index].text = cleaned
                    }
                    entries[index].height = max(entries[index].height, line.height)
                    entries[index].confidence = max(entries[index].confidence, line.confidence)
                } else {
                    seen[key] = entries.count
                    entries.append(OCRLine(text: cleaned, height: line.height, confidence: line.confidence))
                }
            }
        }
        let texts = entries.map(\.text)
        let joined = texts.joined(separator: " ")

        var draft = BookDraft()
        draft.isbn = result.barcodeISBN ?? isbn(in: joined)
        draft.publicationYear = publicationYear(in: texts)
        draft.edition = edition(in: texts)
        let (pages, pagesInferred) = pageCount(in: texts)
        draft.pageCount = pages
        if pagesInferred {
            draft.lowConfidenceFields.insert("pageCount")
        }
        draft.publisher = publisher(in: texts)
        draft.author = labeledOrKnownAuthor(in: entries)
        draft.title = title(in: entries, excluding: draft.author)
        if draft.author.isEmpty {
            draft.author = inferredAuthor(in: entries, title: draft.title, publisher: draft.publisher)
        }

        // Bazı kapaklarda yazar adı kitap adından büyük basılır. Seçilen "ad" kişi adına
        // benziyor, yazar boş kaldı ve isim gibi görünmeyen başka aday varsa ikisini takas et.
        if draft.author.isEmpty, isNameLike(draft.title) {
            let currentTitle = draft.title
            if let alternative = titleCandidates(in: entries)
                .filter({ $0.text != currentTitle && !isNameLike($0.text) })
                .max(by: { $0.height < $1.height }) {
                draft.author = currentTitle
                draft.title = alternative.text
            }
        }

        // Daha önce elle düzeltilmiş hatalı okumalar otomatik düzeltilir
        draft.title = CorrectionMemory.correct(draft.title)
        draft.author = CorrectionMemory.correct(draft.author)
        draft.publisher = CorrectionMemory.correct(draft.publisher)

        markLowConfidenceFields(&draft, result: result)

#if DEBUG
        print("📖 OCR satırları (\(result.lines.count)):")
        for line in result.lines {
            print(String(format: "  h=%.3f g=%.2f | %@", line.height, line.confidence, line.text))
        }
        print("📖 Barkod ISBN: \(result.barcodeISBN ?? "-")")
        print("📖 Çıkarılan → ad=\(draft.title) | yazar=\(draft.author) | isbn=\(draft.isbn) | yayınevi=\(draft.publisher) | yıl=\(draft.publicationYear) | sayfa=\(draft.pageCount)")
#endif

        return draft
    }

    // MARK: - Alan çıkarma

    /// Kitap adı: etiketli değer varsa o; yoksa görüntüdeki EN BÜYÜK yazı.
    /// (Kapakta en büyük punto neredeyse her zaman kitap adıdır; ilk satır çoğu zaman yazardır.)
    private static func title(in entries: [OCRLine], excluding author: String) -> String {
        if let labeled = labeledValue(in: entries.map(\.text), labels: ["kitap adı", "eser adı", "başlık", "title"]) {
            return labeled
        }

        let candidates = titleCandidates(in: entries).filter { $0.text != author }

        guard let tallest = candidates.max(by: { $0.height < $1.height }), tallest.height > 0 else {
            return candidates.first?.text ?? ""
        }

        // Çok satıra bölünmüş adlar ("Kürk Mantolu" / "Madonna"): en büyük satıra bitişik
        // ve benzer puntolu aday satırları okuma sırasıyla birleştir.
        let candidateTexts = Set(candidates.map(\.text))
        guard let tallestIndex = entries.firstIndex(where: { $0.text == tallest.text }) else {
            return tallest.text
        }
        func isSameTitleBlock(_ entry: OCRLine) -> Bool {
            // Çok satırlı adlarda satırlar farklı puntoyla dizilebilir
            // ("Türkiye'nin / Bütün / Ağaçları ve Çalıları"); %45'e kadar fark aynı blok sayılır.
            // Rakamla biten satırlar (dizin girdileri: "Yasemin 854") bloğa katılmaz.
            candidateTexts.contains(entry.text)
                && entry.height > 0
                && entry.text.last?.isNumber != true
                && abs(entry.height - tallest.height) / tallest.height < 0.45
        }
        var start = tallestIndex
        var end = tallestIndex
        while start > 0, isSameTitleBlock(entries[start - 1]) { start -= 1 }
        while end + 1 < entries.count, isSameTitleBlock(entries[end + 1]) { end += 1 }

        var joined = entries[start...end].map(\.text).joined(separator: " ")
        // Aşırı uzun birleşimler (dizin/paragraf yapışması) yerine en büyük satır kullanılır
        if joined.count > 90 {
            joined = tallest.text
        }

        // Çok fotoğraflı taramalarda ad parçalanabilir; künyede adın TEK SATIRDA tam hâli
        // varsa ("TÜRKİYE'NİN BÜTÜN AĞAÇLARI VE ÇALILARI") onu tercih et.
        let joinedKey = foldKey(joined)
        let fullLine = candidates.first { candidate in
            candidate.text.count > joined.count
                && candidate.text.count <= 90
                && foldKey(candidate.text).contains(joinedKey)
        }
        return fullLine?.text ?? joined
    }

    private static func titleCandidates(in entries: [OCRLine]) -> [OCRLine] {
        let ignoredTerms = [
            "adobe scan", "isbn", "yayın", "baskı", "sertifika", "çeviren",
            "hazırlayan", "tasarım", "tel:", "faks:", "www.", "orijinal adı", "yazar",
            "copyright", "sayfa", "edition", "publisher", "editör", "editor",
            "banka", "matbaa", "vakfı", "vakfi"
        ]

        // Çok fotoğraflı birleşik taramalarda ad satırları listenin ilerisine düşebilir;
        // tüm satırlar taranır (cümle/rakam/etiket filtreleri gövde metnini zaten eler).
        let maxHeight = entries.map(\.height).max() ?? 0
        return entries.filter { entry in
            let line = entry.text
            let lower = line.lowercased(with: Locale(identifier: "tr_TR"))
            guard line.count >= 2,
                  line.count <= 80,
                  !ignoredTerms.contains(where: lower.contains) else { return false }

            // Cümle benzeri satırlar (gövde metni) kitap adı olamaz
            if line.hasSuffix(".") || line.hasSuffix(",") || line.hasSuffix(";")
                || line.split(separator: " ").count > 8 {
                return false
            }

            // Salt rakam/noktalama satırları (ISBN, fiyat vb.) elenir; ancak sayfadaki
            // EN BÜYÜK yazıysa kitap adı olabilir ("1984", "1Q84" gibi).
            if line.range(of: #"^[-~.,;:0-9 ]+$"#, options: .regularExpression) != nil {
                return entry.height > 0 && entry.height >= maxHeight && line.count <= 6
            }
            return true
        }
    }

    /// Satır kişi adına benziyor mu: 2-4 kelime, her kelime büyük harfle başlıyor, rakam yok.
    private static func isNameLike(_ rawLine: String) -> Bool {
        let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:"))
        guard (5...40).contains(line.count) else { return false }
        let words = line.split(separator: " ")
        guard (2...4).contains(words.count) else { return false }
        return words.allSatisfy { word in
            guard let first = word.first, first.isUppercase else { return false }
            // Tek harflik noktasız kelimeler logo kırıntısıdır ("TEMA O"); ad sayılmaz.
            // Noktalı kısaltmalar ("K.", "Dr.") geçerlidir.
            if word.count == 1 { return false }
            return word.allSatisfy { $0.isLetter || $0 == "." || $0 == "-" || $0 == "’" || $0 == "'" }
        }
    }

    /// Yazar: "Yazar:" etiketi ya da bilinen yazar adları. Bilinen ad tek kelimelik bir
    /// satırdaysa ("Puşkin") bitişik isim satırıyla birleştirilir ("Aleksandr Sergeyeviç Puşkin").
    private static func labeledOrKnownAuthor(in entries: [OCRLine]) -> String {
        let lines = entries.map(\.text)
        if let labeled = labeledValue(
            in: lines,
            labels: ["yazar", "yazan", "author", "editör", "editor", "derleyen"]
        ), isNameLike(labeled) {
            // Etiketin altındaki satır cümleyse ("toprağın varlığı ise...") yazar sayılmaz
            return labeled
        }

        let authorHints = [
            // Türk edebiyatı
            "orhan pamuk", "elif şafak", "yaşar kemal", "sabahattin ali", "ahmet hamdi",
            "oğuz atay", "peyami safa", "halid ziya", "reşat nuri", "nazım hikmet",
            "necip fazıl", "cemal süreya", "zülfü livaneli", "ahmet ümit", "ihsan oktay anar",
            "buket uzuner", "ayşe kulin", "hakan günday", "aziz nesin", "rıfat ılgaz",
            "kemal tahir", "orhan kemal", "sait faik", "tarık buğra", "attila ilhan",
            "murathan mungan", "adalet ağaoğlu", "sevgi soysal", "latife tekin", "aslı erdoğan",
            // Dünya edebiyatı
            "stephen king", "agatha christie", "dan brown", "rowling", "george orwell",
            "aldous huxley", "franz kafka", "albert camus", "sartre", "dostoyevski",
            "tolstoy", "çehov", "puşkin", "gogol", "turgenyev", "victor hugo",
            "stefan zweig", "hermann hesse", "thomas mann", "goethe", "milan kundera",
            "umberto eco", "italo calvino", "saramago", "marquez", "márquez",
            "paulo coelho", "borges", "haruki murakami", "mişima", "khaled hosseini",
            "john steinbeck", "hemingway", "faulkner", "virginia woolf", "james joyce",
            "charles dickens", "jane austen", "brontë", "mark twain", "jack london",
            "edgar allan poe", "oscar wilde", "saint-exupéry", "jules verne",
            "alexandre dumas", "balzac", "flaubert", "zola", "marcel proust",
            "simone de beauvoir", "tolkien", "le guin", "isaac asimov", "ray bradbury",
            "philip k. dick", "arthur c. clarke", "douglas adams", "neil gaiman",
            "terry pratchett", "harari"
        ]
        for (index, entry) in entries.enumerated() {
            let lower = entry.text.lowercased(with: Locale(identifier: "tr_TR"))
            guard entry.text.count <= 40,
                  authorHints.contains(where: lower.contains) else { continue }

            // Tek kelimelik eşleşmeyi ("Puşkin") bitişik isim satırıyla tamamla
            if entry.text.split(separator: " ").count == 1 {
                if index > 0, isNameLike(entries[index - 1].text) {
                    return entries[index - 1].text + " " + entry.text
                }
                if index + 1 < entries.count, isNameLike(entries[index + 1].text) {
                    return entry.text + " " + entries[index + 1].text
                }
            }
            return entry.text
        }
        return ""
    }

    /// Yazar bulunamadıysa isim desenine göre tahmin: 2-4 kelime, her kelime büyük harfle
    /// başlıyor, rakam yok. Adaylar arasından en büyük puntolu satır seçilir.
    private static func inferredAuthor(in entries: [OCRLine], title: String, publisher: String) -> String {
        let ignoredTerms = [
            "yayın", "isbn", "baskı", "sayfa", "çeviren", "hazırlayan", "tasarım",
            "www.", "tel:", "faks:", "copyright", "kitap", "roman", "öykü", "şiir",
            "orijinal adı", "edition", "publisher", "bestseller"
        ]

        let candidates = entries.prefix(24).filter { entry in
            let line = entry.text
            guard line != title, line != publisher,
                  !title.localizedCaseInsensitiveContains(line) else { return false }

            let lower = line.lowercased(with: Locale(identifier: "tr_TR"))
            guard !ignoredTerms.contains(where: lower.contains) else { return false }

            return isNameLike(line)
        }

        if let best = candidates.max(by: { $0.height < $1.height }), best.height > 0 {
            return best.text
        }
        return candidates.first?.text ?? ""
    }

    private static func publisher(in lines: [String]) -> String {
        if let labeled = labeledValue(
            in: lines,
            labels: ["yayınevi", "yayıncı", "publisher", "published by"]
        ) {
            return cleanPublisher(labeled)
        }

        let keywords = ["yayıncılık", "yayınları", "yayınevi", "kitap", "publishing", "press"]
        let candidates = lines.filter { line in
            let lower = line.lowercased(with: Locale(identifier: "tr_TR"))
            // Cümle görünümlü satırlar ("yayınevinden izin alınmadan...") yayınevi adı olamaz:
            // küçük harfle başlayan ya da virgül/noktayla biten satırlar elenir.
            guard line.first?.isLowercase != true,
                  !line.hasSuffix(","), !line.hasSuffix("."),
                  line.split(separator: " ").count <= 7 else { return false }
            return line.count <= 60
                && keywords.contains(where: lower.contains)
                && !lower.contains("kitap ve kapak")
                && !lower.contains("kitap bilgileri")
                && !lower.contains("bu kitab")
        }

        if candidates.contains(where: { $0.localizedCaseInsensitiveContains("Doğan Kitap") }) {
            return "Doğan Kitap"
        }
        if candidates.contains(where: { $0.localizedCaseInsensitiveContains("Doğan") }) {
            return "Doğan Egmont Yayıncılık"
        }
        // En uzun aday genellikle en eksiksiz addır ("Kültür Yayınları" yerine
        // "TÜRKİYE İŞ BANKASI KÜLTÜR YAYINLARI")
        let best = candidates.max(by: { $0.count < $1.count }) ?? ""
        return cleanPublisher(best)
    }

    /// Yayınevi adındaki © / ® artıklarını ve sondaki yılı temizler.
    private static func cleanPublisher(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"^[©®™\s]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[,;\s]*(?:19|20)\d{2}$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func isbn(in text: String) -> String {
        let labeled = firstMatch(
            in: text,
            pattern: #"(?i)ISBN(?:-1[03])?\s*[:：]?\s*([0-9OQILZSBG][0-9OQILZSBG\-\s]{8,24}[0-9OQILZSBGX])"#,
            group: 1
        )
        let candidates = [labeled] + matches(
            in: text,
            pattern: #"(?i)\b97[89OQILZSBG][0-9OQILZSBG\-\s]{9,22}[0-9OQILZSBG]\b"#
        )
        for candidate in candidates {
            if let valid = validISBN(from: candidate) {
                return valid
            }
        }
        return ""
    }

    /// OCR karışıklıklarını düzeltir ve peşine yapışan fazla rakamları (ör. baskı numarası)
    /// kırparak geçerli bir ISBN-13 üretmeye çalışır.
    private static func validISBN(from raw: String) -> String? {
        let repaired = ISBNFormatter.repair(raw)
        if ISBNFormatter.isValidISBN13(repaired) {
            return repaired
        }

        let replacements: [Character: Character] = [
            "O": "0", "Q": "0", "I": "1", "L": "1",
            "Z": "2", "S": "5", "G": "6", "B": "8"
        ]
        let digits = raw.uppercased()
            .map { replacements[$0] ?? $0 }
            .filter(\.isNumber)
        guard digits.count > 13 else { return nil }
        let firstThirteen = String(digits.prefix(13))
        return ISBNFormatter.isValidISBN13(firstThirteen) ? firstThirteen : nil
    }

    /// Sayfa sayısı. İkinci değer true ise sayı, sayfa numaralarından çıkarılmış bir
    /// tahmindir (kullanıcı kontrolü için düşük güvenli işaretlenir).
    private static func pageCount(in lines: [String]) -> (String, Bool) {
        // Tiraj ("Her 2000 adet...") ve adres satırları sayfa sayısı olarak okunmasın
        let usable = lines.filter {
            let lower = $0.lowercased(with: Locale(identifier: "tr_TR"))
            return !lower.contains("adet") && !lower.contains("no:") && !lower.contains("tel")
        }
        // Regex'in (?i) seçeneği Türkçe I↔ı eşlemez ("SAYFA SAYISI" kaçar); metin Türkçe
        // kurallarla küçültülür, desenler iki i biçimini de kabul eder
        let joined = usable.joined(separator: " ").lowercased(with: Locale(identifier: "tr_TR"))

        // 1) Etiketli değer: "687 sayfa", "sayfa sayısı: 687", "352 pages"
        let patterns = [
            #"(?:sayfa\s*say[ıi]s[ıi]|toplam\s*sayfa|pages?)\s*[:：]?\s*(\d{1,5})\b"#,
            #"\b(\d{2,5})\s*(?:sayfa|pages?|sah[iı]fe)\b"#
        ]
        for pattern in patterns {
            let value = firstMatch(in: joined, pattern: pattern, group: 1)
            if let count = Int(value), (20...10000).contains(count) {
                return (String(count), false)
            }
        }

        // 2) Etiket yok: taranan iç sayfalardaki yalın sayfa numaralarının en büyüğü.
        //    (Kitabın SON sayfası taranırsa bu değer toplam sayfa sayısıdır.)
        var best = 0
        for line in usable {
            let repaired = repairDigits(line.trimmingCharacters(in: .whitespacesAndNewlines))
            guard repaired.count <= 4,
                  repaired.allSatisfy(\.isNumber),
                  let value = Int(repaired),
                  (20...9999).contains(value),
                  !(1900...2099).contains(value) // yalın yıl satırlarını eleme
            else { continue }
            best = max(best, value)
        }
        return best > 0 ? (String(best), true) : ("", false)
    }

    private static func publicationYear(in lines: [String]) -> String {
        // "Her 2000 adet bir baskı..." gibi tiraj satırları yıl olarak okunmasın
        let usable = lines.filter {
            !$0.lowercased(with: Locale(identifier: "tr_TR")).contains("adet")
        }

        // En güvenilir işaret: ay adı + yıl ("8. Baskı: Temmuz 2021"). Birden çok basım
        // satırı varsa EN GÜNCEL yıl kitabın eldeki baskısıdır.
        // OCR aksan hatalarına tolerans: "Agustos", "Subat", "Eylul" gibi okumalar da tanınır
        let monthPattern = #"(?i)(?:ocak|[şs]ubat|mart|nisan|may[ıi]s|haz[ıi]ran|temmuz|a[ğg]ustos|eyl[üu]l|ek[ıi]m|kas[ıi]m|aral[ıi]k)\s*[,/.]?\s*((?:19|20)\d{2})\b"#
        var monthYears: [Int] = []
        for line in usable {
            if let year = Int(firstMatch(in: line, pattern: monthPattern, group: 1)) {
                monthYears.append(year)
            }
        }
        if let latest = monthYears.max() {
            return String(latest)
        }

        let prioritized = usable.filter {
            let lower = $0.lowercased(with: Locale(identifier: "tr_TR"))
            return lower.contains("baskı") || lower.contains("yayın")
                || lower.contains("copyright") || lower.contains("©")
        }
        for line in prioritized.reversed() {
            if let year = matches(in: line, pattern: #"\b(?:19|20)\d{2}\b"#).last {
                return year
            }
        }
        let joined = usable.joined(separator: " ")
        return matches(in: joined, pattern: #"\b(?:19|20)\d{2}\b"#).last ?? ""
    }

    private static func edition(in lines: [String]) -> String {
        // "askı" araması bozuk okunan "~askı / 8askı" varyantlarını da yakalar
        // Cihaz dilinden bağımsız: satır Türkçe kurallarla küçültülür ("45. BASKI" → "baskı",
        // "EDITION" → "edıtıon"); desenler iki i biçimini de kabul eder
        for line in lines.map({ $0.lowercased(with: Locale(identifier: "tr_TR")) })
            where line.range(of: #"ask[ıi]|bas[ıi]m|ed[iı]t[iı]on"#, options: .regularExpression) != nil {
            let patterns = [
                #"\b(\d{1,2})\s*\.?\s*[~\-/*']{0,2}\s*(?:bask[ıi]|bas[ıi]m|ask[ıi]|ed[iı]t[iı]on)"#,
                #"(?:bask[ıi]|bas[ıi]m|ed[iı]t[iı]on)\s*[:：/]?\s*(\d{1,2})\b"#
            ]
            for pattern in patterns {
                let value = firstMatch(in: line, pattern: pattern, group: 1)
                if let edition = Int(value), (1...99).contains(edition) {
                    return String(edition)
                }
            }
        }
        return ""
    }

    /// Düşük güvenli veya boş kalan alanları kullanıcı kontrolü için işaretler.
    private static func markLowConfidenceFields(_ draft: inout BookDraft, result: BookOCRResult) {
        if result.averageConfidence < 0.72 {
            draft.lowConfidenceFields.formUnion(
                ["title", "author", "publisher", "isbn", "publicationYear", "edition", "pageCount"]
            )
        }
        if !draft.isbn.isEmpty && !ISBNFormatter.isValidISBN13(draft.isbn) {
            draft.lowConfidenceFields.insert("isbn")
        }

        let extractedFields: [(String, String)] = [
            ("title", draft.title),
            ("author", draft.author),
            ("publisher", draft.publisher),
            ("isbn", draft.isbn),
            ("publicationYear", draft.publicationYear),
            ("edition", draft.edition),
            ("pageCount", draft.pageCount)
        ]
        for (field, value) in extractedFields
            where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.lowConfidenceFields.insert(field)
        }
    }

    // MARK: - Metin yardımcıları

    private static func clean(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Karşılaştırma anahtarı: küçük harf, aksansız, ı→i ve kesme işaretleri eşitlenmiş.
    /// "Türkiye'nin"/"Türkiye’nin" ve "Ağaçlari"/"Ağaçları" varyantları aynı sayılır.
    private static func foldKey(_ text: String) -> String {
        text
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
    }

    /// OCR'da rakam yerine okunan harfleri düzeltir (I→1, O→0, S→5...) — yalın sayı satırları için.
    private static func repairDigits(_ text: String) -> String {
        let replacements: [Character: Character] = [
            "O": "0", "o": "0", "Q": "0", "I": "1", "l": "1", "İ": "1", "i": "1",
            "Z": "2", "z": "2", "S": "5", "s": "5", "B": "8", "G": "6"
        ]
        return String(text.map { replacements[$0] ?? $0 })
    }

    /// Türkçeye özgü karakter sayısı — aksan hatalı OCR varyantları arasında seçim için.
    private static func turkishScore(_ text: String) -> Int {
        text.filter { "şğıüöçâîûŞĞİÜÖÇÂÎÛ".contains($0) }.count
    }

    private static func labeledValue(in lines: [String], labels: [String]) -> String? {
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased(with: Locale(identifier: "tr_TR"))
            guard let label = labels.first(where: { lower.hasPrefix($0) }) else { continue }

            // Ek almış kelimeler etiket değildir: "yayınevinden izin alınmadan..." satırındaki
            // "yayınevi" bir etiket sanılmamalı — etiketten sonra harf gelmemeli.
            let afterLabel = line.dropFirst(label.count)
            if let nextCharacter = afterLabel.first, nextCharacter.isLetter { continue }

            let remainder = afterLabel
                .trimmingCharacters(in: CharacterSet(charactersIn: " :：-–—"))
            if !remainder.isEmpty {
                return remainder
            }
            if lines.indices.contains(index + 1) {
                let next = lines[index + 1]
                if !labels.contains(where: {
                    next.lowercased(with: Locale(identifier: "tr_TR")).hasPrefix($0)
                }) {
                    return next
                }
            }
        }
        return nil
    }

    private static func firstMatch(in text: String, pattern: String, group: Int) -> String {
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: group), in: text)
        else {
            return ""
        }
        return String(text[range])
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { match in
                guard let range = Range(match.range, in: text) else { return nil }
                return String(text[range])
            }
    }
}
