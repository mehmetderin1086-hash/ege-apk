import AVFoundation
import Speech
import SwiftData
import SwiftUI
import UserNotifications

/// #48 Durum ve güven merkezi: sunucu ve özellikleri, süren/başarısız üretimler, kuyruk, izinler, yedek, depolama.
struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(GenerationCoordinator.self) private var generator
    @Query private var episodes: [Episode]
    @Query private var documents: [SourceDocument]
    @Query(sort: \QueuedRequest.createdAt) private var queue: [QueuedRequest]
    @State private var raw: [String: Any] = [:]
    @State private var error: String?
    @State private var latency: Double?
    @State private var permissions: [(String, String)] = []
    @State private var storage = StorageReport()
    /// Kesilmiş şekil sayısı gövdede hesaplanmaz (bölüm başına dosya okuma); nil = henüz sayılmadı.
    @State private var figureCount: Int?
    @State private var cleaning = false
    @State private var cleanMessage: String?

    var body: some View {
        NavigationStack {
            List {
                serverSection
                generationSection
                Section("İzinler") {
                    ForEach(permissions, id: \.0) { item in row(item.0, item.1) }
                }
                Section("Yedek") {
                    row("Son sunucu yedeği", MacBackup.lastBackupAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Henüz yok")
                }
                storageSection
                Section("Cihaz") {
                    row("Bölümler", "\(episodes.count)")
                    row("Kaynak belge", "\(documents.count)")
                    row("Kaynaksız bölüm", "\(episodes.filter { ($0.sourceDocumentIDs ?? []).isEmpty }.count)")
                    row("Kesilmiş şekil", figureCount.map { "\($0)" } ?? "—")
                }
            }
            .navigationTitle("Durum merkezi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Yenile", systemImage: "arrow.clockwise") { Task { await refreshFigures(); await load() } }
                        .accessibilityLabel("Yenile")
                }
            }
            .task { await load() }
            // Yerel sayım ağ yanıtını beklemez; bölüm eklenip silinince yenilenir.
            .task(id: episodes.count) { await refreshFigures() }
        }
    }

    // MARK: - Bölümler

    @ViewBuilder
    private var serverSection: some View {
        Section("Sunucu") {
            row("Adres", Config.apiBaseURL.absoluteString)
            if let latency { row("Yanıt süresi", "\(Int(latency * 1000)) ms") }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            if let features = raw["features"] as? [String] {
                row("Özellikler", features.isEmpty ? "—" : features.sorted().joined(separator: ", "))
            }
            if let jobs = raw["scriptJobs"] as? [String: Any] {
                row("Senaryo işleri", "\(jobs["running"] ?? 0) çalışıyor · \(jobs["queued"] ?? 0) sırada")
            }
            if let parallel = (raw["tts"] as? [String: Any])?["parallel"] as? [String: Any] {
                row("Seslendirme paralelliği", parallel.keys.sorted().map { "\($0) \(parallel[$0] ?? "")" }.joined(separator: " · "))
            }
            if let models = raw["models"] as? [String: Any] {
                ForEach(models.keys.sorted(), id: \.self) { k in row(k, "\(models[k] ?? "")") }
            }
            if let providers = raw["providers"] as? [String: Any] {
                ForEach(providers.keys.sorted(), id: \.self) { k in row("Sağlayıcı · \(k)", "\(providers[k] ?? "")") }
            }
        }
        if let recent = raw["recent"] as? [[String: Any]], !recent.isEmpty {
            Section("Son istekler") {
                ForEach(Array(recent.prefix(20).enumerated()), id: \.offset) { _, r in
                    HStack {
                        Image(systemName: (r["ok"] as? Bool) == true ? "checkmark.circle" : "xmark.octagon")
                            .foregroundStyle((r["ok"] as? Bool) == true ? .green : .red)
                            .accessibilityLabel((r["ok"] as? Bool) == true ? "Başarılı" : "Hatalı")
                        Text(verbatim: "\(r["path"] ?? "")").font(.caption.monospaced()).lineLimit(1)
                        Spacer()
                        Text(verbatim: "\(r["ms"] ?? "") ms").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var generationSection: some View {
        let running = episodes.filter { $0.status == .generating && !$0.needsApproval }
        let approval = episodes.filter { $0.status == .generating && $0.needsApproval }
        let failed = episodes.filter { $0.status == .failed }
        Section("Üretim") {
            row("Senaryo yazılıyor", "\(generator.drafts.count)")
            row("Seslendiriliyor", "\(running.count)")
            if !approval.isEmpty { row("Onay bekliyor", "\(approval.count)") }
            row("Kuyrukta", "\(queue.count)")
            ForEach(running) { episode in
                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.title).font(.subheadline).lineLimit(2)
                    Text(generator.progressText(for: episode.id) ?? (generator.isRunning(episode) ? "Sürüyor" : "Yarıda kaldı"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(queue) { request in
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.title).font(.subheadline).lineLimit(2)
                    Text(OfflineQueue.stateTitle(request.stateRaw) + (request.lastError.map { " · \($0)" } ?? ""))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            ForEach(failed) { episode in
                VStack(alignment: .leading, spacing: 2) {
                    Label(episode.title, systemImage: "exclamationmark.triangle").font(.subheadline).lineLimit(2)
                    if let message = episode.errorMessage { Text(message).font(.caption).foregroundStyle(.orange).lineLimit(3) }
                }
            }
        }
    }

    @ViewBuilder
    private var storageSection: some View {
        Section {
            row("Podcast'ler", storage.episodes.formatted(.byteCount(style: .file)))
            row("Sahne masterları ve önbellek", storage.caches.formatted(.byteCount(style: .file)))
            HStack {
                row("Güvenlik kopyası", storage.storeBackups.formatted(.byteCount(style: .file)))
                if storage.storeBackups > 0 {
                    Button("Sil", role: .destructive) {
                        OrphanCleanup.clearStoreBackups()
                        Task { await refreshStorage() }
                    }
                    .buttonStyle(.borderless)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Güvenlik kopyasını sil")
                }
            }
            Button {
                Task { await clean() }
            } label: {
                HStack { if cleaning { ProgressView() }; Text("Kalıntıları temizle") }.frame(minHeight: 44)
            }
            .disabled(cleaning || generator.hasActiveWork)
            if let cleanMessage { Text(cleanMessage).font(.caption).foregroundStyle(.secondary) }
        } header: {
            Text("Depolama")
        } footer: {
            Text("Kalıntılar: eski sahne masterları ve hiçbir bölüme ait olmayan, 24 saatten eski klasörler. Güvenlik kopyası, güncelleme öncesi alınan veritabanı kopyasıdır.")
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer(minLength: 8)
                Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(value).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Yükleme

    private func load() async {
        error = nil
        let start = Date.now
        async let perms = Self.permissionRows()
        do {
            var request = URLRequest(url: Config.apiBaseURL.appending(path: "/v1/status"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = PersonalToken.current { request.setValue(token, forHTTPHeaderField: "X-Personal-Token") }
            request.httpBody = Data("{}".utf8)
            request.timeoutInterval = 15
            let (data, _) = try await URLSession.shared.data(for: request)
            latency = Date.now.timeIntervalSince(start)
            raw = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        } catch {
            self.error = "Sunucuya ulaşılamadı: \(error.localizedDescription)"
        }
        permissions = await perms
        await refreshStorage()
    }

    private func refreshStorage() async {
        storage = await StorageReport.measure()
    }

    private func refreshFigures() async {
        let count = await StorageReport.figureCount(episodeIDs: episodes.map(\.id))
        if !Task.isCancelled { figureCount = count }
    }

    private func clean() async {
        cleaning = true
        defer { cleaning = false }
        let purged = SceneMasters.purge()
        let context = self.context
        // Kayıtlar her denetimde bağlamdan taze okunur (geri yükleme bu arada bölüm eklemiş olabilir).
        let removed = await OrphanCleanup.removeOrphanFolders {
            (Set(((try? context.fetch(FetchDescriptor<Episode>())) ?? []).map(\.id)),
             Set(((try? context.fetch(FetchDescriptor<QueuedRequest>())) ?? []).map(\.id)))
        }
        cleanMessage = "\(removed.count) yetim klasör silindi · \((purged).formatted(.byteCount(style: .file))) sahne masterı boşaltıldı."
        await refreshStorage()
    }

    static func permissionRows() async -> [(String, String)] {
        let notification = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        let notificationText = switch notification {
        case .authorized, .provisional, .ephemeral: "İzin verildi"
        case .denied: "Kapalı (Ayarlar'dan açılabilir)"
        default: "Sorulmadı"
        }
        let speechText = switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: "İzin verildi"
        case .denied, .restricted: "Kapalı"
        default: "Sorulmadı"
        }
        let micText = switch AVAudioApplication.shared.recordPermission {
        case .granted: "İzin verildi"
        case .denied: "Kapalı"
        default: "Sorulmadı"
        }
        return [("Bildirimler", notificationText), ("Konuşma tanıma", speechText), ("Mikrofon", micText)]
    }
}

/// Depolama ölçümü (ana iş parçacığı dışında).
nonisolated struct StorageReport: Sendable {
    var episodes: Int64 = 0
    var caches: Int64 = 0
    var storeBackups: Int64 = 0

    @concurrent
    static func measure() async -> StorageReport {
        let support = URL.applicationSupportDirectory
        let backups = OrphanCleanup.storeBackupDirectories().reduce(Int64(0)) { $0 + OrphanCleanup.size(of: $1) }
        return StorageReport(episodes: OrphanCleanup.size(of: support.appending(path: "Episodes")),
                             caches: OrphanCleanup.size(of: URL.cachesDirectory),
                             storeBackups: backups)
    }

    /// Bölüm klasörünün kapladığı alan, okunur metin olarak (Ayarlar > Kütüphane; `measure` ile aynı ölçüm).
    @concurrent
    static func episodesText() async -> String {
        ByteCountFormatter.string(fromByteCount: OrphanCleanup.size(of: EpisodeFiles.location), countStyle: .file)
    }

    /// Bölümlerin kesilmiş şekil toplamı. Ortak önbellekten geçer: dosya damgası aynıysa yeniden okunmaz, klasör oluşturulmaz.
    @concurrent
    static func figureCount(episodeIDs: [UUID]) async -> Int {
        episodeIDs.reduce(0) { $0 + EpisodeBlobCache.shared.figures($1, at: EpisodeFiles.figuresURL(for: $1)).count }
    }
}

/// #48 "Kalıntıları temizle": yetim bölüm klasörleri ve güvenlik kopyası.
nonisolated enum OrphanCleanup {
    /// Yedekten geri yükleme sürerken (P7) true yazılır; temizlik o sırada klasör silmez.
    static let restoringKey = "backup.restoreInProgress"
    static let minimumAge: TimeInterval = 24 * 3600

    /// Silinecek klasör adları (saf; test edilir). Yalnız UUID adlı, bölümü ve kuyruk isteği olmayan, 24 sa'ten eski.
    static func orphans(folders: [(name: String, modified: Date)], episodeIDs: Set<UUID>, requestIDs: Set<UUID>,
                        now: Date, restoring: Bool) -> [String] {
        guard !restoring else { return [] }
        return folders.compactMap { folder in
            guard let id = UUID(uuidString: folder.name),
                  !episodeIDs.contains(id), !requestIDs.contains(id),
                  now.timeIntervalSince(folder.modified) > minimumAge else { return nil }
            return folder.name
        }
    }

    /// Geri yükleme bayrağı: `true` (P7) ya da başlangıç zamanı. Zaman 2 sa'ten eskiyse takılı kalmış sayılır
    /// (geri yükleme sırasında uygulama öldüyse temizlik sonsuza dek kilitlenmesin).
    static func isRestoring(_ value: Any?, now: Date = .now) -> Bool {
        if let started = value as? Date { return now.timeIntervalSince(started) < 2 * 3600 }
        return (value as? Bool) ?? false
    }

    /// Geri yükleme çağıranı için (P7 `Backup.restore` / `MacBackup.restore` sarabilir).
    static func setRestoring(_ on: Bool) {
        if on { UserDefaults.standard.set(Date.now, forKey: restoringKey) } else { UserDefaults.standard.removeObject(forKey: restoringKey) }
    }

    /// Adaylar arka planda bulunur; silmeden hemen önce ana aktörde kayıtlarla (`known`) yeniden denetlenir ve klasörler
    /// tek adımda (aynı birimde ad değiştirme) çöp klasörüne taşınır. `Backup.restore` ana aktörde await'siz çalıştığı için
    /// bu denetim+taşıma adımıyla iç içe geçemez: geri yüklenen bölüm ya kayıtlarda görünür ya da klasörü henüz yoktur.
    /// Böylece güvence P7'nin bayrağına bağlı kalmaz; bayrak yalnız ek kilit.
    @MainActor
    static func removeOrphanFolders(known: () -> (episodes: Set<UUID>, requests: Set<UUID>)) async -> [String] {
        let root = URL.applicationSupportDirectory.appending(path: "Episodes", directoryHint: .isDirectory)
        let first = known()
        let found = await candidates(root: root, episodeIDs: first.episodes, requestIDs: first.requests)
        guard !found.isEmpty, !isRestoring(UserDefaults.standard.object(forKey: restoringKey)) else { return [] }
        let current = known()
        let names = stillOrphans(found, episodeIDs: current.episodes, requestIDs: current.requests)
        guard !names.isEmpty else { return [] }
        let trash = URL.cachesDirectory.appending(path: "OrphanTrash-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        var moved: [String] = []
        for name in names where (try? FileManager.default.moveItem(at: root.appending(path: name), to: trash.appending(path: name))) != nil {
            moved.append(name)
        }
        await purge(trash)
        return moved
    }

    /// Son denetim (saf; test edilir): bu arada bölümü ya da isteği oluşan aday düşer.
    static func stillOrphans(_ names: [String], episodeIDs: Set<UUID>, requestIDs: Set<UUID>) -> [String] {
        names.filter { name in UUID(uuidString: name).map { !episodeIDs.contains($0) && !requestIDs.contains($0) } ?? false }
    }

    @concurrent
    private static func candidates(root: URL, episodeIDs: Set<UUID>, requestIDs: Set<UUID>) async -> [String] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let folders = urls.map { url in
            (name: url.lastPathComponent,
             modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantFuture)
        }
        return orphans(folders: folders, episodeIDs: episodeIDs, requestIDs: requestIDs, now: .now,
                       restoring: isRestoring(UserDefaults.standard.object(forKey: restoringKey)))
    }

    @concurrent
    private static func purge(_ url: URL) async {
        try? FileManager.default.removeItem(at: url)
    }

    static func storeBackupDirectories() -> [URL] {
        let base = URL.applicationSupportDirectory
        let urls = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.lastPathComponent.hasPrefix("StoreBackup-") }
    }

    /// İçerik silinir, boş klasör kalır (aksi hâlde sonraki açılışta aynı etiketle yeniden kopyalanır).
    static func clearStoreBackups() {
        for dir in storeBackupDirectories() {
            for item in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                try? FileManager.default.removeItem(at: item)
            }
        }
    }

    static func size(of url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }
}
