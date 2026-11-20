import SwiftData
import SwiftUI
import UserNotifications

/// #2: Takip edilen kanallar ve oynatma listeleri. Yeni video gelince bildirim; "Otomatik işle" açıksa kuyruğa alınır.
struct FollowedChannelsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var app
    @Query(sort: \FollowedChannel.createdAt) private var channels: [FollowedChannel]
    @Query(sort: \Course.createdAt) private var courses: [Course]
    @Query private var lessons: [VideoLesson]
    @State private var link = ""
    @State private var adding = false
    @State private var checking = false
    @State private var message: String?
    /// Son elle kontrolde en az bir kanal kontrol edilemedi (ileti hata olarak gösterilir).
    @State private var checkFailed = false
    @State private var error: String?
    @State private var notificationsDenied = false
    /// Kuyrukta bekleyen videolar (UserDefaults'tan; sayı ya da işlenen öğe değişince yenilenir).
    @State private var queueItems: [QueuedImport] = []
    @State private var pendingRemoval: QueuedImport?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Kanal, @kullanıcı ya da oynatma listesi bağlantısı", text: $link, axis: .vertical)
                        .lineLimit(1...3)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task { await add() }
                    } label: {
                        HStack {
                            Label("Takip et", systemImage: "plus.circle")
                            if adding { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(adding || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let error { Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red) }
                } header: {
                    Text("Yeni takip")
                } footer: {
                    Text("Mevcut videolar “görülmüş” sayılır; bundan sonra yayımlananlar için bildirim gelir.")
                }

                queueSection

                Section {
                    ForEach(channels) { channel in
                        NavigationLink {
                            ChannelDetailView(channel: channel, courses: courses)
                        } label: {
                            ChannelRow(channel: channel, courseName: courses.first { $0.id == channel.courseID }?.name)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { modelContext.delete(channels[index]) }
                        try? modelContext.save()
                    }
                    if channels.isEmpty {
                        Text("Henüz takip ettiğin kanal yok.").font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Takip edilenler")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if notificationsDenied { Text("Bildirim izni kapalı: yeni videoları yalnızca uygulamayı açtığında görürsün (Ayarlar → Bildirimler).") }
                        Text("Kontrol uygulama açılınca ve iOS izin verdikçe arka planda yapılır; arka plan zamanı garanti değildir.")
                    }
                }

                if !channels.isEmpty {
                    Section {
                        Button {
                            Task { await checkNow() }
                        } label: {
                            HStack {
                                Label("Şimdi kontrol et", systemImage: "arrow.clockwise")
                                if checking { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(checking)
                        if let message {
                            if checkFailed {
                                Label(message, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red)
                            } else {
                                Text(message).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Takip edilen kanallar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
            .task {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                notificationsDenied = settings.authorizationStatus == .denied
            }
            .onAppear {
                // Kuyruk başka ekranlardan da değişir: sayı ve liste açılışta tazelenir.
                app.importQueue.refreshCount()
                queueItems = AutoImportQueue.items
            }
            .onChange(of: app.importQueue.queued) { _, _ in queueItems = AutoImportQueue.items }
            .onChange(of: app.importQueue.activeItemID) { _, _ in queueItems = AutoImportQueue.items }
            .confirmationDialog("Video kuyruktan çıkarılsın mı?", isPresented: Binding(get: { pendingRemoval != nil },
                                                                                    set: { if !$0 { pendingRemoval = nil } }),
                                titleVisibility: .visible, presenting: pendingRemoval) { item in
                Button("Kuyruktan çıkar", role: .destructive) {
                    app.importQueue.remove(item.id)
                    queueItems = AutoImportQueue.items
                }
                Button("Vazgeç", role: .cancel) {}
            } message: { item in
                Text("“\(item.displayTitle)” işlenmeyecek. Kütüphanendeki dersler etkilenmez; videoyu kanal sayfasından yeniden ekleyebilirsin.")
            }
        }
        .debugNarrowScreen()
    }

    @ViewBuilder
    private var queueSection: some View {
        let runner = app.importQueue
        if runner.isRunning || runner.queued > 0 || !runner.failures.isEmpty || runner.pausedReason != nil {
            Section {
                if runner.isRunning, let title = runner.currentTitle {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        ProgressView(value: runner.progress)
                        Text(runner.step).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Button("Durdur", systemImage: "stop.circle", role: .destructive) { runner.stop() }
                } else {
                    if let reason = runner.pausedReason {
                        Label(reason, systemImage: "pause.circle").font(.footnote).foregroundStyle(.orange)
                    }
                    if runner.queued > 0 {
                        Button {
                            runner.kick(context: modelContext)
                        } label: {
                            Label("Kuyruğu başlat (\(runner.queued) video)", systemImage: "play.fill")
                        }
                    }
                }
                ForEach(runner.failures, id: \.self) { failure in
                    Label(failure, systemImage: "xmark.octagon").font(.caption).foregroundStyle(.red)
                }
                // İşlenmekte olan öğe yukarıdaki ilerleme satırıdır; yalnız bekleyenler çıkarılabilir.
                ForEach(queueItems.filter { $0.id != runner.activeItemID }) { item in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayTitle).font(.footnote).lineLimit(2)
                            if item.attempts > 0 {
                                Text("\(item.attempts) kez denendi").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "clock").foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Kuyruktan çıkar", systemImage: "minus.circle", role: .destructive) { pendingRemoval = item }
                    }
                    .contextMenu {
                        Button("Kuyruktan çıkar", systemImage: "minus.circle", role: .destructive) { pendingRemoval = item }
                    }
                }
            } header: {
                Text("İşleme kuyruğu")
            } footer: {
                Text("Kuyruk uygulama açıkken sırayla işlenir; \(runner.queued) video bekliyor."
                     + (queueItems.contains { $0.id != runner.activeItemID } ? " Bir videoyu çıkarmak için sola kaydır ya da basılı tut." : ""))
            }
        }
    }

    private func add() async {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = ImportLinks.channelLink(text.components(separatedBy: .whitespacesAndNewlines).first ?? text) else {
            error = "Geçerli bir kanal bağlantısı ya da @kullanıcı adı yaz."
            return
        }
        if isFollowed(url) {
            error = "Bu kanalı zaten takip ediyorsun."
            return
        }
        adding = true
        error = nil
        defer { adding = false }
        do {
            let feed = try await APIClient.shared.youtubeFeed(url: url)
            // Sunucunun kanonik adresi saklanır; kopya denetimi onunla yinelenir (aynı kanal başka yazımla eklenmiş olabilir).
            let stored = feed.url.isEmpty ? url : feed.url
            if isFollowed(stored) {
                error = "Bu kanalı zaten takip ediyorsun."
                return
            }
            let channel = FollowedChannel(url: stored, title: feed.title)
            channel.knownVideoIDs = FeedDiff.updatedKnown(known: [], feed: feed.videos)
            channel.lastChecked = .now
            modelContext.insert(channel)
            try? modelContext.save()
            link = ""
            if !(await ChannelWatcher.requestNotificationPermission()) { notificationsDenied = true }
            ChannelRefresh.schedule()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func isFollowed(_ url: String) -> Bool {
        let key = ImportLinks.channelKey(url)
        return channels.contains { ImportLinks.channelKey($0.url) == key }
    }

    private func checkNow() async {
        checking = true
        message = nil
        defer { checking = false }
        let summary = await ChannelWatcher.checkAllDetailed(context: modelContext, minInterval: 0, notify: false)
        app.importQueue.kick(context: modelContext)
        checkFailed = summary.failed > 0
        message = FeedDiff.checkMessage(summary)
    }
}

private struct ChannelRow: View {
    var channel: FollowedChannel
    var courseName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(channel.title.isEmpty ? channel.url : channel.title).font(.subheadline.weight(.semibold)).lineLimit(2)
            HStack(spacing: 8) {
                if let last = channel.lastChecked {
                    Text("Kontrol: \(last.formatted(.relative(presentation: .named)))")
                } else {
                    Text("Henüz kontrol edilmedi")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            if channel.autoProcess || courseName != nil {
                // Dar ekranda alt alta.
                VStack(alignment: .leading, spacing: 2) {
                    if channel.autoProcess { Label("Otomatik işle", systemImage: "bolt.fill").foregroundStyle(.orange) }
                    if let courseName { Label(courseName, systemImage: "book.closed").foregroundStyle(.secondary) }
                }
                .font(.caption)
            }
        }
    }
}

/// Bir kanalın ayarları ve son videoları.
private struct ChannelDetailView: View {
    @Bindable var channel: FollowedChannel
    var courses: [Course]

    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var app
    @Query private var lessons: [VideoLesson]
    @State private var videos: [FeedVideo] = []
    @State private var loading = true
    @State private var loadGeneration = 0
    @State private var error: String?
    @State private var queuedIDs: Set<String> = []

    var body: some View {
        List {
            Section {
                Toggle("Otomatik işle", isOn: $channel.autoProcess)
                Picker("Ders", selection: $channel.courseID) {
                    Text("Bağlı değil").tag(UUID?.none)
                    ForEach(courses) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            } footer: {
                Text("Otomatik işle: yeni videolar bildirimle birlikte işleme kuyruğuna girer ve seçtiğin derse bağlanır.")
            }
            Section("Son videolar") {
                if loading { HStack(spacing: 8) { ProgressView(); Text("Yükleniyor…").foregroundStyle(.secondary) } }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red)
                    Button("Tekrar dene", systemImage: "arrow.clockwise") { Task { await load() } }
                }
                ForEach(videos) { video in
                    let exists = LibraryDuplicates.existing(videoID: video.id, url: video.url,
                                                            in: lessons.map { LessonKey(id: $0.id, videoID: $0.videoID, url: $0.url) }) != nil
                    VStack(alignment: .leading, spacing: 6) {
                        Text(video.title).font(.subheadline).lineLimit(3)
                        HStack(spacing: 10) {
                            if let duration = video.duration, duration > 0 {
                                Text(VideoTime.string(duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            if exists {
                                Label("Kütüphanende", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
                            } else if queuedIDs.contains(video.id) {
                                Label("Kuyrukta", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Button("Kuyruğa ekle", systemImage: "plus.circle") { enqueue(video) }
                                    .font(.caption).buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(channel.title.isEmpty ? "Kanal" : channel.title)
        .navigationBarTitleDisplayMode(.inline)
        // Ayrı görev: yenileme sırasında durum değişince SwiftUI yenileme görevini iptal edebiliyor, istek yarıda kesilmesin.
        .refreshable { await Task { await load() }.value }
        .task { await load() }
        .onChange(of: channel.autoProcess) { _, _ in try? modelContext.save() }
        .onChange(of: channel.courseID) { _, _ in try? modelContext.save() }
    }

    private func load() async {
        // İlk yükleme, "Tekrar dene" ve aşağı çekme üst üste binebilir: yalnız en son başlatılanın sonucu yazılır
        // (geç kalan eski istek, yenilenen listenin üstüne hata basmasın).
        loadGeneration += 1
        let generation = loadGeneration
        loading = true
        error = nil
        defer { if generation == loadGeneration { loading = false } }
        do {
            let feed = try await APIClient.shared.youtubeFeed(url: channel.url).videos
            guard generation == loadGeneration else { return }
            videos = feed
            queuedIDs = Set(AutoImportQueue.items.compactMap { item in videos.first { ImportLinks.dedupeKey($0.url) == ImportLinks.dedupeKey(item.url) }?.id })
        } catch is CancellationError {
            // Sayfadan çıkıldı: hata satırı gösterilmez.
        } catch {
            guard generation == loadGeneration else { return }
            self.error = error.localizedDescription
        }
    }

    private func enqueue(_ video: FeedVideo) {
        let keys = lessons.map { LessonKey(id: $0.id, videoID: $0.videoID, url: $0.url) }
        AutoImportQueue.enqueue([video], courseID: channel.courseID, existing: keys)
        queuedIDs.insert(video.id)
        app.importQueue.kick(context: modelContext)
    }
}
