import SwiftUI
import UIKit
import CoreGraphics

nonisolated struct ScanBoxBounds: Equatable, Sendable {
    var top: Double
    var left: Double
    var bottom: Double
    var right: Double
    var values: [Double] { [top, left, bottom, right] }
    var rect: CGRect { CGRect(x: left / 1000, y: top / 1000, width: (right - left) / 1000, height: (bottom - top) / 1000) }
    static func validated(_ values: [Double]) throws -> Self {
        guard values.count == 4, values.allSatisfy({ $0.isFinite }) else { throw ScanBoxEditError.invalidBounds }
        let v = values.map { min(1000, max(0, $0)) }
        guard v[2] - v[0] >= 1, v[3] - v[1] >= 1 else { throw ScanBoxEditError.invalidBounds }
        return Self(top: v[0], left: v[1], bottom: v[2], right: v[3])
    }
}

nonisolated enum ScanBoxEditError: LocalizedError {
    case invalidBounds, sourceMissing
    var errorDescription: String? {
        switch self {
        case .invalidBounds: "Kutu dört sonlu kenardan oluşmalı; üst kenar alttan, sol kenar sağdan önce gelmeli."
        case .sourceMissing: "Bu kitabın kaynak fotoğrafı veya dilimi artık oturumda bulunamıyor."
        }
    }
}

/// Düzenleme bir değer kopyasıdır; Vazgeç oturumu değiştirmez.
nonisolated struct ScanBoxEditDraft: Sendable {
    var id: UUID
    var bounds: ScanBoxBounds
    init(id: UUID, box: [Double]?) {
        self.id = id
        bounds = (try? ScanBoxBounds.validated(box ?? [])) ?? .init(top: 0, left: 0, bottom: 1000, right: 1000)
    }
    mutating func setEdge(_ index: Int, to value: Double) {
        guard value.isFinite else { return }
        let v = min(1000, max(0, value))
        switch index {
        case 0: bounds.top = min(v, bounds.bottom - 1)
        case 1: bounds.left = min(v, bounds.right - 1)
        case 2: bounds.bottom = max(v, bounds.top + 1)
        case 3: bounds.right = max(v, bounds.left + 1)
        default: break
        }
    }
}

enum ScanBoxEditEngine {
    static func applyPhoto(_ values: [Double], bookID: UUID, to original: ScanSession, coverData: Data? = nil) throws -> ScanSession {
        let bounds = try ScanBoxBounds.validated(values)
        guard var source = original.bookSources?[bookID], source.tileID == nil,
              (original.sourceImages ?? []).indices.contains(source.photoIndex) else { throw ScanBoxEditError.sourceMissing }
        var updated = original
        source.box = bounds.values
        source.boxEditedManually = true
        updated.bookSources?[bookID] = source
        updatePendingCover(bookID, coverData: coverData, session: &updated)
        return updated
    }

    static func tileKey(_ tileID: UUID, bookIndex: Int) -> String { "\(tileID.uuidString):\(bookIndex)" }
    static func tileItemID(_ tileID: UUID, bookIndex: Int) -> UUID {
        Book.stableID(title: tileKey(tileID, bookIndex: bookIndex), author: "source-box", isbn: "")
    }

    static func applyShelf(_ values: [Double], tileID: UUID, bookIndex: Int, to original: ScanSession, coverData: Data? = nil) throws -> ScanSession {
        let bounds = try ScanBoxBounds.validated(values)
        guard let result = original.shelfResult, let tile = result.tiles.first(where: { $0.id == tileID }),
              tile.books.indices.contains(bookIndex), let raw = result.books.first(where: { ShelfScanEngine.isSameBook($0, tile.books[bookIndex]) })
        else { throw ScanBoxEditError.sourceMissing }
        var updated = original
        let key = ShelfScanEngine.signature(raw)
        let id = updated.shelfBookKeys?[key] ?? Book.stableID(title: key, author: "shelf-review", isbn: "")
        if updated.shelfBookKeys == nil { updated.shelfBookKeys = [:] }
        updated.shelfBookKeys?[key] = id
        if updated.shelfBoxEdits == nil { updated.shelfBoxEdits = [:] }
        updated.shelfBoxEdits?[tileKey(tileID, bookIndex: bookIndex)] = bounds.values
        var reviewed = updated.reviewedShelfBooks?[key] ?? raw
        reviewed.box_2d = bounds.values
        if updated.reviewedShelfBooks == nil { updated.reviewedShelfBooks = [:] }
        updated.reviewedShelfBooks?[key] = reviewed
        if updated.bookSources == nil { updated.bookSources = [:] }
        updated.bookSources?[id] = ScanBookSource(photoIndex: tile.photo, box: bounds.values, method: "gemini", confidence: reviewed.confidence, tileID: tileID, boxEditedManually: true)
        if !updated.shelfSavedKeys.contains(key), !(updated.savedOperationIDs ?? []).contains(id),
           !updated.pendingBooks.contains(where: { $0.id == id }) {
            updated.pendingBooks.append(VoiceBookEngine.book(from: SesliKitapKaydi(fields: reviewed, cabinet: updated.cabinet, shelf: updated.shelf), id: id))
        }
        updatePendingCover(id, coverData: coverData, session: &updated)
        return updated
    }

    private static func updatePendingCover(_ id: UUID, coverData: Data?, session: inout ScanSession) {
        // Makbuzu bulunan veya kaydedilmiş kitabı kaynak düzeltmesi sessizce yeniden yazmaz.
        guard let coverData, !(session.savedOperationIDs ?? []).contains(id),
              !session.insertedIDs.contains(id), let index = session.pendingBooks.firstIndex(where: { $0.id == id }) else { return }
        let previous = session.pendingBooks[index]
        var pending = previous
        pending.coverData = coverData
        session.pendingBooks[index] = BookFieldMetadata.stampChanges(before: previous, after: pending, source: "manual")
    }
}

struct ScanSourcePhotoItem: Identifiable {
    var id: UUID
    var title: String
    var source: ScanBookSource
}

struct ScanSourcePhotoView: View {
    let image: UIImage
    let items: [ScanSourcePhotoItem]
    var onSave: ((UUID, [Double]) throws -> Void)? = nil
    @State private var edit: ScanBoxEditDraft?
    @State private var confirmed: [UUID: [Double]] = [:]
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(uiImage: image).resizable().scaledToFit()
                .overlay {
                    GeometryReader { geometry in
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if let bounds = try? ScanBoxBounds.validated(box(for: item)) {
                                let selected = edit?.id == item.id
                                Button { select(item) } label: {
                                    Rectangle().fill(Color.clear)
                                        .overlay { Rectangle().stroke(selected ? KitapTema.ana : KitapTema.basari, lineWidth: selected ? 4 : 2) }
                                        .overlay(alignment: .topLeading) {
                                            Text("\(index + 1)").font(.caption.bold()).padding(5)
                                                .background(selected ? KitapTema.ana : KitapTema.basari).foregroundStyle(.white)
                                        }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .frame(width: bounds.rect.width * geometry.size.width, height: bounds.rect.height * geometry.size.height)
                                    .position(x: bounds.rect.midX * geometry.size.width, y: bounds.rect.midY * geometry.size.height)
                                    .accessibilityLabel("Kitap \(index + 1): \(item.title), kutuyu seç")
                            }
                        }
                    }
                }
            if onSave != nil {
                Text("Fotoğraftaki numaralı kutuyu veya aşağıdaki kitabı seçin; kenarları ayarlayıp onaylayın.")
                    .font(.footnote).fixedSize(horizontal: false, vertical: true)
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button { select(item) } label: {
                        Label("\(index + 1). \(item.title)", systemImage: edit?.id == item.id ? "checkmark.square.fill" : "square.dashed")
                            .fixedSize(horizontal: false, vertical: true)
                    }.buttonStyle(.bordered).accessibilityIdentifier("source.box.select.\(index)")
                }
            }
            if let edit {
                Text("Seçili kutunun kenarları · 0–1000 ölçeği").font(.headline)
                ForEach(0..<4, id: \.self) { index in
                    edgeControl(index, value: edit.bounds.values[index])
                }
                HStack {
                    Button("Vazgeç", role: .cancel) { self.edit = nil; error = nil }
                        .accessibilityIdentifier("source.box.cancel")
                    Button("Kutuyu Onayla") { confirm() }.buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("source.box.confirm")
                }
                Text("Kaynak kutusu ve bekleyen taslağın kapak kesiti güncellenir. Daha önce kaydedilmiş kitaplar değişmez.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            if let error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }.interactiveDismissDisabled(edit != nil)
    }

    private func box(for item: ScanSourcePhotoItem) -> [Double] {
        if edit?.id == item.id, let edit { return edit.bounds.values }
        return confirmed[item.id] ?? item.source.box ?? []
    }
    private func select(_ item: ScanSourcePhotoItem) {
        guard onSave != nil else { return }
        edit = ScanBoxEditDraft(id: item.id, box: confirmed[item.id] ?? item.source.box)
        error = nil
    }
    private func edgeControl(_ index: Int, value: Double) -> some View {
        let names = ["Üst", "Sol", "Alt", "Sağ"]
        let binding = Binding<Double>(get: { edit?.bounds.values[index] ?? value }, set: { edit?.setEdge(index, to: $0) })
        return VStack(alignment: .leading, spacing: 4) {
            Stepper("\(names[index]) kenar: \(Int(value.rounded())) / 1000", value: binding, in: 0...1000, step: 1)
                .accessibilityIdentifier("source.box.edge.\(index)")
            Slider(value: binding, in: 0...1000, step: 1)
                .accessibilityLabel("\(names[index]) kenarı ayarla")
        }
    }
    private func confirm() {
        guard let edit, let onSave else { return }
        do {
            let bounds = try ScanBoxBounds.validated(edit.bounds.values)
            try onSave(edit.id, bounds.values)
            confirmed[edit.id] = bounds.values
            self.edit = nil
            error = nil
            AccessibilityNotification.Announcement("Kutu düzeltmesi oturuma kaydedildi").post()
        } catch { self.error = "Kutu kaydedilemedi: \(error.localizedDescription)" }
    }
}
