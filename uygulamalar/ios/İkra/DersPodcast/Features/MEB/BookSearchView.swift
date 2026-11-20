import Foundation
import PDFKit
import SwiftUI

/// Each search owns its PDFDocument. Only small value records return to the UI.
nonisolated enum BookTextSearch {
    struct Hit: Identifiable, Equatable, Sendable {
        let page: Int
        let offset: Int
        let length: Int
        let preview: String
        var id: String { "\(page)-\(offset)" }
    }

    struct Result: Equatable, Sendable {
        var hits: [Hit] = []
        var pagesWithText = 0
        var searchedPages = 0
        var totalPages = 0
        var truncated = false
    }

    enum Failure: LocalizedError {
        case unavailable, locked
        var errorDescription: String? {
            switch self {
            case .unavailable: "Kitap dosyası okunamadı. Kitabı kapatıp yeniden açmayı dene."
            case .locked: "Bu PDF kilitli olduğu için metni aranamıyor."
            }
        }
    }

    /// The limits cap returned data even for very common one-letter searches.
    static func search(url: URL, query: String, limit: Int = 100, previewLimit: Int = 180) throws -> Result {
        try Task.checkCancellation()
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return Result() }
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { throw Failure.unavailable }
        guard !document.isLocked else { throw Failure.locked }
        let resultLimit = min(max(1, limit), 200)
        let previewBudget = min(max(40, previewLimit), 300)
        let locale = Locale(identifier: "tr_TR")
        var result = Result(totalPages: document.pageCount)
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            let text = autoreleasepool { document.page(at: index)?.string ?? "" }
            result.searchedPages += 1
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            result.pagesWithText += 1
            let string = text as NSString
            var cursor = 0
            while cursor < string.length {
                try Task.checkCancellation()
                // Turkish has two distinct pairs: İ/i and I/ı. Foundation's combined
                // diacritic folding removes İ's dot before case comparison and loses
                // valid matches. Locale-aware case comparison preserves both pairs
                // and returns offsets in the original PDF text.
                let found = string.range(of: term, options: [.caseInsensitive],
                                         range: NSRange(location: cursor, length: string.length - cursor), locale: locale)
                guard found.location != NSNotFound, found.length > 0 else { break }
                if result.hits.count == resultLimit { result.truncated = true; return result }
                let lower = max(0, found.location - previewBudget / 3)
                let context = string.rangeOfComposedCharacterSequences(for: NSRange(location: lower, length: min(previewBudget, string.length - lower)))
                let snippet = string.substring(with: context)
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let preview = (context.location > 0 ? "…" : "") + snippet + (NSMaxRange(context) < string.length ? "…" : "")
                result.hits.append(Hit(page: index + 1, offset: found.location, length: found.length, preview: preview))
                cursor = NSMaxRange(found)
            }
        }
        try Task.checkCancellation()
        return result
    }
}

struct BookSearchView: View {
    let url: URL
    let title: String
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var phase: Phase = .idle
    @State private var retryID = UUID()
    @State private var currentID = UUID()
    @State private var worker: Task<BookTextSearch.Result, Error>?

    private enum Phase {
        case idle, loading, cancelled, failed(String), ready(BookTextSearch.Result)
    }

    var body: some View {
        NavigationStack {
            List {
                Section { Text(title).font(.subheadline).foregroundStyle(.secondary) }
                switch phase {
                case .idle:
                    ContentUnavailableView("Kitabın içinde bul", systemImage: "text.magnifyingglass",
                                           description: Text("Bir sözcük veya kısa ifade yaz. Arama internet olmadan çalışır."))
                case .loading:
                    Section {
                        ProgressView("Kitapta aranıyor…")
                        Button("Aramayı durdur", systemImage: "stop.circle") {
                            currentID = UUID(); worker?.cancel(); worker = nil; phase = .cancelled
                        }.frame(minHeight: 44)
                    }
                case .cancelled:
                    Section {
                        Text("Arama durduruldu.").foregroundStyle(.secondary)
                        Button("Yeniden ara", systemImage: "arrow.clockwise") { retryID = UUID() }.frame(minHeight: 44)
                    }
                case .failed(let message):
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                        Button("Yeniden dene", systemImage: "arrow.clockwise") { retryID = UUID() }.frame(minHeight: 44)
                    }
                case .ready(let result):
                    results(result)
                }
            }
            .scrollContentBackground(.hidden).background(Theme.canvas)
            .navigationTitle("Kitap içinde ara").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Sözcük veya ifade")
            .onChange(of: query) { _, value in if value.count > 200 { query = String(value.prefix(200)) } }
            .task(id: query + retryID.uuidString) { await search() }
            .onDisappear { worker?.cancel() }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } } }
        }
    }

    @ViewBuilder private func results(_ result: BookTextSearch.Result) -> some View {
        if result.pagesWithText == 0 {
            ContentUnavailableView("Aranabilir metin yok", systemImage: "doc.viewfinder",
                                   description: Text("Bu kitapta seçilebilir yazı bulunamadı. Taranmış sayfaları PDF görünümünde inceleyebilir, sayfaya not ekleyebilirsin."))
        } else if result.hits.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            Section {
                ForEach(result.hits) { hit in
                    Button { onSelect(hit.page) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Sayfa \(hit.page)", systemImage: "doc.text.magnifyingglass")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
                            Text(hit.preview).font(.body).foregroundStyle(Color.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }.padding(.vertical, 6).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityHint("Eşleşmenin bulunduğu sayfayı açar")
                        .accessibilityIdentifier("book.search.result." + hit.id)
                }
            } header: {
                Text(result.truncated ? "İlk \(result.hits.count) eşleşme" : "\(result.hits.count) eşleşme")
            } footer: {
                if result.truncated { Text("Daha belirgin sonuçlar için daha uzun bir ifade ara.") }
                else if result.pagesWithText < result.totalPages { Text("Yalnız seçilebilir yazı içeren sayfalar aranabildi.") }
            }
        }
    }

    private func search() async {
        worker?.cancel()
        let token = UUID(); currentID = token
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { phase = .idle; return }
        phase = .loading
        do {
            try await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, currentID == token else { return }
            let file = url
            let work = Task.detached(priority: .userInitiated) { try BookTextSearch.search(url: file, query: term) }
            worker = work
            let result = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled, currentID == token else { return }
            worker = nil; phase = .ready(result)
        } catch is CancellationError {
            guard !Task.isCancelled, currentID == token else { return }
            worker = nil; phase = .cancelled
        } catch {
            guard !Task.isCancelled, currentID == token else { return }
            worker = nil; phase = .failed(error.localizedDescription)
        }
    }
}
