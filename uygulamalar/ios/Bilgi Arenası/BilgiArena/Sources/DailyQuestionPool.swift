import SwiftUI
import BackgroundTasks
import UIKit

@MainActor final class DailyQuestionPool: ObservableObject {
    static let shared = DailyQuestionPool()
    static let taskIdentifier = "com.mehmetderin.bilgiarena.daily-pool"
    @Published private(set) var snapshot = PoolSnapshot()
    @Published private(set) var status = "Günlük havuz hazırlanıyor"
    @Published private(set) var running = false
    @Published private(set) var scheduleStatus = ""
    @Published var enabled: Bool { didSet {
        defaults.set(enabled,forKey:"dailyPoolEnabled")
        if enabled { schedule(); resumeIfPossible() }
        else { stop(); BGTaskScheduler.shared.cancel(taskRequestWithIdentifier:Self.taskIdentifier); status = "Otomatik üretim kapalı" }
    } }
    let database: QuestionPoolDatabase?
    let gateway: PhoneGateway
    private let defaults: UserDefaults
    private var operation: Task<Void,Never>?
    private var workerID = UUID()
    private var foreground = false
    private var busy = false
    private var backgroundRunning = false
    private var bootstrapped = false
    private var cooldowns: [String:Double]
    private var suppressed: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-new-round") || ProcessInfo.processInfo.environment["BILGI_PHONE_AUDIT"] != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    init(defaults: UserDefaults = .standard, gateway: PhoneGateway = .shared, database: QuestionPoolDatabase? = nil) {
        self.defaults = defaults; self.gateway = gateway
        enabled = defaults.object(forKey:"dailyPoolEnabled") as? Bool ?? true
        cooldowns = defaults.dictionary(forKey:"dailyPoolCooldowns") as? [String:Double] ?? [:]
        if let database { self.database = database }
        else {
            do {
                let folder = try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true).appendingPathComponent("QuestionPool",isDirectory:true)
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:folder.path)
                self.database = try QuestionPoolDatabase(url:folder.appendingPathComponent("questions.sqlite"))
            } catch { self.database = nil; status = "Soru havuzu açılamadı; depolama alanını kontrol et." }
        }
    }
    func bootstrap(packs: [QuestionPack] = [], reports: [QuestionReport] = [], history: [AnswerRecord] = []) async {
        guard let database else { return }
        do {
            try await database.insert(Seed.questions)
            for pack in packs { try await database.insert(pack.questions) }
            for report in reports { try await database.hide(report.id,hidden:true) }
            if !defaults.bool(forKey:"poolHistoryMigrated") {
                for answer in history { try await database.markPlayed(answer.question) }
                defaults.set(true,forKey:"poolHistoryMigrated")
            }
            bootstrapped = true; await refresh()
            if !running { status = enabled ? "Günlük üretim hazır" : "Otomatik üretim kapalı" }
            schedule(); resumeIfPossible()
        } catch { status = (error as? QuizError)?.message ?? "Havuz kaydı tamamlanamadı." }
    }
    func refresh() async {
        guard let database else { return }
        do { snapshot = try await database.snapshot(day:DailyPoolPlan.day(Date())) }
        catch { status = (error as? QuizError)?.message ?? "Havuz okunamadı." }
    }
    func setForeground(_ value: Bool) {
        foreground = value
        if value { resumeIfPossible() }
        else if !backgroundRunning { stop(); schedule() }
    }
    func setBusy(_ value: Bool) {
        busy = value
        if value && !backgroundRunning { stop(); status = "Oyun ve soru üretimi sonrası devam edecek" }
        else { resumeIfPossible() }
    }
    func resumeIfPossible() {
        guard enabled, bootstrapped, foreground, !busy, !suppressed, operation == nil else { return }
        workerID = UUID(); let id = workerID
        operation = Task { [weak self] in
            guard let self else { return }
            await self.run()
            guard self.workerID == id else { return }
            self.operation = nil
            self.schedule()
            guard self.enabled, self.foreground, !self.busy else { return }
            if Task.isCancelled { self.resumeIfPossible(); return }
            self.operation = Task { [weak self] in
                try? await Task.sleep(for:.seconds(60))
                guard let self, self.workerID == id else { return }
                self.operation = nil; self.resumeIfPossible()
            }
        }
    }
    func stop() { operation?.cancel() }
    func retry() {
        cooldowns = [:]; defaults.removeObject(forKey:"dailyPoolCooldowns")
        stop()
        resumeIfPossible()
    }
    func schedule() {
        guard enabled, !suppressed else { return }
        let request = BGProcessingTaskRequest(identifier:Self.taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        let tomorrow = Calendar.current.startOfDay(for:Date().addingTimeInterval(86_400))
        request.earliestBeginDate = snapshot.today >= DailyPoolPlan.target ? tomorrow : Date().addingTimeInterval(30*60)
        do { try BGTaskScheduler.shared.submit(request); scheduleStatus = "Arka plan isteği kaydedildi" }
        catch { scheduleStatus = "iOS arka plan isteğini kabul etmedi; uygulama açıkken devam eder." }
        defaults.set(scheduleStatus,forKey:"dailyPoolScheduleStatus")
        defaults.set(request.earliestBeginDate,forKey:"dailyPoolNextEarliest")
    }
    func handleBackground(_ task: BGProcessingTask) {
        guard enabled, !suppressed else { task.setTaskCompleted(success:true); return }
        // A single worker owns foreground and scheduled runs; never generate a second copy.
        operation?.cancel()
        let previous = operation
        workerID = UUID()
        backgroundRunning = true
        operation = Task { [weak self] in
            await previous?.value
            guard let self else { task.setTaskCompleted(success:false); return }
            if !self.bootstrapped { await self.bootstrap() }
            await self.run(deadline:Date().addingTimeInterval(240))
            let success = !Task.isCancelled
            self.backgroundRunning = false; self.operation = nil
            self.schedule(); task.setTaskCompleted(success:success)
            self.resumeIfPossible()
        }
        task.expirationHandler = { [weak self] in Task { @MainActor in self?.stop() } }
    }
    static func formatForBatch(_ batch: Int) -> QuestionFormat { [.visual,.listening,.ordering,.matching,.pronunciation,.mixed][max(0,batch)%6] }
    /// Bounded batches, with a durable checkpoint after every complete validated response.
    func run(maxBatches: Int? = nil, deadline: Date? = nil) async {
        guard enabled, let database, !running else { return }
        running = true
        defer { running = false }
        var batches = 0
        do {
            let inventory = try await gateway.inventory()
            let checks = defaults.data(forKey:"checks").flatMap { try? JSONDecoder().decode([String:ModelCheck].self,from:$0) } ?? [:]
            let models = PoolModelRouting.balanced(inventory.models.filter(\.textCapable),checks:checks)
            guard !models.isEmpty else { status = "CLI Proxy'de telefondan bir metin modeli bağla."; return }
            while !Task.isCancelled && enabled {
                if let deadline, Date() >= deadline { break }
                if let maxBatches, batches >= maxBatches { break }
                let day = DailyPoolPlan.day(Date())
                snapshot = try await database.snapshot(day:day)
                guard let cell = DailyPoolPlan.next(counts:snapshot.counts,day:day) else { status = "Bugünün 450 sorusu tamamlandı"; break }
                let cursor = max(0,defaults.integer(forKey:"dailyPoolModelCursor"))
                let ordered = Array(models.dropFirst(cursor % models.count)) + Array(models.prefix(cursor % models.count))
                guard let model = ordered.first(where: { cooldowns[$0,default:0] <= Date().timeIntervalSince1970 }) else {
                    status = "Modeller beklemede; kota veya bağlantı sonrası tekrar denenecek"
                    if maxBatches != nil || deadline != nil { break }
                    try await Task.sleep(for:.seconds(60)); continue
                }
                defaults.set((models.firstIndex(of:model) ?? 0)+1,forKey:"dailyPoolModelCursor")
                let current = snapshot.counts[cell,default:0]
                let needed = min(5,DailyPoolPlan.quota(cell,day:day)-current)
                let detail = Self.detail(for:cell,offset:current,day:day)
                let excluding = try await database.texts(topic:cell.topic)
                status = "\(cell.topic.rawValue) · \(cell.difficulty.rawValue) · \(model)"
                do {
                    _ = try await AIService(gateway:gateway).questions(topic:cell.topic,detail:detail,difficulty:cell.difficulty,count:needed,models:[model],excluding:excluding,diversityOffset:current,format:Self.formatForBatch(current/5 + (DailyPoolPlan.categories.firstIndex(of:cell.topic) ?? 0)*3 + (Difficulty.allCases.firstIndex(of:cell.difficulty) ?? 0)),study:cell.topic == .exam ? StudyCatalog.daily(current + DailyPoolPlan.day(Date()).utf8.reduce(0) { $0+Int($1) }) : nil,accept:{ batch in try await database.novelCandidates(batch) },
                    onBatch: { qs in
                        do { _ = try await database.insert(qs,day:day) }
                        catch is CancellationError { throw CancellationError() }
                        catch { throw PoolPersistenceFailure() }
                    },progress: { _,_,_ in })
                    let updated = try await database.snapshot(day:day)
                    if updated.today == snapshot.today { throw QuizError("Tekrarlanan sorular havuza eklenmedi.") }
                    snapshot = updated
                } catch {
                    try Task.checkCancellation()
                    if error is PoolPersistenceFailure { throw QuizError("Havuz kaydedilemedi. Depolama alanını kontrol et; tamamlanan kayıtlar korunuyor.") }
                    cooldowns[model] = Date().addingTimeInterval(30*60).timeIntervalSince1970
                    defaults.set(cooldowns,forKey:"dailyPoolCooldowns")
                    status = (error as? QuizError)?.message ?? "Model yanıtı tamamlanamadı; sıradaki model denenecek."
                    await refresh()
                }
                batches += 1
                try await Task.sleep(for:.milliseconds(500))
            }
        } catch is CancellationError { status = "Hazırlanan sorular saklandı; kaldığı yerden devam edecek" }
        catch { status = (error as? QuizError)?.message ?? "iPhone model bağlantısı bekleniyor." }
        await refresh()
    }
    static func detail(for cell: PoolCell, offset: Int, day: String) -> String {
        let rotation = (offset/5 + day.utf8.reduce(0) { $0+Int($1) })
        if cell.topic == .language {
            let languages = ["İngilizce","Almanca","Fransızca","İspanyolca","Arapça"]
            let level = cell.difficulty == .easy ? "A1-A2" : cell.difficulty == .medium ? "B1" : "B2-C1"
            return "\(languages[rotation % languages.count]) \(level); yönergeler ve açıklamalar Türkçe olsun."
        }
        if cell.topic == .exam {
            let subjects = ["TYT Türkçe anlam bilgisi","TYT temel matematik","AYT biyoloji temel kavramlar","KPSS tarih ve coğrafya","LGS fen ve matematik"]
            return subjects[rotation % subjects.count] + "; özgün alıştırma hazırla, gerçek sınav sorusunu kopyalama, güncel mevzuat sorma."
        }
        return ""
    }
}

private struct PoolPersistenceFailure: Error {}

enum PoolModelRouting {
    static func balanced(_ models: [PhoneModel], checks: [String:ModelCheck] = [:]) -> [String] {
        let groups = Dictionary(grouping:models,by:\.family)
        let families = groups.keys.sorted()
        let sorted = groups.mapValues { models in
            models.sorted { a,b in
                func rank(_ model: PhoneModel) -> Int { checks[model.id].map { $0.success ? 0 : 2 } ?? 1 }
                if rank(a) != rank(b) { return rank(a) < rank(b) }
                // Prefer distinct native account pools before aliases of a shared gateway.
                let aa = a.owner == "antigravity", ba = b.owner == "antigravity"
                return aa == ba ? a.id < b.id : !aa
            }.map(\.id)
        }
        var result: [String] = []
        for index in 0..<(sorted.values.map(\.count).max() ?? 0) {
            for family in families { if let ids = sorted[family], ids.indices.contains(index) { result.append(ids[index]) } }
        }
        return result
    }
}

final class ArenaAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey:Any]? = nil) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier:DailyQuestionPool.taskIdentifier,using:nil) { task in
            guard let task = task as? BGProcessingTask else { task.setTaskCompleted(success:false); return }
            Task { @MainActor in DailyQuestionPool.shared.handleBackground(task) }
        }
        return true
    }
}
