import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// YouTube Ders Stüdyosu: bağlantı → önizleme → seçenekler → sunucu işi → VideoLesson.
/// Oynatma listesinde seçilen videolar sırayla aynı akışla işlenir.
struct YouTubeImportView: View {
    var onFinish: (VideoLesson) -> Void
    /// Oynatma listesi işlendiğinde oluşan derslerin tümünü birden alan çağıran (ör. podcast kaynağına ekleme).
    /// Verilmezse özet ekranında dersler tek tek açılır.
    var onFinishBatch: (([VideoLesson]) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Query private var lessons: [VideoLesson]
    @Query(sort: \Course.createdAt) private var courses: [Course]

    @State private var link: String
    @State private var info: YouTubeInfoResponse?
    /// `info`'nun ait olduğu bağlantı: alan değişince eski videonun önizlemesi ve Başlat'ı ekranda kalmaz.
    @State private var infoLink: String?
    @State private var infoLoading = false
    @State private var infoError: String?

    // Seçenekler
    @State private var mode: TranscriptMode = .auto
    @State private var captionLanguage = ""          // "" = otomatik seçim
    @State private var translate = false
    @State private var useRange = false
    @State private var rangeStart = ""
    @State private var rangeEnd = ""
    @State private var keyframes = true
    @State private var notes = true
    @State private var selectedEntries: Set<String> = []
    /// "Bu siteyi dene": izinli listede olmayan https adresine kullanıcı onayı.
    @State private var allowOther = false
    /// Çok bağlantılı kuyrukta elle çıkarılanlar.
    @State private var excludedLinks: Set<String> = []
    /// Oynatma listesi işlenince "Derslerim"de ders oluştur/eşle.
    @State private var createCourse = true
    // Sınıf kaydı
    @State private var recording: RecordingDraft?
    @State private var showFilePicker = false
    @State private var pickError: String?
    @State private var duplicateLesson: VideoLesson?

    // Çalışma
    @State private var run: RunState?
    @State private var worker: Task<Void, Never>?
    @State private var runError: String?
    @State private var notice: String?
    @State private var summary: BatchSummary?
    @State private var pending: [PendingYouTubeJob] = []
    /// Takip edilen sunucu işi; durdurulur ya da ekrandan çıkılırsa sunucuda da iptal edilir ("Arka planda sürdür" dışında).
    @State private var activeJobId: String?
    /// Durdurulmadan önce bitip kaydedilen ders sayısı (iptal sonucuyla birlikte bildirilir).
    @State private var savedBeforeStop = 0
    @State private var confirmClose = false
    /// "Arka planda sürdür" seçildi: ekrandan çıkış sunucudaki işi iptal etmez.
    @State private var detached = false
    /// Süren iş videoları bir derse (Derslerim) bağlıyor: arka plana bırakılan video sonradan alınınca bağlanmaz, onayda söylenir.
    @State private var linksCourse = false
    /// Sunucudaki iş bitti, ders kaydediliyor (iş kimliği bırakılmıştır): kapatma onayı bunu "henüz başlamadı" diye anlatmasın.
    @State private var saving = false

    init(initialURL: String? = nil, onFinish: @escaping (VideoLesson) -> Void,
         onFinishBatch: (([VideoLesson]) -> Void)? = nil) {
        self.onFinish = onFinish
        self.onFinishBatch = onFinishBatch
        _link = State(initialValue: initialURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }

    struct RunState {
        var title: String
        var index: Int
        var total: Int
        var progress: Double = 0
        var step = "Başlatılıyor"
    }

    struct BatchFailure: Identifiable {
        let id = UUID()
        var title: String
        var message: String
    }

    struct BatchSummary {
        var lessons: [VideoLesson]
        var failures: [BatchFailure]
        var courseName: String?
    }

    private struct WorkItem: Sendable {
        var url: String
        var title: String
    }

    private var trimmedLink: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Yapıştırılan metindeki bağlantılar (başlık gibi artık metinler atılır).
    private var links: [String] { ImportLinks.parse(link) }
    /// İki ya da daha fazla bağlantı: toplu kuyruk.
    private var isBatch: Bool { links.count >= 2 }
    /// Tek bağlantı modunda işlenen bağlantı.
    private var singleLink: String { links.first ?? trimmedLink }
    private var lessonKeys: [LessonKey] { lessons.map { LessonKey(id: $0.id, videoID: $0.videoID, url: $0.url) } }
    private var batchEntries: [ImportBatch.Entry] { ImportBatch.plan(links: links, existing: lessonKeys, allowOther: allowOther) }
    private var closeChoice: (canDetach: Bool, message: String) {
        YouTubeImportLogic.closeChoice(hasActiveJob: activeJobId != nil, index: run?.index ?? 1, total: run?.total ?? 1,
                                       linksCourse: linksCourse, saving: saving)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let run {
                    runningSection(run)
                } else if let summary {
                    summarySection(summary)
                } else {
                    linkSection
                    if let notice {
                        Section {
                            Label(notice, systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !pending.isEmpty { pendingSection }
                    if let recording {
                        recordingSection(recording)
                    } else if isBatch {
                        batchSection
                        commonOptions(translateDefaultHint: nil)
                        let ready = ImportBatch.runnable(batchEntries, excluded: excludedLinks).count
                        startSection(canStart: ready > 0,
                                     footer: "\(ready) video sırayla işlenir; hata veren atlanır, sonda özet gösterilir.")
                    } else if let video = info?.video, info?.isPlaylist != true {
                        videoPreview(video)
                        videoOptions(video)
                        startSection(canStart: canStartVideo(video), footer: estimate(for: video))
                    } else if let playlist = info?.playlist {
                        playlistSection(playlist)
                        Section {
                            Toggle("Derslerim’de ders oluştur", isOn: $createCourse)
                        } footer: {
                            Text(createCourse ? "‘\(PlaylistCourse.name(from: playlist.title))’ dersi oluşturulur (varsa eşlenir); videolar liste sırasıyla bu derse bağlanır."
                                              : "Videolar derse bağlanmadan kütüphaneye eklenir.")
                        }
                        commonOptions(translateDefaultHint: nil)
                        startSection(canStart: !selectedEntries.isEmpty,
                                     footer: "Seçilen \(selectedEntries.count) video sırayla işlenir; hata veren atlanır, sonda özet gösterilir.")
                    }
                }
            }
            .navigationTitle("YouTube Ders Stüdyosu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Süren iş onaysız kapatılmaz: durdurmak işi sunucuda da iptal eder (dakikalar süren döküm tek dokunuşla gitmesin).
                    // Zaten durduruluyorsa sorulacak bir şey yok.
                    Button("Kapat") {
                        if run != nil, worker?.isCancelled != true { confirmClose = true } else { stop(); dismiss() }
                    }
                }
            }
            .confirmationDialog("İşlem sürüyor", isPresented: $confirmClose, titleVisibility: .visible) {
                if closeChoice.canDetach { Button("Arka planda sürdür") { detachAndClose() } }
                Button("Durdur ve kapat", role: .destructive) { stop(); dismiss() }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text(closeChoice.message)
            }
            .task(id: "\(trimmedLink)|\(allowOther)") { await linkChanged() }
            .onChange(of: trimmedLink) { _, _ in
                // Yeni bağlantı: onaylar ve çıkarılanlar sıfırlanır.
                allowOther = false
                excludedLinks = []
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.audio, .movie, .mpeg4Audio, .mpeg4Movie, .quickTimeMovie],
                          allowsMultipleSelection: false) { result in
                pickRecording(result)
            }
            .alert("Bu video zaten kütüphanende", isPresented: Binding(get: { duplicateLesson != nil }, set: { if !$0 { duplicateLesson = nil } })) {
                Button("Mevcut dersi aç") {
                    if let lesson = duplicateLesson { duplicateLesson = nil; onFinish(lesson) }
                }
                Button("Yine de yeniden işle") { duplicateLesson = nil; start(ignoringDuplicate: true) }
                Button("Vazgeç", role: .cancel) { duplicateLesson = nil }
            } message: {
                Text(duplicateLesson?.title ?? "")
            }
            .onAppear {
                pending = YouTubePendingJobs.all
                consumePendingLinks()
                #if DEBUG
                startRunDemoIfRequested()
                #endif
            }
            // Kısayollar'dan gelen bağlantılar (ikinci paylaşım dahil) açık ekrana eklenir; iş sürüyorsa bitince alınır.
            .onChange(of: app.pendingImportLinks) { _, _ in consumePendingLinks() }
            .onChange(of: run == nil) { _, idle in
                guard idle else { return }
                confirmClose = false
                consumePendingLinks()
            }
            .onDisappear {
                stop()
                // Çalışan kayıt işi kendi `defer`'iyle temizler; yalnız seçilmiş (başlamamış) kayıt burada bırakılır.
                if worker == nil { discardRecording() }
                UIApplication.shared.isIdleTimerDisabled = false
            }
            .interactiveDismissDisabled(run != nil)
            .animation(.smooth, value: run == nil)
        }
    }

    // MARK: - Bağlantı

    private var linkSection: some View {
        Section {
            TextField("https://youtube.com/watch?v=…", text: $link, axis: .vertical)
                .lineLimit(1...5)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Panodan yapıştır", systemImage: "doc.on.clipboard") {
                if let pasted = UIPasteboard.general.string { link = pasted.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            if recording == nil && run == nil {
                Button("Sınıf kaydı yükle (ses/video dosyası)", systemImage: "waveform.badge.plus") { showFilePicker = true }
            }
            if infoLoading {
                HStack(spacing: 8) { ProgressView(); Text("Video bilgisi alınıyor…").foregroundStyle(.secondary) }
            }
            if let infoError {
                Label(infoError, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                if !isBatch, ImportLinks.classify(singleLink) != .invalid {
                    Button("Tekrar dene", systemImage: "arrow.clockwise") { Task { await loadInfo(singleLink) } }
                }
            }
            if let pickError {
                Label(pickError, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            if !isBatch, recording == nil, case .other(let host) = ImportLinks.classify(singleLink), !allowOther {
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(host) izinli site listesinde değil.", systemImage: "globe").font(.subheadline.weight(.semibold))
                    Text("Sunucu bağlantıyı açmayı deneyebilir; her sitede çalışmaz. Bu videolar uygulamada yalnızca ses olarak dinlenir.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Bu siteyi dene", systemImage: "arrow.right.circle") { allowOther = true }
                        .buttonStyle(.bordered)
                }
            }
        } header: {
            Text("Video veya oynatma listesi bağlantısı")
        } footer: {
            if info == nil && infoError == nil && !infoLoading && recording == nil {
                Text("YouTube, Vimeo, Dailymotion bağlantısı (birden çoksa her satıra bir tane yapıştır — sırayla işlenir) ya da bir sınıf kaydı: transkript, bölümler, ders notu ve tahta/slayt kareleri hazırlanır.")
            }
        }
    }

    /// `AppState.pendingImportLinks` içindeki bağlantıları mevcut metne ekler (tekrarsız) ve gelen kutusunu boşaltır.
    private func consumePendingLinks() {
        guard let incoming = app.pendingImportLinks, !incoming.isEmpty, run == nil, worker == nil, recording == nil else { return }
        app.pendingImportLinks = nil
        clearPreview()
        summary = nil
        link = ImportLinks.parse(ImportInbox.merge(link, incoming)).joined(separator: "\n")
    }

    // MARK: - Toplu kuyruk (#3)

    private var batchSection: some View {
        Section {
            ForEach(batchEntries) { entry in
                HStack(alignment: .top, spacing: 10) {
                    let excluded = excludedLinks.contains(entry.link)
                    Image(systemName: icon(for: entry.status, excluded: excluded))
                        .foregroundStyle(color(for: entry.status, excluded: excluded))
                        .frame(width: 24)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ImportLinks.shortName(entry.link)).font(.subheadline).lineLimit(2).strikethrough(excluded)
                        if let note = note(for: entry.status) {
                            Text(note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard entry.status == .ready else { return }
                    if excludedLinks.contains(entry.link) { excludedLinks.remove(entry.link) } else { excludedLinks.insert(entry.link) }
                }
            }
            if batchEntries.contains(where: { $0.status == .needsApproval }) {
                Toggle("İzinli listede olmayan siteleri de dene", isOn: $allowOther)
            }
        } header: {
            Text("\(links.count) bağlantı")
        } footer: {
            Text("Bir satıra dokunarak kuyruktan çıkarabilirsin. Kütüphanede olanlar atlanır.")
        }
    }

    private func icon(for status: ImportBatch.Status, excluded: Bool) -> String {
        if excluded { return "minus.circle" }
        switch status {
        case .ready: return "checkmark.circle.fill"
        case .duplicate: return "books.vertical"
        case .needsApproval: return "questionmark.circle"
        case .rejected: return "xmark.octagon"
        }
    }

    private func color(for status: ImportBatch.Status, excluded: Bool) -> Color {
        if excluded { return .secondary }
        switch status {
        case .ready: return .green
        case .duplicate: return .blue
        case .needsApproval: return .orange
        case .rejected: return .red
        }
    }

    private func note(for status: ImportBatch.Status) -> String? {
        switch status {
        case .ready: nil
        case .duplicate: "Zaten kütüphanende — atlanır"
        case .needsApproval: "İzinli listede değil — onay gerekir"
        case .rejected: "Geçersiz ya da güvenli olmayan (http) bağlantı"
        }
    }

    // MARK: - Sınıf kaydı (#4)

    private func recordingSection(_ draft: RecordingDraft) -> some View {
        Group {
            Section {
                LabeledContent("Dosya", value: draft.name)
                LabeledContent("Boyut", value: ByteFormat.string(draft.bytes))
                if draft.duration > 0 { LabeledContent("Süre", value: VideoTime.string(draft.duration)) }
                TextField("Başlık", text: Binding(get: { recording?.title ?? "" }, set: { recording?.title = $0 }))
                Button("Vazgeç", systemImage: "xmark.circle", role: .destructive) {
                    discardRecording()
                }
            } header: {
                Text("Sınıf kaydı")
            } footer: {
                Text(recordingFootnote(draft))
            }
            commonOptions(translateDefaultHint: nil)
            startSection(canStart: !draft.tooLarge && !draft.title.trimmingCharacters(in: .whitespaces).isEmpty,
                         footer: "Kayıt yapay zekâ ile yazıya dökülür; dönüştürme ve yükleme sırasında ekranı açık tut.",
                         action: startRecording)
        }
    }

    private func recordingFootnote(_ draft: RecordingDraft) -> String {
        if draft.tooLarge { return "Dosya sunucunun 500 MB sınırını aşıyor." }
        let plan = draft.plan
        if plan.uploadVideo { return "Video olduğu gibi yüklenir (kareler çıkarılabilir); ses ayrıca cihazda dersin çevrimdışı sesi olarak hazırlanır." }
        if draft.isVideo { return "Video çok büyük: yalnız sesi cihazda AAC 48 kbps mono’ya dönüştürülüp yüklenir; kare çıkarılmaz." }
        if plan.convertToAAC { return "Dosya cihazda AAC 48 kbps mono’ya dönüştürülür (yaklaşık saatte 22 MB), sonra yüklenir." }
        return "Dosya olduğu gibi yüklenir."
    }

    /// Seçili (başlamamış) kaydı bırakır: dosya erişimi kapanır, varsa geçici ses silinir.
    private func discardRecording() {
        guard let draft = recording else { return }
        draft.release()
        UploadStash.remove(uploadID: draft.id)
        recording = nil
    }

    private func pickRecording(_ result: Result<[URL], Error>) {
        pickError = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard var draft = RecordingDraft(url: url) else {
                pickError = "Dosya okunamadı ya da boş."
                return
            }
            discardRecording()
            clearPreview()
            infoError = nil
            link = ""
            let id = draft.id
            recording = draft
            Task {
                let seconds = await AudioConverter.duration(of: url)
                if recording?.id == id { draft.duration = seconds; recording?.duration = seconds }
            }
        case .failure(let error):
            pickError = error.localizedDescription
        }
    }

    private var pendingSection: some View {
        Section {
            ForEach(pending) { job in
                Button {
                    resume(job)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.title.isEmpty ? job.url : job.title).lineLimit(2)
                            Text("Başladı: \(job.startedAt.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Sonucu al").font(.subheadline.weight(.semibold))
                    }
                }
            }
            .onDelete { offsets in
                // Listeden silinen iş sunucuda da durdurulur (sürüyorsa kota/kuyruk boşa gitmesin).
                let ids = offsets.map { pending[$0].jobId }
                for id in ids {
                    LessonImporter.discardStash(for: id)
                    LessonImporter.forget(id)
                    Task { _ = await Self.cancelOnServer(id) }
                }
                pending = YouTubePendingJobs.all
            }
        } header: {
            Text("Yarım kalan işlemler")
        } footer: {
            Text("Uygulama kapanırsa iş sunucuda sürer; sonuç bittikten sonra 2 saat saklanır. Sola kaydırıp silersen iş sunucuda da durdurulur.")
        }
    }

    // MARK: - Video önizleme ve seçenekler

    private func videoPreview(_ video: VideoInfo) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                AsyncImage(url: video.thumbnail.flatMap { URL(string: $0) } ?? YouTubeLink.thumbnailURL(videoID: video.id)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ZStack { Rectangle().fill(.quaternary); Image(systemName: "play.rectangle").font(.largeTitle).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(video.title).font(.headline)
                if !video.channel.isEmpty { Text(video.channel).font(.subheadline).foregroundStyle(.secondary) }
                HStack(spacing: 12) {
                    Label(VideoTime.string(video.duration), systemImage: "clock")
                    Label(video.chapters.isEmpty ? "Bölüm yok" : "\(video.chapters.count) bölüm", systemImage: "list.bullet")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let platform = YouTubeImportLogic.platformName(video.platform) {
                    Label(platform, systemImage: "globe").font(.subheadline).foregroundStyle(.secondary)
                }
                Label(YouTubeImportLogic.captionStatus(video.captions), systemImage: video.hasCaptions ? "captions.bubble" : "waveform")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(video.hasCaptions ? Color.green : Color.orange)
            }
            .padding(.vertical, 4)
            if video.duration > YouTubeImportLogic.maxDuration && !(useRange && range(for: video).error == nil) {
                Label("Video 4 saatten uzun; tek seferde en fazla 4 saatlik bir bölüm işlenebilir. ‘Zaman aralığı’ndan bir bölüm seç.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                if !useRange {
                    Button("İlk 4 saati seç", systemImage: "scissors") {
                        rangeStart = VideoTime.string(0)
                        rangeEnd = VideoTime.string(YouTubeImportLogic.maxDuration)
                        withAnimation { useRange = true }
                    }
                }
            }
            if !video.isEmbeddable {
                Label("Video sahibi uygulama içinde oynatmaya izin vermiyor; dersi indirilen sesle dinleyebilirsin.",
                      systemImage: "headphones")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let existing = lessons.first(where: { $0.videoID == video.id }) {
                Button {
                    onFinish(existing)
                } label: {
                    Label("Bu video zaten kütüphanende — mevcut dersi aç", systemImage: "checkmark.circle")
                }
            }
        }
    }

    private func videoOptions(_ video: VideoInfo) -> some View {
        Group {
            Section {
                // Segmentli seçici 320 pt'de "Yalnızca altyazı"yı kesiyordu: her kaynak açıklamasıyla kendi satırında.
                ForEach(TranscriptMode.allCases) { item in
                    Button { mode = item } label: {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).foregroundStyle(.primary)
                                Text(item.detail).font(.footnote).foregroundStyle(.secondary)
                            }
                            .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            // Yer her satırda ayrılır: seçim değişince metin yeniden kırılmaz.
                            Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                                .opacity(mode == item ? 1 : 0)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityAddTraits(mode == item ? .isSelected : [])
                }
                if mode == .captions && !video.hasCaptions {
                    Label("Bu videoda altyazı yok. ‘Otomatik’ ya da ‘Yapay zekâ’ seç.", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.red)
                }
                // Yalnızca elle altyazılar seçilebilir: sunucu otomatik altyazıyı her zaman videonun
                // özgün dilinden alır (YouTube'un makine çevirisi izleri istenemez); ‘Otomatik’ onu kapsar.
                if mode != .ai && YouTubeImportLogic.showsCaptionPicker(video) {
                    Picker("Altyazı dili", selection: $captionLanguage) {
                        Text("Otomatik").tag("")
                        ForEach(YouTubeImportLogic.captionLanguages(video.captions), id: \.lang) { track in
                            Text(track.name).tag(track.lang)
                        }
                    }
                }
            } header: {
                Text("Yazıya dökme")
            }
            commonOptions(translateDefaultHint: YouTubeImportLogic.language(of: video))
            Section {
                Toggle("Yalnızca bir kısmını işle", isOn: $useRange.animation())
                if useRange {
                    // Etiket alanın dışında: yan yana iki alanda yer tutucular 320 pt'de kesiliyor, hangisi ne okunmuyordu.
                    LabeledContent("Başlangıç") {
                        TextField("0:00", text: $rangeStart)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                            .accessibilityLabel("Başlangıç")
                    }
                    LabeledContent("Bitiş") {
                        TextField(VideoTime.string(video.duration), text: $rangeEnd)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                            .accessibilityLabel("Bitiş")
                    }
                    if !video.chapters.isEmpty {
                        Menu {
                            ForEach(Array(video.chapters.sorted { $0.start < $1.start }.enumerated()), id: \.offset) { index, chapter in
                                Button("\(VideoTime.string(chapter.start)) · \(chapter.title)") {
                                    let sorted = video.chapters.sorted { $0.start < $1.start }
                                    rangeStart = VideoTime.string(chapter.start)
                                    rangeEnd = VideoTime.string(sorted[safe: index + 1]?.start ?? video.duration)
                                }
                            }
                        } label: {
                            Label("Bölümden seç", systemImage: "list.bullet.rectangle")
                        }
                    }
                    if let message = range(for: video).error {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Zaman aralığı")
            } footer: {
                Text(useRange ? "Saat:dakika:saniye ya da dakika:saniye yaz; boş bırakılan uç videonun başı/sonu sayılır."
                              : "Uzun derslerde yalnızca gereken kısmı işlemek daha hızlıdır.")
            }
        }
    }

    private func commonOptions(translateDefaultHint language: String?) -> some View {
        Section {
            Toggle(isOn: $translate) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Türkçe’ye çevir")
                    if let language, !YouTubeImportLogic.isTurkish(language) {
                        Text("Videonun dili: \(YouTubeImportLogic.languageName(language))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Toggle("Tahta/slayt karelerini yakala", isOn: $keyframes)
            Toggle("Ders notu çıkar", isOn: $notes)
        } header: {
            Text("Çıktılar")
        } footer: {
            Text("Kareler: tahtadaki yazı, slayt ve şemalar zaman damgasıyla saklanır. Ders notu: özet, kavramlar, formüller ve sınav soruları.")
        }
    }

    private func startSection(canStart: Bool, footer: String, action: (() -> Void)? = nil) -> some View {
        Section {
            Button {
                if let action { action() } else { start() }
            } label: {
                Label("Başlat", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .disabled(!canStart)
            if let runError {
                Label(runError, systemImage: "xmark.octagon").foregroundStyle(.red)
            }
        } footer: {
            Text(footer)
        }
    }

    // MARK: - Oynatma listesi

    private func playlistSection(_ playlist: PlaylistInfo) -> some View {
        let allSelected = selectedEntries.count == playlist.entries.count
        return Section {
            // Başlıkta liste adıyla aynı satırdayken ad birkaç harfe iniyordu: ilk satıra alındı.
            if !playlist.entries.isEmpty {
                Button(allSelected ? "Hiçbirini seçme" : "Tümünü seç", systemImage: allSelected ? "circle" : "checkmark.circle") {
                    selectedEntries = allSelected ? [] : Set(playlist.entries.map(\.id))
                }
            }
            ForEach(playlist.entries) { entry in
                Button {
                    if selectedEntries.contains(entry.id) { selectedEntries.remove(entry.id) } else { selectedEntries.insert(entry.id) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selectedEntries.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selectedEntries.contains(entry.id) ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).foregroundStyle(.primary).lineLimit(2)
                            HStack(spacing: 6) {
                                if let d = entry.duration { Text(VideoTime.string(d)) }
                                if lessons.contains(where: { $0.videoID == entry.id }) { Text("· kütüphanende") }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text(playlist.title.isEmpty ? "Oynatma listesi" : playlist.title).lineLimit(2)
        } footer: {
            Text("\(playlist.entries.count) video · \(selectedEntries.count) seçili")
        }
    }

    // MARK: - Çalışma ve özet

    private func runningSection(_ run: RunState) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                if run.total > 1 {
                    Text("Video \(run.index)/\(run.total)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(run.title).font(.headline).lineLimit(3)
                ProgressView(value: run.progress)
                HStack {
                    Text(run.step).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text("%\(Int((run.progress * 100).rounded()))").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
            // İş kimliği gelmeden (sıraya alma, sınıf kaydı yükleme) sunucuda sürdürülecek bir şey yoktur.
            // Ayrılınca sıradaki videolar başlatılmaz, bırakılan video derse bağlanmaz: kaybedilecek bir şey varsa onaydan geçer.
            Button("Arka planda sürdür", systemImage: "arrow.down.right.and.arrow.up.left") {
                if YouTubeImportLogic.detachNeedsConfirm(index: run.index, total: run.total, linksCourse: linksCourse) {
                    confirmClose = true
                } else {
                    detachAndClose()
                }
            }
            .disabled(activeJobId == nil)
            Button("Durdur", systemImage: "stop.circle", role: .destructive) { stop() }
                .disabled(worker?.isCancelled == true)
        } footer: {
            Text(YouTubeImportLogic.runningFooter(index: run.index, total: run.total))
        }
    }

    private func summarySection(_ summary: BatchSummary) -> some View {
        Group {
            Section {
                Label("\(summary.lessons.count) video eklendi", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                if let courseName = summary.courseName, !summary.lessons.isEmpty {
                    Label("Derslerim’de ‘\(courseName)’ dersine bağlandı", systemImage: "book.closed").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(summary.lessons) { lesson in
                    if onFinishBatch == nil {
                        Button(lesson.title) { onFinish(lesson) }
                    } else {
                        Text(lesson.title)
                    }
                }
            } header: {
                Text("Özet")
            }
            if !summary.failures.isEmpty {
                Section("Atlanan videolar (\(summary.failures.count))") {
                    ForEach(summary.failures) { failure in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(failure.title)
                            Text(failure.message).font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            }
            if let onFinishBatch {
                Section {
                    if !summary.lessons.isEmpty {
                        Button("Podcast’e kaynak olarak ekle (\(summary.lessons.count))", systemImage: "plus.circle.fill") {
                            onFinishBatch(summary.lessons)
                        }
                        .font(.headline)
                    }
                    Button(summary.lessons.isEmpty ? "Kapat" : "Eklemeden kapat") { dismiss() }
                } footer: {
                    Text("Dersler ‘YouTube dersleri’ne kaydedildi; eklersen her birinin transkripti bu podcast’e ayrı kaynak olur.")
                }
            } else {
                Section {
                    if let first = summary.lessons.first {
                        Button("İlk dersi aç", systemImage: "play.rectangle") { onFinish(first) }
                    }
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }

    // MARK: - Mantık

    private func linkChanged() async {
        runError = nil
        pickError = nil
        guard !trimmedLink.isEmpty else { clearPreview(); infoError = nil; return }
        // İki ya da daha fazla bağlantı: toplu kuyruk (önizleme yok).
        guard !isBatch else { clearPreview(); infoError = nil; return }
        let url = singleLink
        // Başka bağlantıya geçildi: yenisinin bilgisi gelene dek eski videonun önizlemesi ve Başlat'ı kalmasın
        // (Başlat eski videoyu işlerdi). Yalnız boşluk/onay değişimi aynı bağlantıdır, önizleme korunur.
        if !YouTubeImportLogic.previewIsCurrent(infoLink: infoLink, link: url) { clearPreview() }
        switch ImportLinks.classify(url) {
        case .youtube, .supported:
            break
        case .other(_):
            // İzinli listede olmayan site: kullanıcı "Bu siteyi dene" diyene dek sunucuya sorulmaz.
            guard allowOther else { clearPreview(); infoError = nil; return }
        case .insecure:
            clearPreview()
            infoError = "Diğer siteler için yalnızca https bağlantıları desteklenir."
            return
        case .invalid:
            clearPreview()
            infoError = "Bu geçerli bir video bağlantısı değil."
            return
        }
        infoError = nil
        try? await Task.sleep(for: .milliseconds(450))   // yazarken her harfte istek atma
        guard !Task.isCancelled else { return }
        await loadInfo(url)
    }

    private func loadInfo(_ url: String) async {
        infoLoading = true
        infoError = nil
        defer { infoLoading = false }
        do {
            let response = try await APIClient.shared.youtubeInfo(url: url, allowOther: allowOther)
            guard !Task.isCancelled, url == singleLink else { return }
            info = response
            infoLink = url
            applyDefaults(response)
        } catch is CancellationError {
            return
        } catch {
            guard url == singleLink else { return }
            clearPreview()
            infoError = error.localizedDescription
        }
    }

    private func clearPreview() {
        info = nil
        infoLink = nil
    }

    private func applyDefaults(_ response: YouTubeInfoResponse) {
        mode = .auto
        captionLanguage = ""
        useRange = false
        rangeStart = ""
        rangeEnd = ""
        keyframes = true
        notes = true
        selectedEntries = []
        if let video = response.video, !response.isPlaylist {
            // Dil Türkçe değilse çeviri varsayılan açık.
            translate = YouTubeImportLogic.language(of: video).map { !YouTubeImportLogic.isTurkish($0) } ?? false
        } else {
            translate = false
        }
    }

    private func canStartVideo(_ video: VideoInfo) -> Bool {
        if mode == .captions && !video.hasCaptions { return false }
        // Süre sınırı işlenecek kısma uygulanır: 4 saatten uzun video, aralık seçilince işlenebilir.
        return YouTubeImportLogic.durationBlocker(duration: video.duration, useRange: useRange,
                                                  start: rangeStart, end: rangeEnd) == nil
    }

    private func range(for video: VideoInfo) -> (start: Double?, end: Double?, error: String?) {
        YouTubeImportLogic.range(start: rangeStart, end: rangeEnd, duration: video.duration)
    }

    private func estimate(for video: VideoInfo) -> String {
        let usesAI = mode == .ai || (mode == .auto && !video.hasCaptions)
        var span = video.duration
        if useRange {
            let r = range(for: video)
            if r.error == nil { span = (r.end ?? video.duration) - (r.start ?? 0) }
        }
        let minutes = max(1, Int((span / 60).rounded()))
        if usesAI {
            return "Yapay zekâ ile dökme sürer: \(minutes) dakikalık video için birkaç dakika bekleyebilirsin. Ekran açık kalır."
        }
        return "Altyazılı videolar genellikle bir iki dakikada hazırlanır; kareler ve notlar biraz süre ekler."
    }

    private func request(url: String, single: Bool) -> YouTubeStartRequest {
        var start: Double?
        var end: Double?
        if single, useRange, let video = info?.video {
            let r = range(for: video)
            start = r.start
            end = r.end
        }
        // Yapay zekâ modunda seçili altyazı dili gönderilmez (sunucu onu ses dili ipucu sayar).
        return YouTubeStartRequest(url: url, mode: mode,
                                   language: single && mode != .ai && !captionLanguage.isEmpty ? captionLanguage : nil,
                                   translateTo: translate ? "tr" : nil,
                                   start: start, end: end, keyframes: keyframes, notes: notes,
                                   allowOther: ImportLinks.needsAllowOther(url) ? true : nil)
    }

    private func start(ignoringDuplicate: Bool = false) {
        guard worker == nil else { return }
        var items: [WorkItem] = []
        var courseName: String?
        var skipped = 0
        if isBatch {
            items = ImportBatch.runnable(batchEntries, excluded: excludedLinks).map { WorkItem(url: $0, title: ImportLinks.shortName($0)) }
        } else {
            // Önizleme alandaki bağlantıya ait değilse (yenisi yüklenirken) eski video işlenmez.
            guard let info, YouTubeImportLogic.previewIsCurrent(infoLink: infoLink, link: singleLink) else { return }
            if let video = info.video, !info.isPlaylist {
                let url = video.url.isEmpty ? singleLink : video.url
                // Aynı video zaten kütüphanede: uyar, mevcut derse gitme yolu ver.
                if !ignoringDuplicate, let existing = LibraryDuplicates.existing(videoID: video.id, url: url, in: lessonKeys),
                   let lesson = lessons.first(where: { $0.id == existing }) {
                    duplicateLesson = lesson
                    return
                }
                items = [WorkItem(url: url, title: video.title)]
            } else if let playlist = info.playlist {
                let selected = playlist.entries.filter { selectedEntries.contains($0.id) }
                let fresh = selected.filter { LibraryDuplicates.existing(videoID: $0.id, url: $0.url, in: lessonKeys) == nil }
                skipped = selected.count - fresh.count
                items = fresh.map { WorkItem(url: $0.url, title: $0.title) }
                if createCourse { courseName = PlaylistCourse.name(from: playlist.title) }
            }
        }
        guard !items.isEmpty else {
            notice = skipped > 0 ? "Seçilen videoların hepsi zaten kütüphanende." : nil
            return
        }
        runError = nil
        notice = skipped > 0 ? "\(skipped) video zaten kütüphanende olduğu için atlandı." : nil
        summary = nil
        savedBeforeStop = 0
        detached = false
        let requests = items.map { request(url: $0.url, single: items.count == 1) }
        worker = Task { await runBatch(items, requests: requests, courseName: courseName) }
    }

    private func runBatch(_ items: [WorkItem], requests: [YouTubeStartRequest], courseName: String? = nil) async {
        UIApplication.shared.isIdleTimerDisabled = true
        linksCourse = courseName != nil
        defer {
            UIApplication.shared.isIdleTimerDisabled = false
            run = nil
            worker = nil
            linksCourse = false
            pending = YouTubePendingJobs.all
        }
        var created: [VideoLesson] = []
        var failures: [BatchFailure] = []
        var courseID: UUID?
        for (index, item) in items.enumerated() {
            guard !Task.isCancelled else { return stopped(saved: created.count) }
            run = RunState(title: item.title, index: index + 1, total: items.count, step: "Sıraya alınıyor")
            do {
                // Başlatma isteği iptalden yalıtılır (yapılandırılmamış görev dış iptali devralmaz): istek sunucuya
                // ulaştıysa iş orada başlar; yanıt okunmadan kesilirse iş kimliği kaybolur ve iş sahipsiz çalışır.
                let request = requests[index]
                let jobId = try await LessonImporter.start(request, url: item.url, title: item.title)
                // Başlatma isteği sürerken durdurulduysa iş kimliği ancak şimdi bilinir: sunucuda da durdur.
                guard !Task.isCancelled else {
                    notice = YouTubeImportLogic.stoppingText
                    stopped(saved: created.count)
                    Task { await finishCancel(jobId) }
                    return
                }
                activeJobId = jobId
                defer { if activeJobId == jobId { activeJobId = nil } }
                let lesson = try await follow(jobId: jobId, url: item.url, title: item.title)
                // Oynatma listesi: ders (Derslerim) bir kez oluşturulur/eşlenir, videolar sırayla bağlanır.
                if let courseName {
                    if courseID == nil { courseID = ensureCourse(named: courseName) }
                    lesson.courseID = courseID
                    try? context.save()
                }
                created.append(lesson)
            } catch is CancellationError {
                return stopped(saved: created.count)
            } catch {
                guard !Task.isCancelled else { return stopped(saved: created.count) }
                failures.append(BatchFailure(title: item.title, message: error.localizedDescription))
                // Kota/oturum hatalarında sonraki videoları denemenin anlamı yok.
                if let api = error as? APIError, api.status == 401 || api.status == 429 {
                    for rest in items.dropFirst(index + 1) {
                        failures.append(BatchFailure(title: rest.title, message: "İşlenmedi: \(api.message)"))
                    }
                    break
                }
            }
        }
        // Son ders kaydedilirken durdurulduysa: ders kütüphanede kalır ama ekrana açılmaz.
        guard !Task.isCancelled else { return stopped(saved: created.count) }
        if items.count == 1 {
            if let lesson = created.first { onFinish(lesson) } else { runError = failures.first?.message }
        } else {
            summary = BatchSummary(lessons: created, failures: failures, courseName: created.isEmpty ? nil : courseName)
        }
    }

    private func resume(_ job: PendingYouTubeJob) {
        guard worker == nil else { return }
        runError = nil
        notice = nil
        savedBeforeStop = 0
        detached = false
        worker = Task {
            UIApplication.shared.isIdleTimerDisabled = true
            defer {
                UIApplication.shared.isIdleTimerDisabled = false
                run = nil
                worker = nil
                pending = YouTubePendingJobs.all
            }
            run = RunState(title: job.title.isEmpty ? job.url : job.title, index: 1, total: 1, step: "Durum soruluyor")
            activeJobId = job.jobId
            defer { if activeJobId == job.jobId { activeJobId = nil } }
            do {
                let lesson = try await follow(jobId: job.jobId, url: job.url, title: job.title)
                // Kaydedilirken durdurulduysa ders kütüphanede kalır ama ekrana açılmaz.
                guard !Task.isCancelled else { return stopped(saved: 1) }
                onFinish(lesson)
            } catch is CancellationError {
                return
            } catch {
                runError = error.localizedDescription
                infoError = error.localizedDescription
            }
        }
    }

    #if DEBUG
    /// Ekran denetimi: `-importRunDemo` ile sunucusuz "iş sürüyor" durumu (Kapat onayı, 'Arka planda sürdür' düğmesi).
    private func startRunDemoIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-importRunDemo"), worker == nil, run == nil else { return }
        worker = Task {
            defer { run = nil; worker = nil; activeJobId = nil }
            run = RunState(title: "Demo · 9. Sınıf Biyoloji | Hücre Zarından Madde Geçişleri ve Ozmoz", index: 2, total: 5,
                           progress: 0.42, step: "Yazıya dökülüyor")
            activeJobId = "demo-import-run"
            try? await Task.sleep(for: .seconds(900))
        }
    }
    #endif

    /// "Arka planda sürdür": yalnız takip biter, sunucudaki işe dokunulmaz. İş başlarken bekleyenlere yazıldığı için
    /// 'Yarım kalan işlemler'de kalır ve sonucu oradan alınır; sıradaki videolar başlatılmaz.
    private func detachAndClose() {
        // Takip edilen iş yoksa (iki video arası, iş kimliği bekleniyor) sürdürülecek bir şey yok: olağan durdurma.
        guard activeJobId != nil else { stop(); dismiss(); return }
        detached = true
        activeJobId = nil
        worker?.cancel()
        dismiss()
    }

    /// "Durdur", "Durdur ve kapat" ve ekrandan çıkış: takip biter, takip edilen iş sunucuda da iptal edilir (hata yutulur).
    private func stop() {
        // Arka plana bırakılan iş çıkışta iptal edilmez (yeniden gönderilen işin kimliği sonradan gelse bile).
        guard !detached else { return }
        let jobId = activeJobId
        activeJobId = nil
        if let worker, !worker.isCancelled {
            worker.cancel()
            // Başlatma isteği sürüyorsa iş, kimliği gelince sunucuda durdurulur (runBatch); o ana dek bu adım görünür.
            run?.step = YouTubeImportLogic.stoppingText
        }
        guard let jobId else { return }
        notice = YouTubeImportLogic.stoppingText
        // Yapılandırılmamış görev: ekran kapansa da iptal isteği gider.
        Task { await finishCancel(jobId) }
    }

    private func finishCancel(_ jobId: String) async {
        let outcome = YouTubeImportLogic.afterCancel(await Self.cancelOnServer(jobId))
        // İş başlarken bekleyenlere eklenmişti: bitmiş/ulaşılamamışsa kalır (sonucu alınabilir), iptal edildiyse temizlenir.
        if !outcome.keepPending {
            LessonImporter.discardStash(for: jobId)
            LessonImporter.forget(jobId)
        }
        notice = YouTubeImportLogic.stopNotice(saved: savedBeforeStop, cancel: outcome.message)
        pending = YouTubePendingJobs.all
    }

    /// Durdurulan çalışmanın sonu: kaydedilmiş dersler kütüphanede kalır ama ekrana açılmaz; kullanıcıya bildirilir.
    /// Sunucuya iptal isteği gittiyse sonucu (şimdi ya da sonra) finishCancel aynı bildirime ekler.
    private func stopped(saved: Int) {
        savedBeforeStop = saved
        notice = YouTubeImportLogic.stopNotice(saved: saved, cancel: notice ?? (saved > 0 ? nil : YouTubeImportLogic.cancelledText))
    }

    nonisolated static func cancelOnServer(_ jobId: String) async -> YouTubeCancelResult {
        do {
            return .state(try await APIClient.shared.youtubeCancel(jobId: jobId).state)
        } catch let error as APIError where error.status == 404 {
            return .notFound
        } catch {
            return .unreachable
        }
    }

    /// İşi yoklar (ortak `LessonImporter`); ekran durumu geri bildirimlerle güncellenir. İş sunucuda unutulursa kayıtlı istekle yeniden gönderilir.
    private func follow(jobId: String, url: String, title: String) async throws -> VideoLesson {
        var hooks = LessonImporter.Hooks()
        hooks.progress = { value, step in
            run?.progress = value
            run?.step = step
        }
        hooks.jobChanged = { newID in activeJobId = newID }
        // Sunucudaki iş bitti: kaydederken durdurulursa sunucuda iptal edilecek bir şey yok
        // (iptal yanıtı "sonucu Yarım kalan işlemler'den al" derdi, oysa kayıt sürüp bekleyenlerden silinir).
        hooks.willSave = { activeJobId = nil; saving = true }
        defer { saving = false }
        return try await LessonImporter.follow(jobId: jobId, url: url, title: title, preview: info?.video, context: context, hooks: hooks)
    }

    /// Aynı adlı ders varsa eşler, yoksa oluşturur (#6).
    private func ensureCourse(named name: String) -> UUID {
        if let id = PlaylistCourse.match(name: name, in: courses.map { ($0.id, $0.name) }) { return id }
        let course = Course(name: name, colorHex: Course.palette[courses.count % Course.palette.count])
        context.insert(course)
        try? context.save()
        return course.id
    }

    // MARK: - Sınıf kaydı çalıştırma (#4)

    private func startRecording() {
        guard worker == nil, let draft = recording, !draft.tooLarge else { return }
        runError = nil
        notice = nil
        summary = nil
        savedBeforeStop = 0
        detached = false
        worker = Task { await runRecording(draft) }
    }

    private func runRecording(_ draft: RecordingDraft) async {
        UIApplication.shared.isIdleTimerDisabled = true
        var jobStarted = false
        defer {
            UIApplication.shared.isIdleTimerDisabled = false
            run = nil
            worker = nil
            pending = YouTubePendingJobs.all
            // Başarıda, hatada ve iptalde dosya erişimi kapanır; iş hiç başlamadıysa cihazdaki geçici ses de silinir
            // (başlamış işin sesi iş sonunda derse taşınır ya da iş ölünce `LessonImporter` siler). Hata/iptalden sonra dosya yeniden seçilir.
            draft.release()
            recording = nil
            if !jobStarted { UploadStash.remove(uploadID: draft.id) }
        }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        run = RunState(title: title, index: 1, total: 1, step: "Hazırlanıyor")
        let options = RecordingUploader.Options(translate: translate, keyframes: keyframes, notes: notes)
        do {
            let request = try await RecordingUploader.prepare(source: draft.url, id: draft.id, title: title, isVideo: draft.isVideo,
                                                              plan: draft.plan, options: options) { value, step in
                run?.progress = value
                run?.step = step
            }
            run?.progress = 0
            run?.step = "Sıraya alınıyor"
            let jobId = try await LessonImporter.start(request, url: "", title: title)
            jobStarted = true
            // Başlatma sürerken durdurulduysa iş kimliği ancak şimdi bilinir: sunucuda da durdur.
            guard !Task.isCancelled else {
                notice = YouTubeImportLogic.stoppingText
                stopped(saved: 0)
                Task { await finishCancel(jobId) }
                return
            }
            activeJobId = jobId
            defer { activeJobId = nil }
            let lesson = try await follow(jobId: jobId, url: "", title: title)
            guard !Task.isCancelled else { return stopped(saved: 1) }
            onFinish(lesson)
        } catch is CancellationError {
            return stopped(saved: 0)
        } catch {
            guard !Task.isCancelled else { return stopped(saved: 0) }
            runError = error.localizedDescription
        }
    }
}

// MARK: - Saf yardımcılar (test edilir)

nonisolated enum YouTubeImportLogic {
    static let maxDuration: Double = 4 * 3600
    static let cancelledText = "İptal edildi."
    static let stoppingText = "Durduruluyor…"

    /// Durdurma bildirimi: iptal sonucu (yoksa nil) + durdurulmadan önce biten ve kütüphaneye kaydedilen dersler.
    static func stopNotice(saved: Int, cancel: String?) -> String? {
        guard saved > 0 else { return cancel }
        let savedText = saved == 1
            ? "Durdurulmadan önce biten ders kütüphaneye kaydedildi."
            : "Durdurulmadan önce biten \(saved) ders kütüphaneye kaydedildi."
        return [cancel, savedText].compactMap { $0 }.joined(separator: " ")
    }

    /// İptal isteğinin sonucu → iş "Yarım kalan işlemler"de kalsın mı ve kullanıcıya ne denecek.
    static func afterCancel(_ result: YouTubeCancelResult) -> (keepPending: Bool, message: String) {
        switch result {
        case .state(.cancelled), .notFound:
            (false, cancelledText)
        case .state(.done):
            (true, "İş durdurulmadan önce bitmişti; sonucu ‘Yarım kalan işlemler’den alabilirsin.")
        case .state(.error):
            (false, "İş zaten hatayla bitmişti.")
        case .state(.queued), .state(.running):
            (true, "İptal isteği iletildi; iş sunucuda durduruluyor.")
        case .unreachable:
            (true, "Sunucuya ulaşılamadı; iş sürüyor olabilir. Sonucunu ‘Yarım kalan işlemler’den alabilir ya da oradan silebilirsin.")
        }
    }

    /// Eldeki önizleme alandaki bağlantıya mı ait? (Yeni bağlantının bilgisi gelene dek eskisi gösterilmez, başlatılmaz.)
    static func previewIsCurrent(infoLink: String?, link: String) -> Bool {
        infoLink != nil && infoLink == link
    }

    /// İş sürerken "Kapat": arka planda sürdürme sunulabilir mi (sunucuda takip edilen iş var mı) ve onay iletisi.
    /// `index` çalışan videonun 1'den başlayan sırası; ardından gelenler iki seçenekte de başlatılmaz.
    /// `saving`: sunucudaki iş bitti, ders kaydediliyor (iş kimliği bırakıldığı için "henüz başlamadı" sanılmasın; sürdürülecek iş de yok).
    /// `linksCourse`: videolar bir derse bağlanıyor; arka plana bırakılan video sonucu sonradan alınınca bağlanmaz.
    static func closeChoice(hasActiveJob: Bool, index: Int, total: Int, linksCourse: Bool = false,
                            saving: Bool = false) -> (canDetach: Bool, message: String) {
        let canDetach = hasActiveJob && !saving
        var message: String
        if saving {
            message = "İş bitti, ders kaydediliyor; kapatırsan ders kütüphanede kalır."
        } else if hasActiveJob {
            message = "‘Arka planda sürdür’ dersen iş sunucuda devam eder; sonucunu ‘Yarım kalan işlemler’den alırsın. Durdurursan iş sunucuda da iptal edilir; başlamış işte günlük hak düşülmüş olabilir."
        } else {
            message = "İş henüz sunucuda başlamadı; kapatırsan işlem durdurulur."
        }
        let remaining = total - index
        if remaining > 0 { message += " Sıradaki \(remaining) video başlatılmaz." }
        if canDetach, linksCourse { message += " Arka plana bırakılan video derse kendiliğinden bağlanmaz." }
        return (canDetach, message)
    }

    /// Çalışma bölümündeki 'Arka planda sürdür' onaydan geçmeli mi: ayrılınca sıradaki videolar başlatılmaz, bırakılan video
    /// derse bağlanmaz. Kaybedilecek bir şey yoksa (tek video) tek dokunuş yeter.
    static func detachNeedsConfirm(index: Int, total: Int, linksCourse: Bool = false) -> Bool {
        total > index || linksCourse
    }

    /// Çalışma bölümünün altbilgisi: arka plana bırakınca sıradakilerin başlamayacağı onay açılmadan da görünür.
    static func runningFooter(index: Int, total: Int) -> String {
        let remaining = total - index
        return "‘Arka planda sürdür’ bu sayfayı kapatır; iş sunucuda devam eder, sonucu ‘Yarım kalan işlemler’den alırsın."
            + (remaining > 0 ? " Yalnız şu anki video sürer; sıradaki \(remaining) video başlatılmaz." : "")
            + " Durdurursan iş sunucuda da durdurulur: sırada bekleyen işin günlük hakkı iade edilir; başlamış işte hak düşülmüş olabilir."
    }

    /// Önizlemede gösterilen site adı; YouTube ve bilinmeyen için nil.
    static func platformName(_ platform: String?) -> String? {
        switch platform {
        case "vimeo": "Vimeo"
        case "dailymotion": "Dailymotion"
        case "other": "Diğer site"
        default: nil
        }
    }

    static func isTurkish(_ language: String) -> Bool {
        language.lowercased().hasPrefix("tr")
    }

    /// Videonun dili: sunucunun bildirdiği, yoksa ilk elle altyazının, yoksa ilk altyazının dili.
    static func language(of video: VideoInfo) -> String? {
        if let lang = video.language, !lang.isEmpty { return lang }
        return video.manualCaptions.first?.lang ?? video.captions.first?.lang
    }

    static func languageName(_ code: String) -> String {
        Locale(identifier: "tr_TR").localizedString(forLanguageCode: code)?.localizedCapitalized ?? code
    }

    /// "Elle altyazı (tr)" / "Otomatik altyazı" / "Altyazı yok → yapay zekâ ile dökülecek".
    static func captionStatus(_ captions: [CaptionTrack]) -> String {
        let manual = captions.filter { !$0.auto }
        if let preferred = manual.first(where: { isTurkish($0.lang) }) ?? manual.first {
            return "Elle altyazı (\(preferred.lang))"
        }
        if !captions.isEmpty { return "Otomatik altyazı" }
        return "Altyazı yok → yapay zekâ ile dökülecek"
    }

    /// "tr-TR" → "tr".
    static func baseLanguage(_ code: String) -> String {
        String(code.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "")
    }

    /// Dil seçicide gösterilecek izler: yalnızca elle altyazılar, her dil bir kez.
    /// Sunucu otomatik altyazıyı her zaman videonun özgün dilinden alır; YouTube'un makine çevirisi
    /// izleri (ör. Türkçe videoda "English (otomatik)") istenemez, seçici onları sunmaz.
    static func captionLanguages(_ captions: [CaptionTrack]) -> [CaptionTrack] {
        var seen = Set<String>()
        return captions.filter { !$0.auto && seen.insert($0.lang).inserted }
    }

    /// Dil seçici gösterilsin mi: birden çok elle altyazı varsa ya da tek elle altyazı videonun dilinde
    /// değilse (‘Otomatik’ o durumda videonun dilindeki otomatik altyazıyı seçer).
    static func showsCaptionPicker(_ video: VideoInfo) -> Bool {
        let manual = captionLanguages(video.captions)
        guard let only = manual.first else { return false }
        if manual.count > 1 { return true }
        guard let language = video.language, !language.isEmpty else { return true }
        return baseLanguage(only.lang) != baseLanguage(language)
    }

    /// Sunucunun kabul ettiği en kısa aralık (sn).
    static let minSpan: Double = 5

    /// Zaman aralığı metinlerini saniyeye çevirir ve sunucu kurallarıyla doğrular
    /// (bitiş > 0, aralık ≥ 5 sn, işlenecek kısım ≤ 4 saat). Boş uç nil döner; bitiş süreye kırpılır.
    static func range(start: String, end: String, duration: Double) -> (start: Double?, end: Double?, error: String?) {
        let startText = start.trimmingCharacters(in: .whitespaces)
        let endText = end.trimmingCharacters(in: .whitespaces)
        let s = startText.isEmpty ? nil : VideoTime.parse(startText)
        let e = endText.isEmpty ? nil : VideoTime.parse(endText)
        if !startText.isEmpty && s == nil { return (nil, nil, "Başlangıç anlaşılamadı (ör. 2:30).") }
        if !endText.isEmpty && e == nil { return (nil, nil, "Bitiş anlaşılamadı (ör. 15:00).") }
        if s == nil && e == nil { return (nil, nil, "Başlangıç ya da bitiş yaz.") }
        if let e, e <= 0 { return (nil, nil, "Bitiş 0:00’dan sonra olmalı.") }
        if let s, duration > 0, s >= duration { return (nil, nil, "Başlangıç videonun süresini aşıyor.") }
        if let s, let e, e <= s { return (nil, nil, "Bitiş, başlangıçtan sonra olmalı.") }
        if let e, duration > 0, e > duration + 1 { return (nil, nil, "Bitiş videonun süresini (\(VideoTime.string(duration))) aşıyor.") }
        let clampedEnd = e.map { duration > 0 ? min($0, duration) : $0 }
        // Sunucu işlenecek kısmı min(bitiş, süre) − başlangıç olarak ölçer.
        if let to = clampedEnd ?? (duration > 0 ? duration : nil) {
            let span = to - (s ?? 0)
            if span < minSpan {
                return (nil, nil, e == nil ? "Başlangıç videonun sonuna çok yakın; en az 5 saniyelik bir aralık seç."
                                           : "Bitiş, başlangıçtan en az 5 saniye sonra olmalı.")
            }
            if span > maxDuration {
                return (nil, nil, "Seçilen aralık 4 saatten uzun; en fazla 4 saatlik bir bölüm seç.")
            }
        }
        return (s, clampedEnd, nil)
    }

    /// Başlat'ı engelleyen süre/aralık sorunu; yoksa nil. Sınır videonun tamamına değil işlenecek kısma uygulanır:
    /// 4 saatten uzun video, en fazla 4 saatlik bir aralık seçilince işlenebilir (sunucu da böyle denetler).
    static func durationBlocker(duration: Double, useRange: Bool, start: String, end: String) -> String? {
        if useRange { return range(start: start, end: end, duration: duration).error }
        if duration > maxDuration { return "Video 4 saatten uzun; en fazla 4 saatlik bir aralık seç." }
        return nil
    }
}
