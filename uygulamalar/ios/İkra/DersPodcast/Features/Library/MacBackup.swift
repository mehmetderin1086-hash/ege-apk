import CryptoKit
import Foundation
import SwiftData
import SwiftUI
import UIKit

/// #49: Mac'teki sunucuya içerik adresli (SHA-256), artımlı ve sessiz yedek.
/// Tetikler: açılış, arka plana geçiş (küçük parça), `.episodeReady`. Son başarılı yedek 24 saatten eskiyse çalışır.
/// Mac'e ulaşılamazsa sessizce atlanır; üretim sürerken beklenir. BG görevi yok.
enum MacBackup {
    static let lastAtKey = "backup.mac.lastAt"
    nonisolated static let autoKey = "backup.mac.auto"
    nonisolated static let lastSnapshotKey = "backup.mac.lastSnapshot"
    /// Son başarısız denemenin kısa açıklaması (ağ hatası yazılmaz).
    nonisolated static let lastErrorKey = "backup.mac.lastError"
    /// Otomatik yedek neden tutuluyor (`Hold.rawValue`); elle yedek ya da geri yükleme temizler.
    nonisolated static let holdKey = "backup.mac.hold"
    /// Bu kurulum Mac'teki yedeklerin sahibi: elle yedek başlattı, commit etti ya da geri yükledi.
    nonisolated static let lineageKey = "backup.mac.lineage"
    /// Son kota reddinin (507 `quota_exceeded`) zamanı; başarılı yedek ya da eski yedeği silmek temizler.
    nonisolated static let quotaAtKey = "backup.mac.quotaAt"
    /// Kullanıcı otomatik yedeğin hücresel veride de çalışmasına izin verdi (varsayılan kapalı).
    nonisolated static let cellularKey = "backup.mac.cellular"
    /// Son çalışmada tek dosya sınırını aştığı için yedeğe girmeyen dosyalar (`"<yol>|<bayt>"`); her çalışmada yeniden yazılır.
    nonisolated static let skippedKey = "backup.mac.skipped"

    nonisolated static let interval: TimeInterval = 24 * 3600
    /// Ön planda çalışma başına en çok gönderilecek bayt.
    nonisolated static let maxBytesPerRun: Int64 = 500_000_000
    /// Arka plana geçişte (≈30 sn) gönderilecek küçük parça.
    nonisolated static let backgroundBytesPerRun: Int64 = 40_000_000
    /// Sunucunun tek dosya sınırı (200 MB); daha büyük dosya snapshot'a girmez.
    nonisolated static let maxBlobBytes: Int64 = 200_000_000
    /// Sunucu son 14 snapshot'ı tutar; kota yeni yedekle birlikte en yeni 13'e bakar.
    nonisolated static let keepSnapshots = 14
    /// Kota reddinden sonra otomatik yedek bu kadar beklenir (her açılışta yüzlerce MB yeniden gönderilmesin).
    nonisolated static let quotaRetryInterval: TimeInterval = 24 * 3600
    /// Elle yedekte en çok tur (tur başına `maxBytesPerRun`; 40 × 500 MB = 20 GB).
    nonisolated static let manualMaxRounds = 40
    /// Son başarılı yedek bu kadar günden eskiyse ekranda uyarı çıkar.
    nonisolated static let staleAfterDays = 3

    enum Outcome: Equatable, Sendable {
        case done(files: Int, uploaded: Int)
        /// Bütçe ya da süre doldu; yüklenenler sunucuda kalır, sonraki çalışma sürdürür.
        case partial(uploaded: Int)
        case unavailable
        case busy
        case failed(String)
        /// Mac'teki yedek alanı doldu (507); eski yedek silinmeden yeni yedek kaydedilmez.
        case quotaExceeded(String)
        /// Otomatik yedek tutuldu (Mac'teki yedekler korunur); yalnız elle "Şimdi yedekle" geçer.
        case held(Hold)
    }

    /// Mac'te snapshot varken otomatik yedeğin çalışmadığı durumlar. Sunucu son 14 snapshot'ı tutup eskileri
    /// (ve başvurulmayan ses dosyalarını) sildiği için boş ya da yeni bir cihazın günlük yedeği asıl yedeği döndürebilir.
    enum Hold: String, Equatable, Sendable {
        /// Cihazda bölüm, kart ve Cornell notu yok (yeniden kurulum, yeni cihaz): geri yükleme önerilir.
        case deviceEmpty
        /// Bu kurulum hiç yedeklemedi ya da geri yüklemedi ve Mac'te önceki yedekler var.
        case foreignSnapshots
    }

    static var isAutoEnabled: Bool {
        get { UserDefaults.standard.object(forKey: autoKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoKey) }
    }

    static var lastBackupAt: Date? { UserDefaults.standard.object(forKey: lastAtKey) as? Date }
    static var lastSnapshotID: String? { UserDefaults.standard.string(forKey: lastSnapshotKey) }
    static var lastError: String? { UserDefaults.standard.string(forKey: lastErrorKey) }
    static var quotaExceededAt: Date? { UserDefaults.standard.object(forKey: quotaAtKey) as? Date }
    static var pendingHold: Hold? {
        get { UserDefaults.standard.string(forKey: holdKey).flatMap(Hold.init(rawValue:)) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: holdKey) }
    }

    /// Çalışıyor mu (ekran durumu için).
    private(set) static var isRunning = false
    private static var isRestoring = false
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        Task.detached(priority: .utility) { purgeStaleStaging() }
        // Açılış: sunucu durumu (özellik bayrakları) yüklensin diye biraz sonra.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(25))
            await runIfDue(context: AppDataStore.container.mainContext)
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { runInBackground() }
        }
    }

    static func runIfDue(context: ModelContext) async {
        guard isAutoEnabled, isDue(lastAt: lastBackupAt), !isQuotaBlocked(quotaAt: quotaExceededAt) else { return }
        await run(context: context, budget: maxBytesPerRun)
    }

    /// Sunucu herkese açık adreste olduğundan otomatik yedek yalnız ücretsiz ağda (Wi-Fi) yükler;
    /// elle "Şimdi yedekle" ve kullanıcının hücresel izni her ağda yükler.
    nonisolated static func allowsExpensive(manual: Bool, userAllowsCellular: Bool) -> Bool { manual || userAllowsCellular }

    /// Kota reddinden sonraki bekleme: otomatik yedek `quotaRetryInterval` boyunca denemez (elle yedek dener).
    nonisolated static func isQuotaBlocked(quotaAt: Date?, now: Date = .now) -> Bool {
        guard let quotaAt, quotaAt <= now else { return false }
        return now.timeIntervalSince(quotaAt) < quotaRetryInterval
    }

    /// Mac yedeği ekranında silinebilen snapshot'lar (en yenisi korunur) ve bir sonraki yedekte sunucunun zaten
    /// sileceği eskiler (en yeni 13'ün dışındakiler; bunları silmek kotaya yer açmaz).
    nonisolated static func snapshotRoles(_ list: [BackupSnapshotInfo]) -> (deletable: Set<String>, expiring: Set<String>) {
        let sorted = list.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        let deletable = Set(sorted.dropFirst().map(\.id))
        let expiring = Set(sorted.dropFirst(max(0, keepSnapshots - 1)).map(\.id))
        return (deletable, expiring)
    }

    /// Eski snapshot'ı Mac'ten siler (en yenisi silinmez); kota bekleme süresi temizlenir. Silinen dosya sayısını döndürür.
    static func deleteSnapshot(id: String, list: [BackupSnapshotInfo]) async throws -> Int {
        guard snapshotRoles(list).deletable.contains(id) else {
            throw APIError(status: 0, code: "protected", message: "En yeni yedek silinemez.")
        }
        let removed = try await APIClient.shared.backupDelete(id: id)
        UserDefaults.standard.removeObject(forKey: quotaAtKey)
        return removed
    }

    nonisolated static func isDue(lastAt: Date?, now: Date = .now) -> Bool {
        guard let lastAt else { return true }
        // Saat geri alındıysa da yedekle.
        return lastAt > now || now.timeIntervalSince(lastAt) >= interval
    }

    /// Otomatik yedek günlerdir çalışmadıysa (son başarılı yedek `staleAfterDays` günden eski) geçen gün sayısı; yoksa nil.
    /// Hiç yedek alınmadıysa ya da tarih gelecekteyse (saat geri alındı) uyarı verilmez.
    nonisolated static func staleDays(lastAt: Date?, now: Date = .now) -> Int? {
        guard let lastAt, lastAt <= now else { return nil }
        let days = Int(now.timeIntervalSince(lastAt) / 86_400)
        return days >= staleAfterDays ? days : nil
    }

    nonisolated static func staleText(days: Int) -> String {
        "Son yedek \(days) gün önce; otomatik yedek çalışmıyor olabilir. \"Şimdi yedekle\" ile elle yedekleyebilirsin."
    }

    /// Geri yükleme önerisi: cihazda bölüm, kart ve Cornell notu yok ve Mac'te snapshot var.
    nonisolated static func shouldSuggestRestore(episodes: Int, cards: Int, notes: Int, hasSnapshot: Bool) -> Bool {
        episodes == 0 && cards == 0 && notes == 0 && hasSnapshot
    }

    /// Otomatik yedek tutulmalı mı? `hasLineage`: bu kurulum daha önce yedekledi ya da Mac'ten geri yükledi.
    nonisolated static func autoHold(episodes: Int, cards: Int, notes: Int, hasLineage: Bool, snapshots: [BackupSnapshotInfo]) -> Hold? {
        guard !snapshots.isEmpty else { return nil }
        if shouldSuggestRestore(episodes: episodes, cards: cards, notes: notes, hasSnapshot: true) { return .deviceEmpty }
        return hasLineage ? nil : .foreignSnapshots
    }

    /// Cihaz sayıları; ağ isteği yalnız gerektiğinde (cihaz boş ya da bu kurulumun yedeği yok).
    private static func autoHold(context: ModelContext) async throws -> Hold? {
        let episodes = (try? context.fetchCount(FetchDescriptor<Episode>())) ?? 1
        let cards = (try? context.fetchCount(FetchDescriptor<ReviewCard>())) ?? 1
        let notes = (try? context.fetchCount(FetchDescriptor<CornellNote>())) ?? 1
        let owned = hasLineage
        let empty = episodes == 0 && cards == 0 && notes == 0
        guard empty || !owned else { return nil }
        let snapshots = try await APIClient.shared.backupList()
        return autoHold(episodes: episodes, cards: cards, notes: notes, hasLineage: owned, snapshots: snapshots)
    }

    static var hasLineage: Bool { UserDefaults.standard.bool(forKey: lineageKey) || lastSnapshotID != nil }

    /// Bu kurulum artık bu snapshot'ın devamı (elle yedek ya da geri yükleme sonrası); otomatik yedek serbest.
    static func adoptLineage(snapshotID: String?) {
        if let snapshotID { UserDefaults.standard.set(snapshotID, forKey: lastSnapshotKey) }
        UserDefaults.standard.set(true, forKey: lineageKey)
        pendingHold = nil
    }

    // MARK: - Çalıştırma

    /// `manual`: kullanıcı "Şimdi yedekle"ye bastı; otomatik yedeğin tutma koşulları (`Hold`) atlanır.
    @discardableResult
    static func run(context: ModelContext, budget: Int64, manual: Bool = false) async -> Outcome {
        // Geri yükleme sürerken yedek başlamaz: içe aktarmadan önceki durumu snapshot'layıp en yeni yedek diye kaydederdi.
        guard !isRunning, !isRestoring else { return .busy }
        guard let app = AppState.current, app.serverSupports("backup1") else { return .unavailable }
        isRunning = true
        defer { isRunning = false }
        do {
            if manual {
                // Kullanıcı kararı: yarım kalan elle yedeği otomatik yedek sürdürür.
                adoptLineage(snapshotID: nil)
            } else {
                let hold = try await autoHold(context: context)
                pendingHold = hold
                if let hold { return .held(hold) }
            }
            // Üretim, düzenleme ya da taslak sürüyorsa bekle (en çok 10 dk).
            var waited = 0
            while app.generator.hasActiveWork {
                if waited >= 600 || Task.isCancelled { return .busy }
                try? await Task.sleep(for: .seconds(15))
                waited += 15
            }
            let expensive = allowsExpensive(manual: manual, userAllowsCellular: UserDefaults.standard.bool(forKey: cellularKey))
            // Otomatik yedek hücresel veride dosya ve manifest göndermez: yoklama bu ağdan çıkamıyorsa bağlantı hatasıyla burada durur.
            if !expensive { try await APIClient.shared.backupProbeUnmetered() }
            // Ana aktörde yalnız kayıtlar DTO'ya ve yollara çevrilir; JSON kodlama (base64 bloblar) ve klasör taraması
            // `upload` içinde arka planda yapılır.
            let manifest = try Backup.manifest(context: context)
            let sources = try Backup.entrySources(context: context)
            let device = UIDevice.current.name
            let outcome = try await upload(manifest: manifest, sources: sources, budget: budget, device: device, allowsExpensive: expensive)
            if case .done = outcome {
                UserDefaults.standard.set(Date.now, forKey: lastAtKey)
                UserDefaults.standard.removeObject(forKey: lastErrorKey)
                UserDefaults.standard.removeObject(forKey: quotaAtKey)
                pendingHold = nil
            }
            return outcome
        } catch is CancellationError {
            return .partial(uploaded: 0)
        } catch let error as APIError where error.isBackupQuotaExceeded {
            // Sunucu eski yedeği kendiliğinden silmez: kullanıcı Mac yedeği ekranından eski yedek siler.
            UserDefaults.standard.set(Date.now, forKey: quotaAtKey)
            UserDefaults.standard.removeObject(forKey: lastErrorKey)
            return .quotaExceeded(error.message)
        } catch let error as APIError where error.code == "network" || error.status == 0 {
            // Sunucuya ulaşılamıyor (bağlantı yok, sunucu kapalı ya da otomatik yedek hücresel veride): sessizce atla.
            return .unavailable
        } catch {
            UserDefaults.standard.set(error.localizedDescription, forKey: lastErrorKey)
            return .failed(error.localizedDescription)
        }
    }

    /// Elle yedek bir tur daha çalışmalı mı: bütçe doldu (`.partial`) ve bu turda dosya gönderildiyse evet.
    /// İlerleme olmayan tur (`.partial(0)`: iptal), hata, kota ve `manualMaxRounds` durdurur. `round` 0 tabanlıdır.
    nonisolated static func shouldContinueManual(_ outcome: Outcome, round: Int) -> Bool {
        guard case let .partial(uploaded) = outcome else { return false }
        return uploaded > 0 && round + 1 < manualMaxRounds
    }

    /// Elle "Şimdi yedekle": bütçe doldukça yeniden çalışır; kullanıcı büyük ilk yedekte defalarca basmak zorunda kalmaz.
    /// `uploaded` turların toplamıdır; `progress` her tur sonunda o ana kadarki toplamla çağrılır. Görev iptal edilirse durur.
    static func runManual(context: ModelContext, progress: (Int) -> Void = { _ in }) async -> (outcome: Outcome, uploaded: Int) {
        var total = 0
        var round = 0
        while true {
            let outcome = await run(context: context, budget: maxBytesPerRun, manual: true)
            switch outcome {
            case let .done(_, uploaded), let .partial(uploaded): total += uploaded
            default: break
            }
            guard shouldContinueManual(outcome, round: round), !Task.isCancelled else { return (outcome, total) }
            progress(total)
            round += 1
        }
    }

    /// Hash (önbellekli) → eksikleri sor → bütçe kadar yükle → hepsi oradaysa commit.
    @concurrent
    nonisolated private static func upload(manifest: BackupManifest, sources: [Backup.EntrySource], budget: Int64, device: String,
                                           allowsExpensive: Bool) async throws -> Outcome {
        let work = workDirectory
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let manifestURL = work.appending(path: "manifest.json")
        try manifest.encoded().write(to: manifestURL, options: .atomic)
        let all = [Backup.Entry(path: "manifest.json", url: manifestURL)] + Backup.entries(from: sources)
        var cache = BackupHashCache.load()
        let hashed: [BackupItem]
        do {
            hashed = try BackupHashCache.items(for: all, cache: &cache).items
        } catch {
            // İptalde (arka plan süresi doldu) o ana kadar hesaplanan özetler korunur; sonraki çalışma sürdürür.
            BackupHashCache.save(cache)
            throw error
        }
        BackupHashCache.save(cache)
        // Sınırı aşan dosya snapshot'a girmez; ekranda gösterilsin diye kaydedilir (yoksa eksik ancak geri yüklemede fark edilir).
        let split = splitBySize(hashed, limit: maxBlobBytes)
        let items = split.kept
        if split.oversized.isEmpty {
            UserDefaults.standard.removeObject(forKey: skippedKey)
        } else {
            UserDefaults.standard.set(skippedEntries(split.oversized), forKey: skippedKey)
        }
        try Task.checkCancellation()

        var missing = Set<String>()
        let hashes = Array(Set(items.map(\.record.sha256))).sorted()
        for start in stride(from: 0, to: hashes.count, by: 5000) {
            let chunk = Array(hashes[start..<min(hashes.count, start + 5000)])
            missing.formUnion(try await APIClient.shared.backupMissing(chunk))
        }
        let plan = uploadPlan(items: items, missing: missing, budget: budget)
        var uploaded = 0
        for item in plan.uploads {
            try Task.checkCancellation()
            try await APIClient.shared.backupUpload(file: item.url, sha256: item.record.sha256, allowsExpensive: allowsExpensive)
            uploaded += 1
        }
        guard plan.complete else { return .partial(uploaded: uploaded) }
        let snapshot = BackupSnapshotBody(createdAt: Date.now.ISO8601Format(), device: device, appVersion: appVersion,
                                          files: items.map(\.record))
        let id = try await APIClient.shared.backupCommit(snapshot)
        UserDefaults.standard.set(id, forKey: lastSnapshotKey)
        _ = try await QSBackupReadback.verify(snapshot: id, expected: items.map(\.record))
        return .done(files: items.count, uploaded: uploaded)
    }

    /// Tek dosya sınırına göre ayırır (sıra korunur): `kept` yedeğe girer, `oversized` girmez.
    nonisolated static func splitBySize(_ items: [BackupItem], limit: Int64) -> (kept: [BackupItem], oversized: [BackupItem]) {
        var kept: [BackupItem] = []
        var oversized: [BackupItem] = []
        for item in items {
            if item.record.bytes <= limit { kept.append(item) } else { oversized.append(item) }
        }
        return (kept, oversized)
    }

    nonisolated static func skippedEntries(_ items: [BackupItem]) -> [String] {
        items.map { "\($0.record.path)|\($0.record.bytes)" }
    }

    /// `skippedKey` kayıtlarını çözer (bozuk kayıt düşer). Yolda `|` olabilir; boyut son `|`'dan sonradır.
    nonisolated static func parseSkipped(_ raw: [String]) -> [(path: String, bytes: Int64)] {
        raw.compactMap { entry in
            guard let bar = entry.lastIndex(of: "|"), let bytes = Int64(entry[entry.index(after: bar)...]) else { return nil }
            return (path: String(entry[..<bar]), bytes: bytes)
        }
    }

    static var skippedFiles: [(path: String, bytes: Int64)] {
        parseSkipped(UserDefaults.standard.stringArray(forKey: skippedKey) ?? [])
    }

    /// Yedek yolundaki kayıt kimliği: `Audio/<id>.m4a`, `EpisodeFiles/<id>/…` (bölüm), `Videos/<id>/…` (ders). Başka yolda nil.
    nonisolated static func ownerID(ofBackupPath path: String) -> UUID? {
        let parts = path.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        switch parts[0] {
        case "Audio": return UUID(uuidString: String(parts[1].prefix { $0 != "." }))
        case "EpisodeFiles", "Videos": return UUID(uuidString: String(parts[1]))
        default: return nil
        }
    }

    /// Sınırı aşan dosyaların uyarı metni; en çok üç ad yazılır.
    nonisolated static func skippedText(_ files: [(name: String, bytes: Int64)]) -> String {
        let size: (Int64) -> String = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        let names = files.prefix(3).map { "\($0.name) (\(size($0.bytes)))" }.joined(separator: ", ")
        let more = files.count > 3 ? " ve \(files.count - 3) dosya daha" : ""
        return "\(files.count) dosya \(size(maxBlobBytes)) sınırını aştığı için yedeğe girmedi: \(names)\(more). Geri yüklemede bu dosyalar gelmez."
    }

    /// Yüklenecekler: sunucuda olmayan içerikler (aynı içerik bir kez), bütçeye sığanlar. `complete` = hepsi sığdı.
    nonisolated static func uploadPlan(items: [BackupItem], missing: Set<String>, budget: Int64) -> (uploads: [BackupItem], complete: Bool) {
        var seen = Set<String>()
        var uploads: [BackupItem] = []
        var used: Int64 = 0
        var complete = true
        for item in items where missing.contains(item.record.sha256) && seen.insert(item.record.sha256).inserted {
            if used + item.record.bytes <= budget {
                uploads.append(item)
                used += item.record.bytes
            } else {
                complete = false
            }
        }
        return (uploads, complete)
    }

    nonisolated static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    nonisolated static var workDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "MacBackup", directoryHint: .isDirectory)
    }

    // MARK: - Arka plana geçiş

    private final class BackgroundRun {
        var id: UIBackgroundTaskIdentifier = .invalid
        var task: Task<Void, Never>?
        func end() {
            task?.cancel()
            if id != .invalid { UIApplication.shared.endBackgroundTask(id); id = .invalid }
        }
    }

    private static func runInBackground() {
        guard isAutoEnabled, isDue(lastAt: lastBackupAt), !isQuotaBlocked(quotaAt: quotaExceededAt), !isRunning,
              AppState.current?.serverSupports("backup1") == true else { return }
        let run = BackgroundRun()
        run.id = UIApplication.shared.beginBackgroundTask(withName: "MacBackup") {
            MainActor.assumeIsolated { run.end() }
        }
        guard run.id != .invalid else { return }
        run.task = Task { @MainActor in
            _ = await MacBackup.run(context: AppDataStore.container.mainContext, budget: backgroundBytesPerRun)
            run.task = nil
            run.end()
        }
    }

    // MARK: - Geri yükleme

    /// Geri yüklemeye önerilecek snapshot (yoksa nil). Özellik yoksa nil.
    static func latestSnapshot() async -> BackupSnapshotInfo? {
        guard AppState.current?.serverSupports("backup1") == true else { return nil }
        return preferredSnapshot((try? await APIClient.shared.backupList()) ?? [])
    }

    /// İçerikli (manifest dışında dosyası olan) en yeni snapshot; hiçbiri yoksa en yenisi.
    /// Boş cihazdan elle alınmış yalnız-manifest snapshot'ı asıl yedeğin önüne geçmez.
    nonisolated static func preferredSnapshot(_ list: [BackupSnapshotInfo]) -> BackupSnapshotInfo? {
        let newest: (BackupSnapshotInfo, BackupSnapshotInfo) -> Bool = { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        return list.filter { $0.files > 1 }.max(by: newest) ?? list.max(by: newest)
    }

    /// Snapshot dosyalarını `Backup.make` düzeninde hazırlık klasörüne indirir, klasör yedeğiyle aynı içe aktarmayı (`Backup.restoreDetailed`) çağırır.
    /// Cihazda zaten olan bölüm ve derslerin dosyaları inmez; her dosyanın özeti doğrulanır, geçici hatada yeniden denenir.
    /// İndirme yarıda kalırsa (hata ya da iptal) hazırlık klasörü durur: aynı yedek yeniden denendiğinde yalnız eksik dosyalar iner.
    /// Dönen özet eklenen kayıtları tür tür verir; sesi yedekte bulunmayan bölümler `skippedEpisodes`'tadır (hata fırlatılmaz).
    static func restore(snapshotID: String, context: ModelContext,
                        progress: @escaping @MainActor (Double) -> Void = { _ in }) async throws -> Backup.RestoreSummary {
        // Hazırlık klasörü ortak: kütüphanedeki bant ve yedek ekranı aynı anda geri yükleme başlatamaz.
        guard !isRestoring else { throw APIError(status: 0, code: "busy", message: "Geri yükleme zaten sürüyor.") }
        isRestoring = true
        defer { isRestoring = false }
        let files = try await APIClient.shared.backupSnapshot(id: snapshotID)
        // Kimlikler okunamazsa küme boş kalır: hiçbir dosya düşmez (eski davranış).
        let existingEpisodes = Set(((try? context.fetch(FetchDescriptor<Episode>())) ?? []).map(\.id))
        let existingLessons = Set(((try? context.fetch(FetchDescriptor<VideoLesson>())) ?? []).map(\.id))
        let plan = restorePlan(files, existingEpisodes: existingEpisodes, existingLessons: existingLessons)
        guard plan.contains(where: { $0.path == "manifest.json" }) else {
            throw APIError(status: 0, code: "manifest", message: "Yedekte manifest bulunamadı.")
        }
        let folder = restoreStagingRoot.appending(path: stagingName(snapshotID: snapshotID), directoryHint: .isDirectory)
        removeStaging(except: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let total = plan.reduce(Int64(0)) { $0 + $1.bytes }
        var done: Int64 = 0
        for file in plan {
            try Task.checkCancellation()
            guard let relative = safeRelativePath(file.path) else { continue }
            let destination = folder.appending(path: relative)
            // Önceki denemeden kalan dosya özeti yeniden doğrulanırsa inmez; doğrulanamayan tek dosya geri yüklemeyi durdurur
            // (eksik ya da bozuk dosyayla içe aktarma yapılmaz, hazırlık sonraki deneme için kalır).
            if !(await stagedIsVerified(file, at: destination)) {
                try await download(file, to: destination)
            }
            done += file.bytes
            progress(restoreProgress(done: done, total: total))
        }
        // İndirme bitti: içe aktarma nasıl sonuçlanırsa sonuçlansın hazırlık temizlenir (sorunlu dosya sonraki denemeye taşınmaz).
        defer { try? FileManager.default.removeItem(at: folder) }
        let summary = try Backup.restoreDetailed(from: folder, context: context)
        adoptLineage(snapshotID: snapshotID)
        return summary
    }

    /// İndirilecek dosyalar: güvenli yol ve geçerli özet. Cihazda zaten olan bölümlerin (`Audio/<id>.m4a`, `EpisodeFiles/<id>/…`)
    /// ve YouTube derslerinin (`Videos/<id>/…`) dosyaları düşer: `Backup.restore` var olan kaydı atladığı için kullanılmazlar.
    /// manifest, Documents, VoiceNotes ve Tools her zaman kalır.
    nonisolated static func restorePlan(_ files: [BackupFileRecord], existingEpisodes: Set<UUID>, existingLessons: Set<UUID>) -> [BackupFileRecord] {
        files.filter { file in
            guard safeRelativePath(file.path) != nil, BackupBlobID.isValid(file.sha256) else { return false }
            let parts = file.path.split(separator: "/")
            guard parts.count >= 2 else { return true }
            switch parts[0] {
            case "Audio":
                guard parts.count == 2, parts[1].hasSuffix(".m4a"), let id = UUID(uuidString: String(parts[1].dropLast(4))) else { return true }
                return !existingEpisodes.contains(id)
            case "EpisodeFiles":
                guard let id = UUID(uuidString: String(parts[1])) else { return true }
                return !existingEpisodes.contains(id)
            case "Videos":
                guard let id = UUID(uuidString: String(parts[1])) else { return true }
                return !existingLessons.contains(id)
            default:
                return true
            }
        }
    }

    /// Hazırlık klasöründeki dosyanın boyutu kayıttakiyle aynı mı (yoksa ya da eksikse false)?
    nonisolated static func stagedIsComplete(url: URL, bytes: Int64) -> Bool {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber else { return false }
        return size.int64Value == bytes
    }

    /// Hazırlıktaki dosya bu kaydın dosyası mı: boyut tutuyorsa özeti de yeniden hesaplanır (içe alınan her dosya bu çalışmada doğrulanmış olur).
    nonisolated static func stagedMatches(url: URL, record: BackupFileRecord) -> Bool {
        stagedIsComplete(url: url, bytes: record.bytes) && (try? BackupBlobID.sha256(of: url)) == record.sha256
    }

    @concurrent
    nonisolated private static func stagedIsVerified(_ file: BackupFileRecord, at url: URL) async -> Bool {
        stagedMatches(url: url, record: file)
    }

    /// Geçici sayılan indirme hataları (bağlantı koptu, dosya bozuk indi). 401/404 ve iptal yeniden denenmez.
    nonisolated static func isRetryableDownload(_ error: Error) -> Bool {
        guard let error = error as? APIError else { return false }
        return error.code == "network" || error.code == APIError.backupHashMismatchCode
    }

    /// Yeniden denemelerden önceki beklemeler (sn); deneme sayısı bunun bir fazlasıdır.
    nonisolated static let downloadRetryDelays: [Double] = [1, 3]

    /// İlerleme bayt üzerinden: küçük JSON'lar çubuğu doldurup büyük seslerde takılmasın.
    nonisolated static func restoreProgress(done: Int64, total: Int64) -> Double {
        total > 0 ? min(1, max(0, Double(done) / Double(total))) : 1
    }

    /// Geri yükleme hatasının ekran metni; indirme yarıda kaldıysa sürdürülebildiğini de söyler.
    nonisolated static func restoreFailureText(_ error: Error) -> String {
        isRetryableDownload(error)
            ? "\(error.localizedDescription) İnen dosyalar saklandı; yeniden denediğinde kaldığı yerden sürer."
            : error.localizedDescription
    }

    /// Kullanıcı geri yüklemeyi durdurdu (inen dosyalar hazırlıkta kalır).
    nonisolated static let restoreStoppedText = "Geri yükleme durduruldu. İnen dosyalar saklandı; yeniden denediğinde kaldığı yerden sürer."

    /// Kullanıcı elle yedeği durdurdu. Sayı verilmez: iptal edilen turda yüklenen dosyalar sayılamıyor (`run` 0 döndürür).
    nonisolated static let backupStoppedText = "Yedek durduruldu. Gönderilen dosyalar sunucuda kaldı; sonraki yedek kaldığı yerden sürer."

    private static func download(_ file: BackupFileRecord, to destination: URL) async throws {
        var attempt = 0
        while true {
            do {
                try await APIClient.shared.backupDownload(sha256: file.sha256, to: destination)
                return
            } catch {
                guard attempt < downloadRetryDelays.count, isRetryableDownload(error) else { throw error }
                try await Task.sleep(for: .seconds(downloadRetryDelays[attempt]))
                attempt += 1
            }
        }
    }

    /// Geri yükleme hazırlık kökü. Caches altında: iCloud yedeğine girmez, sistem yer açmak için silebilir (o zaman yeniden iner).
    nonisolated static var restoreStagingRoot: URL {
        URL.cachesDirectory.appending(path: "MacRestore", directoryHint: .isDirectory)
    }

    /// Snapshot kimliği sunucudan gelir; klasör adı olarak özeti kullanılır (yol ayırıcı ya da ".." taşıyamaz).
    nonisolated static func stagingName(snapshotID: String) -> String {
        SHA256.hash(data: Data(snapshotID.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Sürdürülmeyen hazırlık bu süreden sonra silinir (Caches'te yüzlerce MB kalmasın).
    nonisolated static let stagingMaxAge: TimeInterval = 7 * 24 * 3600

    nonisolated static func isStagingStale(created: Date?, now: Date = .now) -> Bool {
        guard let created else { return true }
        return now.timeIntervalSince(created) > stagingMaxAge
    }

    /// Açılışta (geri yükleme başlamadan önce) çağrılır: sürdürülmemiş eski hazırlık klasörlerini siler.
    nonisolated static func purgeStaleStaging(now: Date = .now) {
        let fm = FileManager.default
        for url in (try? fm.contentsOfDirectory(at: restoreStagingRoot, includingPropertiesForKeys: [.creationDateKey])) ?? []
        where isStagingStale(created: (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate, now: now) {
            try? fm.removeItem(at: url)
        }
    }

    /// Yarıda kalmış başka bir yedeğin hazırlığı artık kullanılmaz; yalnız `keep` kalır.
    nonisolated private static func removeStaging(except keep: URL) {
        let fm = FileManager.default
        for url in (try? fm.contentsOfDirectory(at: restoreStagingRoot, includingPropertiesForKeys: nil)) ?? []
        where url.lastPathComponent != keep.lastPathComponent {
            try? fm.removeItem(at: url)
        }
    }

    /// Sunucudan gelen yol yedek kökünün dışına çıkamaz (".." yok, mutlak değil, boş parça yok).
    nonisolated static func safeRelativePath(_ path: String) -> String? {
        guard !path.isEmpty, path.count <= 300, !path.hasPrefix("/"), !path.contains("\\") else { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.allSatisfy({ !$0.isEmpty && $0 != ".." && $0 != "." }) else { return nil }
        let allowedRoots: Set<Substring> = ["manifest.json", "Audio", "EpisodeFiles", "Documents", "VoiceNotes", "Videos", "Tools", "IkraSupport", "QuestionArchive"]
        guard let first = parts.first, allowedRoots.contains(first) else { return nil }
        return path
    }
}

/// Hash'i hesaplanmış yedek dosyası.
nonisolated struct BackupItem: Hashable, Sendable {
    var record: BackupFileRecord
    var url: URL
}

/// `(yedek yolu, boyut, mtime)` → SHA-256 önbelleği (Application Support/MacBackup/hashes.json).
nonisolated enum BackupHashCache {
    struct Entry: Codable, Hashable, Sendable {
        var bytes: Int64
        var mtime: Double
        var sha256: String
    }

    static var fileURL: URL { MacBackup.workDirectory.appending(path: "hashes.json") }

    static func load(from url: URL = fileURL) -> [String: Entry] {
        (try? JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: url))) ?? [:]
    }

    static func save(_ cache: [String: Entry], to url: URL = fileURL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(cache).write(to: url, options: .atomic)
    }

    /// Değişmeyen dosya (aynı yol, boyut, mtime) yeniden okunmaz. Kaybolan dosya atlanır; önbellek yalnız var olanları tutar.
    /// İptalde `cache` o ana kadar hesaplananlarla güncellenir (eski kayıtlar korunur) ve `CancellationError` fırlatılır.
    static func items(for entries: [Backup.Entry], cache: inout [String: Entry],
                      isCancelled: () -> Bool = { Task.isCancelled }) throws -> (items: [BackupItem], hashed: Int) {
        var out: [BackupItem] = []
        var next: [String: Entry] = [:]
        var hashed = 0
        for entry in entries {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: entry.url.path),
                  let size = (attrs[.size] as? NSNumber)?.int64Value else { continue }
            let mtime = ((attrs[.modificationDate] as? Date) ?? .distantPast).timeIntervalSince1970
            let sha: String
            if let hit = cache[entry.path], hit.bytes == size, hit.mtime == mtime {
                sha = hit.sha256
            } else {
                if isCancelled() {
                    cache.merge(next) { _, new in new }
                    throw CancellationError()
                }
                sha = try sha256(of: entry.url)
                hashed += 1
            }
            next[entry.path] = Entry(bytes: size, mtime: mtime, sha256: sha)
            out.append(BackupItem(record: BackupFileRecord(path: entry.path, sha256: sha, bytes: size, mtime: mtime), url: entry.url))
        }
        cache = next
        return (out, hashed)
    }

    static func sha256(of url: URL) throws -> String { try BackupBlobID.sha256(of: url) }
}

// MARK: - Ekranlar

/// Kütüphanede: cihaz boşsa ve Mac'te yedek varsa geri yükleme önerisi. Bu kurulum hiç yedeklemediyse ve Mac'te
/// önceki yedekler varsa (otomatik yedek tutuluyor) geri yükleme ya da yeni yedek başlatma seçeneği.
struct MacRestoreBanner: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @AppStorage(MacBackup.holdKey) private var holdRaw = ""
    @State private var snapshot: BackupSnapshotInfo?
    @State private var deviceEmpty = true
    @State private var restoring = false
    @State private var startingNew = false
    @State private var progress = 0.0
    @State private var message: String?
    @State private var canRetry = false
    @State private var dismissed = false
    /// Süren geri yükleme ya da yedek; "Vazgeç"/"Durdur" bunu iptal eder.
    @State private var task: Task<Void, Never>?
    @State private var backupProgress: String?

    var body: some View {
        Group {
            if let snapshot, !dismissed {
                VStack(alignment: .leading, spacing: 10) {
                    Label(deviceEmpty ? "Sunucuda yedeğin var" : "Sunucuda önceki yedeklerin var", systemImage: "externaldrive.badge.icloud")
                        .font(.subheadline.bold())
                    Text("\(snapshot.date?.formatted(date: .abbreviated, time: .shortened) ?? snapshot.createdAt) · \(snapshot.files) dosya · \(ByteCountFormatter.string(fromByteCount: snapshot.bytes, countStyle: .file))")
                        .font(.caption).foregroundStyle(.secondary)
                    if !deviceEmpty, message == nil {
                        Text("Otomatik yedek, sunucudaki eski yedekleri silmemek için bekliyor. Geri yüklersen eksik kayıtlar eklenir; var olanlar değişmez.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if restoring || startingNew {
                        if restoring { ProgressView(value: progress) } else { ProgressView() }
                        ViewThatFits(in: .horizontal) {
                            HStack { busyText; Spacer(minLength: 8); stopButton }
                            VStack(alignment: .leading) { busyText; stopButton }
                        }
                    } else if let message {
                        Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
                        // Yarıda kalan geri yükleme buradan sürdürülebilsin; sonuç iletisi okununca bant kapatılabilsin.
                        if canRetry {
                            ViewThatFits(in: .horizontal) {
                                HStack { restoreButton; laterButton }
                                VStack(alignment: .leading) { restoreButton; laterButton }
                            }
                        } else {
                            Button("Kapat") { dismissed = true }
                                .buttonStyle(.bordered)
                                .frame(minHeight: 44)
                        }
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack { restoreButton; if !deviceEmpty { newBackupButton }; laterButton }
                            VStack(alignment: .leading) { restoreButton; if !deviceEmpty { newBackupButton }; laterButton }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .task(id: "\(app.server != nil)-\(holdRaw)") { await check() }
    }

    /// Eski yedekler istenmiyorsa: bu cihazdan yeni yedek (otomatik yedek bundan sonra çalışır).
    // Meşgul bayrağı görev kurulmadan önce, dokunuşla aynı anda kalkar: ardışık iki dokunuş iki iş başlatamaz.
    private var newBackupButton: some View {
        Button("Yeni yedek başlat") {
            guard !restoring, !startingNew else { return }
            startingNew = true
            task = Task { await startNewBackup() }
        }
        .buttonStyle(.bordered)
        .frame(minHeight: 44)
    }

    private var restoreButton: some View {
        Button("Geri yükle") {
            guard !restoring, !startingNew else { return }
            restoring = true
            task = Task { await restore() }
        }
        .buttonStyle(.borderedProminent)
        .frame(minHeight: 44)
    }

    private var busyText: some View {
        Text(restoring ? "Geri yükleniyor… %\(Int(progress * 100))" : backupProgress ?? "Yedekleniyor…")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var stopButton: some View {
        Button(restoring ? "Vazgeç" : "Durdur") { task?.cancel() }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
    }

    private var laterButton: some View {
        Button("Şimdi değil") { dismissed = true }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
    }

    private func check() async {
        // Başka yerde (Mac yedeği ekranı) karar verildiyse bant kalkar. Buradan başlatılan iş sürerken kalkmaz:
        // elle yedek tutmayı hemen kaldırır; ilerleme, "Durdur" ve sonuç iletisi görünür kalmalı.
        if snapshot != nil, !deviceEmpty, message == nil, !restoring, !startingNew, MacBackup.pendingHold == nil { snapshot = nil; return }
        guard snapshot == nil, app.serverSupports("backup1") else { return }
        let episodes = (try? context.fetchCount(FetchDescriptor<Episode>())) ?? 1
        let cards = (try? context.fetchCount(FetchDescriptor<ReviewCard>())) ?? 1
        let notes = (try? context.fetchCount(FetchDescriptor<CornellNote>())) ?? 1
        let empty = episodes == 0 && cards == 0 && notes == 0
        guard empty || MacBackup.pendingHold == .foreignSnapshots else { return }
        let latest = await MacBackup.latestSnapshot()
        if empty {
            guard MacBackup.shouldSuggestRestore(episodes: episodes, cards: cards, notes: notes, hasSnapshot: latest != nil) else { return }
        }
        deviceEmpty = empty
        snapshot = latest
    }

    private func startNewBackup() async {
        startingNew = true
        backupProgress = nil
        defer { startingNew = false; task = nil }
        // Bütçe doldukça sürdürülür: büyük ilk yedekte defalarca basmak gerekmez.
        let result = await MacBackup.runManual(context: context) { backupProgress = "\($0) dosya gönderildi, sürüyor…" }
        if Task.isCancelled { message = MacBackup.backupStoppedText; return }
        switch result.outcome {
        case .done: message = "Bu cihazın yedeği alındı; otomatik yedek açık."
        case .partial: message = "Yedeğin bir kısmı gönderildi; kalanı sonraki yedekte."
        case .unavailable: message = "Sunucuya ulaşılamadı."
        case .busy: message = "Üretim, yedek ya da geri yükleme sürüyor; sonra tekrar dene."
        case let .failed(text): message = text
        // Sunucunun kota iletisi ev ağındaki Mac'i anlatır; ekranda kendi metnimiz gösterilir.
        case .quotaExceeded: message = MacBackupView.quotaBannerText
        case .held: message = nil
        }
    }

    private func restore() async {
        restoring = true
        defer { restoring = false; task = nil }
        guard let snapshot else { return }
        canRetry = false
        progress = 0
        do {
            message = try await MacBackup.restore(snapshotID: snapshot.id, context: context) { progress = $0 }.text
        } catch {
            // İptal ağ katmanından başka bir hata olarak da dönebilir; görev iptal edildiyse "durduruldu" denir.
            if error is CancellationError || Task.isCancelled {
                message = MacBackup.restoreStoppedText
                canRetry = true
            } else {
                message = "Geri yüklenemedi: \(MacBackup.restoreFailureText(error))"
                canRetry = MacBackup.isRetryableDownload(error)
            }
        }
    }
}

/// Sunucu yedeği durumu: otomatik yedek, şimdi yedekle, snapshot'lar, geri yükleme ve (kota dolunca) eski yedeği silme.
struct MacBackupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @State private var auto = MacBackup.isAutoEnabled
    @AppStorage(MacBackup.cellularKey) private var cellular = false
    @State private var snapshots: [BackupSnapshotInfo] = []
    @State private var running = false
    @State private var status: String?
    @State private var confirmRestore: BackupSnapshotInfo?
    @State private var confirmDelete: BackupSnapshotInfo?
    @State private var deleting: String?
    @State private var progress: Double?
    /// Geri yüklenen yedek: gösterge dokunulan satırda da çıkar.
    @State private var restoringID: String?
    @State private var quotaFull = MacBackup.quotaExceededAt != nil
    @State private var listError: String?
    @State private var listLoading = false
    @State private var restoreTask: Task<Void, Never>?
    @State private var backupTask: Task<Void, Never>?
    @State private var skippedText: String?
    /// Yalnız Debug (`-p7BackupWarnings`): eskimiş yedek uyarısının örnek gün sayısı.
    @State private var staleDemo: Int?

    /// Yedek, silme ya da geri yükleme sürüyor: ikinci bir iş başlatılamaz, sayfa aşağı çekilerek kapanmaz.
    private var busy: Bool { running || deleting != nil || progress != nil }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Otomatik yedekle", isOn: $auto)
                        .onChange(of: auto) { _, on in MacBackup.isAutoEnabled = on }
                    Toggle("Hücresel veride de yedekle", isOn: $cellular)
                        .disabled(!auto)
                    LabeledContent("Son yedek", value: MacBackup.lastBackupAt?.formatted(date: .abbreviated, time: .shortened) ?? "Henüz yok")
                    if let check = QSBackupReadback.receipt {
                        LabeledContent("Son geri açma denetimi", value: check.checkedAt.formatted(date: .abbreviated, time: .shortened))
                        Text("\(check.listedFiles) dosyanın listesi; \(check.openedFiles) arşiv dosyası geri indirildi ve açıldı. \(check.questions.map { "\($0) soru; " } ?? "")\(check.libraryRecords) kütüphane kaydı okundu.").font(.caption)
                    }
                    if let failure = UserDefaults.standard.string(forKey: QSBackupReadback.errorKey) {
                        Text("Yedek geri okuma denetimi tamamlanamadı: " + failure).font(.caption).foregroundStyle(.orange)
                    }
                    Text("Dosya listesi her tamamlanan yedekte, kayıt arşivlerinin geri açılması haftada bir sınanır. Ses ve videoların tamamı bu haftalık denetimde yeniden indirilmez.").font(.caption).foregroundStyle(.secondary)
                    // Kota ve tutma uyarıları nedeni zaten söyler; eskimiş yedek uyarısı yalnız sessiz atlamada çıkar.
                    if auto, !quotaFull, MacBackup.pendingHold == nil,
                       let days = staleDemo ?? MacBackup.staleDays(lastAt: MacBackup.lastBackupAt) {
                        warningLabel(MacBackup.staleText(days: days), systemImage: "clock.badge.exclamationmark")
                    }
                    if let skippedText { warningLabel(skippedText, systemImage: "exclamationmark.triangle.fill") }
                    if let error = MacBackup.lastError { Text(error).font(.caption).foregroundStyle(.red) }
                    if quotaFull {
                        Label {
                            Text(Self.quotaText).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "externaldrive.badge.exclamationmark")
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                    if let hold = MacBackup.pendingHold {
                        Text(Self.holdText(hold)).font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        // Meşgul bayrağı görev kurulmadan önce kalkar: ardışık iki dokunuş iki yedek başlatamaz.
                        guard !busy else { return }
                        running = true
                        backupTask = Task { await backupNow() }
                    } label: {
                        HStack { if running { ProgressView() }; Text(running ? "Yedekleniyor…" : "Şimdi yedekle") }
                    }
                    .disabled(busy || !supported)
                    if running {
                        Button("Yedeği durdur", systemImage: "stop.circle") { backupTask?.cancel() }
                    }
                    if let status { Text(status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                } footer: {
                    Text(supported
                         ? "Günde bir kez, yalnız değişen dosyalar sunucuya gönderilir. Bağlantı yoksa sessizce atlanır. \(Self.networkText(cellular: cellular))"
                         : "Sunucu bu özelliği desteklemiyor ya da şu an ulaşılamıyor.")
                }
                if let listError {
                    Section {
                        warningLabel("Yedek listesi alınamadı: \(listError)", systemImage: "exclamationmark.triangle.fill")
                        Button {
                            Task { await load() }
                        } label: {
                            HStack { if listLoading { ProgressView() }; Label("Tekrar dene", systemImage: "arrow.clockwise") }
                        }
                        .disabled(listLoading || busy)
                    }
                }
                if !snapshots.isEmpty {
                    let roles = MacBackup.snapshotRoles(snapshots)
                    Section {
                        ForEach(snapshots) { s in
                            snapshotRow(s, expiring: roles.expiring.contains(s.id))
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if roles.deletable.contains(s.id), !busy {
                                        // Rol `.destructive` değil: satır onaydan önce listeden düşmesin.
                                        Button { confirmDelete = s } label: { Label("Sil", systemImage: "trash") }
                                            .tint(.red)
                                    }
                                }
                        }
                    } header: {
                        Text("Sunucudaki yedekler")
                    } footer: {
                        Text("Son \(MacBackup.keepSnapshots) tamamlanan yedek saklanır; yeni yedek geldikçe en eskiler kaldırılır. Bu adet sınırıdır, sabit gün garantisi değildir. Geri yüklemek için yedeğe dokun. Eski bir yedeği silmek için satırı sola kaydır; en yeni yedek silinemez.")
                    }
                }
            }
            // İlerleme ve "Vazgeç" listenin içinde değil, alta sabit: satırlar kapalıyken kaydırma konumu ne olursa olsun görünür.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let progress {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress)
                        ViewThatFits(in: .horizontal) {
                            HStack { restoreText(progress); Spacer(minLength: 8); cancelRestoreButton }
                            VStack(alignment: .leading) { restoreText(progress); cancelRestoreButton }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.bar)
                }
            }
            .navigationTitle("Sunucu yedeği")
            .navigationBarTitleDisplayMode(.inline)
            // Geri yükleme sürerken ekran kapanmaz: "Vazgeç" ve sonuç iletisi görünür kalsın.
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() }.disabled(progress != nil) } }
            .interactiveDismissDisabled(busy)
            // Sunucu durumu sonradan gelirse (özellik bayrağı) liste yeniden yüklenir.
            .task(id: supported) { await load() }
            .confirmationDialog("Bu yedek geri yüklensin mi?", isPresented: Binding(get: { confirmRestore != nil }, set: { if !$0 { confirmRestore = nil } }),
                                titleVisibility: .visible) {
                Button("Geri yükle") {
                    guard let s = confirmRestore, !busy else { return }
                    progress = 0
                    restoringID = s.id
                    restoreTask = Task { await restore(s) }
                }
            } message: {
                Text("Cihazda olmayan kayıtlar eklenir; var olanlar değişmez.")
            }
            .alert("Bu yedek sunucudan silinsin mi?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
                Button("Vazgeç", role: .cancel) {}
                Button("Yedeği sil", role: .destructive) {
                    guard let s = confirmDelete, !busy else { return }
                    deleting = s.id
                    Task { await delete(s) }
                }
            } message: {
                Text("Bu yedek ve yalnız ona ait dosyalar sunucudan kalıcı olarak silinir. Cihazdaki bölümlerin değişmez.")
            }
        }
    }

    private func snapshotRow(_ s: BackupSnapshotInfo, expiring: Bool) -> some View {
        Button {
            confirmRestore = s
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.date?.formatted(date: .abbreviated, time: .shortened) ?? s.createdAt).foregroundStyle(.primary)
                    Text("\(s.device) · \(s.files) dosya · \(ByteCountFormatter.string(fromByteCount: s.bytes, countStyle: .file))")
                        .font(.caption).foregroundStyle(.secondary)
                    if expiring {
                        Text("Sonraki yedekte sunucu kendisi siler").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if Self.rowIsWorking(s.id, deleting: deleting, restoring: restoringID) { ProgressView() }
            }
            .frame(minHeight: 44, alignment: .leading)
        }
        .disabled(busy)
    }

    /// Satırda dönen gösterge: o yedek siliniyor ya da geri yükleniyor.
    nonisolated static func rowIsWorking(_ id: String, deleting: String?, restoring: String?) -> Bool {
        id == deleting || id == restoring
    }

    private func restoreText(_ progress: Double) -> some View {
        Text("Geri yükleniyor… %\(Int(progress * 100))")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var cancelRestoreButton: some View {
        Button("Vazgeç") { restoreTask?.cancel() }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
    }

    private func warningLabel(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.caption)
        .foregroundStyle(.orange)
    }

    private var supported: Bool { app.serverSupports("backup1") }

    static let quotaText = "Sunucudaki yedek alanı doldu; yeni yedek kaydedilemiyor. Aşağıdan eski bir yedeği sola kaydırıp sil, sonra \"Şimdi yedekle\"ye bas. Otomatik yedek bir gün bekler."
    /// Kütüphanedeki bantta (yedek listesi görünmezken) kota uyarısı.
    static let quotaBannerText = "Sunucudaki yedek alanı doldu; yeni yedek kaydedilemedi. Eski yedekleri Kütüphane → Araçlar → Sunucu yedeği ekranından silebilirsin."

    static func networkText(cellular: Bool) -> String {
        cellular ? "Otomatik yedek hücresel veride de çalışır."
                 : "Otomatik yedek yalnız Wi-Fi'de çalışır; \"Şimdi yedekle\" her ağda gönderir."
    }

    static func holdText(_ hold: MacBackup.Hold) -> String {
        switch hold {
        case .deviceEmpty:
            "Otomatik yedek bekliyor: cihaz boş ve sunucuda yedeğin var. Boş yedek eskisinin yerine geçmesin diye önce geri yükle."
        case .foreignSnapshots:
            "Otomatik yedek bekliyor: sunucuda bu kurulumdan önceki yedekler var. Birini geri yükle ya da \"Şimdi yedekle\" ile bu cihazdan yeni yedeklemeye başla (sunucu son 14 yedeği tutar, eskiler zamanla silinir)."
        }
    }

    private func load() async {
        quotaFull = MacBackup.quotaExceededAt != nil
        refreshSkipped()
        #if DEBUG
        // Ekran denetimi: `-p7Sheet=backup` ile birlikte `-p7BackupWarnings` sınırı aşan dosya ve eskimiş yedek uyarılarını,
        // `-p7BackupError` liste hatasını, `-p7Quota` kota uyarısını ve örnek yedek listesini gösterir.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-p7BackupWarnings") {
            staleDemo = 5
            skippedText = MacBackup.skippedText([(name: "P7 Demo · Uzun ders kaydı", bytes: 231_000_000)])
        }
        if arguments.contains("-p7BackupError") {
            listError = "Sunucuya bağlanılamadı (örnek hata)."
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-p7Quota") {
            quotaFull = true
            let day: TimeInterval = 86_400
            snapshots = (0..<15).map { i in
                BackupSnapshotInfo(id: "demo-\(i)", createdAt: Date.now.addingTimeInterval(-Double(i) * day).ISO8601Format(),
                                   device: "iPhone", files: 120 + i, bytes: 700_000_000 + Int64(i) * 1_000_000)
            }
            return
        }
        #endif
        guard supported else { return }
        listLoading = true
        defer { listLoading = false }
        do {
            snapshots = try await APIClient.shared.backupList().sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            listError = nil
        } catch {
            // Hata yutulmaz: liste boş kalırsa neden boş olduğu ve "Tekrar dene" görünür. Önceki liste (varsa) durur.
            if !Task.isCancelled { listError = error.localizedDescription }
        }
    }

    /// Sınırı aştığı için son yedeğe girmeyen dosyalar, sahibinin (bölüm, ders, belge) adıyla.
    private func refreshSkipped() {
        let files = MacBackup.skippedFiles
        skippedText = files.isEmpty ? nil : MacBackup.skippedText(files.map { (name: ownerName(ofBackupPath: $0.path), bytes: $0.bytes) })
    }

    private func ownerName(ofBackupPath path: String) -> String {
        let file = (path as NSString).lastPathComponent
        if path.hasPrefix("Documents/") {
            return ((try? context.fetch(FetchDescriptor<SourceDocument>(predicate: #Predicate { $0.fileName == file }))) ?? []).first?.name ?? file
        }
        guard let id = MacBackup.ownerID(ofBackupPath: path) else { return file }
        if path.hasPrefix("Videos/") {
            return ((try? context.fetch(FetchDescriptor<VideoLesson>(predicate: #Predicate { $0.id == id }))) ?? []).first?.title ?? file
        }
        return ((try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id }))) ?? []).first?.title ?? file
    }

    private func backupNow() async {
        running = true
        defer { running = false; backupTask = nil }
        // Bütçe doldukça sürdürülür (en çok `manualMaxRounds` tur); arada kaç dosyanın gittiği görünür.
        let result = await MacBackup.runManual(context: context) { status = "\($0) dosya gönderildi, sürüyor…" }
        if Task.isCancelled {
            status = MacBackup.backupStoppedText
        } else {
            switch result.outcome {
            case let .done(files, _): status = "Yedeklendi: \(files) dosya, \(result.uploaded) yeni."
            case .partial: status = "\(result.uploaded) dosya gönderildi; kalanı sonraki yedekte."
            case .unavailable: status = "Sunucuya ulaşılamadı."
            case .busy: status = "Üretim, yedek ya da geri yükleme sürüyor; sonra tekrar dene."
            case let .failed(message): status = message
            // Ayrıntı ve çıkış yolu yukarıdaki kota uyarısında (`quotaText`); sunucunun iletisi gösterilmez.
            case .quotaExceeded: status = "Yeni yedek kaydedilemedi: sunucudaki yedek alanı dolu."
            case let .held(hold): status = Self.holdText(hold)
            }
        }
        await load()
    }

    private func delete(_ snapshot: BackupSnapshotInfo) async {
        deleting = snapshot.id
        defer { deleting = nil }
        do {
            let removed = try await MacBackup.deleteSnapshot(id: snapshot.id, list: snapshots)
            status = removed > 0 ? "Yedek silindi; \(removed) dosya sunucudan kaldırıldı." : "Yedek silindi."
        } catch {
            status = "Yedek silinemedi: \(error.localizedDescription)"
        }
        await load()
    }

    private func restore(_ snapshot: BackupSnapshotInfo) async {
        progress = 0
        restoringID = snapshot.id
        defer { progress = nil; restoreTask = nil; restoringID = nil }
        #if DEBUG
        // `-p7Quota` örnek listesi: ağ olmadan ilerleme, meşgul durumu ve "Vazgeç" denetlenir (hiçbir şey geri yüklenmez).
        if snapshot.id.hasPrefix("demo-") {
            do {
                for step in 1...40 {
                    try await Task.sleep(for: .milliseconds(250))
                    progress = Double(step) / 40
                }
                status = Backup.RestoreSummary(episodes: 3, cards: 120, notes: 4).text
            } catch {
                status = MacBackup.restoreStoppedText
            }
            return
        }
        #endif
        do {
            status = try await MacBackup.restore(snapshotID: snapshot.id, context: context) { progress = $0 }.text
        } catch {
            // İptal ağ katmanından başka bir hata olarak da dönebilir; görev iptal edildiyse "durduruldu" denir.
            status = error is CancellationError || Task.isCancelled ? MacBackup.restoreStoppedText : MacBackup.restoreFailureText(error)
        }
    }
}
