import Foundation
import PDFKit
import UIKit
import Vision

/// #8: taranmış PDF sayfalarını cihazda metne çevirir (Vision, tr-TR + en-US).
/// `PDFDocument` iş parçacığı güvenli değil: her görev kendi belge örneğini açar; en çok 4 paralel.
nonisolated enum PageOCR {
    static let maxParallel = 4

    /// `pages`: PDF içindeki 0 tabanlı sayfa indeksleri → tanınan metin (boşsa yok).
    @concurrent
    static func recognize(pdf url: URL, pages: [Int]) async -> [Int: String] {
        var result: [Int: String] = [:]
        await withTaskGroup(of: (Int, String?).self) { group in
            var iterator = pages.makeIterator()
            func addNext() {
                guard let index = iterator.next() else { return }
                group.addTask {
                    guard !Task.isCancelled, let image = render(url: url, index: index) else { return (index, nil) }
                    return (index, await recognize(image))
                }
            }
            for _ in 0..<maxParallel { addNext() }
            while let (index, text) = await group.next() {
                if let text, !text.isEmpty { result[index] = text }
                addNext()
            }
        }
        return result
    }

    /// Sayfayı (kendi belge örneğiyle) OCR için yeterli çözünürlükte çizer.
    static func render(url: URL, index: Int) -> CGImage? {
        guard let document = PDFDocument(url: url), let page = document.page(at: index) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale = min(3, 2400 / max(bounds.width, bounds.height, 1))
        return page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox).cgImage
    }

    static func recognize(_ image: CGImage) async -> String? {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [Locale.Language(identifier: "tr-TR"), Locale.Language(identifier: "en-US")]
        let observations: [RecognizedTextObservation]
        do {
            observations = try await request.perform(on: image)
        } catch {
            // Dil desteklenmiyorsa otomatik algılamayla bir kez daha.
            var fallback = RecognizeTextRequest()
            fallback.automaticallyDetectsLanguage = true
            guard let retry = try? await fallback.perform(on: image) else { return nil }
            observations = retry
        }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
