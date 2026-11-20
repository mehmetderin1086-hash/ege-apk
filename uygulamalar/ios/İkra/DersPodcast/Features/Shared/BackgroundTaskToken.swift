import UIKit

/// Arka plan görevini bir kez kapatır (hem süre dolunca hem iş bitince çağrılabilir).
final class BackgroundTaskToken {
    var id: UIBackgroundTaskIdentifier = .invalid

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
