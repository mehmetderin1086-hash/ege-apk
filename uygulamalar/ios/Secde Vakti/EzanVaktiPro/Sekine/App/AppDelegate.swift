import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Composition root `SekineApp.init()` tarafından, `@UIApplicationDelegateAdaptor`
    /// bu instance'ı yarattıktan hemen sonra enjekte edilir (`appDelegate.scheduler = ...`).
    /// `AppDelegate` kendi `RollingScheduler` instance'ını ASLA yaratmaz — uygulama
    /// genelinde tek kanonik instance `PrayerTimeStore` ile burası arasında paylaşılır.
    var scheduler: RollingScheduler?

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == OfficialMealStore.sessionID else { completionHandler(); return }
        OfficialMealStore.shared.backgroundCompletion = completionHandler
    }


    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if let scheduler {
            BackgroundRefresh.register(scheduler: scheduler)
        } else {
            // Olmaması gereken durum: composition root enjeksiyonu `SekineApp.init()`'te,
            // `didFinishLaunchingWithOptions`'tan ÖNCE tamamlanır (bkz. SekineApp.swift).
            assertionFailure("AppDelegate.scheduler enjekte edilmeden didFinishLaunching çağrıldı.")
        }
        return true
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Uygulama önplandayken bir vakit bildirimi tetiklenirse: banner+ses göster
    /// VE pencereyi tazele + Tam Ekran Sesli Video Ayet & Hadis Alarmını aç!
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if let prayerRaw = notification.request.content.userInfo["vakitPrayer"] as? String {
            await MainActor.run {
                NotificationCenter.default.post(name: .triggerFullScreenVakitAlarm, object: prayerRaw)
            }
        }
        await BackgroundRefresh.rescheduleFromCache()
        return [.banner, .sound, .list]
    }

    /// Kullanıcı bir bildirime dokunduğunda Tam Ekran Sesli Video Ayet & Hadis Oynatıcısını aç!
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if let prayerRaw = response.notification.request.content.userInfo["vakitPrayer"] as? String {
            await MainActor.run {
                NotificationCenter.default.post(name: .triggerFullScreenVakitAlarm, object: prayerRaw)
            }
        }
        await BackgroundRefresh.rescheduleFromCache()
    }
}
