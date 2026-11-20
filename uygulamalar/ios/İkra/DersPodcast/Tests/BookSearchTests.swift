import Foundation
import PDFKit
import SwiftUI
import Testing
import UIKit
@testable import Ikra

@Suite @MainActor struct BookSearchTests {
    private func pdf(_ pages: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "oku-search-\(UUID().uuidString).pdf")
        let bounds = CGRect(x: 0, y: 0, width: 440, height: 740)
        try UIGraphicsPDFRenderer(bounds: bounds).writePDF(to: url) { context in
            for text in pages {
                context.beginPage()
                if text.isEmpty {
                    UIColor.gray.setFill()
                    context.cgContext.fill(CGRect(x: 30, y: 30, width: 100, height: 100))
                } else {
                    (text as NSString).draw(in: bounds.insetBy(dx: 24, dy: 24), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
                }
            }
        }
        return url
    }

    @Test func TurkishQueriesKeepTheCorrectPDFPageAnchor() throws {
        let file = try pdf(["IŞIK bitkiler için gereklidir.", "İNSAN hücresi zarla çevrilidir.", "Mitokondri enerji üretir."])
        defer { try? FileManager.default.removeItem(at: file) }
        let light = try BookTextSearch.search(url: file, query: "  ışık \n")
        #expect(light.hits.count == 1 && light.hits.first?.page == 1)
        #expect(light.hits.first?.preview.contains("IŞIK") == true)
        let human = try BookTextSearch.search(url: file, query: "insan")
        #expect(human.hits.count == 1 && human.hits.first?.page == 2)
        #expect(human.hits.first?.offset == 0 && human.hits.first?.length == 5)
        let energy = try BookTextSearch.search(url: file, query: "ENERJİ")
        #expect(energy.hits.count == 1 && energy.hits.first?.page == 3)
        #expect(energy.totalPages == 3 && energy.searchedPages == 3 && energy.pagesWithText == 3)
    }

    @Test func RepeatedTermsHaveBoundedResultsAndPreviews() throws {
        let file = try pdf([String(repeating: "enerji ", count: 300)])
        defer { try? FileManager.default.removeItem(at: file) }
        let result = try BookTextSearch.search(url: file, query: "enerji", limit: 4, previewLimit: 40)
        #expect(result.hits.count == 4 && result.truncated)
        #expect(Set(result.hits.map(\.id)).count == 4)
        #expect(result.hits.allSatisfy { $0.page == 1 && $0.preview.utf16.count <= 42 })
        let capped = try BookTextSearch.search(url: file, query: "enerji", limit: 2_000, previewLimit: 20_000)
        #expect(capped.hits.count <= 200 && capped.hits.allSatisfy { $0.preview.utf16.count <= 302 })
    }

    @Test func PDFSelectionCarriesItsSourcePageAndClearsWithNativeSelection() throws {
        let file = try pdf(["İlk sayfada farklı bir konu var.", "Hücre zarı seçici geçirgendir."])
        defer { try? FileManager.default.removeItem(at: file) }
        let document = try #require(PDFDocument(url: file))
        let nativeSelection = try #require(document.findString("Hücre zarı", withOptions: [.caseInsensitive]).first)
        var selected: MEBTextSelection?
        let wrapper = MEBPDFView(document: document, page: .constant(1), count: .constant(document.pageCount),
                                 selection: Binding(get: { selected }, set: { selected = $0 }), jump: nil)
        let coordinator = wrapper.makeCoordinator()
        let view = PDFView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        view.document = document
        view.setCurrentSelection(nativeSelection, animate: false)

        coordinator.selectionChanged(Notification(name: .PDFViewSelectionChanged, object: view))
        // The selected text is on page 2 even though the reader's visible-page binding is 1.
        #expect(selected == MEBTextSelection(page: 2, text: "Hücre zarı"))

        view.clearSelection()
        coordinator.selectionChanged(Notification(name: .PDFViewSelectionChanged, object: view))
        #expect(selected == nil)
    }

    @Test func NoSearchableTextIsDifferentFromNoMatchOrEmptyQuery() throws {
        let scan = try pdf([""])
        let text = try pdf(["Hücre zarı seçici geçirgendir."])
        defer { try? FileManager.default.removeItem(at: scan); try? FileManager.default.removeItem(at: text) }
        let imageOnly = try BookTextSearch.search(url: scan, query: "hücre")
        let absent = try BookTextSearch.search(url: text, query: "kloroplast")
        let empty = try BookTextSearch.search(url: text, query: " \n ")
        #expect(imageOnly.hits.isEmpty && imageOnly.pagesWithText == 0 && imageOnly.totalPages == 1)
        #expect(absent.hits.isEmpty && absent.pagesWithText == 1)
        #expect(empty == BookTextSearch.Result())
        #expect(throws: BookTextSearch.Failure.self) {
            try BookTextSearch.search(url: text.appendingPathExtension("missing"), query: "hücre")
        }
    }

    @Test func ACancelledSearchDoesNotReturnStaleResults() async throws {
        let file = try pdf(["Hücre zarı seçici geçirgendir."])
        defer { try? FileManager.default.removeItem(at: file) }
        // This actor cannot begin the worker until the test yields, so cancellation is deterministic.
        let worker = Task { @MainActor in try BookTextSearch.search(url: file, query: "hücre") }
        worker.cancel()
        do {
            _ = try await worker.value
            Issue.record("İptal edilen kitap araması sonuç döndürmemeli")
        } catch is CancellationError {
            // Expected: search checks cancellation before opening the document.
        } catch {
            Issue.record("Beklenmeyen arama hatası: \(error)")
        }
    }
}
