import PDFKit
import SwiftUI
import UIKit

// MARK: - Öneri 23: kaynak sayfayı aç

struct PDFPageSheet: View {
    var url: URL
    var page: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFKitView(url: url, page: page)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Sayfa \(page)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    var url: URL
    var page: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        if let target = view.document?.page(at: max(0, page - 1)) { view.go(to: target) }
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}

// MARK: - #8: "s. N" etiketinin açacağı kaynak (PDF sayfası ya da görsel kaynak)

nonisolated struct SourceDocRef: Hashable, Sendable {
    var name: String
    /// "pdf" | "image" | "text"
    var kind: String
    var url: URL
    var pageCount: Int
}

nonisolated enum SourcePageResolution: Equatable, Sendable {
    case pdf(URL, page: Int)
    case choosePDF([SourceDocRef], page: Int)
    case image(URL)
    case missing

    /// Sayfayı içeren PDF'ler önce; PDF yoksa (ya da hiçbiri o sayfaya erişmiyorsa) görsel kaynak açılır:
    /// birden çok fotoğrafta N. fotoğraf, yoksa ilki.
    static func resolve(page: Int, documents: [SourceDocRef]) -> SourcePageResolution {
        let pdfs = documents.filter { $0.kind == "pdf" }
        let images = documents.filter { $0.kind == "image" }
        let fitting = pdfs.filter { $0.pageCount == 0 || page <= $0.pageCount }
        if fitting.count == 1 { return .pdf(fitting[0].url, page: page) }
        if fitting.count > 1 { return .choosePDF(fitting, page: page) }
        if let image = images[safe: page - 1] ?? images.first { return .image(image.url) }
        if pdfs.count == 1 { return .pdf(pdfs[0].url, page: page) }
        if pdfs.count > 1 { return .choosePDF(pdfs, page: page) }
        return .missing
    }
}

/// Görsel kaynak (fotoğraf/taranmış sayfa): iki parmakla yakınlaştırılır.
struct SourceImageSheet: View {
    var url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: UIScreen.main.bounds.width * scale)
                        .gesture(MagnifyGesture()
                            .onChanged { scale = max(1, min(5, base * $0.magnification)) }
                            .onEnded { _ in base = scale })
                        .onTapGesture(count: 2) { withAnimation { scale = scale > 1 ? 1 : 2.5; base = scale } }
                } else {
                    ContentUnavailableView("Görsel açılamadı", systemImage: "photo")
                }
            }
            .background(Color.black.opacity(0.9))
            .navigationTitle("Kaynak görseli")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
            .task { image = UIImage(contentsOfFile: url.path) }
        }
    }
}
