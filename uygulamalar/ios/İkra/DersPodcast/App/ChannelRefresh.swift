import BackgroundTasks
import Foundation

/// BGTask tamamlama bildirimini tam bir kez yapar (görev bitişi ile süre dolumu yarışabilir).
nonisolated final class CompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let onComplete: @Sendable (Bool) -> Void

    init(_ onComplete: @escaping @Sendable (Bool) -> Void) {
        self.onComplete = onComplete
    }

    /// İlk çağrı iletilir, sonrakiler yok sayılır. İletildiyse true.
    @discardableResult
    func complete(success: Bool) -> Bool {
        let first = lock.withLock { () -> Bool in
            defer { finished = true }
            return !finished
        }
        if first { onComplete(success) }
        return first
    }
}

/// Takip edilen kanalların arka planda kontrolü (BGAppRefreshTask). Zamanında çalışması garanti değildir; açılışta da kontrol edilir.
enum ChannelRefresh {
    nonisolated static let taskIdentifier = "com.mehmetderin.derspodcast.channelRefresh"
    /// iOS'a en erken ne zaman çalıştırılabileceği (4 saat).
    nonisolated static let interval: TimeInterval = 4 * 3600

    /// Uygulama açılışında (ilk sahneden önce) bir kez çağrılır. Geri çağrı arka kuyrukta gelir: MainActor kapanışı verilmez.
    nonisolated static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refresh)
        }
    }

    /// Bir sonraki çalışmayı planlar (her çalışmada ve arka plana geçerken yeniden çağrılır).
    nonisolated static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(request)
    }

    nonisolated private static func handle(_ task: BGAppRefreshTask) {
        schedule()
        nonisolated(unsafe) let task = task
        // Süre dolumu ile normal bitiş yarışabilir: tamamlama bildirimi tek sefer.
        let gate = CompletionGate { success in task.setTaskCompleted(success: success) }
        let work = Task { @MainActor in
            // Kısa arka plan süresi: en eski kontrol edilen birkaç kanal.
            await ChannelWatcher.checkAll(context: AppDataStore.container.mainContext, minInterval: 15 * 60,
                                          limit: ChannelWatcher.backgroundChannelLimit)
            gate.complete(success: !Task.isCancelled)
        }
        task.expirationHandler = {
            work.cancel()
            gate.complete(success: false)
        }
    }
}
