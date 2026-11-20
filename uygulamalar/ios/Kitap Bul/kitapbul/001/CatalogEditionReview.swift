import SwiftUI

/// Ekleme kararını ISBN/baskı/cilt ve gerçek nüsha etkisiyle görünür kılar.
struct CatalogEditionReviewPanel: View {
    let preview: CatalogSavePreview
    @Binding var decision: CatalogSaveDecision

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(preview.actionText).font(.headline)
            editionRow(preview.incoming, title: "Eklenecek kitap")
            ForEach(preview.reasons, id: \.self) { reason in
                Label(reason, systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.primary)
            }
            Button {
                decision = .keepSeparate
            } label: {
                Label("Ayrı kitap / baskı olarak tut", systemImage: decision == .keepSeparate ? "checkmark.circle.fill" : "circle")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("edition.keepSeparate")
            ForEach(preview.candidates) { candidate in
                VStack(alignment: .leading, spacing: 8) {
                    editionRow(candidate, title: "Katalogdaki kayıt")
                    if CatalogSaveEngine.canMerge(preview.incoming, into: candidate) {
                        Button {
                            decision = .mergeInto(candidate.id)
                        } label: {
                            Label(mergeLabel(candidate),
                                  systemImage: decision == .mergeInto(candidate.id) ? "checkmark.circle.fill" : "plus.circle")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("edition.merge." + candidate.id.uuidString)
                    } else {
                        Text("Farklı ISBN, cilt veya yazar bilgisi nedeniyle ayrı tutulur.")
                            .font(.footnote).foregroundStyle(.primary)
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
            }
            if decision == .automatic && preview.requiresChoice {
                Text("Kaydetmeden önce ayrı kayıt veya hedef katalog kaydı seçin.")
                    .font(.footnote.weight(.semibold))
            }
        }
    }

    private func mergeLabel(_ candidate: Book) -> String {
        let added = max(1, preview.incoming.quantity ?? 1)
        let (total, overflow) = max(1, candidate.quantity ?? 1).addingReportingOverflow(added)
        return "Bu kayda \(added) nüsha ekle · " + (overflow ? "adet sınırı aşılıyor" : "toplam \(total)")
    }

    @ViewBuilder
    private func editionRow(_ book: Book, title: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold))
            Text(book.title).font(.subheadline.weight(.semibold))
            Text(book.author.isEmpty ? "Yazar eksik" : book.author).font(.footnote)
            Text("ISBN: \((book.isbn ?? "").isEmpty ? "eksik" : book.isbn!)").font(.footnote.monospaced())
            Text([book.publisher, book.edition.map { "Baskı: " + $0 }, book.publicationYear,
                  book.volume.map { "Cilt: \($0)" }, book.pageCount.map { $0 + " sayfa" }]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.footnote)
            Text("\(max(1, book.quantity ?? 1)) nüsha · " + [book.cabinet, book.shelf].compactMap { $0 }.joined(separator: " / "))
                .font(.footnote)
            if !book.notes.isEmpty { Text(book.notes).font(.caption).lineLimit(3) }
        }
        .foregroundStyle(.primary)
    }
}
