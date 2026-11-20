import Charts
import PhotosUI
import SwiftData
import SwiftUI
import Vision

/// Podcast bölümünden slayt destesi: üretim, görüntüleme, PDF ve PowerPoint.
struct DeckView: View {
    @Bindable var episode: Episode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var slideCount = 14
    /// Yapay zekâ çizimleri — 0: yok (varsayılan; kaynaktan kesilen şekiller her zaman kullanılır), 1: yalnızca görsel slaytları, 2: madde slaytlarına da.
    @AppStorage("deck.imageLevel") private var imageLevel = 0
    @State private var photoItems: [PhotosPickerItem] = []
    /// Deste varken kurulum formu yeniden açık ("Desteyi yeniden oluştur"): üretim ancak formdaki düğmeyle başlar.
    @State private var reconfiguring = false
    /// Deste varken seçilen fotoğraflar: yeniden üretim onaylanınca kaydedilir; vazgeçilirse hiçbir şey değişmez.
    @State private var pendingPhotos: [PhotosPickerItem] = []
    /// Yeniden oluşturma formu açılırken genel varsayılanların kopyası. Form destenin ayarlarıyla açılır; vazgeçilirse
    /// (ya da ekran deste üretilmeden kapanırsa) geri yazılır: başka bölümün ilk destesi bu destenin ayarını devralmasın.
    @State private var defaultsBeforeReconfigure: DeckFormDefaults?
    @State private var sourceNote: String?
    private var includeImages: Bool { imageLevel > 0 }
    @State private var phase: String?
    @State private var error: String?
    @State private var page = 0
    @State private var shareURL: URL?
    @State private var showPresentation = false
    @State private var showOverview = false
    @State private var editingSlide = false
    @State private var imageFailures: [Int: String] = [:]
    @AppStorage("deck.palette") private var paletteRaw = DeckPalette.studio.rawValue
    @AppStorage("deck.style") private var styleRaw = DeckIllustrationStyle.textbook.rawValue
    @State private var job: Task<Void, Never>?
    /// Ekranda gösterilen küçültülmüş görseller ve şekiller (her kaydırmada diskten okumamak için).
    @State private var images: [Int: UIImage] = [:]
    @State private var figures: [SourceFigure] = []
    /// Bölüm başlıkları ve başlangıçları: zaman çizelgesi her slayt çiziminde yeniden okunmasın.
    @State private var chapters: [TimedChapter] = []

    var body: some View {
        NavigationStack {
            Group {
                if let deck = episode.deck, !reconfiguring {
                    viewer(deck)
                } else {
                    setup
                }
            }
            .navigationTitle("Sunum stüdyosu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                if episode.deck != nil, phase == nil, !reconfiguring {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Bu slaytı PNG olarak paylaş", systemImage: "photo") { Task { await exportPNG() } }
                            Button("PDF olarak paylaş", systemImage: "doc.richtext") { Task { await exportPDF() } }
                            Button("PowerPoint olarak paylaş", systemImage: "rectangle.on.rectangle.angled") { Task { await exportPPTX() } }
                            Divider()
                            photoPicker
                            Button("Desteyi yeniden oluştur", systemImage: "arrow.clockwise") { reconfigure() }
                        } label: { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
            .sheet(item: $shareURL) { url in ShareSheet(items: [url]) }
            .sheet(isPresented: $showOverview) {
                if let deck = episode.deck { DeckOverview(deck: deck, images: images, page: $page) }
            }
            .sheet(isPresented: $editingSlide) {
                if let deck = episode.deck, let slide = deck.slides[safe: page] {
                    DeckSlideEditor(slide: slide) { updated in
                        var value = deck
                        value.slides[page] = updated
                        if page == 0, updated.kind == "title" { value.title = updated.title }
                        saveDeck(value)
                    }
                }
            }
            .fullScreenCover(isPresented: $showPresentation) {
                if let deck = episode.deck { DeckPresentationView(deck: deck, images: images, figures: figures, page: $page) }
            }
            .task { await loadAssets() }
            .onDisappear { job?.cancel(); restoreDefaults() }
            .alert("Hata", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    // MARK: - Kurulum

    private var setup: some View {
        Form {
            Section {
                OkuSectionHeading(title: episode.title, detail: "Bu bölümün kaynaklarından sunum oluştur.")
            }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
            if episode.deck != nil {
                Section {
                    Label("Yeni deste şimdikinin yerine geçer: düzenlemelerin ve hazır çizimler silinir. Üretim başarısız olursa eski deste kalır.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                    if !pendingPhotos.isEmpty {
                        Label("\(pendingPhotos.count) yeni fotoğraf, desteyi oluşturunca kaynaklara eklenir.", systemImage: "photo.badge.plus")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Vazgeç, desteye dön") {
                        pendingPhotos = []
                        restoreDefaults()
                        reconfiguring = false
                    }
                    .disabled(phase != nil)
                }
            }
            Section {
                Stepper("Hedef slayt sayısı: \(slideCount)", value: $slideCount, in: 8...30, step: 2)
                Picker("Görseller", selection: $imageLevel) {
                    Text("Kaynak").tag(0)
                    Text("Dengeli").tag(1)
                    Text("Zengin").tag(2)
                }
                .modifier(AccessiblePickerStyle())
            } footer: {
                Text("Bir destede en fazla 12 yapay zekâ çizimi hazırlanır. Kaynak belgedeki şekil, tablo ve fotoğraflar kesilip slaytlara büyük olarak yerleştirilir. \"Görseller\" ayarı yalnızca yapay zekâ çizimleri içindir. Tablo ve grafikler belgedeki sayılardan üretilir.")
            }
            Section("Tasarım") {
                Picker("Renk teması", selection: $paletteRaw) {
                    ForEach(DeckPalette.allCases) { palette in Text(palette.title).tag(palette.rawValue) }
                }
                Picker("Çizim tarzı", selection: $styleRaw) {
                    ForEach(DeckIllustrationStyle.allCases) { style in Text(style.title).tag(style.rawValue) }
                }.disabled(!includeImages)
                Label("Uzun tablolar okunabilir slaytlara bölünür. Kaynak görseller korunur.", systemImage: "rectangle.split.2x2")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                sourceStatus
                photoPicker
            } header: { Text("Kaynak") }
            Section {
                Button {
                    start()
                } label: {
                    HStack { if phase != nil { ProgressView() }; Text(phase ?? "Desteyi oluştur") }
                }
                .disabled(phase != nil)
                // Ayrı satır: Form'da aynı satırdaki iki düğme tek dokunuşla birlikte tetiklenir.
                if phase != nil, job != nil { Button("Durdur") { job?.cancel() } }
            }
        }
    }

    /// Formdaki üç seçici doğrudan kalıcı ayarlara (@AppStorage) bağlıdır.
    private var formDefaults: DeckFormDefaults {
        get { DeckFormDefaults(imageLevel: imageLevel, palette: paletteRaw, style: styleRaw) }
        nonmutating set { imageLevel = newValue.imageLevel; paletteRaw = newValue.palette; styleRaw = newValue.style }
    }

    /// Onaysız yeniden üretim yerine kurulum formunu şimdiki destenin ayarlarıyla açar. Genel varsayılanlar saklanır:
    /// yeni deste kaydedilmezse `restoreDefaults` geri yazar.
    private func reconfigure() {
        guard let deck = episode.deck else { return }
        slideCount = DeckAssets.suggestedSlideCount(deck)
        let current = formDefaults
        defaultsBeforeReconfigure = current
        formDefaults = current.reconfiguring(deck)
        reconfiguring = true
    }

    /// Yeniden oluşturma formundan deste üretilmeden çıkıldı: form açılırken saklanan varsayılanlar geri yazılır.
    private func restoreDefaults() {
        guard let saved = defaultsBeforeReconfigure else { return }
        defaultsBeforeReconfigure = nil
        formDefaults = saved
    }

    /// Bu bölüme bağlı kaynak belgeler ve kesilen şekil sayısı.
    private var sourceStatus: some View {
        let summary = FigureExtractor.sourceSummary(documents: (episode.sourceDocumentIDs ?? []).count, figures: episode.sourceFigures)
        return Label {
            Text(summary.text)
        } icon: {
            Image(systemName: summary.warning ? "exclamationmark.triangle" : "photo.on.rectangle.angled")
                .foregroundStyle(summary.warning ? .orange : .secondary)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var photoPicker: some View {
        PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
            Label("Kitap sayfası fotoğrafı ekle", systemImage: "camera.on.rectangle")
        }
        .disabled(phase != nil)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            if episode.deck != nil {
                // Deste varken fotoğraf eklemek yeniden üretim demektir (düzenlemeler ve çizimler gider):
                // seçim bekletilir, kurulum formunda onay alınır.
                photoItems = []
                pendingPhotos = Array((pendingPhotos + items).prefix(10))
                if !reconfiguring { reconfigure() }
            } else {
                Task { if await addPhotos(items) { start() } }
            }
        }
    }

    /// Seçilen fotoğrafları tam çözünürlükte kaynak belge olarak kaydeder ve şekil listesini eskimiş işaretler: şekiller
    /// sonraki üretimde yeniden kesilir, o zamana dek eskileri (ve yeniden çıkarılamayan video kareleri) yerinde kalır.
    /// Hiçbir fotoğraf okunamadıysa false; bu durumda hiçbir şey değişmez.
    private func addPhotos(_ items: [PhotosPickerItem]) async -> Bool {
        phase = "Fotoğraflar kaydediliyor…"
        defer { phase = nil }
        var sources: [ImportedSource] = []
        let existing = (episode.sourceDocumentIDs ?? []).count
        for (i, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let jpeg = await DeckAssets.sourceJPEG(data) else { continue }
            sources.append(ImportedSource(name: "Kitap sayfası \(existing + i + 1)", kind: .image(jpeg)))
        }
        photoItems = []
        guard !sources.isEmpty, episode.modelContext != nil else { return false }
        let ids = DocumentLibrary.persist(sources, context: context)
        episode.sourceDocumentIDs = (episode.sourceDocumentIDs ?? []) + ids
        if !ids.isEmpty { FigureExtractor.markStale(episode.directory) }
        try? context.save()
        return true
    }

    // MARK: - Görüntüleyici

    private func viewer(_ deck: Deck) -> some View {
        let language = episode.settings?.language.rawValue ?? "tr"
        return ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    Label("\(deck.slides.count) slayt", systemImage: "rectangle.stack").font(.subheadline.bold())
                    Spacer()
                    Menu {
                        ForEach(DeckPalette.allCases) { palette in
                            Button { paletteRaw = palette.rawValue; var value = deck; value.theme = palette.rawValue; saveDeck(value) } label: {
                                Label(palette.title, systemImage: deck.palette == palette ? "checkmark.circle.fill" : "circle")
                            }
                        }
                    } label: { Label(deck.palette.title, systemImage: "paintpalette") }
                    .disabled(phase != nil)
                }
                if let phase {
                    HStack { ProgressView(); Text(phase).font(.caption); Spacer(); Button("Durdur") { job?.cancel() }.disabled(job == nil) }
                }
                TabView(selection: $page) {
                    ForEach(Array(deck.slides.enumerated()), id: \.offset) { index, slide in
                        SlideCanvas(slide: slide, deck: deck, index: index, image: images[index],
                                    figure: figures.first { $0.id == slide.figureId },
                                    chapterTitle: DeckAssets.chapterTitle(for: slide, chapters: chapters, language: language))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(deck.palette.accent.opacity(0.15)))
                            .padding(.horizontal, 2).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // Slayt oranında: sabit yükseklik dar ekranda slaydın üstünde ve altında boşluk bırakıyordu.
                // Genişlik sınırı yatay tutuşta slaydın ekrana sığması için.
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: 420)

                HStack(spacing: 6) {
                    Button { page = max(0, page - 1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .disabled(page == 0).accessibilityLabel("Önceki slayt")
                    Text("\(page + 1) / \(deck.slides.count)").font(.subheadline.monospacedDigit().bold()).lineLimit(1).minimumScaleFactor(0.8)
                    Button { page = min(deck.slides.count - 1, page + 1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .disabled(page + 1 >= deck.slides.count).accessibilityLabel("Sonraki slayt")
                    Spacer()
                    Button { showOverview = true } label: { Image(systemName: "square.grid.2x2").frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .accessibilityLabel("Tüm slaytlar")
                    Button { showPresentation = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .accessibilityLabel("Tam ekran sun")
                }
                .tint(deck.palette.accent)
                thumbnailStrip(deck)

                if let slide = deck.slides[safe: page] {
                    HStack {
                        Label(slide.kindTitle, systemImage: "rectangle.on.rectangle").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Düzenle", systemImage: "pencil") { editingSlide = true }.font(.subheadline).disabled(phase != nil)
                    }
                    if let chapter = slide.chapterIndex, let start = chapters.first(where: { $0.id == chapter })?.start {
                        Button("Bu konuyu dinle", systemImage: "play.circle.fill") {
                            AppState.current?.player.load(episode, context: context, autoplay: false)
                            AppState.current?.player.seek(to: start)
                            AppState.current?.player.play()
                            dismiss()
                        }.buttonStyle(.bordered).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !slide.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Konuşmacı notu", systemImage: "text.alignleft").font(.caption.bold()).foregroundStyle(deck.palette.accent)
                            Text(slide.notes).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(16).background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
                    }
                    DeckIssuesBanner(episode: episode, deck: deck, page: page, select: { page = $0 })
                    DisclosureGroup("Slaydın tam metni") { Text(slide.readableText).font(.body).textSelection(.enabled).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading) }
                    imageControls(deck)
                }
                if let sourceNote {
                    Label(sourceNote, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                sourceStatus.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
    }

    private func thumbnailStrip(_ deck: Deck) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                // Tembel: 30+ slaytlık destede yalnız görünen küçük resimlerin tuvali kurulur.
                LazyHStack(spacing: 10) {
                    ForEach(Array(deck.slides.enumerated()), id: \.offset) { index, slide in
                        Button { page = index } label: {
                            VStack(spacing: 5) {
                                SlideCanvas(slide: slide, deck: deck, index: index, image: images[index])
                                    .frame(width: 104, height: 59).clipShape(RoundedRectangle(cornerRadius: 7))
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(index == page ? deck.palette.accent : Color.secondary.opacity(0.2), lineWidth: index == page ? 2 : 1))
                                Text("\(index + 1)").font(.caption2.monospacedDigit()).foregroundStyle(index == page ? deck.palette.accent : .secondary)
                            }
                        }.buttonStyle(.plain).id(index).accessibilityLabel("Slayt \(index + 1), \(slide.title)")
                    }
                }.padding(2)
            }.onChange(of: page) { _, value in withAnimation { proxy.scrollTo(value, anchor: .center) } }
        }
    }

    private func imageControls(_ deck: Deck) -> some View {
        let plan = DeckAssets.imagePlan(deck)
        let missing = plan.filter { images[$0.0] == nil }.count
        return VStack(alignment: .leading, spacing: 10) {
            if !plan.isEmpty {
                HStack {
                    Label(missing == 0 ? "Çizimler hazır" : "\(missing) çizim tamamlanabilir", systemImage: missing == 0 ? "checkmark.circle" : "photo.badge.plus")
                        .font(.subheadline.bold())
                    Spacer()
                    Menu(deck.illustrationStyle.title) {
                        ForEach(DeckIllustrationStyle.allCases) { style in
                            Button(style.title) { styleRaw = style.rawValue; var value = deck; value.imageStyle = style.rawValue; saveDeck(value) }
                        }
                    }.font(.caption).disabled(phase != nil)
                }
                if let failure = imageFailures[page] { Text(failure).font(.caption).foregroundStyle(.red) }
                // Yan yana sığmıyorsa (dar ekran, Kalın Yazı) alt alta: etiketler ikiye kırılmasın.
                ViewThatFits(in: .horizontal) {
                    HStack { imageButtons(missing: missing, planned: plan.contains { $0.0 == page }) }
                    VStack(alignment: .leading, spacing: 8) { imageButtons(missing: missing, planned: plan.contains { $0.0 == page }) }
                }.disabled(phase != nil)
                Text("Hazır görseller saklanır. Çizim tarzı, sonraki oluşturma ve yenileme işlemlerinde kullanılır.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func imageButtons(missing: Int, planned: Bool) -> some View {
        if missing > 0 { Button("Eksikleri tamamla") { startImages() }.buttonStyle(.borderedProminent) }
        if planned {
            Button(images[page] == nil ? "Bu görseli oluştur" : "Bu görseli yenile") { startImages(index: page, force: true) }.buttonStyle(.bordered)
        }
    }

    private func saveDeck(_ deck: Deck) {
        let old = episode.deck
        episode.deck = deck
        do { try context.save() } catch { episode.deck = old; self.error = "Değişiklik kaydedilemedi: \(error.localizedDescription)" }
    }

    private func startImages(index: Int? = nil, force: Bool = false) {
        guard job == nil, phase == nil, let deck = episode.deck else { return }
        job = Task {
            defer { job = nil; phase = nil }
            await generateImages(deck, index: index, force: force)
        }
    }

    private func generateImages(_ deck: Deck, index: Int? = nil, force: Bool = false) async {
        let jobs = DeckAssets.imagePlan(deck).filter { (index == nil || $0.0 == index) && (force || images[$0.0] == nil) }
        guard !jobs.isEmpty else { return }
        var completed = 0
        // İki çizim aynı anda; her başarı atomik saklanır. Yarım kalan deste yeniden açıldığında devam edebilir.
        for start in stride(from: 0, to: jobs.count, by: 2) {
            if abandoned { return }
            let chunk = Array(jobs[start..<min(start + 2, jobs.count)])
            phase = "Çizimler hazırlanıyor · \(completed)/\(jobs.count)"
            let results = await withTaskGroup(of: (Int, Data?, String?).self) { group in
                for (i, prompt) in chunk {
                    group.addTask {
                        do {
                            let data = try await DeckAssets.generateImage(prompt: prompt, aspect: deck.slides[i].kind == "bullets" ? "1:1" : "16:9", style: deck.illustrationStyle)
                            return (i, data, nil)
                        } catch is CancellationError { return (i, nil, nil) }
                        catch { return (i, nil, error.localizedDescription) }
                    }
                }
                var out: [(Int, Data?, String?)] = []
                for await result in group { out.append(result) }
                return out
            }
            if abandoned { return }
            for (i, data, failure) in results {
                completed += 1
                if let data {
                    do {
                        let url = episode.deckImageURL(i)
                        try data.write(to: url, options: .atomic)
                        images[i] = await DeckAssets.thumbnail(url)
                        imageFailures[i] = nil
                    } catch { imageFailures[i] = "Görsel kaydedilemedi. Yeniden deneyebilirsin." }
                } else if let failure { imageFailures[i] = failure }
            }
        }
        let failed = jobs.filter { imageFailures[$0.0] != nil }.count
        if failed > 0 { error = "\(failed) görsel tamamlanamadı. Hazır slaytlar ve görseller saklandı. Eksikleri tamamla ile devam edebilirsin." }
    }

    // MARK: - Üretim

    private func start() {
        guard job == nil, phase == nil else { return }
        job = Task {
            defer { job = nil }
            // Bekleyen fotoğraflar üretim onaylanınca kaydedilir; okunamazsa deste ve bekleyen seçim yerinde kalır.
            if !pendingPhotos.isEmpty {
                guard await addPhotos(pendingPhotos) else {
                    if !abandoned { error = "Seçilen fotoğraflar okunamadı. Deste değişmedi." }
                    return
                }
                pendingPhotos = []
            }
            await generate()
        }
    }

    /// Bölüm silindiyse ya da ekran kapandıysa üretim durur.
    private var abandoned: Bool { Task.isCancelled || episode.modelContext == nil }

    private func generate() async {
        guard let script = episode.script, let timeline = episode.timeline else { return }
        error = nil
        sourceNote = nil
        defer { phase = nil }
        let directory = episode.directory
        let imageURL: (Int) -> URL = { directory.appending(path: "deck_\($0).png") }
        // 1) Kaynaktaki şekil/tablo/fotoğraflar. Bir kez kesilir; yeni fotoğraf eklendiyse ya da önceki tarama eksik
        //    kaldıysa (işaret dosyası) yeniden kesilir. Video kareleri her durumda korunur.
        let existing = episode.sourceFigures
        var figures = existing
        // Eski deste eski belge şekillerine bağlıdır: yenileri ancak yeni deste kaydedilince onların yerine geçer.
        var pending: FigureExtractor.Extraction?
        if !(episode.sourceDocumentIDs ?? []).isEmpty,
           FigureExtractor.needsExtraction(existing: existing, stale: FigureExtractor.isStale(directory)) {
            phase = "Kaynaktaki görseller aranıyor…"
            do {
                let extraction = try await FigureExtractor.extract(episode, context: context) { p in
                    Task { @MainActor in phase = "Kaynaktaki görseller aranıyor \(min(p.done + 1, p.total))/\(p.total)…" }
                }
                if abandoned {
                    FigureExtractor.discard(extraction, in: directory)
                    return
                }
                figures = FigureExtractor.figures(after: extraction, existing: existing)
                sourceNote = FigureExtractor.note(for: extraction)
                if existing.contains(where: { !FigureExtractor.isVideoFrame($0.id) }) {
                    pending = extraction
                } else {
                    // Yerine geçilecek belge şekli yok: sonuç hemen kalıcıdır (deste isteği düşerse çıkarım yinelenmez).
                    FigureExtractor.commit(extraction, to: episode)
                }
            } catch {
                if abandoned { return }
                sourceNote = "Kaynak görselleri çıkarılamadı: \(error.localizedDescription)"
            }
        }
        if abandoned {
            dropPending(pending, in: directory)
            return
        }
        // 2) Deste içeriği
        phase = "Deste içeriği hazırlanıyor…"
        do {
            let used = DeckAssets.deckFigures(figures)
            let response = try await APIClient.shared.deck(DeckAssets.deckRequest(
                title: script.title, sourceNotes: script.sourceNotes, timeline: timeline, slideCount: slideCount,
                language: episode.settings?.language.rawValue ?? "tr", includeImages: includeImages, figures: used))
            if abandoned {
                dropPending(pending, in: directory)
                return
            }
            var deck = DeckReadability.prepare(DeckAssets.reconcile(response.deck, figures: used))
            deck.theme = paletteRaw
            deck.imageStyle = styleRaw
            deck.imageLevel = imageLevel
            let previousDeck = episode.deck
            let previousModel = episode.deckModel
            episode.deck = deck
            episode.deckModel = response.model
            do { try context.save() } catch {
                episode.deck = previousDeck
                episode.deckModel = previousModel
                throw error
            }
            if let extraction = pending {
                pending = nil
                FigureExtractor.commit(extraction, to: episode)
            }
            // Kırpma notu ancak deste kaydedilince yazılır: üretim düşerse eski destenin altında yanlış not kalmasın.
            if let note = DeckAssets.deckFiguresNote(all: figures, used: used) {
                sourceNote = [sourceNote, note].compactMap { $0 }.joined(separator: " ")
            }
            for index in 0..<max(64, previousDeck?.slides.count ?? 0) { try? FileManager.default.removeItem(at: imageURL(index)) }
            page = 0
            reconfiguring = false
            defaultsBeforeReconfigure = nil   // yeni deste bu ayarlarla kaydedildi: artık varsayılan bunlar
            await loadAssets()
            imageFailures = [:]
            await generateImages(deck)
        } catch {
            // Yeni deste kaydedilemedi: bu çıkarımın dosyaları silinir, eski şekiller ve eski deste olduğu gibi kalır.
            dropPending(pending, in: directory)
            if !abandoned { self.error = error.localizedDescription }
        }
    }

    /// Kalıcı yapılmayan çıkarımı geri alır (üretim hata verdi ya da durduruldu): dosyaları silinir, notu da düzeltilir
    /// ("bulunan şekiller kullanıldı" notu, şekilleri silinmiş bir çıkarım için eski destenin altında kalmasın).
    private func dropPending(_ pending: FigureExtractor.Extraction?, in directory: URL) {
        guard let pending else { return }
        FigureExtractor.discard(pending, in: directory)
        sourceNote = FigureExtractor.note(afterDiscarding: pending)
    }

    /// Görselleri diskten bir kez, küçültülmüş olarak yükler.
    private func loadAssets() async {
        chapters = episode.timeline?.chapters ?? []
        guard let deck = episode.deck else { return }
        let figures = episode.sourceFigures
        let directory = episode.directory   // döngüde modele dokunulmaz (yükleme sürerken bölüm silinebilir)
        self.figures = figures
        var loaded: [Int: UIImage] = [:]
        for (index, slide) in deck.slides.enumerated() {
            if let url = DeckAssets.imageURL(for: slide, index: index, directory: directory, figures: figures),
               let image = await DeckAssets.thumbnail(url) {
                loaded[index] = image
            }
        }
        images = loaded
    }

    // MARK: - Dışa aktarma

    private func exportPNG() async {
        guard phase == nil, let deck = episode.deck, let slide = deck.slides[safe: page] else { return }
        phase = "Slayt görseli hazırlanıyor…"
        defer { phase = nil }
        await Task.yield()
        let canvas = SlideCanvas(slide: slide, deck: deck, index: page, image: images[page],
                                 figure: figures.first { $0.id == slide.figureId },
                                 chapterTitle: DeckAssets.chapterTitle(for: slide, chapters: chapters, language: episode.settings?.language.rawValue ?? "tr"))
        let renderer = ImageRenderer(content: canvas.content.frame(width: 1280, height: 720))
        renderer.scale = 2
        guard let data = renderer.uiImage?.pngData() else { error = "Slayt görseli oluşturulamadı."; return }
        let url = URL.temporaryDirectory.appending(path: "\(fileName(deck.title))-\(page + 1).png")
        do { try data.write(to: url, options: .atomic); shareURL = url }
        catch { self.error = error.localizedDescription }
    }

    private func exportPDF() async {
        guard phase == nil, let deck = episode.deck else { return }
        phase = "PDF hazırlanıyor…"
        defer { phase = nil }
        let url = URL.temporaryDirectory.appending(path: "\(fileName(deck.title)).pdf")
        await Task.yield()   // ilerleme metni çizilsin
        let images = deck.slides.indices.map { self.images[$0] }
        let figures = deck.slides.map { slide in self.figures.first { $0.id == slide.figureId } }
        let language = episode.settings?.language.rawValue ?? "tr"
        let titles = deck.slides.map { DeckAssets.chapterTitle(for: $0, chapters: chapters, language: language) }
        do {
            try DeckPDF.render(deck: deck, images: images, figures: figures, chapterTitles: titles, to: url)
            shareURL = url
        } catch {
            self.error = "PDF oluşturulamadı: \(error.localizedDescription)"
        }
    }

    private func exportPPTX() async {
        guard phase == nil, let deck = episode.deck else { return }
        phase = "PowerPoint hazırlanıyor…"
        defer { phase = nil }
        // Küçültülmüş görseller JPEG olarak (istek boyutu makul kalsın).
        var payload: [String: DeckImagePayload] = [:]
        for (index, image) in images {
            if let data = await DeckAssets.jpeg(image) {
                payload[String(index)] = DeckImagePayload(data: data.base64EncodedString(), mimeType: "image/jpeg")
            }
        }
        do {
            // Tel biçimi `PPTXWireRequest`: sunucunun zorunlu tuttuğu null alanları yazar; deste sunucu sınırlarına uydurulur.
            let request = PPTXWireRequest(deck: PPTXWireDeck(DeckAssets.exportSafe(deck)), images: payload, theme: deck.palette.exportTheme)
            let response: DeckPPTXResponse = try await APIClient.shared.post("/v1/deck/pptx", request)
            guard let data = Data(base64Encoded: response.pptx) else {
                throw APIError(status: 0, code: "decode", message: "PowerPoint dosyası okunamadı.")
            }
            let url = URL.temporaryDirectory.appending(path: "\(fileName(deck.title)).pptx")
            try data.write(to: url)
            shareURL = url
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func fileName(_ s: String) -> String { String(s.map { "/\\:?%*|\"<>".contains($0) ? "-" : $0 }.prefix(60)) }
}

// MARK: - Slayt tuvali (1280×720 tasarım, ölçeklenir)

struct SlideCanvas: View {
    var slide: DeckSlide
    var deck: Deck
    var index: Int
    /// Üretilmiş görsel ya da kaynak şeklinin kırpılmış hali.
    var image: UIImage?
    var figure: SourceFigure? = nil
    var chapterTitle: String? = nil

    static let size = CGSize(width: 1280, height: 720)
    private var accent: Color { deck.palette.accent }

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / Self.size.width, geo.size.height / Self.size.height)
            content
                .frame(width: Self.size.width, height: Self.size.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: Self.size.width * scale, height: Self.size.height * scale, alignment: .topLeading)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slayt \(index + 1). " + slide.readableText)
    }

    /// Ölçeksiz içerik (PDF de bunu çizer).
    var content: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(isDark
                ? AnyShapeStyle(LinearGradient(colors: [accent, accent.opacity(0.84)], startPoint: .topLeading, endPoint: .bottomTrailing))
                : AnyShapeStyle(deck.palette.surface))
            if isDark {
                // Süs: yarı saydam büyük daireler
                Circle().fill(.white.opacity(0.08)).frame(width: 620).offset(x: 860, y: -180)
                Circle().fill(warm.opacity(0.35)).frame(width: 260).offset(x: 1080, y: 520)
            } else {
                Circle().fill(accent.opacity(0.05)).frame(width: 420).offset(x: 1040, y: -200)
            }
            switch slide.kind {
            case "section":
                VStack(alignment: .leading, spacing: 18) {
                    Spacer()
                    if let number = slide.chapterIndex {
                        Text(String(format: "%02d", number + 1)).font(.system(size: 120, weight: .black)).foregroundStyle(.white.opacity(0.35))
                    }
                    Text(slide.title).font(.system(size: 64, weight: .bold)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.6)
                    if let sub = slide.subtitle { Text(sub).font(.system(size: 30)).foregroundStyle(.white.opacity(0.85)) }
                    Spacer()
                }
                .padding(90)
            case "stat":
                VStack(spacing: 18) {
                    Spacer()
                    Text(slide.stat?.value ?? "").font(.system(size: 170, weight: .black)).foregroundStyle(accent).minimumScaleFactor(0.4).lineLimit(1)
                    Text(slide.stat?.label ?? slide.title).font(.system(size: 40, weight: .semibold)).multilineTextAlignment(.center)
                    if let context = slide.stat?.context { Text(context).font(.system(size: 26)).foregroundStyle(.gray).multilineTextAlignment(.center) }
                    Spacer()
                }
                .padding(.horizontal, 120)
                .frame(maxWidth: .infinity)
            case "title":
                VStack(alignment: .leading, spacing: 24) {
                    Spacer()
                    Text(deck.title).font(.system(size: 72, weight: .bold)).foregroundStyle(.white).lineLimit(4).minimumScaleFactor(0.55)
                    Text(deck.subtitle).font(.system(size: 34)).foregroundStyle(.white.opacity(0.9)).lineLimit(3).minimumScaleFactor(0.7)
                    Spacer()
                    Text("OKU  /  GÖRSEL DERS NOTLARI").tracking(2).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                }
                .padding(80)
            case "quote":
                VStack(spacing: 24) {
                    Spacer()
                    Text("“\(slide.quote ?? slide.title)”").font(.system(size: 48, weight: .medium).italic()).multilineTextAlignment(.center)
                    Text(slide.title).font(.system(size: 26)).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(100)
                .frame(maxWidth: .infinity)
            default:
                VStack(alignment: .leading, spacing: 26) {
                    if let chapterTitle, slide.kind != "agenda", slide.kind != "summary" {
                        // Büyük harfe çevirme `DeckAssets.chapterTitle` içinde, bölümün diline göre yapılır.
                        Text(chapterTitle).font(.system(size: 18, weight: .bold)).tracking(1.5)
                            .foregroundStyle(accent).padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Capsule().fill(accent.opacity(0.1)))
                    }
                    HStack {
                        Rectangle().fill(accent).frame(width: 10, height: 48)
                        Text(slide.title).font(.system(size: 46, weight: .bold)).lineLimit(2).minimumScaleFactor(0.6)
                    }
                    body(for: slide)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(.horizontal, 70)
                .padding(.top, 56)
                .padding(.bottom, 70)
            }
            footer
        }
        .clipped()
        .foregroundStyle(isDark ? .white : .black)
        .environment(\.colorScheme, .light)
    }

    private var isDark: Bool { slide.kind == "title" || slide.kind == "section" }
    private var warm: Color { deck.palette.secondary }

    private var footer: some View {
        VStack {
            Spacer()
            HStack {
                // Eski destelerde video karesi şekillerinden kalan `0` sayfası gösterilmez.
                let pages = slide.sourcePages.filter { $0 > 0 }
                if !pages.isEmpty, !isDark {
                    Text("Kaynak: s. " + pages.map(String.init).joined(separator: ", ")).font(.system(size: 18)).foregroundStyle(.gray).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer()
                Text("Ders Podcast · \(index + 1) / \(deck.slides.count)").font(.system(size: 18)).foregroundStyle(isDark ? .white.opacity(0.7) : .gray)
            }
            .padding(.horizontal, 70)
            .padding(.bottom, 26)
        }
    }

    @ViewBuilder
    private func body(for slide: DeckSlide) -> some View {
        switch slide.kind {
        case "table":
            if let table = slide.table { TableBlock(table: table, accent: accent) }
        case "chart":
            if let chart = slide.chart { ChartBlock(chart: chart, accent: accent, secondary: warm) }
        case "diagram":
            if let diagram = slide.diagram { DiagramBlock(diagram: diagram, accent: accent, secondary: warm) }
        case "agenda":
            let items = slide.bullets ?? []
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)], spacing: 20) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(spacing: 18) {
                        Text("\(i + 1)").font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 56, height: 56).background(Circle().fill(i % 2 == 0 ? accent : warm))
                        Text(item).font(.system(size: 28, weight: .medium)).lineLimit(2).minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.gray.opacity(0.07)))
                }
            }
        case "timeline":
            let items = slide.timeline ?? []
            VStack(spacing: 0) {
                Spacer()
                ZStack(alignment: .top) {
                    Rectangle().fill(accent.opacity(0.35)).frame(height: 6).padding(.top, 25)
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                            VStack(spacing: 10) {
                                Circle().fill(i % 2 == 0 ? accent : warm).frame(width: 56, height: 56)
                                    .overlay(Text(item.label).font(.system(size: 15, weight: .bold)).foregroundStyle(.white).minimumScaleFactor(0.5).padding(4))
                                Text(item.title).font(.system(size: 24, weight: .bold)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
                                Text(item.detail).font(.system(size: 18)).foregroundStyle(.gray).multilineTextAlignment(.center).lineLimit(4).minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                Spacer()
            }
        case "figure":
            FigureBlock(image: image, figure: figure, caption: slide.caption, bullets: [], accent: accent)
        case "twoColumn":
            HStack(alignment: .top, spacing: 44) {
                BulletBlock(bullets: slide.bullets ?? [], accent: accent, size: 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 18))
                            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                    } else {
                        RoundedRectangle(cornerRadius: 18).fill(accent.opacity(0.08))
                            .overlay(Image(systemName: "photo").font(.system(size: 70)).foregroundStyle(accent.opacity(0.4)))
                    }
                }
                .frame(maxWidth: 520, maxHeight: .infinity)
            }
        case "image":
            HStack(spacing: 40) {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 18))
                } else {
                    RoundedRectangle(cornerRadius: 18).fill(accent.opacity(0.06))
                        .overlay(VStack(spacing: 18) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 64))
                            Text("Çizim henüz hazır değil").font(.system(size: 26, weight: .semibold))
                        }.foregroundStyle(accent))
                }
                if let bullets = slide.bullets, !bullets.isEmpty { BulletBlock(bullets: bullets, accent: accent, size: 28).frame(width: 420) }
            }
        default:
            if let image, slide.kind == "bullets" {
                HStack(alignment: .center, spacing: 44) {
                    BulletBlock(bullets: slide.bullets ?? [], accent: accent, size: 30)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
                        .frame(width: 470, height: 440)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                }
            } else {
                BulletBlock(bullets: slide.bullets ?? [], accent: accent, size: slide.kind == "summary" ? 32 : 34)
            }
        }
    }
}

/// Kaynak şekli: iyileştirilmiş görsel + italik başlık + kaynak etiketi (+ yanında kısa maddeler).
private struct FigureBlock: View {
    var image: UIImage?
    var figure: SourceFigure?
    var caption: String?
    var bullets: [String]
    var accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 36) {
            VStack(alignment: .leading, spacing: 12) {
                if let image {
                    Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.25)))
                } else {
                    RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1))
                }
                HStack(spacing: 10) {
                    if let caption = caption ?? figure?.caption {
                        Text(caption).font(.system(size: 20).italic()).foregroundStyle(.gray).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if let figure {
                        Text(figure.sourceLabel).font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(accent).padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(accent.opacity(0.1)))
                    }
                }
            }
            if !bullets.isEmpty {
                BulletBlock(bullets: bullets, accent: accent, size: 26).frame(width: 380)
            }
        }
    }
}

private struct BulletBlock: View {
    var bullets: [String]
    var accent: Color
    var size: CGFloat

    /// Yazı, alana sığan en büyük boyutta çizilir (taşma yok); en küçükte satırlar kısaltılır.
    var body: some View {
        ViewThatFits(in: .vertical) {
            list(size, spacing: 0.6)
            list(size * 0.88, spacing: 0.5)
            list(size * 0.78, spacing: 0.45)
            list(size * 0.68, spacing: 0.4)
            list(size * 0.6, spacing: 0.35)
            list(size * 0.6, spacing: 0.3, limit: 2)
        }
    }

    private func list(_ size: CGFloat, spacing: CGFloat, limit: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: size * spacing) {
            ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                HStack(alignment: .firstTextBaseline, spacing: size * 0.55) {
                    Circle().fill(accent).frame(width: size * 0.42, height: size * 0.42)
                    Text(bullet).font(.system(size: size)).lineLimit(limit).fixedSize(horizontal: false, vertical: limit == nil)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TableBlock: View {
    var table: DeckTable
    var accent: Color

    var body: some View {
        // Çok satırlı/sütunlu tablolar küçülerek 720 px'e sığar.
        let rows = Array(table.rows.prefix(14))
        let headers = Array(table.headers.prefix(7))
        let dense = rows.count > 5 || headers.count > 5
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    Text(header).font(.system(size: dense ? 18 : 24, weight: .bold)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(dense ? 8 : 14).background(accent)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                GridRow {
                    ForEach(Array(headers.indices), id: \.self) { c in
                        Text(row[safe: c] ?? "").font(.system(size: dense ? 16 : 22)).lineLimit(dense ? 2 : 3).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(dense ? 6 : 12)
                            .background(r % 2 == 0 ? Color.gray.opacity(0.08) : Color.white)
                    }
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
    }
}

private struct ChartBlock: View {
    var chart: DeckChart
    var accent: Color
    var secondary: Color

    private struct Point: Identifiable { var id: String { series + label }; var series: String; var label: String; var value: Double }

    private var points: [Point] {
        chart.series.flatMap { s in zip(chart.labels, s.values).map { Point(series: s.name, label: $0, value: $1) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(chart.title + (chart.unit.map { " (\($0))" } ?? "")).font(.system(size: 26, weight: .semibold))
            Group {
                switch chart.type {
                case "pie":
                    Chart(points.filter { $0.series == chart.series.first?.name }) { p in
                        SectorMark(angle: .value(p.label, p.value), innerRadius: .ratio(0.45), angularInset: 2)
                            .foregroundStyle(by: .value("Etiket", p.label))
                            .annotation(position: .overlay) { Text(p.value.formatted()).font(.system(size: 18, weight: .bold)).foregroundStyle(.white) }
                    }
                case "line":
                    Chart(points) { p in
                        LineMark(x: .value("Etiket", p.label), y: .value(chart.unit ?? "Değer", p.value))
                            .foregroundStyle(by: .value("Seri", p.series)).symbol(by: .value("Seri", p.series))
                    }
                default:
                    Chart(points) { p in
                        BarMark(x: .value("Etiket", p.label), y: .value(chart.unit ?? "Değer", p.value))
                            .foregroundStyle(by: .value("Seri", p.series)).position(by: .value("Seri", p.series))
                            .annotation(position: .top) { Text(p.value.formatted()).font(.system(size: 16)) }
                    }
                }
            }
            .chartForegroundStyleScale(range: chart.series.count > 1 || chart.type == "pie"
                ? [accent, secondary, Color(red: 0.2, green: 0.7, blue: 0.6), .orange, .pink, .teal, .indigo, .mint]
                : [accent])
            .chartLegend(chart.series.count > 1 || chart.type == "pie" ? .visible : .hidden)
            .chartXAxis { AxisMarks { AxisValueLabel().font(.system(size: 18)) } }
            .chartYAxis { AxisMarks { AxisGridLine(); AxisValueLabel().font(.system(size: 16)) } }
        }
    }
}

private struct DiagramBlock: View {
    var diagram: DeckDiagram
    var accent: Color
    var secondary: Color

    var body: some View {
        GeometryReader { geo in
            let layout = DeckDiagramGeometry.make(layout: diagram.layout, count: diagram.nodes.count, size: geo.size)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for (a, b) in layout.edges {
                        let first = layout.boxes[a], last = layout.boxes[b]
                        let from = port(first, toward: CGPoint(x: last.midX, y: last.midY))
                        let to = port(last, toward: CGPoint(x: first.midX, y: first.midY))
                        var line = Path(); line.move(to: from); line.addLine(to: to)
                        context.stroke(line, with: .color(accent.opacity(0.65)), lineWidth: 3)
                        let angle = atan2(to.y - from.y, to.x - from.x)
                        var head = Path()
                        head.move(to: CGPoint(x: to.x - 12 * cos(angle - .pi / 6), y: to.y - 12 * sin(angle - .pi / 6)))
                        head.addLine(to: to)
                        head.addLine(to: CGPoint(x: to.x - 12 * cos(angle + .pi / 6), y: to.y - 12 * sin(angle + .pi / 6)))
                        context.stroke(head, with: .color(accent), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                }
                ForEach(Array(diagram.nodes.prefix(layout.boxes.count).enumerated()), id: \.offset) { i, original in
                    let box = layout.boxes[i]
                    let node = diagram.layout == "cycle" && layout.boxes.count > 4 ? DeckDiagram.Node(title: original.title, detail: "") : original
                    NodeBox(node: node, accent: accent, secondary: secondary, width: box.width,
                            filled: diagram.layout == "hierarchy" && i == 0,
                            number: diagram.layout == "steps" || diagram.layout == "cycle" ? i + 1 : nil,
                            large: layout.boxes.count <= 4 && diagram.layout != "cycle",
                            compact: diagram.layout == "cycle", header: diagram.layout == "compare", tint: i % 2 == 0)
                        .frame(width: box.width, height: box.height).clipped()
                        .position(x: box.midX, y: box.midY)
                }
            }
        }
    }

    private func port(_ box: CGRect, toward point: CGPoint) -> CGPoint {
        let dx = point.x - box.midX, dy = point.y - box.midY
        let t = min(box.width / (2 * max(abs(dx), 0.01)), box.height / (2 * max(abs(dy), 0.01)))
        return CGPoint(x: box.midX + dx * t, y: box.midY + dy * t)
    }
}

private struct NodeBox: View {
    var node: DeckDiagram.Node
    var accent: Color
    var secondary: Color
    var width: CGFloat?
    var filled = false
    var number: Int?
    /// Az kart varken daha büyük yazı.
    var large = false
    /// Döngüde kartlar küçük tutulur.
    var compact = false
    /// Karşılaştırma: başlık renkli şeritte.
    var header = false
    var tint = true

    private var titleSize: CGFloat { compact ? 21 : large ? 32 : 25 }
    private var detailSize: CGFloat { compact ? 16 : large ? 25 : 20 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                if let number {
                    Text("\(number)").font(.system(size: titleSize * 0.75, weight: .bold)).foregroundStyle(.white)
                        .frame(width: titleSize * 1.35, height: titleSize * 1.35)
                        .background(Circle().fill(filled ? Color.white.opacity(0.3) : accent))
                }
                // Kelime bölünmesin: iki satıra sığmazsa yazı küçülür.
                Text(node.title).font(.system(size: titleSize, weight: .bold)).lineLimit(2).minimumScaleFactor(0.55)
                    .foregroundStyle(header ? .white : (filled ? .white : .black))
            }
            .padding(header ? 14 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(header ? AnyShapeStyle(tint ? accent : secondary) : AnyShapeStyle(Color.clear),
                        in: UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
            if !node.detail.isEmpty {
                Text(node.detail).font(.system(size: detailSize)).lineLimit(compact ? 3 : 6).minimumScaleFactor(0.6)
                    .padding(.horizontal, header ? 14 : 0)
            }
            Spacer(minLength: 0)
        }
        .padding(header ? 0 : (compact ? 10 : 16))
        .padding(.bottom, header ? 14 : 0)
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16).fill(filled ? accent : (header ? Color.white : accent.opacity(0.08))))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(header ? 0.25 : 0.45), lineWidth: 2))
        .foregroundStyle(filled ? .white : .black)
    }
}

// MARK: - PDF

enum DeckPDF {
    /// Her slayt 1280×720 noktalık bir PDF sayfası (vektörel metin ve grafikler).
    static func render(deck: Deck, images: [UIImage?], figures: [SourceFigure?] = [], chapterTitles: [String?] = [], to url: URL) throws {
        var box = CGRect(origin: .zero, size: SlideCanvas.size)
        guard let consumer = CGDataConsumer(url: url as CFURL), let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        for (index, slide) in deck.slides.enumerated() {
            let view = SlideCanvas(slide: slide, deck: deck, index: index, image: images[safe: index] ?? nil,
                                   figure: figures[safe: index] ?? nil, chapterTitle: chapterTitles[safe: index] ?? nil).content
                .frame(width: SlideCanvas.size.width, height: SlideCanvas.size.height)
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(SlideCanvas.size)
            renderer.render { _, draw in
                pdf.beginPDFPage(nil)
                draw(pdf)
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()
    }
}

/// Slayt görselleri: kaynak şekli (figureId) varsa onun iyileştirilmiş kırpımı, yoksa üretilmiş görsel.
enum DeckAssets {
    static func imageURL(for slide: DeckSlide, index: Int, episode: Episode, figures: [SourceFigure]) -> URL? {
        imageURL(for: slide, index: index, directory: episode.directory, figures: figures)
    }

    /// Modele dokunmayan biçim (dosya adları `Episode.figureURL` / `deckImageURL` ile aynı): uzun işlerde bölüm klasörü
    /// baştan alınır, iş sürerken bölüm silinse de modele bir daha dokunulmaz.
    nonisolated static func imageURL(for slide: DeckSlide, index: Int, directory: URL, figures: [SourceFigure]) -> URL? {
        if let id = slide.figureId, figures.contains(where: { $0.id == id }) {
            let url = FigureExtractor.figureFile(id, in: directory)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        let url = directory.appending(path: "deck_\(index).png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Slayt için çizim istemi; görsel gerekmiyorsa nil.
    /// Bol modda madde slaytlarına da konuyu anlatan bir çizim eklenir (yazısız, sunucu "no text" ekler).
    static func imagePrompt(for slide: DeckSlide, deck: Deck, level: Int) -> String? {
        guard level > 0, slide.figureId == nil else { return nil }
        let scene: String
        if slide.kind == "image" || slide.kind == "twoColumn" {
            guard let prompt = slide.imagePrompt else { return nil }
            scene = prompt
        } else {
            guard level >= 2, slide.kind == "bullets", let bullets = slide.bullets, !bullets.isEmpty else { return nil }
            scene = "Konu: \(slide.title). Gösterilecekler: \(bullets.prefix(3).joined(separator: "; "))"
        }
        return wrapPrompt(scene, style: deck.illustrationStyle)
    }

    /// Görsel modeline sahne tarifi + sıkı kurallar. Yazı istenmez: üretilen harfler sık sık bozuk ya da İngilizce çıkar;
    /// etiketler zaten slayt maddelerinde. (Deste başlığı istemde yer almaz; model onu resme yazıyordu.)
    static func wrapPrompt(_ scene: String, strict: Bool = false, style: DeckIllustrationStyle = .textbook) -> String {
        let rules = "Bilimsel olarak doğru eğitim illüstrasyonu. \(style.direction) Yapıları ve oranları koru; uydurma parça ekleme. Görselde yazı, harf, rakam, etiket, başlık, filigran YOK (no text, no letters, no labels, no captions)."
        let hard = strict ? " Önceki denemede yazı vardı. Bu kez SIFIR yazı." : ""
        let prefix = "\(rules)\(hard)\nSahne: "
        return prefix + scene.prefix(max(0, 800 - prefix.count))
    }

    static func imagePlan(_ deck: Deck) -> [(Int, String)] {
        let candidates = deck.slides.enumerated().compactMap { index, slide -> (Int, String)? in
            let level = deck.imageLevel ?? 1
            return imagePrompt(for: slide, deck: deck, level: level).map { (index, $0) }
        }
        // Asıl görsel slaytları, isteğe bağlı madde çizimlerinden önce gelir.
        let required = candidates.filter { deck.slides[$0.0].kind != "bullets" }
        let optional = candidates.filter { deck.slides[$0.0].kind == "bullets" }
        return Array((required + optional).prefix(12)).sorted { $0.0 < $1.0 }
    }

    /// Ağ/çözümleme hataları görünürdür. İptal ikinci isteği başlatmaz; eski başarılı görsel değişmez.
    static func generateImage(prompt: String, aspect: String, style: DeckIllustrationStyle) async throws -> Data {
        let scene = String(prompt.components(separatedBy: "Sahne: ").last ?? prompt)
        for attempt in 0..<2 {
            try Task.checkCancellation()
            let text = attempt == 0 ? prompt : wrapPrompt(scene, strict: true, style: style)
            let result = try await APIClient.shared.deckImage(DeckImageRequest(prompt: text, aspect: aspect))
            try Task.checkCancellation()
            guard let data = Data(base64Encoded: result.image), let image = UIImage(data: data),
                  image.size.width > 0, image.size.height > 0, let png = image.pngData() else {
                throw APIError(status: 0, code: "decode", message: "Görsel verisi okunamadı. Yeniden deneyebilirsin.")
            }
            if await !containsText(data) { return png }
        }
        throw APIError(status: 0, code: "image_text", message: "Çizimde istenmeyen yazılar algılandı. Yeniden oluşturabilirsin.")
    }

    /// Görselde okunabilir yazı var mı? (Cihazda OCR; bozuk ya da İngilizce etiketli görseller slayta girmesin.)
    @concurrent
    static func containsText(_ data: Data) async -> Bool {
        guard let cg = UIImage(data: data)?.cgImage else { return false }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["tr-TR", "en-US"]
        request.usesLanguageCorrection = false
        do { try VNImageRequestHandler(cgImage: cg, orientation: .up).perform([request]) }
        catch { return true } // Denetlenemeyen görüntü yazısız kabul edilmez.
        let letters = (request.results ?? []).compactMap { $0.topCandidates(1).first }
            .filter { $0.confidence > 0.3 }
            .map { $0.string.filter(\.isLetter).count }
            .reduce(0, +)
        return letters >= 4
    }

    /// Yazı denetimli üretim: yazı çıkarsa sıkı istemle bir kez daha dener; yine çıkarsa nil (slayt görselsiz kalır).
    static func reliableImage(prompt: String, aspect: String) async -> Data? {
        let scene = String(prompt.components(separatedBy: "Sahne: ").last ?? prompt)
        for attempt in 0..<2 {
            let text = attempt == 0 ? prompt : wrapPrompt(scene, strict: true)
            guard let result = try? await APIClient.shared.deckImage(DeckImageRequest(prompt: text, aspect: aspect)),
                  let data = Data(base64Encoded: result.image) else { continue }
            if await !containsText(data) { return data }
        }
        return nil
    }

    /// Slayttaki bölüm etiketi: bölüm başlığı, bölümün diline göre büyük harfle (tuval gelen metni olduğu gibi basar).
    static func chapterTitle(for slide: DeckSlide, episode: Episode) -> String? {
        chapterTitle(for: slide, chapters: episode.timeline?.chapters ?? [], language: episode.settings?.language.rawValue ?? "tr")
    }

    /// Saf biçim: bölümler bir kez okunup verilir (görüntüleyici, PDF ve video her slayt için zaman çizelgesini yeniden okumasın).
    nonisolated static func chapterTitle(for slide: DeckSlide, chapters: [TimedChapter], language: String) -> String? {
        guard let index = slide.chapterIndex, let title = chapters.first(where: { $0.id == index })?.title else { return nil }
        return chapterBadge(title, language: language)
    }

    /// Sunucu destesini kaynak şekillerle uzlaştırır:
    /// - bilinmeyen şekil kimliği temizlenir (şekil slaytı madde slaytına döner ya da çıkarılır);
    /// - tablo şekilleri, okunan içerikle düzenli tablo slaytına çevrilir.
    static func reconcile(_ deck: Deck, figures: [SourceFigure]) -> Deck {
        var deck = deck
        var consumed = Set<String>()   // tabloya çevrilen şekiller
        deck.slides = deck.slides.compactMap { original in
            var slide = original
            guard let id = slide.figureId else { return slide }
            guard let figure = figures.first(where: { $0.id == id }) else {
                slide.figureId = nil
                if slide.kind == "figure" {
                    guard let bullets = slide.bullets, !bullets.isEmpty else { return nil }
                    slide.kind = "bullets"
                }
                return slide
            }
            if slide.kind == "figure", let bullets = slide.bullets, !bullets.isEmpty {
                // Şekil slaytında fotoğraf büyük kalsın; maddeler konuşmacı notuna taşınır (sunucunun not sınırı 1500).
                slide.notes = ServerText.prefix(([slide.notes] + bullets.map { "• " + $0 }).filter { !$0.isEmpty }.joined(separator: "\n"), 1500)
                slide.bullets = nil
            }
            if slide.kind == "figure", figure.kind == "table", var table = figure.table, !table.headers.isEmpty {
                table.rows = Array(table.rows.prefix(14))
                consumed.insert(id)
                slide.kind = "table"
                slide.table = table
                slide.figureId = nil
                if slide.sourcePages.isEmpty, figure.page > 0 { slide.sourcePages = [figure.page] }
            }
            return slide
        }
        // Destede kullanılmayan her kaynak şekli kendi slaytına konur (özet slaytından önce).
        let used = Set(deck.slides.compactMap(\.figureId)).union(consumed)
        let extra = figures.filter { !used.contains($0.id) }
            .map { figure -> DeckSlide in
                // Başlık sınırı 150 (şekil başlığı 200'e kadar gelir); video karelerinde sayfa yoktur (`page` 0).
                let title = ServerText.prefix(figure.caption, 150)
                let pages: [Int] = figure.page > 0 ? [figure.page] : []
                if figure.kind == "table", var table = figure.table, !table.headers.isEmpty {
                    table.rows = Array(table.rows.prefix(14))
                    return DeckSlide(kind: "table", title: title.isEmpty ? "Tablo" : title, chapterIndex: nil,
                                     sourcePages: pages, notes: "", table: table)
                }
                return DeckSlide(kind: "figure", title: title.isEmpty ? "Kaynaktan görsel" : title, chapterIndex: nil,
                                 sourcePages: pages, notes: "", figureId: figure.id, caption: figure.caption)
            }
        if !extra.isEmpty {
            let insertAt = deck.slides.lastIndex { $0.kind == "summary" } ?? deck.slides.endIndex
            deck.slides.insert(contentsOf: extra, at: insertAt)
        }
        return deck
    }

    /// En uzun kenarı 1600 px'e küçültülmüş görsel (1280×720 slayt için yeterli).
    @concurrent
    static func thumbnail(_ url: URL) async -> UIImage? {
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        let longest = max(image.size.width, image.size.height) * image.scale
        guard longest > 1600 else { return image }
        let ratio = 1600 / longest
        return await image.byPreparingThumbnail(ofSize: CGSize(width: image.size.width * image.scale * ratio,
                                                              height: image.size.height * image.scale * ratio)) ?? image
    }

    @concurrent
    static func jpeg(_ image: UIImage) async -> Data? { image.jpegData(compressionQuality: 0.85) }

    /// Seçilen fotoğraf → kaynak belge olarak saklanacak JPEG (en uzun kenar 4200 px). Yeniden çizim ve kodlama
    /// fotoğraf başına yarım saniyeyi bulur; ana iş parçacığı dışında yapılır.
    @concurrent
    static func sourceJPEG(_ data: Data) async -> Data? {
        UIImage(data: data)?.normalizedUp(maxSide: 4200).jpegData(compressionQuality: 0.92)
    }
}
