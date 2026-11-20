import Foundation

/// Uygulamanın vakit beyni: cache'i yükler, gerektiğinde indirir (Diyanet → Aladhan →
/// lokal fallback zinciri), diske yazar ve bildirimleri yeniden zamanlar.
@MainActor
final class PrayerTimeStore: ObservableObject {
    @Published private(set) var schedule: PrayerSchedule?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    /// Öncelik sırası: birebir Diyanet → Aladhan (yaklaşık, konum) → lokal hesap (çevrimdışı).
    private let providers: [PrayerTimeProvider]
    private let scheduler: RollingScheduler
    private var refreshID = UUID()

    /// `scheduler`: uygulama genelinde TEK kanonik instance enjekte edilir (composition
    /// root `SekineApp.init()`) — bu tip kendi instance'ını YARATMAZ. Varsayılan değer
    /// yalnızca watchOS hedefi (kendi ayrı `WatchBackgroundRefresh`'i olan, iOS'un
    /// `BackgroundRefresh`'iyle instance paylaşmayan bağımsız bir süreç) için korunur.
    init(providers: [PrayerTimeProvider] = [
        DiyanetProvider(), AladhanProvider(), LocalCalculationProvider()
    ], scheduler: RollingScheduler = RollingScheduler()) {
        self.providers = providers
        self.scheduler = scheduler
        if let cached = PrayerCache.load() {
            self.schedule = cached
        } else {
            let defaultLoc = SavedLocation(name: "İstanbul", latitude: 41.0082, longitude: 28.9784, diyanetDistrictID: "9541")
            self.schedule = try? LocalCalculationProvider().fetchScheduleSync(for: defaultLoc)
        }
    }

    // MARK: - Türetilmiş görünümler

    var today: PrayerDay? { schedule?.day(containing: Date()) }
    var nextTime: PrayerTime? { schedule?.nextTime(after: Date()) }
    var currentTime: PrayerTime? { schedule?.currentTime(at: Date()) }

    // MARK: - Veri yaşam döngüsü

    func ensureData(for location: SavedLocation, settings: AppSettings) async {
        if needsRefresh(for: location) {
            await refresh(location: location, settings: settings)
        } else {
            await rescheduleNotifications(settings: settings)
        }
    }

    func refresh(location: SavedLocation, settings: AppSettings) async {
        let requestID = UUID()
        refreshID = requestID
        isLoading = true
        errorMessage = nil
        defer { if refreshID == requestID { isLoading = false } }

        var lastError: Error?
        for provider in providers where provider.canHandle(location) {
            do {
                let result = try await provider.fetchSchedule(for: location)
                guard refreshID == requestID, !Task.isCancelled else { return }
                guard !result.days.isEmpty else { throw PrayerProviderError.emptyResult }
                apply(result)
                isLoading = false
                // Diyanet dışı bir kaynağa düştüysek kullanıcıyı bilgilendir.
                if result.source != "diyanet" {
                    errorMessage = "Diyanet vakitleri alınamadı; yaklaşık vakitler gösteriliyor. Bağlantı gelince güncellenecek."
                }
                await rescheduleNotifications(settings: settings)
                return
            } catch {
                guard refreshID == requestID, !Task.isCancelled else { return }
                lastError = error
                continue
            }
        }
        guard refreshID == requestID, !Task.isCancelled else { return }
        errorMessage = (lastError as? PrayerProviderError)?.errorDescription
            ?? "Vakitler yüklenemedi. İnternet bağlantınızı kontrol edin."
        await rescheduleNotifications(settings: settings)
    }

    func rescheduleNotifications(settings: AppSettings) async {
        guard let schedule else { return }
        let enabled = Set(Prayer.ordered.filter { settings.isNotificationEnabled(for: $0) })
        let config = SchedulerConfig(
            enabledPrayers: enabled,
            sound: NotificationSound(rawValue: settings.notificationSound) ?? .default,
            perPrayerSounds: settings.perPrayerSounds,
            silent: settings.silentNotifications,
            preReminderMinutes: settings.preReminderMinutes,
            breakThroughFocus: settings.breakThroughFocus,
            fridayReminder: settings.fridayReminder,
            fridayReminderHour: settings.fridayReminderHour,
            specialDayGreetings: settings.specialDayGreetings,
            dailyVerse: settings.dailyVerse,
            dailyVerseHour: settings.dailyVerseHour,
            ramadanReminders: settings.ramadanReminders,
            sahurLeadMinutes: settings.sahurLeadMinutes)
        let result = await scheduler.reschedule(from: schedule, config: config)
        if !result.isFullSuccess {
            print("PrayerTimeStore: reschedule kısmen başarısız — istenen \(result.requested), " +
                  "eklendi \(result.added), başarısız \(result.failed), ertelendi \(result.deferred).")
        }
    }

    // MARK: - Yardımcılar

    private func apply(_ schedule: PrayerSchedule) {
        self.schedule = schedule
        PrayerCache.save(schedule)
    }

    /// Yeniden indirme gerekiyor mu? (konum değişti, kaynak yükseltilebilir, kapsam bitiyor)
    private func needsRefresh(for location: SavedLocation) -> Bool {
        guard let schedule else { return true }
        let sameLocation: Bool
        if let scheduleLat = schedule.latitude, let scheduleLon = schedule.longitude,
           let lat = location.latitude, let lon = location.longitude {
            sameLocation = abs(scheduleLat - lat) < 0.01 && abs(scheduleLon - lon) < 0.01
        } else {
            // Koordinat yoksa (geocode başarısız) yer adı kimlik olarak kullanılır.
            sameLocation = schedule.placeName == location.name
        }
        if !sameLocation { return true }
        // Diyanet ID'si var ama cache Diyanet değilse, birebir veriye yükselt.
        if location.diyanetDistrictID != nil, schedule.source != "diyanet" { return true }
        // Diyanet ~1 aylık pencere döner; kapsam 12 günün altına düşünce tazele
        // (bildirim penceresi ~12 gün → hep dolu kalsın).
        guard let lastDay = schedule.days.map(\.dayStart).max() else { return true }
        return lastDay.timeIntervalSinceNow < 12 * 24 * 3600
    }
}
