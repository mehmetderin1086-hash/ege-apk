import SwiftUI
import SwiftData
import PhotosUI
import UIKit

// MARK: - Raf Tara (çoklu kitap ekleme + raf sayımı)

/// Tek fotoğrafta birden çok kitap: raftaki sırtlar ya da masadaki kapaklar.
/// "Ekle" modu: bulunan kitaplar liste hâlinde gelir, seçilenler tek dokunuşla kaydedilir.
/// "Sayım" modu: fotoğraftaki kitaplar o rafa kayıtlı kitaplarla karşılaştırılır.
struct ShelfScanPage: View {
    var sessionID: UUID? = nil
    enum Mode: String, CaseIterable, Identifiable {
        case add = "Kitap Ekle"
        case count = "Raf Sayımı"
        var id: Self { self }
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CatalogBook.addedAt, order: .reverse) private var books: [CatalogBook]
    @Query private var loans: [ActiveLoan]
    @Query private var copies: [BookCopy]
    @Query private var reservations: [Reservation]

    @State private var mode: Mode = .add
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var videoItem: PhotosPickerItem?
    @State private var isExtractingVideo = false
    @State private var images: [Data] = []
    @State private var isShowingCamera = false
    @State private var cabinet = ""
    @State private var shelf = ""
    @State private var isWorking = false
    @State private var found: [GeminiBookFields] = []
    @State private var selected: Set<Int> = []
    @State private var comparison: ShelfScanEngine.ShelfComparison?
    @State private var message: (text: String, isError: Bool)?
    /// Dilim ilerlemesi (okunan, toplam); uzun taramalarda kullanıcı bekleyişi görür
    @State private var progress: (done: Int, total: Int)?
    /// Sayfadan çıkılınca yarım tarama iptal edilir (boşa Gemini isteği gitmez)
    @State private var scanTask: Task<Void, Never>?
    @State private var photoRelation: ScanPhotoRelation = .overlapping
    @State private var detailedResult: ShelfScanResult?
    @State private var currentSession = ScanSession(kind: .shelf, title: "Raf taraması")
    @State private var editingIndex: Int?
    @State private var sourceField: GeminiBookFields?
    @State private var savedKeys: Set<String> = []
    @State private var foundSourceKeys: [String] = []
    @State private var catalogLease: ActiveCatalogLease?

    var body: some View {
        Form {
            Section {
                Picker("Mod", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Fotoğrafların ilişkisi", selection: $photoRelation) {
                    ForEach(ScanPhotoRelation.allCases) { Text($0.rawValue).tag($0) }
                }
                .disabled(isWorking)
                Text(photoRelation == .overlapping ? "Aynı nüsha farklı açılarda görünürse en yüksek adet korunur." : "Farklı raflarda görülen nüshalar toplanır.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("Dolap (ör. B)", text: $cabinet).textFieldStyle(.roundedBorder)
                    TextField("Raf (ör. 3)", text: $shelf).textFieldStyle(.roundedBorder)
                }
            } footer: {
                Text(mode == .add
                     ? "Rafın ya da masadaki kitapların fotoğrafını çekin; fotoğraf raf satırlarına ve şeritlere bölünerek okunur, her kitap ayrı kayıt olur, yan yana duran nüshalar adet olarak sayılır. Raf etiketi (\"6 TÜRK EDEBİYATI\") ve kenar kodu (\"B\") okunursa boş dolap/raf alanları otomatik dolar."
                     : "Sayım için dolap (ve raf) zorunlu: fotoğraftaki kitaplar o rafa kayıtlı kitaplarla karşılaştırılır.")
            }

            Section("Fotoğraflar") {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, data in
                            ZStack(alignment: .topTrailing) {
                                CoverThumb(data: data, size: 70)
                                Button { images.remove(at: index) } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .red)
                                }
                                .accessibilityLabel("Fotoğrafı kaldır")
                                .offset(x: 6, y: -6)
                            }
                        }
                        if images.count < 4 {
                            PhotosPicker(selection: $pickerItems, maxSelectionCount: 4 - images.count, matching: .images) {
                                Label("Galeri", systemImage: "photo.on.rectangle")
                            }
                            .buttonStyle(.kitapTonlu(KitapTema.foto))
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Button { isShowingCamera = true } label: {
                                    Label("Kamera", systemImage: "camera")
                                }
                                .buttonStyle(.kitapTonlu(KitapTema.foto))
                            }
                            PhotosPicker(selection: $videoItem, matching: .videos) {
                                Label(isExtractingVideo ? "Kareler…" : "Video", systemImage: "video")
                            }
                            .buttonStyle(.kitapTonlu(KitapTema.foto))
                            .disabled(isExtractingVideo)
                            .accessibilityHint("Rafı yavaşça tarayan bir videodan 4 kare alınır")
                        }
                    }
                    .padding(.vertical, 4)
                }
                // Tarama sürerken fotoğraf listesi değişmesin (kamera açılışı taramayı iptal etmesin)
                .disabled(isWorking)
                Button {
                    scanTask = Task { await scan() }
                } label: {
                    Label(scanButtonTitle, systemImage: "sparkles")
                }
                .buttonStyle(.kitapDolu(KitapTema.foto))
                .disabled(images.isEmpty || isWorking || (mode == .count && cabinet.isEmpty))
            }

            if let message {
                Section {
                    Label(message.text, systemImage: message.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(message.isError ? KitapTema.vurgu : KitapTema.basari)
                        .font(.footnote)
                }
            }

            if let result = detailedResult, result.unfinishedTileCount > 0 {
                Section("Tamamlanmayan alanlar") {
                    Text("\(result.successfulTileCount) dilim başarılı; \(result.unfinishedTileCount) dilim yeniden okunmalı. Sayım sonuçları kısmi olabilir.")
                        .foregroundStyle(KitapTema.vurgu)
                    ForEach(result.tiles.filter { $0.status != .read }) { tile in
                        HStack {
                            CoverThumb(data: tile.jpeg, size: 50)
                            VStack(alignment: .leading) {
                                Text("Fotoğraf \(tile.photo + 1), raf \(tile.row + 1), şerit \(tile.column + 1)")
                                Text(tile.errorMessage ?? "Okuma bekliyor").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("Yalnız Tamamlanmayan Dilimleri Yeniden Tara") {
                        scanTask = Task { await scan(retryFailedOnly: true) }
                    }.disabled(isWorking)
                }
            }
            if mode == .add, !found.isEmpty { addResults }
            if mode == .count, let comparison { countResults(comparison) }
        }
        .task {
            guard acceptsActiveCatalogResult() else { return }
            guard let sessionID, let saved = ScanSessionStore.all().first(where: { $0.id == sessionID }) else { return }
            let recovered = (try? ScanSessionStore.reconciled(saved, context: modelContext)) ?? saved
            currentSession = recovered
            detailedResult = recovered.shelfResult
            cabinet = recovered.cabinet
            shelf = recovered.shelf
            savedKeys = Set(recovered.shelfSavedKeys)
            photoRelation = recovered.shelfResult?.photoRelation ?? .overlapping
            updateFound(from: recovered.shelfResult?.books ?? [])
            selected = Set(found.indices.filter { (found[$0].confidence ?? 0) >= 0.6 && (found[$0].uncertain ?? []).isEmpty })
            message = ("Kaydedilen tarama oturumu açıldı; tamamlanmayan dilimlerden devam edebilirsiniz.", false)
        }
        .sheet(isPresented: Binding(get: { editingIndex != nil }, set: { if !$0 { editingIndex = nil } })) {
            if let index = editingIndex, found.indices.contains(index) {
                ShelfBookFieldsEditor(fields: found[index]) { updated in
                    found[index] = updated
                    if foundSourceKeys.indices.contains(index) {
                        var reviewed = currentSession.reviewedShelfBooks ?? [:]
                        reviewed[foundSourceKeys[index]] = updated
                        currentSession.reviewedShelfBooks = reviewed
                    }
                    selected.insert(index)
                    editingIndex = nil
                    persistShelfSession()
                }
            }
        }
        .sheet(isPresented: Binding(get: { sourceField != nil }, set: { if !$0 { sourceField = nil } })) {
            if let field = sourceField {
                NavigationStack {
                    ScrollView {
                        ForEach(detailedResult?.tiles.filter { tile in tile.books.contains { ShelfScanEngine.isSameBook($0, field) } } ?? []) { tile in
                            if let image = UIImage(data: tile.jpeg) {
                                ScanSourcePhotoView(image: image, items: shelfSourceItems(tile)) { id, box in
                                    try confirmShelfSourceBox(box, itemID: id, tile: tile)
                                }.padding()
                                Text("Fotoğraf \(tile.photo + 1) · Raf \(tile.row + 1) · Şerit \(tile.column + 1)")
                            }
                        }
                    }.navigationTitle(field.title ?? "Kaynak fotoğraf")
                    .toolbar { Button("Kapat") { sourceField = nil } }
                }
            }
        }
        // Ekle kartı, Yönetim ve araç panelindeki adla aynı (tek ad kaynağı: KatalogAraci.shelfScan)
        .navigationTitle(KatalogAraci.shelfScan.aracBasligi ?? "")
        .navigationBarTitleDisplayMode(.inline)
        // Sayfa gerçekten kapanırken iptal; kamera tam ekranı açılırken değil
        .onDisappear { if !isShowingCamera { scanTask?.cancel() } }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), images.count < 4 { images.append(data) }
                }
                pickerItems = []
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { data in if images.count < 4 { images.append(data) } }
                .ignoresSafeArea()
        }
        .onChange(of: videoItem) { _, item in
            guard let item else { return }
            isExtractingVideo = true
            Task {
                defer {
                    isExtractingVideo = false
                    videoItem = nil
                }
                guard let video = try? await item.loadTransferable(type: VideoDosyasi.self) else {
                    message = ("Video açılamadı.", true)
                    return
                }
                defer { try? FileManager.default.removeItem(at: video.url) }
                photoRelation = .overlapping
                let frames = await VideoKareCikarici.kareler(url: video.url, adet: 4 - images.count)
                images.append(contentsOf: frames.prefix(4 - images.count))
                message = frames.isEmpty
                    ? ("Videodan kare alınamadı.", true)
                    : ("Videodan \(frames.count) kare alındı; aynı kitap birden çok karede görünse de bir kez listelenir.", false)
            }
        }
    }

    private var scanButtonTitle: String {
        guard isWorking else { return "Gemini ile Tara" }
        if let progress, progress.total > 0 {
            return progress.done == 0
                ? "\(progress.total) dilim hazırlandı, okunuyor…"
                : "Dilim \(progress.done)/\(progress.total) okundu…"
        }
        return "Fotoğraf dilimleniyor…"
    }

    private func existing(_ fields: GeminiBookFields) -> CatalogBook? {
        return books.first { !$0.isWithdrawn && CatalogSaveEngine.sameEdition($0, VoiceBookEngine.book(from: SesliKitapKaydi(fields: fields))) }
    }

    private var addResults: some View {
        Section {
            ForEach(Array(found.enumerated()), id: \.offset) { index, fields in
                Button {
                    if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: selected.contains(index) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(KitapTema.basari)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(fields.title ?? "").font(.subheadline.weight(.semibold))
                                if let copies = fields.copies, copies > 1 {
                                    // Yan yana duran nüshalar: kayıtta adet olarak işlenir
                                    Text("×\(copies)")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(KitapTema.ana.opacity(0.12), in: .capsule)
                                        .foregroundStyle(KitapTema.ana)
                                        .accessibilityLabel("\(copies) nüsha")
                                }
                            }
                            Text([fields.author, fields.publisher].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                if existing(fields) != nil {
                                    Text(CatalogSaveEngine.preview(VoiceBookEngine.book(from: SesliKitapKaydi(fields: fields)), catalog: books).actionText).font(.caption2).foregroundStyle(KitapTema.amazon)
                                }
                                if let confidence = fields.confidence, confidence < 0.6 {
                                    Text("Düşük güven").font(.caption2).foregroundStyle(KitapTema.vurgu)
                                }
                            }
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected.contains(index) ? [.isSelected] : [])
                .contextMenu {
                    Button("Alanları ve Adedi Düzenle", systemImage: "pencil") { editingIndex = index }
                    Button("Kaynak Fotoğrafı Aç", systemImage: "photo") { openSource(index: index) }
                }
                HStack {
                    Button("Düzenle", systemImage: "pencil") { editingIndex = index }
                    Button("Kaynak", systemImage: "photo") { openSource(index: index) }
                }.font(.caption).buttonStyle(.bordered)
                let reviewBook = reviewBook(at: index)
                let review = CatalogSaveEngine.preview(reviewBook, catalog: books)
                if !review.candidates.isEmpty {
                    DisclosureGroup("Baskıyı ve kaydetme etkisini karşılaştır") {
                        CatalogEditionReviewPanel(preview: review, decision: Binding(
                            get: { currentSession.saveDecisions?[reviewBook.id] ?? .automatic },
                            set: { decision in
                                let key = foundSourceKeys.indices.contains(index) ? foundSourceKeys[index] : ShelfScanEngine.signature(fields)
                                var keys = currentSession.shelfBookKeys ?? [:]
                                keys[key] = reviewBook.id
                                currentSession.shelfBookKeys = keys
                                currentSession.saveDecisions = currentSession.saveDecisions ?? [:]
                                currentSession.saveDecisions?[reviewBook.id] = decision
                                persistShelfSession()
                            }))
                    }
                }
            }
            Button {
                saveSelected()
            } label: {
                Label("Seçilenleri Kaydet (\(selected.count))", systemImage: "tray.and.arrow.down.fill")
            }
            .buttonStyle(.kitapDolu(KitapTema.basari))
            .disabled(selected.isEmpty)
        } header: {
            Text("Bulunan kitaplar (\(found.count))")
        } footer: {
            Text("Düşük güvenli kayıtlar varsayılan olarak seçilmez; kontrol edip işaretleyin.")
        }
    }

    @ViewBuilder
    private func countResults(_ result: ShelfScanEngine.ShelfComparison) -> some View {
        Section("Nüsha farkları (\(result.quantityDifferences.count))") {
            if !(detailedResult?.isComplete ?? false) {
                Text("Tarama kısmi; görülmeyen nüshalar için eksiklik kararı vermeden tamamlanmayan dilimleri yeniden okuyun.")
                    .font(.footnote).foregroundStyle(KitapTema.vurgu)
            }
            ForEach(result.quantityDifferences, id: \.book.id) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.book.title)
                    Text("Görülen \(item.seen) · Rafta beklenen \(item.expected) · Ödünçte \(item.loaned)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        Section("Rafta ve kayıtlı (\(result.found.count))") {
            ForEach(result.found) { Label($0.title, systemImage: "checkmark.circle").foregroundStyle(KitapTema.basari) }
        }
        Section("Kayıtlı ama rafta görülmedi (\(result.missing.count))") {
            ForEach(result.missing) { book in
                VStack(alignment: .leading) {
                    Text(book.title)
                    if !(book.loanedTo ?? "").isEmpty { Text("Ödünçte olabilir").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        Section("Yanlış rafta (\(result.misplaced.count))") {
            ForEach(result.misplaced, id: \.book.id) { item in
                HStack {
                    Text(item.book.title)
                    Spacer()
                    Text("Kayıtlı: \(item.registered)").font(.caption).foregroundStyle(KitapTema.vurgu)
                }
            }
            if !result.misplaced.isEmpty {
                Button("Hepsinin yerini bu raf yap") { moveMisplaced(result) }
                    .disabled(!(detailedResult?.isComplete ?? false))
                    .buttonStyle(.kitapTonlu(KitapTema.ana))
            }
        }
        Section("Katalogda yok (\(result.unknown.count))") {
            ForEach(Array(result.unknown.enumerated()), id: \.offset) { _, fields in
                Text([fields.title, fields.author].compactMap { $0 }.joined(separator: " — "))
            }
        }
    }

    private func scan(retryFailedOnly: Bool = false) async {
        guard acceptsActiveCatalogResult() else { return }
        isWorking = true
        message = nil
        found = []
        comparison = nil
        progress = nil
        defer {
            isWorking = false
            progress = nil
        }
        do {
            if !retryFailedOnly {
                currentSession = ScanSession(kind: .shelf, title: "Raf taraması")
                savedKeys = []
            }
            let detailed = try await ShelfScanEngine.scanDetailed(images: images, photoRelation: photoRelation,
                retrying: retryFailedOnly ? detailedResult : nil, progress: { done, total in
                    guard acceptsActiveCatalogResult() else { return }
                    progress = (done, total)
                }, checkpoint: { checkpoint in
                    guard acceptsActiveCatalogResult() else { return }
                    detailedResult = checkpoint
                    persistShelfSession()
                })
            guard acceptsActiveCatalogResult() else { return }
            detailedResult = detailed
            let result = detailed.books.filter { !savedKeys.contains(ShelfScanEngine.signature($0)) }
            persistShelfSession()
            guard !result.isEmpty else {
                message = (detailed.unfinishedTileCount > 0
                    ? "Tarama tamamlanamadı; dilimleri yeniden deneyebilirsiniz."
                    : "Fotoğrafta okunabilir kitap bulunamadı. Daha yakından, net çekin.", true)
                return
            }
            // Raf etiketi / dolap kodu okunduysa boş alanlar otomatik dolar
            var labelNote = ""
            if cabinet.isEmpty, let code = detailed.cabinetLabel { cabinet = code }
            if shelf.isEmpty, detailed.rafOtomatikDolabilir, let number = detailed.shelfNumber { shelf = number }
            if detailed.shelfLabels.count > 1 {
                // Tam dolap karesi: hangi kitabın hangi rafta olduğu bilinmez, raf alanı doldurulmaz
                labelNote = " Birden çok raf etiketi görüldü (\(detailed.shelfLabels.map { $0.capitalized(with: Locale(identifier: "tr_TR")) }.joined(separator: ", "))); rafı kendiniz seçin."
            } else if let label = detailed.shelfLabel, detailed.satirSayisi > 1 {
                // Tek etiket okundu ama fotoğrafta birden çok raf var: etiket yalnız bir rafa ait
                labelNote = " Raf etiketi \(label.capitalized(with: Locale(identifier: "tr_TR"))) okundu; fotoğrafta \(detailed.satirSayisi) raf olduğu için raf alanı doldurulmadı."
            } else if let label = detailed.shelfLabel {
                labelNote = " Raf etiketi: \(label.capitalized(with: Locale(identifier: "tr_TR")))."
            } else if let code = detailed.cabinetLabel {
                labelNote = " Dolap kodu: \(code)."
            }
            if mode == .add {
                updateFound(from: detailed.books)
                selected = Set(result.indices.filter { (result[$0].confidence ?? 0) >= 0.6 && (result[$0].uncertain ?? []).isEmpty })
                let copiesNote = detailed.totalCopies > result.count ? ", \(detailed.totalCopies) nüsha" : ""
                message = ("\(result.count) kitap bulundu\(copiesNote) (\(detailed.successfulTileCount)/\(detailed.tileCount) dilim başarıyla okundu).\(labelNote)", detailed.unfinishedTileCount > 0)
            } else {
                comparison = ShelfScanEngine.compare(result, catalog: books, cabinet: cabinet, shelf: shelf,
                    loans: loans, copies: copies, reservations: reservations)
                message = ("\(result.count) kitap okundu ve rafla karşılaştırıldı.", false)
            }
            AccessibilityNotification.Announcement(message?.text ?? "").post()
        } catch is CancellationError {
            // Sayfadan çıkıldı: sessizce bırak
        } catch {
            message = ((error as? GeminiError)?.errorDescription ?? error.localizedDescription, true)
        }
    }

    private func writeShelfSession() throws {
        if catalogLease == nil { catalogLease = try ActiveCatalogLease.captureCurrent(context: modelContext) }
        try catalogLease?.requireCurrent(context: modelContext)
        currentSession.shelfResult = detailedResult
        currentSession.shelfSavedKeys = Array(savedKeys)
        currentSession.cabinet = cabinet
        currentSession.shelf = shelf
        var keys = currentSession.shelfBookKeys ?? [:]
        let previousPending = Dictionary(currentSession.pendingBooks.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        currentSession.pendingBooks = (detailedResult?.books ?? []).compactMap { raw in
            let key = ShelfScanEngine.signature(raw)
            guard !savedKeys.contains(key) else { return nil }
            let id = keys[key] ?? UUID()
            keys[key] = id
            let fields = currentSession.reviewedShelfBooks?[key] ?? raw
            var pending = VoiceBookEngine.book(from: SesliKitapKaydi(fields: fields, cabinet: cabinet, shelf: shelf), id: id)
            pending.coverData = previousPending[id]?.coverData
            pending.fieldMetadata = previousPending[id]?.fieldMetadata
            return pending
        }
        currentSession.shelfBookKeys = keys
        try ScanSessionStore.save(currentSession)
    }

    private func persistShelfSession() {
        do { try writeShelfSession() }
        catch { message = ("Oturum saklanamadı: \(error.localizedDescription)", true) }
    }

    private func updateFound(from raw: [GeminiBookFields]) {
        let pending = raw.filter { !savedKeys.contains(ShelfScanEngine.signature($0)) }
        foundSourceKeys = pending.map(ShelfScanEngine.signature)
        found = pending.map { currentSession.reviewedShelfBooks?[ShelfScanEngine.signature($0)] ?? $0 }
    }

    private func reviewBook(at index: Int) -> Book {
        let fields = found[index]
        let key = foundSourceKeys.indices.contains(index) ? foundSourceKeys[index] : ShelfScanEngine.signature(fields)
        let id = currentSession.shelfBookKeys?[key] ?? Book.stableID(title: key, author: "shelf-review", isbn: "")
        return VoiceBookEngine.book(from: SesliKitapKaydi(fields: fields, cabinet: cabinet, shelf: shelf), id: id)
    }

    private func openSource(index: Int) {
        guard found.indices.contains(index) else { return }
        let key = foundSourceKeys.indices.contains(index) ? foundSourceKeys[index] : ShelfScanEngine.signature(found[index])
        sourceField = detailedResult?.books.first { ShelfScanEngine.signature($0) == key } ?? found[index]
    }

    private func shelfSourceItems(_ tile: ShelfTileReading) -> [ScanSourcePhotoItem] {
        tile.books.enumerated().map { index, fields in
            let box = currentSession.shelfBoxEdits?[ScanBoxEditEngine.tileKey(tile.id, bookIndex: index)] ?? fields.box_2d
            return ScanSourcePhotoItem(id: ScanBoxEditEngine.tileItemID(tile.id, bookIndex: index), title: fields.title ?? "Algılanan kitap",
                source: ScanBookSource(photoIndex: tile.photo, box: box, method: "gemini", confidence: fields.confidence, tileID: tile.id))
        }
    }

    private func confirmShelfSourceBox(_ box: [Double], itemID: UUID, tile: ShelfTileReading) throws {
        guard let index = tile.books.indices.first(where: { ScanBoxEditEngine.tileItemID(tile.id, bookIndex: $0) == itemID })
        else { throw ScanBoxEditError.sourceMissing }
        var latest = try ScanSessionStore.reconciled(currentSession, context: modelContext)
        latest.shelfResult = detailedResult
        latest.shelfSavedKeys = Array(savedKeys.union(latest.shelfSavedKeys))
        latest.cabinet = cabinet
        latest.shelf = shelf
        let bounds = try ScanBoxBounds.validated(box)
        let crop = CokluKitapAlgilayici.kapakKesiti(tile.jpeg, kutu: bounds.rect)
        let updated = try ScanBoxEditEngine.applyShelf(bounds.values, tileID: tile.id, bookIndex: index, to: latest, coverData: crop)
        try ScanSessionStore.save(updated)
        currentSession = updated
        savedKeys = Set(updated.shelfSavedKeys)
        updateFound(from: detailedResult?.books ?? [])
    }

    private func saveSelected() {
        guard acceptsActiveCatalogResult() else { return }
        var catalog = books
        var saved = 0
        var merged = 0
        var completed = Set<Int>()
        var errors: [String] = []
        for index in selected.sorted() where found.indices.contains(index) {
            let kaydi = SesliKitapKaydi(fields: found[index], cabinet: cabinet, shelf: shelf)
            do {
                try writeShelfSession()
                let key = foundSourceKeys.indices.contains(index) ? foundSourceKeys[index] : ShelfScanEngine.signature(found[index])
                guard let operationID = currentSession.shelfBookKeys?[key] else { throw CatalogSaveEngine.SaveError(message: "Tarama taslağının işlem kimliği bulunamadı.") }
                let raw = detailedResult?.books.first { ShelfScanEngine.signature($0) == key }
                var metadata: String?
                if let raw, currentSession.reviewedShelfBooks?[key] != nil {
                    metadata = BookFieldMetadata.stampChanges(
                        before: VoiceBookEngine.book(from: SesliKitapKaydi(fields: raw), id: operationID),
                        after: VoiceBookEngine.book(from: kaydi, id: operationID), source: "manual").fieldMetadata
                } else { metadata = nil }
                let pending = currentSession.pendingBooks.first(where: { $0.id == operationID })
                if let coverEvidence = BookFieldMetadata.decode(pending?.fieldMetadata)["coverData"] {
                    var evidence = BookFieldMetadata.decode(metadata)
                    evidence["coverData"] = coverEvidence
                    metadata = BookFieldMetadata.encode(evidence)
                }
                let outcome = try VoiceBookSaver.save(kaydi, in: modelContext, catalog: catalog,
                    operationID: operationID, source: "gemini", fieldMetadata: metadata, coverData: pending?.coverData, confidence: found[index].confidence,
                    decision: currentSession.saveDecisions?[operationID] ?? .automatic)
                if case .merged(_, let added) = outcome {
                    if added > 0 { merged += 1 }
                    currentSession.mergedCopies[outcome.book.id, default: 0] += added
                } else {
                    saved += 1
                    catalog.insert(outcome.book, at: 0)
                    currentSession.insertedIDs.append(outcome.book.id)
                }
                currentSession.savedOperationIDs = (currentSession.savedOperationIDs ?? []) + [operationID]
                savedKeys.insert(key)
                completed.insert(index)
                VoiceBookSaver.enrichInBackground(outcome.book, context: modelContext)
                persistShelfSession()
            } catch { errors.append("\(found[index].title ?? "Kitap"): \(error.localizedDescription)") }
        }
        let original = found
        let remainingIndices = original.indices.filter { !completed.contains($0) }
        found = remainingIndices.map { original[$0] }
        foundSourceKeys = remainingIndices.map { foundSourceKeys[$0] }
        selected = Set(remainingIndices.enumerated().compactMap { newIndex, oldIndex in selected.contains(oldIndex) ? newIndex : nil })
        currentSession.lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        persistShelfSession()
        message = ("\(saved) yeni kitap kaydedildi, \(merged) kitabın adedi artırıldı." +
                   (errors.isEmpty ? "" : " \(errors.count) kayıt kaydedilemedi; taslaklar ve kaynak fotoğraflar korunuyor."), !errors.isEmpty)
        if found.isEmpty && (detailedResult?.unfinishedTileCount ?? 0) == 0 { images = [] }
    }

    private func acceptsActiveCatalogResult() -> Bool {
        do {
            if catalogLease == nil { catalogLease = try ActiveCatalogLease.captureCurrent(context: modelContext) }
            try catalogLease?.requireCurrent(context: modelContext)
            return true
        } catch {
            scanTask?.cancel()
            message = ("Etkin katalog değişti veya tarama iptal edildi; kaynaklar eski oturumda korunuyor. Yeni katalogda yeniden başlayın. \(error.localizedDescription)", true)
            return false
        }
    }

    private func moveMisplaced(_ result: ShelfScanEngine.ShelfComparison) {
        guard acceptsActiveCatalogResult() else { return }
        guard YetkiDurumu.shared.yonetici else { message = ("Raf değiştirmek için yönetici kimliği gerekir.", true); return }
        var updates: [Book] = []
        for item in result.misplaced where !item.book.isDeleted {
            var book = item.book.book
            book.cabinet = cabinet
            if !shelf.isEmpty { book.shelf = shelf }
            updates.append(book)
        }
        do {
            _ = try CatalogSaveEngine.saveBatch(updates, context: modelContext, catalog: books, mergeWithinBatch: false)
            comparison?.found.append(contentsOf: result.misplaced.map(\.book))
            comparison?.misplaced = []
            message = ("Yer bilgileri güncellendi.", false)
        } catch { message = ("Yer bilgileri kaydedilemedi: \(error.localizedDescription)", true) }
    }
}

private struct ShelfBookFieldsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var fields: GeminiBookFields
    var onSave: (GeminiBookFields) -> Void
    private var validISBN: Bool {
        let isbn = ISBNFormatter.normalize(fields.isbn ?? "")
        return isbn.isEmpty || ISBNFormatter.isValidISBN13(ISBNFormatter.repair(isbn))
    }
    private func text(_ key: WritableKeyPath<GeminiBookFields, String?>) -> Binding<String> {
        Binding(get: { fields[keyPath: key] ?? "" }, set: { fields[keyPath: key] = $0 })
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Fotoğraftan okunan alanlar") {
                    TextField("Kitap adı", text: text(\.title))
                    TextField("Yazar", text: text(\.author))
                    TextField("Yayınevi", text: text(\.publisher))
                    TextField("ISBN", text: text(\.isbn)).keyboardType(.numberPad)
                    if !validISBN { Text("ISBN denetim basamağı geçersiz; düzeltin veya alanı boş bırakın.").font(.caption).foregroundStyle(.red) }
                    TextField("Cilt", text: text(\.volume))
                    Stepper("\(fields.nusha) nüsha", value: Binding(get: { fields.nusha }, set: { fields.copies = $0 }), in: 1...99)
                }
                Section {
                    Text("Görülen nüsha adedini ve baskıyı kaynak fotoğrafla karşılaştırın. Onaylanan alanlar bu kayıt için kontrol edilmiş sayılır.")
                }
            }.navigationTitle("Kaydı Kontrol Et")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Onayla") {
                        fields.uncertain = []
                        onSave(fields)
                        dismiss()
                    }.disabled((fields.title ?? "").trimmingCharacters(in: .whitespaces).isEmpty || !validISBN)
                }
            }
        }
    }
}

// MARK: - Haftalık AI raporu

struct WeeklyReportPage: View {
    @Query private var books: [CatalogBook]
    @Query private var loans: [ActiveLoan]

    @State private var data: WeeklyReportData?
    @State private var commentary = ""
    @State private var isWorking = false
    @State private var pdfURL: URL?
    @State private var errorText: String?

    var body: some View {
        List {
            if let data {
                Section("Ödünç hareketleri (son 7 gün)") {
                    LabeledContent("Ödünç verilen", value: "\(data.lentCount)")
                    LabeledContent("İade alınan", value: "\(data.returnedCount)")
                    LabeledContent("Gecikmeli iade", value: "\(data.lateReturns)")
                    LabeledContent("Şu an gecikmiş", value: "\(data.overdueNow)")
                        .foregroundStyle(data.overdueNow > 0 ? KitapTema.vurgu : .primary)
                }
                Section("Koleksiyon") {
                    LabeledContent("Toplam kitap", value: "\(data.totalBooks)")
                    LabeledContent("Bu hafta eklenen", value: "\(data.newBooks)")
                    LabeledContent("Hiç ödünç verilmemiş", value: "\(data.neverLoaned)")
                }
                if !data.topBooks.isEmpty {
                    Section("En çok ödünç verilenler") {
                        ForEach(data.topBooks, id: \.title) { LabeledContent($0.title, value: "\($0.count)") }
                    }
                }
                Section("Eksik alanlar") {
                    LabeledContent("Kategorisiz", value: "\(data.missingCategory)")
                    LabeledContent("Kapaksız", value: "\(data.missingCover)")
                    LabeledContent("ISBN'siz", value: "\(data.missingISBN)")
                }
                Section("Gemini yorumu") {
                    if commentary.isEmpty {
                        Button {
                            Task { await comment(data) }
                        } label: {
                            Label(isWorking ? "Hazırlanıyor…" : "Yorum ve Öneri Üret", systemImage: "sparkles")
                        }
                        .buttonStyle(.kitapDolu(KitapTema.dosya))
                        .disabled(isWorking)
                    } else {
                        Text(commentary).textSelection(.enabled)
                    }
                    if let errorText { Text(errorText).font(.caption).foregroundStyle(.red) }
                }
                Section {
                    if let pdfURL {
                        ShareLink(item: pdfURL) {
                            Label("PDF Raporu Paylaş", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .navigationTitle("Haftalık Rapor")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh() }
    }

    private func refresh() {
        let report = WeeklyReportData.build(books: books, loans: loans, events: LoanHistoryStore.all)
        data = report
        makePDF(report)
    }

    private func makePDF(_ report: WeeklyReportData) {
        var sections = report.pdfSections
        if !commentary.isEmpty { sections.append(.init(title: "Değerlendirme", rows: [(commentary, "")])) }
        let pdf = PDFReportBuilder.build(
            title: "Haftalık Kütüphane Raporu",
            subtitle: "\(report.from.formatted(date: .long, time: .omitted)) – \(report.to.formatted(date: .long, time: .omitted))",
            sections: sections
        )
        pdfURL = SharedPDF.write(pdf, name: "Haftalik-Rapor")
    }

    private func comment(_ report: WeeklyReportData) async {
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        do {
            commentary = try await GeminiClient.shared.generateText(
                prompt: report.promptSummary,
                system: "Sen bir okul kütüphanesi danışmanısın. Verilen haftalık sayılara bakıp Türkçe, 4–6 cümlelik bir değerlendirme ve 3 somut öneri yaz (madde işaretiyle). Uydurma sayı kullanma.",
                temperature: 0.5, maxOutputTokens: 1500, thinking: .auto
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            makePDF(report)
        } catch {
            errorText = (error as? GeminiError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Kiosk: sesli kitap sorma

/// Öğrencilerin kiosktan "Harry Potter var mı?" diye sorduğu ekran. Bağlama yalnızca kitap
/// adı, yazar, yer ve boşta nüsha girer — öğrenci ya da ödünç bilgisi GİTMEZ.
struct KioskAskView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CatalogBook.title) private var books: [CatalogBook]
    @Query private var loans: [ActiveLoan]

    @State private var question = ""
    @State private var answer = ""
    @State private var isThinking = false
    @State private var speech = SpeechInput()
    @State private var voice = SpeechOutput()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(KitapTema.amazon)
                Text("Hangi kitabı arıyorsun?")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)

                Button {
                    Task { await toggleMic() }
                } label: {
                    Label(speech.isListening ? "Dinliyorum… (bitir)" : "Konuşarak Sor", systemImage: speech.isListening ? "waveform" : "mic.fill")
                        .font(.title2.weight(.semibold))
                }
                .buttonStyle(.kitapDolu(speech.isListening ? .red : KitapTema.amazon))
                .padding(.horizontal, 40)

                HStack {
                    TextField("ya da yaz: Şeker Portakalı var mı?", text: $question)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                        .submitLabel(.search)
                        .onSubmit { Task { await ask() } }
                    Button { Task { await ask() } } label: { Image(systemName: "arrow.up.circle.fill").font(.largeTitle) }
                        .buttonStyle(.kitapSade)
                        .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || isThinking)
                        .accessibilityLabel("Sor")
                }
                .padding(.horizontal, 40)

                if isThinking { ProgressView() }
                if !answer.isEmpty {
                    Text(answer)
                        .font(.title3)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(KitapTema.amazon.opacity(0.12), in: .rect(cornerRadius: 16))
                        .padding(.horizontal, 40)
                }
                Spacer()
            }
            .padding(.top, 30)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } }
            }
            .onAppear {
                speech.onFinalTranscript = { text in
                    question = text
                    Task { await ask() }
                }
            }
            .onDisappear { speech.stop(); voice.stop() }
        }
    }

    private func toggleMic() async {
        if speech.isListening {
            let text = speech.transcript
            speech.stop()
            if !text.isEmpty { question = text; await ask() }
            return
        }
        voice.stop()
        guard await speech.requestAuthorization() else { return }
        speech.start()
    }

    private func ask() async {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        isThinking = true
        defer { isThinking = false }
        let counts = AssistantContext.loanCounts(loans)
        let matches = AssistantContext.matchingBooks(for: text, in: books, limit: 25)
        let lines = matches.map { book -> String in
            let free = max(0, (book.quantity ?? 1) - (counts[book.id] ?? 0) - ((book.loanedTo ?? "").isEmpty ? 0 : 1))
            return "- \(book.title) — \(book.author) | yer: \(book.konumMetni ?? "bilinmiyor") | boşta \(free)"
        }
        let context = lines.isEmpty ? "Eşleşen kitap yok." : lines.joined(separator: "\n")
        do {
            answer = try await GeminiClient.shared.generateText(
                prompt: "KATALOG EŞLEŞMELERİ:\n\(context)\n\nÖĞRENCİNİN SORUSU: \(text)",
                system: "Sen okul kütüphanesi kioskusun; öğrencilerle konuşuyorsun. Türkçe, sıcak ve 1–3 kısa cümle cevap ver. Yalnızca verilen eşleşmelere dayan: kitap varsa dolap/raf yerini ve boşta olup olmadığını söyle; boşta değilse kütüphaneciye ayırtabileceğini söyle; yoksa benzer bir öneriyi yalnızca listeden yap. Kişisel bilgi isteme.",
                temperature: 0.4, maxOutputTokens: 800
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if UIAccessibility.isVoiceOverRunning {
                AccessibilityNotification.Announcement(answer).post()
            } else {
                voice.speak(answer)
            }
        } catch {
            answer = "Şu an cevap veremiyorum; kütüphaneciye sorabilirsin."
        }
    }
}

/// Bir sayfayı sayfa (sheet) olarak açarken gezinme çubuğu ve "Kapat" düğmesi ekler.
struct KapatilabilirSayfa<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Kapat") { dismiss() }
                    }
                }
        }
    }
}
