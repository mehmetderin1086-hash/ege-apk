import SwiftUI
import SwiftData

/// Eksik Alan Panosu: hangi alan kaç kayıtta eksik olduğunu tek ekranda gösterir
/// ve mevcut toplu tamamlama araçlarına yönlendirir. 2.500+ kitaplık kataloglarda
/// "önce neyi düzelteyim" sorusuna hızlı cevap verir.
struct DataQualityDashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var books: [CatalogBook]

    @State private var isFillingCovers = false
    @State private var coversFilled = 0
    @State private var coversNotFound = 0
    @State private var coversLocked = 0
    @State private var coverSummary: String?
    @State private var confirmingClose = false

    private var active: [CatalogBook] { books.filter { !$0.isWithdrawn } }

    private var missingAuthor: Int {
        active.filter { $0.author.isEmpty || isPlaceholderAuthorName($0.author) }.count
    }
    private var missingCover: Int { active.filter { $0.coverData == nil }.count }
    private var missingPublisher: Int { active.filter { ($0.publisher ?? "").isEmpty }.count }
    private var missingShelf: Int { active.filter { ($0.shelf ?? "").isEmpty }.count }
    private var missingCabinet: Int { active.filter { ($0.cabinet ?? "").isEmpty }.count }
    private var missingISBN: Int { active.filter { ($0.isbn ?? "").isEmpty }.count }
    private var missingAccession: Int { active.filter { ($0.accessionCode ?? "").isEmpty }.count }
    private var missingPageCount: Int { active.filter { ($0.pageCount ?? "").isEmpty }.count }
    private var missingCategory: Int { active.filter { ($0.category ?? "").isEmpty }.count }

    private func isPlaceholderAuthorName(_ author: String) -> Bool {
        let placeholders = ["kolektif", "anonim", "bilinmiyor", "derleme", "yazar bilinmiyor", "various"]
        return placeholders.contains(author.trimmingCharacters(in: .whitespaces).lowercased(with: Locale(identifier: "tr_TR")))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Aktif kayıt", value: "\(active.count)")
                } header: {
                    Label("Genel", systemImage: "books.vertical")
                        .foregroundStyle(KitapTema.ana)
                }

                Section {
                    row("ISBN eksik", count: missingISBN, icon: "barcode", color: KitapTema.vurgu, alan: "ISBN")
                    row("Yazar eksik/genel", count: missingAuthor, icon: "person", color: KitapTema.vurgu,
                        hint: "Amazon'dan Doldur ISBN'i olanları tamamlar", alan: "Yazar")
                    row("Yayınevi eksik", count: missingPublisher, icon: "building.2", color: KitapTema.vurgu, alan: "Yayınevi")
                    row("Kategori eksik", count: missingCategory, icon: "tag", color: KitapTema.vurgu, alan: "Kategori")
                    row("Kapak görseli eksik", count: missingCover, icon: "photo", color: KitapTema.foto, alan: "Kapak")
                    row("Sayfa sayısı eksik", count: missingPageCount, icon: "doc.plaintext", color: KitapTema.dosya)
                } header: {
                    Label("Kitap Bilgileri", systemImage: "info.circle")
                        .foregroundStyle(KitapTema.amazon)
                } footer: {
                    Text("Bu alanlar Amazon, Kitapyurdu, Google Books ve OpenLibrary üzerinden ISBN ile otomatik doldurulabilir.")
                }

                if missingCover > 0 || isFillingCovers {
                    coverFillSection
                }

                Section {
                    row("Dolap eksik", count: missingCabinet, icon: "archivebox", color: KitapTema.toplu, alan: "Dolap")
                    row("Raf eksik", count: missingShelf, icon: "square.grid.3x3", color: KitapTema.toplu,
                        hint: "Raf Atama Modu ile barkodla atanır", alan: "Raf")
                    row("Demirbaş kodu eksik", count: missingAccession, icon: "number", color: KitapTema.toplu)
                } header: {
                    Label("Yerleşim ve Kayıt", systemImage: "map")
                        .foregroundStyle(KitapTema.toplu)
                }
            }
            .navigationTitle("Eksik Alan Panosu")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // İndirme sürerken kapatmak sessizce arka planda ağ isteği bırakıyordu; önce duraklatılır.
                    Button("Kapat") {
                        if isFillingCovers { confirmingClose = true } else { dismiss() }
                    }
                }
            }
            .interactiveDismissDisabled(isFillingCovers)
            .confirmationDialog("Kapak indirme sürüyor", isPresented: $confirmingClose, titleVisibility: .visible) {
                Button("Duraklat ve kapat") {
                    isFillingCovers = false
                    dismiss()
                }
                Button("İndirmeye devam et", role: .cancel) { }
            } message: {
                Text("\(coversFilled) kapak bulundu. Kapatırsanız indirme duraklatılır; kalanlar sonra yeniden başlatılabilir.")
            }
        }
    }

    // MARK: - Toplu kapak tamamlama

    /// Kapağı eksik VE ISBN'i olan kitaplar — kapak ancak ISBN ile aranabilir.
    private var coverPending: [CatalogBook] {
        active.filter { $0.coverData == nil && !($0.isbn ?? "").isEmpty }
    }

    private var coverFillSection: some View {
        Section {
            if isFillingCovers {
                HStack {
                    ProgressView()
                    Text("İndiriliyor… \(coversFilled) bulundu, \(coversNotFound) bulunamadı, kalan \(coverPending.count)")
                        .font(.callout)
                }
            } else if let coverSummary {
                Label(coverSummary, systemImage: "checkmark.circle")
                    .font(.callout)
                    .accessibilityIdentifier("quality.coverSummary")
            }
            Button {
                toggleCoverFill()
            } label: {
                Label(
                    isFillingCovers ? "Duraklat" : "Eksik Kapakları İndir (\(coverPending.count))",
                    systemImage: isFillingCovers ? "pause.circle" : "square.and.arrow.down.on.square"
                )
            }
            .disabled(!isFillingCovers && coverPending.isEmpty)
        } header: {
            Label("Kapak Tamamlama", systemImage: "photo.stack")
                .foregroundStyle(KitapTema.foto)
        } footer: {
            if coverPending.isEmpty && missingCover > 0 {
                Text("Kapağı eksik \(missingCover) kitabın hiçbirinde ISBN yok. Önce ISBN girin; kapak ISBN ile aranır.")
            } else {
                Text("Her kitap için Amazon → Kitapyurdu → OpenLibrary → Google Books sırayla denenir, en yüksek çözünürlüklü kapak seçilir. İndirme sürerken bu ekranı kapatmayın; istediğiniz an duraklatabilirsiniz.")
            }
        }
    }

    private func toggleCoverFill() {
        if isFillingCovers {
            isFillingCovers = false
            return
        }
        isFillingCovers = true
        coversFilled = 0
        coversNotFound = 0
        coversLocked = 0
        coverSummary = nil

        Task { @MainActor in
            // Bu turda bulunamayanlar tekrar denenmez; sonraki açılışta yeniden aranabilir
            var tried = Set<UUID>()

            while isFillingCovers {
                guard let book = coverPending.first(where: { !tried.contains($0.id) }) else { break }
                tried.insert(book.id)

                // Kilitli kapak otomatik tamamlamada korunur; ağ isteği bile atılmaz.
                if BookFieldMetadata.isLocked("coverData", on: book) {
                    coversLocked += 1
                    continue
                }

                let normalized = ISBNFormatter.normalize(book.isbn ?? "")
                let isbn = normalized.isEmpty ? (book.isbn ?? "") : normalized
                if let cover = await BookMetadataService.officialCover(
                    isbn: isbn,
                    title: book.title,
                    author: book.author,
                    publisher: book.publisher ?? ""
                ) {
                    // İndirme sürerken kitap silinmişse silinmiş modele yazmak çöker; atla
                    guard !book.isDeleted, book.modelContext != nil else { continue }
                    let before = book.book
                    book.coverData = cover
                    // Kaynak damgası: Bilgi kaynakları panelinde kapak "api" olarak görünür.
                    book.fieldMetadata = BookFieldMetadata.stampChanges(before: before, after: book.book, source: "api").fieldMetadata
                    coversFilled += 1
                } else {
                    coversNotFound += 1
                }

                if (coversFilled + coversNotFound) % 10 == 0 {
                    try? modelContext.save()
                }
                // Amazon'un engellememesi için istekler arası bekleme
                try? await Task.sleep(for: .seconds(2))
            }

            try? modelContext.save()
            // Döngü kullanıcı duraklattığı için bittiyse isFillingCovers zaten kapalıdır.
            let durdu = !isFillingCovers
            isFillingCovers = false
            var ozet = "\(coversFilled) kapak bulundu, \(coversNotFound) bulunamadı"
            if coversLocked > 0 { ozet += ", \(coversLocked) kilitli alan atlandı" }
            if durdu { ozet += " (duraklatıldı)" }
            coverSummary = ozet
            AppLog.write("Toplu kapak indirme: " + ozet)
        }
    }

    /// Eksik alanı olan kitapları Kitaplar sekmesinde süzer.
    private func listele(alan: String) {
        KitapFiltreRotasi.shared.bekleyen = KitapFiltresi(eksikAlan: alan)
        DerinBaglanti.shared.hedefSekme = .kitaplar
        dismiss()
    }

    @ViewBuilder
    private func row(_ title: String, count: Int, icon: String, color: Color, hint: String? = nil, alan: String? = nil) -> some View {
        if let alan, count > 0 {
            Button { listele(alan: alan) } label: {
                satir(title, count: count, icon: icon, color: color, hint: hint, gezinilebilir: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Bu kitapları Kitaplar sekmesinde listeler")
        } else {
            satir(title, count: count, icon: icon, color: color, hint: hint, gezinilebilir: false)
        }
    }

    private func satir(_ title: String, count: Int, icon: String, color: Color, hint: String?, gezinilebilir: Bool) -> some View {
        // İpucu satırın içinde durur: büyük yazı boyutlarında kesilmez, alt satıra taşmaz
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label(title, systemImage: icon)
                    .foregroundStyle(count == 0 ? .secondary : .primary)
                Spacer()
                Text("\(count)")
                    .font(.headline)
                    .foregroundStyle(count == 0 ? KitapTema.basari : color)
                if gezinilebilir {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
            }
            if let hint, count > 0 {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
