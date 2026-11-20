import Foundation
import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers

/// Kullanıcının eklediği bir kaynak (henüz sunucuya gönderilmemiş).
nonisolated struct ImportedSource: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case pdf(URL, pageCount: Int)
        case text(String)
        case image(Data)
    }

    let id = UUID()
    var name: String
    var kind: Kind
    /// Yalnızca PDF: gönderilecek sayfalar (1 tabanlı, orijinal numaralar). nil = tümü.
    var pageRange: ClosedRange<Int>?
    /// Belge kütüphanesinden geldiyse kaydın kimliği (yeniden kopyalanmaz).
    var documentID: UUID?
    /// Yalnız liste satırı için küçük JPEG (kalıcı değil): satır her çizimde 2000 piksellik görseli yeniden çözmesin.
    var thumbnailData: Data?
    /// Bölümlere ayrılmış kitabın parçası: belge kütüphanesine kitabın kendi adıyla (tek belge olarak) kaydedilir;
    /// `name` parça adı olarak istek başlığında ve kaynak adlarında kalır. Kalıcı değil.
    var libraryName: String?

    var isImage: Bool { if case .image = kind { true } else { false } }

    var pageCount: Int? {
        if case let .pdf(_, count) = kind { return count }
        return nil
    }

    var symbol: String {
        switch kind {
        case .pdf: "doc.richtext"
        case .text: "doc.text"
        case .image: "photo"
        }
    }

    var detail: String {
        switch kind {
        case let .pdf(_, pages):
            if let range = pageRange { "PDF · \(range.lowerBound)–\(range.upperBound). sayfalar (\(pages) sayfadan)" } else { "PDF · \(pages) sayfa" }
        case let .text(text): "Metin · \(text.count.formatted()) karakter"
        case .image: "Fotoğraf"
        }
    }

    var thumbnail: UIImage? {
        if let thumbnailData, let small = UIImage(data: thumbnailData) { return small }
        if case let .image(data) = kind { return UIImage(data: data) }
        return nil
    }
}

/// İçe aktarılan kaynak adları (saf; test edilir).
nonisolated enum SourceNaming {
    static let maxLength = 80

    /// Listede olmayan en küçük "Ad n": art arda eklenen fotoğraflar 1, 2, 3 diye sıralanır.
    static func next(_ base: String, existing: [String]) -> String {
        let taken = Set(existing)
        var n = 1
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    /// Yeniden adlandırma girdisi: boşluklar kırpılır, sınıra kesilir; boşsa nil.
    static func cleaned(_ raw: String) -> String? {
        let name = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
        return name.isEmpty ? nil : name
    }
}

/// Görsel sınırları kaynak adımında denetlenir (saf; test edilir): `DocumentLoader.payload` aynı sınırları ancak
/// ayarlar yapılıp "Oluştur"a basıldıktan sonra uyguluyordu.
nonisolated enum SourceLimits {
    static func problem(imageCount: Int, imageBytes: Int) -> String? {
        if imageCount > Config.maxImages {
            return "Bir podcast'e en fazla \(Config.maxImages) fotoğraf ya da taranmış sayfa gönderilebilir (şu an \(imageCount)). Fazlasını kaldır ya da fotoğrafları metne çevir."
        }
        if imageBytes > Config.maxTotalPayloadBytes {
            let megabyte = 1024.0 * 1024.0
            let size = (Double(imageBytes) / megabyte).formatted(.number.precision(.fractionLength(1)))
            return "Fotoğraflar birlikte çok büyük (\(size) MB; sınır \(Config.maxTotalPayloadBytes / (1024 * 1024)) MB). Birkaçını kaldır ya da fotoğrafları metne çevir."
        }
        return nil
    }

    static func problem(for sources: [ImportedSource]) -> String? {
        var count = 0, bytes = 0
        for source in sources {
            guard case let .image(data) = source.kind else { continue }
            count += 1
            bytes += data.count
        }
        return problem(imageCount: count, imageBytes: bytes)
    }

    /// Tarama sonrası bildirim: sınır yüzünden alınmayan ve işlenemeyen sayfalar; sorun yoksa nil.
    static func scanNote(total: Int, taken: Int, failed: Int) -> String? {
        var parts: [String] = []
        if total > taken { parts.append("Taranan \(total) sayfadan yalnız ilk \(taken) sayfa alındı (en fazla \(Config.maxImages) görsel gönderilebilir).") }
        if failed > 0 { parts.append("\(failed) sayfa işlenemedi.") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// Sayfa aralığı girdisi (saf; test edilir).
nonisolated enum PageRangeInput {
    /// 1…pageCount'a kırpar, ters girişi çevirir; bütün sayfalar seçildiyse nil.
    static func resolve(start: Int, end: Int, pageCount: Int) -> ClosedRange<Int>? {
        let count = max(pageCount, 1)
        let a = min(max(start, 1), count), b = min(max(end, 1), count)
        let lower = min(a, b), upper = max(a, b)
        return lower == 1 && upper == count ? nil : lower...upper
    }

    /// Metin kutularından: boş ya da sayı olmayan ilk sayfa 1, son sayfa belgenin sonu sayılır.
    static func resolve(startText: String, endText: String, pageCount: Int) -> ClosedRange<Int>? {
        resolve(start: Int(startText.trimmingCharacters(in: .whitespaces)) ?? 1,
                end: Int(endText.trimmingCharacters(in: .whitespaces)) ?? pageCount, pageCount: pageCount)
    }
}

nonisolated extension Array where Element == ImportedSource {
    /// Kaynağı `offset` kadar taşır (−1 yukarı, +1 aşağı); sınırı aşıyorsa ya da kimlik yoksa dizi değişmez.
    func moving(id: UUID, by offset: Int) -> [ImportedSource] {
        guard let from = firstIndex(where: { $0.id == id }) else { return self }
        let to = from + offset
        guard to != from, indices.contains(to) else { return self }
        var result = self
        result.insert(result.remove(at: from), at: to)
        return result
    }
}

nonisolated enum DocumentLoaderError: LocalizedError {
    case unreadable(String), empty(String), tooLarge, tooManyImages, unsupported(String)

    var errorDescription: String? {
        switch self {
        case let .unreadable(name): "\"\(name)\" açılamadı."
        case let .empty(name): "\"\(name)\" içinde okunabilir metin bulunamadı."
        case .tooLarge: "Seçilen belgeler bir podcast için çok büyük. Daha az sayfa veya daha küçük dosya seç."
        case .tooManyImages: "En fazla \(Config.maxImages) fotoğraf veya taranmış sayfa ekleyebilirsin."
        case let .unsupported(name): "\"\(name)\" desteklenmiyor. PDF, Word, metin veya fotoğraf seç."
        }
    }
}

enum DocumentLoader {
    static let importTypes: [UTType] = [.pdf, .plainText, .rtf, UTType("org.openxmlformats.wordprocessingml.document")!, .image]

    /// Dosya seçicisinden gelen URL → kaynak. Güvenlik kapsamlı URL'yi kopyalar.
    static func load(url: URL) throws -> ImportedSource {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let name = url.deletingPathExtension().lastPathComponent
        let type = UTType(filenameExtension: url.pathExtension.lowercased())

        if type?.conforms(to: .pdf) == true {
            let local = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
            try FileManager.default.copyItem(at: url, to: local)
            guard let document = PDFDocument(url: local), document.pageCount > 0 else { throw DocumentLoaderError.unreadable(name) }
            return ImportedSource(name: name, kind: .pdf(local, pageCount: document.pageCount))
        }
        if url.pathExtension.lowercased() == "docx" {
            let text = try DocxTextExtractor.extractText(from: Data(contentsOf: url))
            guard text.count > 20 else { throw DocumentLoaderError.empty(name) }
            return ImportedSource(name: name, kind: .text(text))
        }
        if type?.conforms(to: .rtf) == true {
            let attributed = try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            let text = attributed.string
            guard text.count > 20 else { throw DocumentLoaderError.empty(name) }
            return ImportedSource(name: name, kind: .text(text))
        }
        if type?.conforms(to: .text) == true {
            guard let text = decodeText(try Data(contentsOf: url)) else { throw DocumentLoaderError.unreadable(name) }
            guard text.count > 20 else { throw DocumentLoaderError.empty(name) }
            return ImportedSource(name: name, kind: .text(text))
        }
        if type?.conforms(to: .image) == true {
            guard let image = UIImage(data: try Data(contentsOf: url)), let jpeg = prepare(image) else { throw DocumentLoaderError.unreadable(name) }
            return ImportedSource(name: name, kind: .image(jpeg), thumbnailData: thumbnailJPEG(jpeg))
        }
        throw DocumentLoaderError.unsupported(url.lastPathComponent)
    }

    /// Düz metin baytları → metin (saf; test edilir). BOM varsa ona göre; yoksa sırayla UTF-8, Windows-1254 (Not Defteri'nin
    /// Türkçe "ANSI" kaydı) ve Latin-1. NUL içeren sonuç (ikili dosya, BOM'suz UTF-16) hiçbir kodlamada kabul edilmez;
    /// bozuk karakter ("�") içeren sonuç yalnız UTF-16 ve yedek kodlamalarda reddedilir.
    nonisolated static func decodeText(_ data: Data) -> String? {
        func clean(_ text: String?) -> String? {
            guard var text, !text.contains("\0") else { return nil }
            if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
            return text
        }
        func strict(_ text: String?) -> String? { clean(text).flatMap { $0.contains("\u{FFFD}") ? nil : $0 } }
        let head = [UInt8](data.prefix(3))
        if head.starts(with: [0xEF, 0xBB, 0xBF]) { return clean(String(data: data.dropFirst(3), encoding: .utf8)) }
        if head.starts(with: [0xFF, 0xFE]) { return strict(String(data: data.dropFirst(2), encoding: .utf16LittleEndian)) }
        if head.starts(with: [0xFE, 0xFF]) { return strict(String(data: data.dropFirst(2), encoding: .utf16BigEndian)) }
        // Geçerli UTF-8 kesin sonuçtur: içindeki gerçek "�" metnin parçasıdır, yedek kodlamaya düşürmez
        // (1254 ve Latin-1 her baytı kabul ettiği için bütün metin bozuk harflerle yüklenirdi).
        if let utf8 = String(data: data, encoding: .utf8) { return clean(utf8) }
        // Hasarlı ama ağırlıkla geçerli UTF-8 (ör. son baytı kesik): hasarlı yer "�" olur, kalan metin korunur.
        // Gerçek 1254 metinde Türkçe harflerin baytları geçerli UTF-8 dizisi oluşturmaz; orada bozuklar ağır basar.
        let lossy = String(decoding: data, as: UTF8.self)
        var bad = 0, good = 0
        for scalar in lossy.unicodeScalars where scalar.value > 0x7F { if scalar == "\u{FFFD}" { bad += 1 } else { good += 1 } }
        if good > bad { return clean(lossy) }
        for encoding in [String.Encoding.windowsCP1254, .isoLatin1] {
            if let text = strict(String(data: data, encoding: encoding)) { return text }
        }
        return nil
    }

    /// Birden çok dosya: yüklenebilenler kaynak olur, yüklenemeyenlerin hatası dosya adıyla toplanır (hiçbiri sessizce düşmez).
    static func loadAll(_ urls: [URL]) -> (sources: [ImportedSource], errors: [String]) {
        var sources: [ImportedSource] = []
        var errors: [String] = []
        for url in urls {
            do { sources.append(try load(url: url)) } catch { errors.append(message(for: error, fileName: url.lastPathComponent)) }
        }
        return (sources, errors)
    }

    /// Hata metni; dosya adını içermiyorsa (sistem ya da Word ayrıştırma hatası) başına eklenir.
    nonisolated static func message(for error: Error, fileName: String) -> String {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let stem = (fileName as NSString).deletingPathExtension
        return text.contains(fileName) || text.contains("\"\(stem)\"") ? text : "\"\(fileName)\": \(text)"
    }

    static func image(_ image: UIImage, name: String) -> ImportedSource? {
        prepare(image).map { ImportedSource(name: name, kind: .image($0), thumbnailData: thumbnailJPEG($0)) }
    }

    /// Fotoğraf verisi → en uzun kenar ≤ 2000 px JPEG (%75), ana iş parçacığı dışında. ImageIO küçülterek çözer:
    /// tam çözünürlüklü görsel belleğe açılmaz (48 MP fotoğrafta yaklaşık 190 MB).
    @concurrent
    nonisolated static func jpeg(fromImageData data: Data) async -> Data? {
        downsampled(data, maxPixel: Int(Config.maxImageDimension)).flatMap { UIImage(cgImage: $0).jpegData(compressionQuality: 0.75) }
    }

    /// Taranan sayfa (bellekteki görsel) → JPEG, ana iş parçacığı dışında.
    @concurrent
    nonisolated static func jpeg(from image: UIImage) async -> Data? { prepare(image) }

    /// Hazır JPEG'den görsel kaynağı (liste için küçük resmiyle), ana iş parçacığı dışında.
    @concurrent
    nonisolated static func imageSource(jpeg: Data, name: String) async -> ImportedSource {
        ImportedSource(name: name, kind: .image(jpeg), thumbnailData: thumbnailJPEG(jpeg))
    }

    /// Liste satırı (44 nokta, 3x) için küçük JPEG.
    nonisolated static func thumbnailJPEG(_ data: Data, maxPixel: Int = 132) -> Data? {
        downsampled(data, maxPixel: maxPixel).flatMap { UIImage(cgImage: $0).jpegData(compressionQuality: 0.7) }
    }

    /// Yön bilgisi uygulanmış, en uzun kenarı `maxPixel`'i aşmayan görsel (büyütmez).
    nonisolated private static func downsampled(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    /// En uzun kenar ≤ 2000 px, JPEG %75.
    nonisolated static func prepare(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, Config.maxImageDimension / max(longest, 1))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.75)
    }

    /// Kaynakları sunucuya gidecek biçime çevirir. Büyük PDF'ler metne, metinsiz sayfalar görsele dönüşür.
    @concurrent
    static func payload(for sources: [ImportedSource]) async throws -> [SourcePayload] {
        var result: [SourcePayload] = []
        var imageCount = sources.filter { if case .image = $0.kind { true } else { false } }.count
        var total = 0
        var textBudget = Config.maxTotalTextCharacters

        /// Toplam metin sınırı (sunucu: tüm kaynaklarda 400.000 karakter; JS `length` = UTF-16 birimi).
        func clipped(_ text: String) -> String {
            let part = ServerText.prefix(text, max(textBudget, 0))
            textBudget -= part.utf16.count
            return part
        }

        for source in sources {
            try Task.checkCancellation()
            switch source.kind {
            case let .text(text):
                if textBudget > 0 { result.append(.text(clipped(text), name: source.name)) }
            case let .image(data):
                result.append(.image(data: data, name: source.name))
            case let .pdf(originalURL, _):
                // Sayfa aralığı seçildiyse yalnızca o sayfaları içeren geçici bir PDF üret.
                let url = try source.pageRange.map { try trimmedPDF(originalURL, range: $0, name: source.name) } ?? originalURL
                let firstPage = source.pageRange?.lowerBound ?? 1
                let data = try Data(contentsOf: url)
                if data.count <= Config.maxInlinePDFBytes, total + data.count <= Config.maxTotalPayloadBytes {
                    if let range = source.pageRange, textBudget > 0 {
                        result.append(.text(clipped("Not: \"\(source.name)\" PDF'i orijinal belgenin \(range.lowerBound)–\(range.upperBound). sayfalarından oluşuyor. sourcePage değerlerini orijinal numaralara göre ver: PDF'in 1. sayfası = orijinal \(range.lowerBound). sayfa."), name: "\(source.name) — sayfa bilgisi"))
                    }
                    result.append(.pdf(data: data, name: source.name))
                } else {
                    // #8: metin sırayla okunur; taranmış sayfalar görsel sınırını aşarsa OCR ile metne çevrilir (atılmaz).
                    let parts = try await largePDFParts(url: url, hashURL: originalURL, name: source.name, firstPage: firstPage,
                                                        range: source.pageRange, imagesSoFar: imageCount)
                    for part in parts {
                        switch part.kind {
                        case "image":
                            imageCount += 1
                            if let payload = part.payload { result.append(payload) }
                        default:
                            if let text = part.text, textBudget > 0 { result.append(.text(clipped(text), name: part.name)) }
                        }
                    }
                }
            }
            total = result.reduce(0) { $0 + $1.byteCount }
            guard total <= Config.maxTotalPayloadBytes else { throw DocumentLoaderError.tooLarge }
        }
        guard imageCount <= Config.maxImages else { throw DocumentLoaderError.tooManyImages }
        return result
    }

    /// #8: taranmış sayfalar görsel olarak mı gider yoksa OCR ile metne mi çevrilir (saf; test edilir).
    nonisolated static func scanStrategy(imagesSoFar: Int, scannedPages: Int) -> String {
        imagesSoFar + scannedPages <= Config.maxImages ? "img" : "ocr"
    }

    /// Büyük PDF → metin + (taranmış sayfalar için) görsel ya da OCR metni. Sonuç önbelleğe alınır.
    /// `hashURL`: önbellek anahtarı için orijinal dosya (aralıklı PDF'in geçici kesiti her seferinde farklı baytlar taşıyabilir).
    nonisolated static func largePDFParts(url: URL, hashURL: URL, name: String, firstPage: Int, range: ClosedRange<Int>?,
                                          imagesSoFar: Int) async throws -> [PayloadCache.Part] {
        guard let document = PDFDocument(url: url) else { throw DocumentLoaderError.unreadable(name) }
        var pageTexts: [(Int, String)] = []
        var scanned: [Int] = []
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }
            let pageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if pageText.count >= 40 { pageTexts.append((index, pageText)) } else { scanned.append(index) }
        }
        let method = scanStrategy(imagesSoFar: imagesSoFar, scannedPages: scanned.count)
        let hash = try? PayloadCache.sha256(of: hashURL)
        let key = hash.map { PayloadCache.key(fileHash: $0, range: range, method: method) }
        if let key, let cached = PayloadCache.load(key) { return cached }

        var parts: [PayloadCache.Part] = []
        var ocrTexts: [Int: String] = [:]
        if method == "ocr", !scanned.isEmpty {
            ocrTexts = await PageOCR.recognize(pdf: url, pages: scanned)
            try Task.checkCancellation()
        }
        var text = ""
        var merged = pageTexts.map { ($0.0, $0.1, false) }
        if method == "ocr" { merged += ocrTexts.map { ($0.key, $0.value, true) } }
        for (index, pageText, ocr) in merged.sorted(by: { $0.0 < $1.0 }) {
            text += "\n[Sayfa \(index + firstPage)]\(ocr ? " (taranmış)" : "")\n\(pageText)\n"
        }
        if !text.isEmpty { parts.append(.init(kind: "text", name: name, text: text)) }
        if method == "img" {
            for index in scanned {
                guard let page = document.page(at: index), let jpeg = render(page) else { continue }
                parts.append(.init(kind: "image", name: "\(name) — sayfa \(index + firstPage)", data: jpeg))
            }
        }
        if let key { PayloadCache.store(parts, key: key) }
        return parts
    }

    /// Seçilen sayfa aralığını yeni bir geçici PDF'e kopyalar.
    nonisolated static func trimmedPDF(_ url: URL, range: ClosedRange<Int>, name: String) throws -> URL {
        guard let source = PDFDocument(url: url) else { throw DocumentLoaderError.unreadable(name) }
        let lower = max(1, range.lowerBound), upper = min(source.pageCount, range.upperBound)
        guard lower <= upper else { throw DocumentLoaderError.empty(name) }
        let output = PDFDocument()
        for (i, pageNumber) in (lower...upper).enumerated() {
            if let page = source.page(at: pageNumber - 1)?.copy() as? PDFPage { output.insert(page, at: i) }
        }
        let target = URL.temporaryDirectory.appending(path: "\(UUID().uuidString)-kesit.pdf")
        guard output.write(to: target) else { throw DocumentLoaderError.unreadable(name) }
        return target
    }

    nonisolated private static func render(_ page: PDFPage) -> Data? {
        let bounds = page.bounds(for: .mediaBox)
        let scale = min(2.5, Config.maxImageDimension / max(bounds.width, bounds.height, 1))
        let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
        return image.jpegData(compressionQuality: 0.75)
    }
}
