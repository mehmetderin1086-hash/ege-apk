import Foundation
import PDFKit
import SwiftData

/// #6: bölümün kaynak PDF'inden istenen sayfaların metni (PDFKit; metni olmayan sayfa OCR ile).
/// Sayfalar 1 tabanlı, orijinal belge numaralarıdır. P4 (sahne stüdyosu) ve P6 kullanır.
enum SourcePages {
    static func texts(for episode: Episode, pages: [Int], maxChars: Int, context: ModelContext) async -> [PageText] {
        let wanted = normalized(pages)
        guard !wanted.isEmpty, maxChars > 0 else { return [] }
        let pdfs = (episode.sourceDocumentIDs ?? [])
            .compactMap { DocumentLibrary.fetch($0, context: context) }
            .filter { $0.kindRaw == "pdf" }
            .map(\.url)
        guard !pdfs.isEmpty else { return [] }
        return await extract(from: pdfs, pages: wanted, maxChars: maxChars)
    }

    /// Tekrarsız, sıralı, pozitif sayfalar.
    nonisolated static func normalized(_ pages: [Int]) -> [Int] {
        Array(Set(pages.filter { $0 > 0 })).sorted()
    }

    /// Her sayfa ilk sahip PDF'ten okunur; toplam `maxChars` aşılmaz (son sayfa kırpılır).
    @concurrent
    nonisolated static func extract(from pdfs: [URL], pages: [Int], maxChars: Int) async -> [PageText] {
        var found: [Int: String] = [:]
        var scanned: [URL: [Int]] = [:]
        for url in pdfs {
            guard let document = PDFDocument(url: url) else { continue }
            for page in pages where found[page] == nil && page <= document.pageCount {
                let text = document.page(at: page - 1)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if text.count >= 40 { found[page] = text } else if scanned.values.allSatisfy({ !$0.contains(page) }) { scanned[url, default: []].append(page) }
            }
        }
        for (url, list) in scanned {
            let missing = list.filter { found[$0] == nil }
            guard !missing.isEmpty else { continue }
            let ocr = await PageOCR.recognize(pdf: url, pages: missing.map { $0 - 1 })
            for (index, text) in ocr { found[index + 1] = text }
        }
        return budgeted(pages.compactMap { p in found[p].map { PageText(page: p, text: $0) } }, maxChars: maxChars)
    }

    /// Toplam karakter sınırı (saf; test edilir). Sayfa başına en çok 6000 (sunucu sınırı). Sunucu gibi UTF-16
    /// birimiyle ölçülür; PDFKit'in ayrışık (NFD) döndürdüğü Türkçe harfler önce birleşik biçime getirilir.
    nonisolated static func budgeted(_ pages: [PageText], maxChars: Int, perPage: Int = 6000) -> [PageText] {
        var left = maxChars
        var result: [PageText] = []
        for page in pages where left > 0 {
            let text = ServerText.prefix(page.text, min(perPage, left))
            guard !text.isEmpty else { continue }
            result.append(PageText(page: page.page, text: text))
            left -= text.utf16.count
        }
        return result
    }
}
