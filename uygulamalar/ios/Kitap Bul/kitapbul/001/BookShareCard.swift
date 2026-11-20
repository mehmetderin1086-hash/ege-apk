import SwiftUI

/// Tek bir kitabı görsel kart olarak paylaşma (kapak + ad + yazar + ISBN).
/// Kart bir View olarak render edilip ImageRenderer ile görsele çevrilir.
struct BookShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let book: Book

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                cardPreview
                    .padding()

                if let rendered = renderedImage {
                    ShareLink(
                        item: rendered,
                        preview: SharePreview(book.title, image: rendered)
                    ) {
                        Label("Kartı Paylaş", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                }

                ShareLink(item: shareText) {
                    Label("Sadece Metni Paylaş", systemImage: "text.quote")
                }
                .padding(.bottom)

                Spacer()
            }
            .navigationTitle("Kitabı Paylaş")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }

    private var cardPreview: some View {
        VStack(spacing: 12) {
            if let data = book.coverData, let image = CoverImageDecoder.thumbnail(from: data, maxPixelSize: 300) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(.rect(cornerRadius: 10))
            } else {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.white)
                    .frame(width: 140, height: 200)
                    .background(KitapTema.kitapRengi(book.title).gradient, in: .rect(cornerRadius: 10))
            }
            Text(book.title).font(.title3.weight(.bold)).multilineTextAlignment(.center)
            if !book.author.isEmpty {
                Text(book.author).font(.subheadline).foregroundStyle(.secondary)
            }
            if let isbn = book.isbn, !isbn.isEmpty {
                Text("ISBN: \(isbn)").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(KitapTema.baslikGradyani, in: .rect(cornerRadius: 16))
    }

    private var shareText: String {
        var lines = [book.title]
        if !book.author.isEmpty { lines.append(book.author) }
        if let isbn = book.isbn, !isbn.isEmpty { lines.append("ISBN: \(isbn)") }
        lines.append("Kitap Bul ile paylaşıldı")
        return lines.joined(separator: "\n")
    }

    @MainActor
    private var renderedImage: Image? {
        // Paylaşılan görsel ortam temasını devralmaz: opak zemin + açık tema ile her
        // sohbet arka planında okunur kalır
        let renderer = ImageRenderer(content: cardPreview.frame(width: 320)
            .background(Color.white)
            .environment(\.colorScheme, .light))
        renderer.scale = 3
        #if os(iOS)
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
        #elseif os(macOS)
        guard let nsImage = renderer.nsImage else { return nil }
        return Image(nsImage: nsImage)
        #else
        return nil
        #endif
    }
}
