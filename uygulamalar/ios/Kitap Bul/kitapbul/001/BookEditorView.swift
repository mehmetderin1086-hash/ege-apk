import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct BookEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    private let validatedSave: (Book) -> SaveOutcome
    /// Yalnız Ekle akışının tekli kaydı son konumu yazar; onay kuyruğu ve kitap ayrıntısı düzenlemesi yazmaz.
    private let sonKonumuHatirla: Bool
    private let onDraftChange: ((BookDraft) -> Void)?
    private let onMergeDecision: ((CatalogSaveDecision) -> Void)?
    /// Baskı karşılaştırması için yalnız ISBN ya da ada uyan adaylar (tüm katalog belleğe alınmaz).
    @State private var editionCatalog: [CatalogBook] = []
    /// Taslağın kataloğda kayıtlı bir kitaba ait olup olmadığı; açılışta tek `fetchCount` ile okunur.
    @State private var taslakKayitli = false
    @State private var kayitliDenetlendi = false
    @State private var dogrulamaOnbellegi = DogrulamaOnbellegi()
    @State private var barkodTarama = false
    @State private var kimlikSorusu = false
    @State private var oneriler = EditorOnerileri()
    @State private var mergeDecision: CatalogSaveDecision = .automatic
    @State private var saveError: String?
    @State private var showingDiscard = false
    /// Kaydet/Kapat sonrası bekleyen otomatik taslak yazımı, temizlenen taslağı geri yazmasın
    @State private var isClosing = false
    @State private var initialDraft: BookDraft
    /// Katalogda aynı ad ya da ISBN ile duran kayıtlar (mükerrer uyarısı)
    @State private var possibleDuplicates: [MukerrerDenetimi.Eslesme] = []

    @State private var draft: BookDraft
    @State private var isFetchingAmazon = false
    @State private var amazonStatusMessage: String?
    @State private var isAmazonStatusError = false
    @State private var isEditingCover = false
    @State private var isReReading = false
    @State private var catalogLease: ActiveCatalogLease?
    /// "Diğer bilgiler" grubu; içinde kontrol edilecek alan varsa açık başlar
    @State private var digerBilgilerAcik: Bool
    @AppStorage(SonKonum.yerAnahtari) private var sonYer = ""
    @AppStorage(SonKonum.dolapAnahtari) private var sonDolap = ""
    @AppStorage(SonKonum.rafAnahtari) private var sonRaf = ""
    /// Kaynak kaydına göre Gemini'nin doldurduğu alanlar; mavi güven noktası yalnız bunlarda çıkar
    private let geminiAlanlari: Set<String>
    /// Ekran açıldığındaki OCR değerleri — kullanıcı düzeltirse bunlardan öğrenilir
    private let originalTitle: String
    private let originalAuthor: String
    private let originalPublisher: String

    init(validating draft: BookDraft, save validatedSave: @escaping (Book) -> SaveOutcome,
         onDraftChange: ((BookDraft) -> Void)? = nil,
         initialMergeDecision: CatalogSaveDecision = .automatic,
         onMergeDecision: ((CatalogSaveDecision) -> Void)? = nil,
         sonKonumuHatirla: Bool = false) {
        _draft = State(initialValue: draft)
        self.validatedSave = validatedSave
        self.sonKonumuHatirla = sonKonumuHatirla
        self.onDraftChange = onDraftChange
        self.onMergeDecision = onMergeDecision
        _mergeDecision = State(initialValue: initialMergeDecision)
        _initialDraft = State(initialValue: draft)
        // Sorunun varlığı eski değer ayrıcalığına bağlı değil; yalnız engelleyip engellemediği bağlı.
        _digerBilgilerAcik = State(initialValue: !EditorDigerBilgiler.sorunluAlanlar(
            BookEditorValidation.validate(draft.dogrulamaGirdisi), dusukGuvenli: draft.lowConfidenceFields).isEmpty)
        // Editörde kaynak kaydı değişmez (elle damga kayıtta basılır); bir kez okunur
        geminiAlanlari = EditorGuvenIsareti.geminiAlanlari(draft.fieldMetadata)
        originalTitle = draft.title
        originalAuthor = draft.author
        originalPublisher = draft.publisher
    }

    private func editorInput(_ value: BookDraft) -> BookEditorValidation.Input {
        value.dogrulamaGirdisi
    }

    private var validationBaseline: BookEditorValidation.Input? {
        // BookDraft(book:) yeni OCR/AI kayıtları için de kullanılır. Eski değer
        // ayrıcalığı yalnız halen katalogda duran gerçek kayıt için geçerlidir.
        guard initialDraft.existingBookID != nil, taslakKayitli else { return nil }
        return editorInput(initialDraft)
    }

    /// Aynı girdiyle gövde boyunca (ve yeniden çizimlerde) tek doğrulama yapılır.
    private var editorValidation: BookEditorValidation.Result {
        let girdi = editorInput(draft)
        let baseline = validationBaseline
        return dogrulamaOnbellegi.sonuc(girdi: girdi, baseline: baseline) {
            BookEditorValidation.validate(girdi, existing: baseline)
        }
    }

    private var rawInitialBook: Book {
        BookEditorValidation.preservingInput(in: initialDraft.snapshot, input: editorInput(initialDraft))
    }

    private var previewBook: Book {
        (try? BookEditorValidation.preparedBook(draft.snapshot, input: editorInput(draft), existing: validationBaseline))
            ?? BookEditorValidation.preservingInput(in: draft.snapshot, input: editorInput(draft))
    }

    @ViewBuilder
    private func validationMessage(_ field: BookEditorValidation.Field) -> some View {
        if let issue = editorValidation.issue(for: field) {
            Label(issue.description, systemImage: issue.isBlocking ? "exclamationmark.triangle" : "info.circle")
                .font(.footnote).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("editor.validation." + field.rawValue)
        }
    }

    private var hasUnsavedChanges: Bool {
        let current = [draft.title, draft.author, draft.publisher, draft.isbn, draft.publicationYear,
            draft.edition, draft.pageCount, draft.notes, draft.category, draft.location, draft.language,
            draft.readingStatus, draft.shelf, draft.cabinet, draft.series, draft.tags, draft.readingLevel, draft.contentWarning]
        let initial = [initialDraft.title, initialDraft.author, initialDraft.publisher, initialDraft.isbn,
            initialDraft.publicationYear, initialDraft.edition, initialDraft.pageCount, initialDraft.notes,
            initialDraft.category, initialDraft.location, initialDraft.language, initialDraft.readingStatus,
            initialDraft.shelf, initialDraft.cabinet, initialDraft.series, initialDraft.tags,
            initialDraft.readingLevel, initialDraft.contentWarning]
        return current != initial || draft.quantity != initialDraft.quantity || draft.rating != initialDraft.rating
            || draft.volume != initialDraft.volume || draft.coverData != initialDraft.coverData
            || draft.backCoverData != initialDraft.backCoverData || draft.imprintData != initialDraft.imprintData
            || draft.isTextbook != initialDraft.isTextbook
    }

    private var autosaveKey: [String] {
        [draft.title, draft.author, draft.publisher, draft.isbn, draft.publicationYear,
         draft.edition, draft.pageCount, draft.notes, draft.category, draft.location, draft.language,
         draft.readingStatus, draft.shelf, draft.cabinet, draft.series, draft.tags, draft.readingLevel,
         draft.contentWarning, String(draft.quantity), String(draft.rating), String(draft.volume), String(draft.isTextbook),
         String(draft.coverData?.hashValue ?? 0), String(draft.backCoverData?.hashValue ?? 0), String(draft.imprintData?.hashValue ?? 0)]
    }

    /// Alanın üstüne küçük ad yazar: doldurulmuş alanda yer tutucu kaybolsa da ne olduğu görünür.
    /// Ad yalnız görseldir; VoiceOver alanın kendi adını okur.
    private func etiketli<Content: View>(_ etiket: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(etiket)
                .font(.caption)
                .foregroundStyle(KitapTema.ikincilMetin)
                .accessibilityHidden(true)
            content()
        }
    }

    /// Şüpheli (düşük güvenli) alanların yanına turuncu uyarı işareti koyar.
    @ViewBuilder
    private func fieldRow<Content: View>(
        _ field: String,
        _ yol: KeyPath<BookDraft, String>,
        etiket: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        etiketli(etiket) {
            HStack {
                content()
                // Güven noktası: turuncu üçgen = kontrol edin, mavi nokta = Gemini okudu (emin)
                if draft.lowConfidenceFields.contains(field) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(KitapTema.vurgu)
                        .accessibilityLabel("Bu alan kontrol edilmeli")
                } else if EditorGuvenIsareti.geminiOkudu(field, deger: draft[keyPath: yol],
                                                         ilkDeger: initialDraft[keyPath: yol],
                                                         taslak: draft, geminiAlanlari: geminiAlanlari) {
                    Circle()
                        .fill(KitapTema.ana)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel("Gemini bu alanı güvenle okudu")
                }
            }
        }
    }

    /// "Diğer bilgiler" grubundaki doğrulama sorunu ya da düşük güvenli alanlar.
    private var digerBilgilerSorunlari: Set<String> {
        EditorDigerBilgiler.sorunluAlanlar(editorValidation, dusukGuvenli: draft.lowConfidenceFields)
    }

    /// Kayıtlı son konum varsa ve forma henüz yazılmamışsa düğme başlığı; yeni kayıtta görünür.
    private var sonKonumDugmesi: String? {
        guard draft.existingBookID == nil,
              [draft.location, draft.cabinet, draft.shelf] != [sonYer, sonDolap, sonRaf] else { return nil }
        return SonKonum.dugmeBasligi(yer: sonYer, dolap: sonDolap, raf: sonRaf)
    }

    /// Düzeltilmiş fotoğrafı yeniden OCR'dan geçirip boş alanları doldurur.
    private func reReadFromCover() {
        guard acceptsActiveCatalogResult() else { return }
        guard let cover = draft.coverData else { return }
        isReReading = true
        Task { @MainActor in
            defer { isReReading = false }
            guard let fresh = await BookOCREngine.recognizeBook(imageData: cover) else { return }
            guard acceptsActiveCatalogResult() else { return }
            if draft.title.isEmpty { draft.title = fresh.title }
            if draft.author.isEmpty { draft.author = fresh.author }
            if draft.publisher.isEmpty { draft.publisher = fresh.publisher }
            if draft.isbn.isEmpty { draft.isbn = fresh.isbn }
            if draft.publicationYear.isEmpty { draft.publicationYear = fresh.publicationYear }
            if draft.pageCount.isEmpty { draft.pageCount = fresh.pageCount }
            if draft.edition.isEmpty { draft.edition = fresh.edition }
        }
    }

    /// Kullanıcının elle yaptığı düzeltmeleri kalıcı belleğe işler.
    private func learnCorrections() {
        CorrectionMemory.learn(ocrText: originalTitle, correctedText: draft.title)
        CorrectionMemory.learn(ocrText: originalAuthor, correctedText: draft.author)
        CorrectionMemory.learn(ocrText: originalPublisher, correctedText: draft.publisher)
    }

    @ViewBuilder
    private var amazonBolumu: some View {
        Section {
            Button {
                fetchAmazonData()
            } label: {
                HStack {
                    Spacer()
                    if isFetchingAmazon {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("Amazon’dan Doğrulanıyor…")
                    } else {
                        Label("Amazon’dan Doğrula", systemImage: "checkmark.seal")
                    }
                    Spacer()
                }
            }
            .disabled(
                isFetchingAmazon
                    || draft.isbn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )

            if let message = amazonStatusMessage {
                Label(
                    message,
                    systemImage: isAmazonStatusError
                        ? "exclamationmark.triangle"
                        : "checkmark.circle"
                )
                .font(.footnote)
                .foregroundStyle(isAmazonStatusError ? Color.orange : Color.green)
            }
        } footer: {
            Text("Okunan ISBN ile Amazon’dan resmi kitap bilgileri çekilir; yazım hataları düzeltilir ve eksik alanlar doldurulur.")
        }
    }

    @ViewBuilder
    private var konumBolumu: some View {
        // Konum her kitapta yazılmasın: son yeni kaydın konumu tek dokunuşla geri gelir
        Section {
            if let baslik = sonKonumDugmesi {
                Button {
                    draft.location = sonYer
                    draft.cabinet = sonDolap
                    draft.shelf = sonRaf
                } label: {
                    Label(baslik, systemImage: "clock.arrow.circlepath")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("editor.useLastLocation")
            }
            etiketli("Oda / Genel konum") {
                TextField("Oda / Genel konum", text: $draft.location).accessibilityIdentifier("editor.location")
            }
            validationMessage(.location)
            etiketli("Dolap") {
                TextField("Dolap", text: $draft.cabinet).accessibilityIdentifier("editor.cabinet")
            }
            validationMessage(.cabinet)
            etiketli("Raf") {
                TextField("Raf", text: $draft.shelf).accessibilityIdentifier("editor.shelf")
            }
            validationMessage(.shelf)
            HStack {
                Text("Adet")
                Spacer()
                TextField("Adet", value: $draft.quantity, format: .number.grouping(.never))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72).frame(minHeight: 44)
                    .accessibilityLabel("Adet")
                    .accessibilityIdentifier("editor.quantity")
                Stepper("Adet", value: $draft.quantity, in: BookEditorValidation.quantityRange)
                    .labelsHidden()
                    .accessibilityIdentifier("editor.quantity.stepper")
            }
            validationMessage(.quantity)
        } header: {
            Label("Konum ve Adet", systemImage: "cabinet")
                .foregroundStyle(KitapTema.ana)
        }
    }

    @ViewBuilder
    private var digerBolumu: some View {
        // Okul kütüphanesinde seyrek doldurulan alanlar katlı durur; içlerinde kontrol
        // edilecek alan belirince grup kendiliğinden açılır.
        Section {
            DisclosureGroup(isExpanded: $digerBilgilerAcik) {
                fieldRow("publisher", \.publisher, etiket: "Yayınevi") {
                    TextField("Yayınevi", text: $draft.publisher)
                }
                oneriCipleri(oneriler.yayinevi, secili: $draft.publisher)
                fieldRow("category", \.category, etiket: "Kategori") {
                    TextField("Kategori", text: $draft.category)
                }
                oneriCipleri(oneriler.kategori, secili: $draft.category)
                fieldRow("language", \.language, etiket: "Dil") {
                    TextField("Dil", text: $draft.language)
                }
                Picker("Okuma durumu", selection: $draft.readingStatus) {
                    // Listede olmayan mevcut değer (CSV'den serbest metin gelebilir) boş görünmesin, ezilmesin.
                    if !PickerSecenekleri.durumlar.contains(draft.readingStatus) && !draft.readingStatus.isEmpty {
                        Text("Mevcut: \(draft.readingStatus)").tag(draft.readingStatus)
                    }
                    ForEach(PickerSecenekleri.durumlar, id: \.self) { Text($0).tag($0) }
                }
                Stepper("Puan: \(draft.rating == 0 ? "Yok" : String(draft.rating))", value: $draft.rating, in: 0...5)
                fieldRow("publicationYear", \.publicationYear, etiket: "Basım yılı") {
                    TextField("Basım yılı", text: $draft.publicationYear)
                        .keyboardType(.numberPad).accessibilityIdentifier("editor.publicationYear")
                }
                validationMessage(.publicationYear)
                Toggle("Ders Kitabı", isOn: $draft.isTextbook)
                fieldRow("edition", \.edition, etiket: "Baskı numarası") {
                    TextField("Baskı numarası", text: $draft.edition)
                }
                fieldRow("pageCount", \.pageCount, etiket: "Sayfa sayısı") {
                    TextField("Sayfa sayısı", text: $draft.pageCount)
                        .keyboardType(.numberPad).accessibilityIdentifier("editor.pageCount")
                }
                validationMessage(.pageCount)
                etiketli("Notlar") {
                    TextField("Notlar", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                etiketli("Seri adı") {
                    TextField("Seri adı (örn. Harry Potter)", text: $draft.series)
                }
                oneriCipleri(oneriler.seri, secili: $draft.series)
                if !draft.series.isEmpty {
                    Stepper("Cilt: \(draft.volume == 0 ? "Yok" : String(draft.volume))", value: $draft.volume, in: 0...500)
                }
                etiketli("Etiketler") {
                    TextField("Etiketler (virgülle: macera, dostluk)", text: $draft.tags)
                }
                Picker("Okuma düzeyi", selection: $draft.readingLevel) {
                    Text("Belirtilmedi").tag("")
                    // "5–7. sınıf" gibi listede olmayan değer korunur ve seçili görünür.
                    if !draft.readingLevel.isEmpty && !OkumaDuzeyi.liste.contains(draft.readingLevel) {
                        Text("Mevcut: \(draft.readingLevel)").tag(draft.readingLevel)
                    }
                    ForEach(OkumaDuzeyi.liste, id: \.self) { Text($0).tag($0) }
                }
                etiketli("İçerik uyarısı") {
                    TextField("İçerik uyarısı (varsa)", text: $draft.contentWarning, axis: .vertical)
                        .lineLimit(1...3)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Diğer bilgiler")
                    if !digerBilgilerAcik {
                        if digerBilgilerSorunlari.isEmpty {
                            Text("Yayınevi, kategori, dil, basım, seri, etiket ve düzey")
                                .font(.caption)
                                .foregroundStyle(KitapTema.ikincilMetin)
                        } else {
                            Label("Kontrol edilecek alan var", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        } footer: {
            if digerBilgilerAcik {
                Text("Seri ve cilt, eksik ciltleri bulmayı; etiket ve düzey, öğrencilere uygun kitap önermeyi kolaylaştırır.")
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Canlı önizleme: yazdıkça kart güncellenir
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            if let veri = draft.coverData, let resim = UIImage(data: veri) {
                                Image(uiImage: resim).resizable().scaledToFill()
                            } else {
                                Rectangle().fill(KitapTema.kitapRengi(draft.title).gradient)
                                Image(systemName: "book.closed.fill").font(.title2).foregroundStyle(.white)
                            }
                        }
                        .frame(width: 64, height: 94)
                        .clipShape(.rect(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(draft.title.isEmpty ? "Kitap adı" : draft.title)
                                .font(.headline)
                                .foregroundStyle(draft.title.isEmpty ? Color.primary.opacity(0.5) : .primary)
                                .lineLimit(2)
                            Text(draft.author.isEmpty ? "Yazar" : draft.author)
                                .font(.subheadline)
                                .foregroundStyle(KitapTema.ikincilMetin)
                            let konum = CatalogBook.konumMetni(yer: draft.location, dolap: draft.cabinet, raf: draft.shelf)
                            if !draft.category.isEmpty || konum != nil {
                                Text([draft.category, konum ?? ""]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(KitapTema.ana)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    .animation(.snappy, value: draft.title + draft.author)
                    .accessibilityElement(children: .combine)
                    .listRowBackground(
                        LinearGradient(colors: [KitapTema.kitapRengi(draft.title).opacity(0.25), Color(.secondarySystemGroupedBackground)],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                }

                // Barkodla gelen ISBN kaynaklarda bulunamadıysa ya da kaynaklara ulaşılamadıysa neden formda söylenir
                if let not = draft.bilgiNotu {
                    Section {
                        Label(not, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("editor.infoNote")
                    }
                }

                if let coverData = draft.coverData {
                    Section {
                        CoverPreview(data: coverData)
                        Button {
                            isEditingCover = true
                        } label: {
                            Label("Fotoğrafı Düzelt (kırp / döndür)", systemImage: "crop.rotate")
                        }
                        Button {
                            reReadFromCover()
                        } label: {
                            Label(
                                isReReading ? "Yeniden okunuyor…" : "Bu Fotoğrafı Yeniden Oku",
                                systemImage: "text.viewfinder"
                            )
                        }
                        .disabled(isReReading)
                    } header: {
                        Label("Kapak", systemImage: "photo")
                            .foregroundStyle(KitapTema.foto)
                    }
                }

                if draft.backCoverData != nil || draft.imprintData != nil {
                    Section {
                        if let back = draft.backCoverData {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Arka kapak").font(.caption).foregroundStyle(.secondary)
                                CoverPreview(data: back)
                            }
                        }
                        if let imprint = draft.imprintData {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Künye sayfası").font(.caption).foregroundStyle(.secondary)
                                CoverPreview(data: imprint)
                            }
                        }
                    } header: {
                        Label("Ek Görseller", systemImage: "photo.stack")
                            .foregroundStyle(KitapTema.toplu)
                    } footer: {
                        Text("Çok fotoğraflı taramalarda ikinci ve üçüncü fotoğraflar burada saklanır.")
                    }
                }

                Section {
                    if draft.recognizedByGemini {
                        if let warning = GeminiBookRecognizer.imageQualityWarning(for: draft) {
                            Label(warning, systemImage: "camera.metering.unknown")
                                .font(.caption)
                                .foregroundStyle(KitapTema.vurgu)
                        }
                        Label("Gemini OCR ile okundu — soru işaretli alanları kontrol edin", systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(KitapTema.foto)
                            .accessibilityLabel("Bu kayıt Gemini yapay zekâ OCR ile okundu")
                    }
                    fieldRow("title", \.title, etiket: "Kitap adı") {
                        TextField("Kitap adı", text: $draft.title)
                            .accessibilityIdentifier("editor.title")
                    }
                    validationMessage(.title)
                    fieldRow("author", \.author, etiket: "Yazar") {
                        TextField("Yazar", text: $draft.author)
                    }
                    fieldRow("isbn", \.isbn, etiket: "ISBN") {
                        TextField("ISBN", text: $draft.isbn)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                            .accessibilityIdentifier("editor.isbn")
                        Button { barkodTarama = true } label: {
                            Image(systemName: "barcode.viewfinder")
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Barkodu okut")
                        .accessibilityIdentifier("editor.isbn.scan")
                    }
                    if editorValidation.issue(for: .isbn) != nil {
                        validationMessage(.isbn)
                        let oneriler = ISBNOnarici.oneriler(draft.isbn)
                        if !oneriler.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Bunlardan biri mi? (rakam karışması/yer değişmesi)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        ForEach(oneriler, id: \.self) { oneri in
                                            Button(oneri) {
                                                draft.isbn = oneri
                                                draft.lowConfidenceFields.insert("isbn")
                                            }
                                            .buttonStyle(.kitapTonlu(KitapTema.amazon))
                                            .font(.caption.monospacedDigit())
                                            .accessibilityLabel("ISBN önerisi \(oneri)")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if onMergeDecision == nil {
                        ForEach(possibleDuplicates) { match in
                            Label("Benzer kayıt: “\(match.title)”\(match.detail). Baskı, ISBN ve cilt bilgisini karşılaştırın.", systemImage: "square.on.square")
                                .font(.footnote).foregroundStyle(.primary)
                        }
                    }
                } header: {
                    Label("Temel Bilgiler", systemImage: "book")
                        .foregroundStyle(KitapTema.ana)
                }

                if onMergeDecision != nil, !taslakKayitli, !editionCatalog.isEmpty {
                    let onizleme = CatalogSaveEngine.preview(previewBook, catalog: editionCatalog)
                    if !onizleme.candidates.isEmpty {
                        Section("Kayıt ve baskı karşılaştırması") {
                            CatalogEditionReviewPanel(preview: onizleme, decision: $mergeDecision)
                        }
                    }
                }

                amazonBolumu

                // Yalnız fotoğraf kalitesi işaretliyse liste boş kalır; o uyarı en üstte zaten görünür
                if !lowConfidenceDescription.isEmpty {
                    Section {
                        Label(
                            "Kontrol edilecek alanlar: \(lowConfidenceDescription)",
                            systemImage: "eye.trianglebadge.exclamationmark"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }
                }

                konumBolumu

                digerBolumu

                Section {
                    Text("Otomatik tanıma sonucunu kaydetmeden önce kontrol edin. Özellikle sayfa sayısı her PDF’nin seçili dört sayfasında bulunmayabilir.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $isEditingCover) {
                if let cover = draft.coverData {
                    ImageEditorView(imageData: cover) { edited in
                        draft.coverData = edited
                    }
                }
            }
            .navigationTitle("Kitap Bilgileri")
            .onChange(of: digerBilgilerSorunlari) { eski, yeni in
                // Yeni bir sorun ya da kontrol edilecek alan belirince katlı grup açılır; kullanıcı yine kapatabilir
                if !yeni.isSubset(of: eski) { withAnimation { digerBilgilerAcik = true } }
            }
            .onChange(of: mergeDecision) { _, decision in
                guard acceptsActiveCatalogResult() else { return }
                onMergeDecision?(decision)
            }
            .onChange(of: autosaveKey) { _, _ in
                guard acceptsActiveCatalogResult() else { return }
                var snapshot = draft
                snapshot.fieldMetadata = BookFieldMetadata.stampChanges(before: rawInitialBook,
                    after: BookEditorValidation.preservingInput(in: snapshot.snapshot, input: editorInput(snapshot)), source: "manual").fieldMetadata
                onDraftChange?(snapshot)
            }
            .task(id: draft.title + "|" + draft.isbn) {
                // Yazma bitince denetle (her harfte sorgu atılmasın)
                guard acceptsActiveCatalogResult() else { return }
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                guard acceptsActiveCatalogResult() else { return }
                possibleDuplicates = MukerrerDenetimi.eslesmeler(
                    title: draft.title, isbn: draft.isbn, haric: draft.existingBookID, context: modelContext)
            }
            .task(id: autosaveKey) {
                // Yeni kayıt yarım kalırsa (uygulama kapanır/çökerse) taslak kaybolmasın
                guard acceptsActiveCatalogResult(), draft.existingBookID == nil, !draft.title.isEmpty || !draft.isbn.isEmpty else { return }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard acceptsActiveCatalogResult(), !isClosing else { return }
                TaslakDeposu.kaydet([BookFieldMetadata.stampChanges(before: rawInitialBook,
                    after: BookEditorValidation.preservingInput(in: draft.snapshot, input: editorInput(draft)), source: "manual")])
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
            .confirmationDialog("Kaydedilmemiş değişiklikler var", isPresented: $showingDiscard, titleVisibility: .visible) {
                Button("Devam Et", role: .cancel) { }
                    .accessibilityIdentifier("editor.keepEditing")
                Button("Kaydetmeden Kapat", role: .destructive) {
                    isClosing = true
                    if let id = draft.existingBookID { DuzenlemeTaslagi.birak(kitap: id) }
                    if acceptsActiveCatalogResult() { TaslakDeposu.temizle() }
                    dismiss()
                }
            }
            .alert("Kitap kaydedilemedi", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                if kimlikGerekiyor {
                    Button("Kimliği doğrula ve yeniden dene") {
                        Task {
                            guard await YetkiDurumu.shared.yoneticiOl() else {
                                saveError = YetkiDurumu.shared.hata ?? "Kimlik doğrulanamadı. Taslak korunuyor."
                                return
                            }
                            kaydet()
                        }
                    }
                }
                Button("Tamam", role: .cancel) { }
            } message: { Text(saveError ?? "Taslak korunuyor.") }
            .fullScreenCover(isPresented: $barkodTarama) {
                ZStack(alignment: .topTrailing) {
                    LiveISBNScannerView { kod in
                        barkodTarama = false
                        let isbn = ISBNFormatter.repair(kod)
                        draft.isbn = isbn.isEmpty ? kod : isbn
                    } onCancel: {
                        barkodTarama = false
                    }
                    .ignoresSafeArea()
                    Button { barkodTarama = false } label: {
                        Label("Kapat", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                            .shadow(radius: 3)
                    }
                    .padding()
                    .accessibilityLabel("Barkod okumayı kapat")
                }
            }
            .task {
                guard !kayitliDenetlendi else { return }
                let id = initialDraft.existingBookID ?? draft.snapshot.id
                taslakKayitli = ((try? modelContext.fetchCount(FetchDescriptor<CatalogBook>(predicate: #Predicate { $0.id == id }))) ?? 0) > 0
                kayitliDenetlendi = true
                oneriler = KategoriOnerileri.hepsi(context: modelContext, limit: 8)
            }
            .task(id: draft.title + "|" + draft.isbn) {
                guard onMergeDecision != nil else { return }
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                editionCatalog = Self.baskiAdaylari(title: draft.title, isbn: draft.isbn, context: modelContext)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") {
                        if hasUnsavedChanges { showingDiscard = true }
                        else {
                            isClosing = true
                            if let id = draft.existingBookID { DuzenlemeTaslagi.birak(kitap: id) }
                            if acceptsActiveCatalogResult() { TaslakDeposu.temizle() }
                            dismiss()
                        }
                    }.accessibilityIdentifier("editor.cancel")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { kaydet() }
                    .accessibilityIdentifier("editor.save")
                    .disabled(!editorValidation.canSave)
                }
            }
        }
    }

    /// Kaydetme yönetici kimliği olmadığı için başarısız olduysa uyarıda yeniden deneme sunulur.
    private var kimlikGerekiyor: Bool {
        (saveError ?? "").localizedCaseInsensitiveContains("yönetici kimliği") && !YetkiDurumu.shared.yonetici
    }

    private func kaydet() {
        guard acceptsActiveCatalogResult() else { return }
        saveError = nil
        let prepared: Book
        do {
            prepared = try BookEditorValidation.preparedBook(draft.snapshot,
                input: editorInput(draft), existing: validationBaseline)
        } catch { saveError = error.localizedDescription; return }
        let savedBook = BookFieldMetadata.stampChanges(before: rawInitialBook,
            after: prepared, source: "manual")

        let result = validatedSave(savedBook)
        if case .failed(let error) = result {
            saveError = error
            // Kayıt reddedilse de yazılanlar yitmesin: kitap yeniden açılınca taslak geri gelir.
            if let id = draft.existingBookID { DuzenlemeTaslagi.koru(draft, kitap: id) }
            return
        }
        if let id = draft.existingBookID { DuzenlemeTaslagi.birak(kitap: id) }
        if SonKonum.yazilmali(hatirla: sonKonumuHatirla, existingBookID: draft.existingBookID) {
            SonKonum.kaydet(yer: draft.location, dolap: draft.cabinet, raf: draft.shelf)
        }
        learnCorrections()
        isClosing = true
        TaslakDeposu.temizle()
        dismiss()
    }

    /// Aynı ISBN'li ya da adı içeren kayıtlar (baskı karşılaştırması için); tüm katalog okunmaz.
    private static func baskiAdaylari(title: String, isbn: String, context: ModelContext) -> [CatalogBook] {
        var sonuc: [CatalogBook] = []
        let isbnAnahtar = ISBNFormatter.normalize(isbn)
        if !isbnAnahtar.isEmpty {
            var tam = FetchDescriptor<CatalogBook>(predicate: #Predicate { $0.isbn == isbnAnahtar })
            tam.fetchLimit = 50
            var aday = (try? context.fetch(tam)) ?? []
            if aday.isEmpty {
                // Tireli ya da boşluklu kayıtlı ISBN: son iki rakamla daraltılıp rakamlar tam karşılaştırılır.
                let son = Array(isbnAnahtar.suffix(2)).map(String.init)
                let bitisik = son.joined(), tireli = son.joined(separator: "-"), bosluklu = son.joined(separator: " ")
                var genis = FetchDescriptor<CatalogBook>(predicate: #Predicate {
                    ($0.isbn?.contains(bitisik) ?? false) || ($0.isbn?.contains(tireli) ?? false) || ($0.isbn?.contains(bosluklu) ?? false)
                })
                genis.fetchLimit = 2_000
                aday = ((try? context.fetch(genis)) ?? []).filter { ISBNFormatter.normalize($0.isbn ?? "") == isbnAnahtar }
            }
            sonuc += aday
        }
        let adAnahtar = CatalogMatcher.normalize(title)
        if adAnahtar.count >= 3 {
            var istek = FetchDescriptor<CatalogBook>(predicate: #Predicate { $0.searchKey?.contains(adAnahtar) ?? false })
            istek.fetchLimit = 100
            sonuc += (try? context.fetch(istek)) ?? []
        }
        var gorulen = Set<UUID>()
        return sonuc.filter { gorulen.insert($0.id).inserted }
    }

    /// Dokunulunca alanı dolduran öneri çipleri (telefonda yazmadan seçmek için).
    @ViewBuilder
    private func oneriCipleri(_ degerler: [String], secili: Binding<String>) -> some View {
        let gorunen = degerler.filter { $0.caseInsensitiveCompare(secili.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame }
        if !gorunen.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(gorunen, id: \.self) { deger in
                        Button(deger) { secili.wrappedValue = deger }
                            .buttonStyle(.kitapTonlu(KitapTema.ana))
                            .font(.footnote)
                            .accessibilityLabel("Öneri: \(deger)")
                    }
                }
            }
        }
    }

    private func acceptsActiveCatalogResult() -> Bool {
        do {
            if catalogLease == nil { catalogLease = try ActiveCatalogLease.captureCurrent(context: modelContext) }
            try catalogLease?.requireCurrent(context: modelContext)
            return true
        } catch {
            saveError = "Etkin katalog değişti veya işlem iptal edildi. Taslak yeni kataloğa yazılmadı; yeniden açın. \(error.localizedDescription)"
            return false
        }
    }

    private var lowConfidenceDescription: String {
        let names = [
            "title": "kitap adı",
            "author": "yazar",
            "publisher": "yayınevi",
            "isbn": "ISBN",
            "publicationYear": "basım yılı",
            "edition": "baskı",
            "pageCount": "sayfa sayısı",
            "category": "kategori",
            "language": "dil"
        ]
        return draft.lowConfidenceFields
            .compactMap { names[$0] }
            .sorted()
            .joined(separator: ", ")
    }

    private func fetchAmazonData() {
        guard acceptsActiveCatalogResult() else { return }
        let query = draft.isbn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isFetchingAmazon = true
        amazonStatusMessage = nil
        isAmazonStatusError = false

        Task { @MainActor in
            defer { isFetchingAmazon = false }
            if let metadata = await BookMetadataService.fetch(
                isbn: query,
                title: draft.title,
                author: draft.author,
                publisher: draft.publisher
            ) {
                guard acceptsActiveCatalogResult() else { return }
                AmazonBookScraper.apply(metadata: metadata, to: &draft, overwrite: true)
                amazonStatusMessage = "Amazon’dan kitap bilgileri başarıyla çekildi."
                isAmazonStatusError = false
            } else {
                amazonStatusMessage = "Bu ISBN ile kitap bulunamadı. ISBN’i ve internet bağlantınızı kontrol edin."
                isAmazonStatusError = true
            }
        }
    }
}

extension BookDraft {
    /// Editör doğrulamasının baktığı alanlar.
    var dogrulamaGirdisi: BookEditorValidation.Input {
        BookEditorValidation.Input(title: title, isbn: isbn,
            publicationYear: publicationYear, pageCount: pageCount,
            quantity: quantity, location: location, cabinet: cabinet, shelf: shelf)
    }
}

/// Editörün katlı "Diğer bilgiler" grubu. Kitap adı, yazar, ISBN, konum ve adet hep açıktır;
/// grup yalnız kendi alanlarında sorun ya da düşük güven varsa kendiliğinden açılır (boş kitap
/// adı her yeni formda sorun olduğundan grubu açmaz).
enum EditorDigerBilgiler {
    /// Grubun içindeki doğrulanan alanlar.
    static let dogrulananAlanlar: Set<BookEditorValidation.Field> = [.publicationYear, .pageCount]
    /// Grubun içindeki, OCR'ın "kontrol edin" diye işaretleyebildiği alanlar (`lowConfidenceFields` anahtarları).
    /// Vision yayınevi/basım bilgilerini, Gemini ayrıca kategori ve dili belirsiz işaretleyebilir.
    static let guvenAlanlari: Set<String> = ["publisher", "category", "language", "publicationYear", "edition", "pageCount"]

    static func sorunluAlanlar(_ dogrulama: BookEditorValidation.Result, dusukGuvenli: Set<String>) -> Set<String> {
        Set(dogrulama.issues.map(\.field).filter(dogrulananAlanlar.contains).map(\.rawValue))
            .union(dusukGuvenli.intersection(guvenAlanlari))
    }
}

/// Alanın yanındaki mavi "Gemini bu alanı güvenle okudu" noktası. Yanlış güvence vermektense eksik
/// kalır: barkoddan ya da veri servisinden gelen, boş duran veya editörde (elle ya da Amazon
/// doğrulamasıyla) değişen alanda nokta çıkmaz.
enum EditorGuvenIsareti {
    /// Kaynak kaydında Gemini'nin doldurduğu alanlar (`BookFieldMetadata` anahtarları).
    static func geminiAlanlari(_ fieldMetadata: String?) -> Set<String> {
        Set(BookFieldMetadata.decode(fieldMetadata).filter { $0.value.source == "gemini" }.keys)
    }

    static func geminiOkudu(_ alan: String, deger: String, ilkDeger: String,
                            taslak: BookDraft, geminiAlanlari: Set<String>) -> Bool {
        taslak.recognizedByGemini && geminiAlanlari.contains(alan)
            && !taslak.lowConfidenceFields.contains(alan) && deger == ilkDeger
            && !deger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Son yeni kitabın konumu: editördeki "Son konumu kullan" düğmesi ve seri tarama / raf atama
/// kurulumları bununla dolar. Yalnız Ekle akışındaki yeni kayıt yazar; mevcut kitabın ya da onay
/// kuyruğundaki taslağın düzenlenmesi yazmaz (yoksa rastgele bir kaydın konumu "son konum" olur).
/// Konum kataloğa özgüdür: anahtarlar arşiv ayarlarındadır (`ArchiveSettings.allowedKeys`), başka
/// bir arşive geçince ya da geri yüklemede o kataloğun son konumu gelir (yoksa boşalır).
enum SonKonum {
    nonisolated static let yerAnahtari = "sonKonum.yer"
    nonisolated static let dolapAnahtari = "sonKonum.dolap"
    nonisolated static let rafAnahtari = "sonKonum.raf"
    nonisolated static let anahtarlar: Set<String> = [yerAnahtari, dolapAnahtari, rafAnahtari]

    static func yazilmali(hatirla: Bool, existingBookID: UUID?) -> Bool {
        hatirla && existingBookID == nil
    }

    /// Üç alan birlikte yazılır; hepsi boşsa önceki konum korunur.
    static func kaydet(yer: String, dolap: String, raf: String, defaults: UserDefaults = .standard) {
        let degerler = [yer, dolap, raf].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard degerler.contains(where: { !$0.isEmpty }) else { return }
        defaults.set(degerler[0], forKey: yerAnahtari)
        defaults.set(degerler[1], forKey: dolapAnahtari)
        defaults.set(degerler[2], forKey: rafAnahtari)
    }

    static func yukle(defaults: UserDefaults = .standard) -> (yer: String, dolap: String, raf: String) {
        (defaults.string(forKey: yerAnahtari) ?? "", defaults.string(forKey: dolapAnahtari) ?? "",
         defaults.string(forKey: rafAnahtari) ?? "")
    }

    /// "Son konumu kullan (Dolap 3 · Raf 2)"; kayıtlı konum yoksa `nil`.
    static func dugmeBasligi(yer: String, dolap: String, raf: String) -> String? {
        CatalogBook.konumMetni(yer: yer, dolap: dolap, raf: raf).map { "Son konumu kullan (\($0))" }
    }
}

struct CoverPreview: View {
    let data: Data

    var body: some View {
        if let image = CoverImageDecoder.thumbnail(from: data, maxPixelSize: 800) {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 260)
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityLabel("Seçilen kitabın kapağı")
        }
    }
}


/// Düzenleyici doğrulamasını girdi değişmedikçe yeniden çalıştırmayan, gözlenmeyen önbellek.
final class DogrulamaOnbellegi {
    private var girdi: BookEditorValidation.Input?
    private var baseline: BookEditorValidation.Input?
    private var kayitli: BookEditorValidation.Result?

    func sonuc(girdi yeni: BookEditorValidation.Input, baseline yeniBaseline: BookEditorValidation.Input?,
               hesapla: () -> BookEditorValidation.Result) -> BookEditorValidation.Result {
        if let kayitli, girdi == yeni, baseline == yeniBaseline { return kayitli }
        let sonuc = hesapla()
        girdi = yeni; baseline = yeniBaseline; kayitli = sonuc
        return sonuc
    }
}

struct EditorOnerileri: Equatable {
    var kategori: [String] = []
    var yayinevi: [String] = []
    var seri: [String] = []
}

nonisolated enum PickerSecenekleri {
    static let durumlar = ["Okunacak", "Okunuyor", "Okundu"]
}

/// Kaydı reddedilen düzenleme taslağı bellekte tutulur; kitap yeniden düzenlenmek istenirse geri gelir.
enum DuzenlemeTaslagi {
    private static var bekleyen: [UUID: BookDraft] = [:]
    static func koru(_ taslak: BookDraft, kitap: UUID) { bekleyen[kitap] = taslak }
    static func birak(kitap: UUID) { bekleyen[kitap] = nil }
    static func taslak(kitap: UUID) -> BookDraft? { bekleyen[kitap] }
}
