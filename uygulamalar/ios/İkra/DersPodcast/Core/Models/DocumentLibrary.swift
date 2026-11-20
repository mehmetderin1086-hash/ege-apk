import Foundation
import SwiftData

/// Belge kütüphanesi (öneri 20): kaynakların kalıcı kopyası; transkriptten PDF sayfası açmak için de kullanılır.
enum DocumentLibrary {
    /// Kaynakları kütüphaneye kaydeder (zaten kayıtlıysa yeniden kopyalamaz) ve kimliklerini döndürür.
    static func persist(_ sources: [ImportedSource], context: ModelContext) -> [UUID] {
        var ids: [UUID] = []
        for source in sources {
            if let id = source.documentID {
                if let doc = fetch(id, context: context) { doc.lastUsedAt = .now }
                ids.append(id)
                continue
            }
            let id = UUID()
            let document: SourceDocument?
            switch source.kind {
            case let .pdf(url, pageCount):
                let name = "\(id.uuidString).pdf"
                document = (try? FileManager.default.copyItem(at: url, to: DocumentStore.directory.appending(path: name))).map {
                    SourceDocument(name: source.name, kind: "pdf", fileName: name, pageCount: pageCount)
                }
            case let .text(text):
                let name = "\(id.uuidString).txt"
                document = (try? text.write(to: DocumentStore.directory.appending(path: name), atomically: true, encoding: .utf8)).map {
                    SourceDocument(name: source.name, kind: "text", fileName: name, pageCount: 0)
                }
            case let .image(data):
                let name = "\(id.uuidString).jpg"
                document = (try? data.write(to: DocumentStore.directory.appending(path: name))).map {
                    SourceDocument(name: source.name, kind: "image", fileName: name, pageCount: 1)
                }
            }
            guard let document else { continue }
            document.id = id
            context.insert(document)
            ids.append(id)
        }
        try? context.save()
        return ids
    }

    static func fetch(_ id: UUID, context: ModelContext) -> SourceDocument? {
        try? context.fetch(FetchDescriptor<SourceDocument>(predicate: #Predicate { $0.id == id })).first
    }

    /// Kütüphanedeki belgeyi yeniden kaynak olarak kullan.
    static func importedSource(_ document: SourceDocument) -> ImportedSource? {
        var source: ImportedSource
        switch document.kindRaw {
        case "pdf":
            source = ImportedSource(name: document.name, kind: .pdf(document.url, pageCount: document.pageCount))
        case "text":
            guard let text = try? String(contentsOf: document.url, encoding: .utf8) else { return nil }
            source = ImportedSource(name: document.name, kind: .text(text))
        default:
            guard let data = try? Data(contentsOf: document.url) else { return nil }
            source = ImportedSource(name: document.name, kind: .image(data), thumbnailData: DocumentLoader.thumbnailJPEG(data))
        }
        source.documentID = document.id
        return source
    }

    static func delete(_ document: SourceDocument, context: ModelContext) {
        try? FileManager.default.removeItem(at: document.url)
        context.delete(document)
        try? context.save()
    }
}
