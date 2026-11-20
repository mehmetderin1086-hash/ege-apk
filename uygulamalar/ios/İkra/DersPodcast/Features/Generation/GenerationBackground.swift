import BackgroundTasks
import Foundation
import os
import UIKit

/// #3: iOS 26+ `BGContinuedProcessingTask` ile kilitliyken üretim. Görev iş başına dinamik kaydedilir
/// (`com.mehmetderin.derspodcast.generate.<uuid>`); aynı kimlik ikinci kez kaydedilmez (çöker).
/// Uygun değilse çağıran eski `withBackgroundTime` + "açılınca sür" yoluna düşer.
@MainActor
enum GenerationBackground {
    static let prefix = "com.mehmetderin.derspodcast.generate."

    static func identifier(for id: UUID) -> String { prefix + id.uuidString.lowercased() }

    /// Bu süreçte kaydedilmiş kimlikler (ikinci kayıt çöktürür).
    private static var registered: Set<String> = []
    /// Görevi çalışan (sistem arayüzü gösterilen) üretimler.
    private(set) static var active: Set<UUID> = []
    /// Süre dolunca ya da kullanıcı sistem arayüzünden durdurunca çağrılır (üretim "duraklatıldı" olur).
    static var onExpire: ((UUID) -> Void)?

    static func isActive(_ id: UUID) -> Bool { active.contains(id) }

    private static let log = Logger(subsystem: "com.mehmetderin.derspodcast", category: "GenerationBackground")

    /// Yalnız uygulama etkinken açılabilir (sistem kuralı); açılamazsa çağıran ön plana dönünce yeniden dener.
    /// Başarılıysa true (sistem ilerleme arayüzünü gösterir).
    @discardableResult
    static func begin(_ id: UUID, title: String, subtitle: String) -> Bool {
        guard #available(iOS 26, *) else { return false }
        guard UIApplication.shared.applicationState == .active, !active.contains(id) else { return false }
        // Birim testlerinde sistem görevi açılmaz.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return false }
        let identifier = identifier(for: id)
        if !registered.contains(identifier) {
            let ok = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil, launchHandler: launchHandler(for: id))
            guard ok else {
                log.error("Sistem görevi kaydedilemedi: \(identifier, privacy: .public)")
                return false
            }
            registered.insert(identifier)
        }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
        request.strategy = .fail
        // Önceki koşudan kalan erken bitiş/ilerleme kaydı yeni görevi başlar başlamaz kapatmasın.
        let stale = TaskBox.shared.reset(id)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Reddedilen gönderimin ardından önceki gönderimin görevi hâlâ başlayabilir: kapanış kaydı geri konur.
            if let stale { TaskBox.shared.complete(id, success: stale) }
            log.error("Sistem görevi açılamadı (\(identifier, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            return false
        }
        active.insert(id)
        return true
    }

    /// Son bildirilen oran (geri gitmez; kalp atışı buradan sürer).
    private static var levels: [UUID: Double] = [:]
    /// Kalp atışının yaklaştığı üst sınır (sonraki adımın başı).
    private static var ceilings: [UUID: Double] = [:]
    private static var pulses: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]
    static let pulseInterval: Duration = .seconds(8)

    /// İlerleme (0…1) ve başlık; ilerleme bildirmeyen görev sistemce sonlandırılabilir.
    static func update(_ id: UUID, fraction: Double, title: String? = nil, subtitle: String? = nil) {
        guard active.contains(id), #available(iOS 26, *) else { return }
        let level = max(fraction, levels[id] ?? 0)
        levels[id] = level
        TaskBox.shared.update(id, fraction: level, title: title, subtitle: subtitle)
    }

    /// Ölçülemeyen uzun adımda (OCR, yükleme, plan, doğrulama, birleştirme) ilerlemeyi `ceiling`'e doğru
    /// azar azar artırır; görev açık değilse bir şey yapmaz. Yeniden çağrı yalnız sınırı günceller.
    static func pulse(_ id: UUID, toward ceiling: Double) {
        guard active.contains(id) else { return }
        ceilings[id] = min(ceiling, 0.995)
        guard pulses[id] == nil else { return }
        let token = UUID()
        let task = Task {
            defer { if pulses[id]?.token == token { pulses[id] = nil } }
            while !Task.isCancelled {
                try? await Task.sleep(for: pulseInterval)
                guard !Task.isCancelled, active.contains(id), let ceiling = ceilings[id] else { return }
                let next = PulseMath.next(levels[id] ?? 0, toward: ceiling)
                if next > (levels[id] ?? 0) { update(id, fraction: next) }
            }
        }
        pulses[id] = (token, task)
    }

    static func stopPulse(_ id: UUID) {
        pulses.removeValue(forKey: id)?.task.cancel()
        ceilings[id] = nil
    }

    /// Otomatik yeniden deneme beklenirken görev açık tutulur: başlık değişir, ilerleme son düzeyden yalnız çok az
    /// artar (ilerleme bildirmeyen görevi sistem sonlandırabilir).
    static func hold(_ id: UUID, title: String, subtitle: String) {
        guard active.contains(id) else { return }
        let level = levels[id] ?? 0
        update(id, fraction: level, title: title, subtitle: subtitle)
        // Kalp atışı tur başına en az 0,001 ilerler ve sınırın 0,002 altında durur: 0,02 pay en uzun bekleme
        // (`RetryPolicy.keepsBackgroundTask`, 2 dk) boyunca ilerleme bildirmeye yeter.
        pulse(id, toward: level + holdHeadroom)
    }

    /// Bekleme sırasında kalp atışına bırakılan pay (bkz. `hold`).
    static let holdHeadroom = 0.02

    static func finish(_ id: UUID, success: Bool) {
        stopPulse(id)
        levels[id] = nil
        guard active.remove(id) != nil, #available(iOS 26, *) else { return }
        TaskBox.shared.complete(id, success: success)
    }

    /// Sistem görevi başlattığında (arka plan kuyruğunda) çağrılır.
    @available(iOS 26, *)
    nonisolated private static func launchHandler(for id: UUID) -> @Sendable (BGTask) -> Void {
        { task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            task.progress.totalUnitCount = 1000
            TaskBox.shared.store(task, for: id)
            task.expirationHandler = {
                TaskBox.shared.complete(id, success: false)
                Task { @MainActor in
                    active.remove(id)
                    stopPulse(id)
                    levels[id] = nil
                    onExpire?(id)
                }
            }
        }
    }
}

/// Kalp atışı adımı (saf; test edilir): kalan aralığın %6'sı, en az 0,001 (sistem birimi); sınırın 0,001 altında durur.
nonisolated enum PulseMath {
    static func next(_ level: Double, toward ceiling: Double) -> Double {
        let gap = ceiling - level
        guard gap > 0.002 else { return level }
        return min(level + max(gap * 0.06, 0.001), ceiling - 0.001)
    }
}

/// Ön plana dönüşte sistem görevi açılacak işler (saf; test edilir): görevi isteyen, hâlâ süren ve görevi açık olmayanlar.
nonisolated enum BackgroundAdoption {
    static func candidates(wanted: Set<UUID>, running: Set<UUID>, active: Set<UUID>) -> Set<UUID> {
        wanted.intersection(running).subtracting(active)
    }
}

/// Sistem görevlerini kilitle korunan sözlükte tutar (görev nesnesi Sendable değil; erişim tek yerden).
nonisolated private final class TaskBox: @unchecked Sendable {
    static let shared = TaskBox()
    private let lock = NSLock()
    private var tasks: [UUID: BGTask] = [:]
    /// Görev başlamadan gelen son ilerleme (başladığında uygulanır).
    private var pending: [UUID: (Double, String?, String?)] = [:]
    /// Görev sistemce başlatılmadan iş bittiyse sonucu (başlar başlamaz kapatılır).
    private var finishedEarly: [UUID: Bool] = [:]

    func store(_ task: BGTask, for id: UUID) {
        lock.lock()
        let done = finishedEarly.removeValue(forKey: id)
        if done == nil { tasks[id] = task }
        let early = pending.removeValue(forKey: id)
        lock.unlock()
        if let done {
            task.setTaskCompleted(success: done)
            return
        }
        if let early { apply(task, early.0, early.1, early.2) }
    }

    /// Yeni gönderimden önce: görevi henüz başlamamış önceki koşunun kayıtlarını siler ve erken bitiş kaydını döndürür.
    func reset(_ id: UUID) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        pending[id] = nil
        return finishedEarly.removeValue(forKey: id)
    }

    func update(_ id: UUID, fraction: Double, title: String?, subtitle: String?) {
        lock.lock()
        let task = tasks[id]
        if task == nil { pending[id] = (fraction, title, subtitle) }
        lock.unlock()
        if let task { apply(task, fraction, title, subtitle) }
    }

    func complete(_ id: UUID, success: Bool) {
        lock.lock()
        let task = tasks.removeValue(forKey: id)
        pending[id] = nil
        if task == nil { finishedEarly[id] = success }
        lock.unlock()
        task?.setTaskCompleted(success: success)
    }

    private func apply(_ task: BGTask, _ fraction: Double, _ title: String?, _ subtitle: String?) {
        guard #available(iOS 26, *), let task = task as? BGContinuedProcessingTask else { return }
        task.progress.completedUnitCount = Int64((min(max(fraction, 0), 1) * 1000).rounded())
        if let title { task.updateTitle(title, subtitle: subtitle ?? "") }
    }
}
