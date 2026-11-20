// Dosyalar'dan PDF/görsel içe aktarma, belge tarayıcısı sayfaları ve PDF yardımcıları.
// ContentView'dan (P8) taşındı; davranış değişmedi.
import SwiftUI
import SwiftData
import PhotosUI
@preconcurrency import Vision
import PDFKit
import ImageIO
import UniformTypeIdentifiers
import CoreImage
#if os(iOS)
import UIKit
import VisionKit
#endif

extension ContentView {
    /// Uzun okuma işini iptal edilebilir bir görev olarak başlatır; önceki iş varsa iptal edilir.
    func islemBaslat(_ islem: @escaping @MainActor () async -> Void) {
        islemGorevi?.cancel()
        islemGorevi = Task { @MainActor in await islem() }
    }

    func processFileImport(_ result: Result<[URL], Error>) async {
        guard acceptsActiveCatalogResult() else { return }
        do {
            let urls = try result.get()
            guard !urls.isEmpty else {
                return
            }

            isRecognizing = true
            scanProgress = 0
            scanTotal = urls.count
            defer {
                isRecognizing = false
                scanProgress = 0
                scanTotal = 0
            }

            beginAddSession()
            var drafts: [BookDraft] = []

            // Birden çok görsel dosyası = AYNI kitabın sayfaları (tek kayıt).
            // Her PDF ise kendi başına tek kitaptır.
            var imageLines: [OCRLine] = []
            var imageBarcode: String?
            var imageCover: Data?
            var imageDatas: [Data] = []   // Gemini tüm sayfaları (kapak + künye) birlikte görsün
            let imageCount = urls.filter { $0.pathExtension.lowercased() != "pdf" }.count

            let ozet = await DosyaIceAktarma.calistir(urls: urls, ilerleme: { scanProgress = $0 }) { url in
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

                // Koordineli okuma: iCloud'da inmemiş dosya önce indirilir; hata dosya adıyla raporlanır.
                let data = try await KoordineliDosyaOkuma.oku(url)
                if url.pathExtension.lowercased() == "pdf" {
                    do {
                        let pdfDraft = try await draftFromPDF(data: data)
                        acceptOrQueue(pdfDraft, reviewQueue: &drafts)
                    } catch BookScanError.invalidPDF {
                        throw DosyaOkumaHatasi(neden: "bozuk PDF")
                    } catch BookScanError.noText {
                        throw DosyaOkumaHatasi(neden: "okunabilir metin yok")
                    }
                } else if imageCount >= 2 {
                    imageDatas.append(data)
                    if imageCover == nil {
                        let coverTask = Task.detached(priority: .userInitiated) { () -> Data? in
                            if let jpeg = BookOCREngine.coverData(from: data) { return jpeg }
                            guard let image = BookOCREngine.decodeImage(from: data) else { return nil }
                            return BookOCREngine.encodePNG(image)
                        }
                        imageCover = await coverTask.value
                    }
                    guard let result = await BookOCREngine.recognize(imageData: data) else {
                        try Task.checkCancellation()
                        throw DosyaOkumaHatasi(neden: "görsel okunamadı")
                    }
                    imageLines.append(contentsOf: result.lines)
                    imageBarcode = imageBarcode ?? result.barcodeISBN
                } else {
                    do {
                        let imageDraft = try await draftFromImageData(data)
                        acceptOrQueue(imageDraft, reviewQueue: &drafts)
                    } catch BookScanError.invalidImage {
                        try Task.checkCancellation()
                        throw DosyaOkumaHatasi(neden: "görsel okunamadı")
                    }
                }
            }

            if !imageLines.isEmpty || imageBarcode != nil {
                var merged = BookOCRExtractor.draft(
                    from: BookOCRResult(lines: imageLines, barcodeISBN: imageBarcode)
                )
                merged.coverData = imageCover
                await GeminiBookRecognizer.enrichIfEnabled(&merged, images: imageDatas)
                reconcileWithCatalog(&merged)
                await replaceWithOfficialCover(&merged)
                acceptOrQueue(merged, reviewQueue: &drafts)
            }

            guard acceptsActiveCatalogResult() else { return }
            if drafts.isEmpty {
                // routeBatch boş listede sessiz döner; sonuç ve başarısız dosyalar mutlaka söylenir.
                if let mesaj = ozet.mesaj {
                    bulkMessage = mesaj
                } else if ozet.okunan > 0 {
                    bulkMessage = "\(ozet.okunan) dosya okundu; kataloğa eklenecek kitap bilgisi bulunamadı."
                }
            } else {
                // Açılacak form ya da kuyruk varken uyarı penceresi çakışmasın: not taslağın içinde görünür.
                if let mesaj = ozet.mesaj {
                    drafts[0].bilgiNotu = [drafts[0].bilgiNotu, mesaj].compactMap { $0 }.joined(separator: "\n")
                }
                routeBatch(drafts)
            }
        } catch {
            recognitionError = error.localizedDescription
        }
    }

    func draftFromImageData(_ data: Data) async throws -> BookDraft {
        // Görüntü çözme + OCR + kapak kodlama tamamen arka planda koşar (donma yapmaz)
        // recognizeBook, Gemini'yi ana OCR olarak Vision ile eşzamanlı çalıştırır
        guard var parsedDraft = await BookOCREngine.recognizeBook(imageData: data) else {
            throw BookScanError.invalidImage
        }
        reconcileWithCatalog(&parsedDraft)
        return parsedDraft
    }

    func draftFromPDF(data: Data) async throws -> BookDraft {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw BookScanError.invalidPDF
        }

        let indices = PDFPageSelector.indices(for: document.pageCount)
        var lines: [OCRLine] = []
        var barcodeISBN: String?
        var coverData: Data?

        // Gemini (ana OCR) için seçili PDF sayfalarının görüntüleri + gömülü metin toplanır;
        // Vision/metin çıkarımı ile AYNI ANDA gönderilir.
        var geminiImages: [Data] = []
        var embeddedText = ""
        for index in indices {
            guard let page = document.page(at: index) else { continue }
            if let pageImage = render(page: page, maximumDimension: 1400),
               let jpeg = GeminiImagePreparer.jpegData(from: pngData(from: pageImage) ?? Data(), maxPixel: 1400) {
                geminiImages.append(jpeg)
            }
            if let text = page.string, text.count > 20 { embeddedText += text + "\n" }
        }
        let geminiTask = Task {
            await GeminiBookRecognizer.fieldsIfEnabled(
                images: geminiImages, extraText: embeddedText.isEmpty ? nil : embeddedText
            )
        }

        for index in indices {
            guard let page = document.page(at: index) else {
                continue
            }

            if index == 0, let pageImage = render(page: page, maximumDimension: 1600) {
                coverData = pngData(from: pageImage)
            }

            let embeddedLines = page.string?
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty } ?? []

            if embeddedLines.count >= 3 {
                lines.append(contentsOf: embeddedLines.map {
                    OCRLine(text: $0, height: 0, confidence: 1)
                })
            } else if let pageImage = render(page: page, maximumDimension: 2200) {
                let result = try await BookOCREngine.recognize(cgImage: pageImage)
                lines.append(contentsOf: result.lines)
                barcodeISBN = barcodeISBN ?? result.barcodeISBN
            }
        }

        let geminiFields = await geminiTask.value
        guard !lines.isEmpty || geminiFields?.isBook == true else {
            throw BookScanError.noText
        }

        var parsedDraft = BookOCRExtractor.draft(
            from: BookOCRResult(lines: lines, barcodeISBN: barcodeISBN)
        )
        if let geminiFields { GeminiBookRecognizer.merge(geminiFields, into: &parsedDraft) }
        if parsedDraft.pageCount.isEmpty {
            // PDF'in kendi sayfa sayısı yalnızca kitabın TAMAMI taranmışsa anlamlıdır.
            // Birkaç sayfalık tarama PDF'lerinde (kapak + künye) yanlış değer yazmak yerine
            // alan boş bırakılır; Amazon doğrulaması doldurur.
            if document.pageCount >= 20 {
                parsedDraft.pageCount = String(document.pageCount)
            }
            parsedDraft.lowConfidenceFields.insert("pageCount")
        }
        parsedDraft.coverData = coverData
        reconcileWithCatalog(&parsedDraft)
        await replaceWithOfficialCover(&parsedDraft)
        return parsedDraft
    }

    func processScannedPages(_ pages: [Data]) async {
        guard acceptsActiveCatalogResult() else { return }
        guard !pages.isEmpty else {
            return
        }

        isRecognizing = true
        defer { isRecognizing = false }

        do {
            let selectedIndices = PDFPageSelector.indices(for: pages.count)
            var lines: [OCRLine] = []
            var barcodeISBN: String?

            // Kamera belge tarayıcı: Gemini (ana OCR) seçili sayfaları Vision ile aynı anda okur
            let geminiTask = Task {
                await GeminiBookRecognizer.fieldsIfEnabled(images: selectedIndices.map { pages[$0] })
            }

            for index in selectedIndices {
                guard let result = await BookOCREngine.recognize(imageData: pages[index]) else { continue }
                lines.append(contentsOf: result.lines)
                barcodeISBN = barcodeISBN ?? result.barcodeISBN
            }

            let geminiFields = await geminiTask.value
            guard acceptsActiveCatalogResult() else { return }
            guard !lines.isEmpty || geminiFields?.isBook == true else {
                throw BookScanError.noText
            }

            var parsedDraft = BookOCRExtractor.draft(
                from: BookOCRResult(lines: lines, barcodeISBN: barcodeISBN)
            )
            if let geminiFields { GeminiBookRecognizer.merge(geminiFields, into: &parsedDraft) }
            if let firstPage = pages.first, let image = makeCGImage(from: firstPage) {
                parsedDraft.coverData = pngData(from: image)
            }
            reconcileWithCatalog(&parsedDraft)
            await replaceWithOfficialCover(&parsedDraft)
            guard acceptsActiveCatalogResult() else { return }
            presentOrQuickSave(parsedDraft)
        } catch {
            recognitionError = error.localizedDescription
        }
    }

    func makeCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2600,
            kCGImageSourceShouldCacheImmediately: false
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    func render(page: PDFPage, maximumDimension: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        let scale = maximumDimension / max(bounds.width, bounds.height)
        let width = max(Int(bounds.width * scale), 1)
        let height = max(Int(bounds.height * scale), 1)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }
}
