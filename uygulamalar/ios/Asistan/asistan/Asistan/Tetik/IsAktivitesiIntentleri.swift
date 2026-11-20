import ActivityKit
import AlarmKit
import AppIntents
import Foundation

/// P2.14: Live Activity düğmeleri. Bu dosya hem uygulamaya hem widget uzantısına (AsistanKontrol) derlenir: uzantı düğmenin
/// intent türünü görür, `LiveActivityIntent.perform` ise uygulama sürecinde çalışır (gerekirse uygulama arka planda açılır).

/// Uygulama süreci ile intent arasındaki köprü: `AsistanApp.init` kancayı kurar (Beyin.iptal).
@MainActor
enum IsKoprusu {
    /// Süren işi durdurur; bir şey durdurduysa true döner. Kurulmamışsa (süreç intent için yeni açıldı) ya da durduracak iş
    /// yoksa açık iş etkinlikleri doğrudan "Durduruldu" ile kapatılır (etkinlik "çalışıyor"da asılı kalmasın).
    static var durdurKancasi: (@MainActor () -> Bool)?

    static func durdur() async {
        if let k = durdurKancasi, k() { return }
        await acikEtkinlikleriKapat()
    }

    /// Saf karar (test): kapatılan etkinliğin son durumu.
    nonisolated static func durdurulmusDurum(_ s: AsistanIsNitelikleri.ContentState) -> AsistanIsNitelikleri.ContentState {
        var d = s
        d.bitti = true; d.hata = true; d.durduruldu = true; d.adim = "Durduruldu"
        return d
    }

    nonisolated static func acikEtkinlikleriKapat() async {
        for a in Activity<AsistanIsNitelikleri>.activities where a.activityState == .active || a.activityState == .stale {
            await a.end(.init(state: durdurulmusDurum(a.content.state), staleDate: nil), dismissalPolicy: .immediate)
        }
    }
}

/// Kilit ekranı / Dynamic Island "Durdur": süren asistan işini keser.
struct IsiDurdurIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Durdur"
    static let description = IntentDescription("Asistan'ın süren işini durdurur.")
    static let isDiscoverable = false

    init() {}

    @MainActor func perform() async throws -> some IntentResult {
        await IsKoprusu.durdur()
        return .result()
    }
}

/// Sonucu uygulamada açar (`asistan://sohbet?kimlik=`). Live Activity'de bunun yerine `widgetURL`/`Link` kullanılır
/// (LiveActivityIntent olmayan intent uzantı sürecinde çalışır, oradan uygulamayı açmak güvenilir değil); bu intent
/// uygulama sürecinde çalışan yüzeyler (ör. snippet) içindir.
struct SonucuAcIntent: AppIntent {
    static let title: LocalizedStringResource = "Sonucu aç"
    static let description = IntentDescription("Asistan'ın yanıtladığı sohbeti açar.")
    static let openAppWhenRun = true
    static let isDiscoverable = false

    @Parameter(title: "Sohbet") var sohbetID: String

    init() {}
    init(sohbetID: String) { self.sohbetID = sohbetID }

    @MainActor func perform() async throws -> some IntentResult & OpensIntent {
        // Bozuk kimlikte arşiv açılır (opak dönüş türü tek olmalı).
        let url = IsAktivitesiGorunum.sohbetAdresi(sohbetID) ?? URL(string: "asistan://arsiv")!
        return .result(opensIntent: OpenURLIntent(url))
    }
}

/// AlarmKit etkinliği: zamanlayıcı/alarmı durdurur. Geri sayımdaki (stop kabul etmeyen) kayıt iptal edilir.
struct AlarmDurdurIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Alarmı durdur"
    static let isDiscoverable = false

    @Parameter(title: "Alarm") var alarmKimligi: String

    init() {}
    init(alarmKimligi: String) { self.alarmKimligi = alarmKimligi }

    @MainActor func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmKimligi) else { return .result() }
        do { try AlarmManager.shared.stop(id: id) } catch { try? AlarmManager.shared.cancel(id: id) }
        return .result()
    }
}

/// AlarmKit etkinliği: geri sayımı duraklatır; duraklatılmışsa sürdürür.
struct AlarmDuraklatIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Duraklat ya da sürdür"
    static let isDiscoverable = false

    @Parameter(title: "Alarm") var alarmKimligi: String

    init() {}
    init(alarmKimligi: String) { self.alarmKimligi = alarmKimligi }

    @MainActor func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmKimligi) else { return .result() }
        let m = AlarmManager.shared
        let durum = (try? m.alarms)?.first { $0.id == id }?.state
        if durum == .paused { try? m.resume(id: id) } else { try? m.pause(id: id) }
        return .result()
    }
}
