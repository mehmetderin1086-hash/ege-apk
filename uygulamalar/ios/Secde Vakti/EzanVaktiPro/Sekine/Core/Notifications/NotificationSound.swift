import Foundation
import UserNotifications

/// Çevrimdışı bildirim sesleri; özel kayıtlar 30 saniyeden kısadır.
enum NotificationSound: String, CaseIterable, Identifiable {
    case `default`
    case chime
    case ezan          // Mekke Ezanı (≤30 sn bildirim + tam ezan)
    case ezanMedine    // Medine Ezanı (≤30 sn bildirim + tam ezan)

    case besmele, prayerCall, imsakReminder, sabahReminder, ogleReminder, ikindiReminder, aksamReminder, yatsiReminder, iftarReminder, fridayReminder, duaReminder, dhikrReminder, salawatReminder, quranReminder, gratitudeReminder, fatiha2, fatiha5, ihlas1, ihlas2, ihlas3, ihlas4

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: return "Sistem Varsayılanı"
        case .besmele: return "Besmele"
        case .prayerCall: return "Namaza davet"
        case .imsakReminder: return "İmsak hatırlatması"
        case .sabahReminder: return "Sabah namazı"
        case .ogleReminder: return "Öğle namazı"
        case .ikindiReminder: return "İkindi namazı"
        case .aksamReminder: return "Akşam namazı"
        case .yatsiReminder: return "Yatsı namazı"
        case .iftarReminder: return "İftar müjdesi"
        case .fridayReminder: return "Hayırlı cumalar"
        case .duaReminder: return "Dua molası"
        case .dhikrReminder: return "Zikir hatırlatması"
        case .salawatReminder: return "Salavat hatırlatması"
        case .quranReminder: return "Kur’an okuma vakti"
        case .gratitudeReminder: return "Şükür hatırlatması"
        case .fatiha2: return "Fâtiha · 2. âyet"
        case .fatiha5: return "Fâtiha · 5. âyet"
        case .ihlas1: return "İhlâs · 1. âyet"
        case .ihlas2: return "İhlâs · 2. âyet"
        case .ihlas3: return "İhlâs · 3. âyet"
        case .ihlas4: return "İhlâs · 4. âyet"
        case .chime: return "Huzur Çıngırağı"
        case .ezan: return "Mekke Ezanı (Makamlı)"
        case .ezanMedine: return "Medine Ezanı (Huzur)"
        }
    }

    var category: String {
        switch self {
        case .default, .chime: return "Kısa uyarılar"
        case .ezan, .ezanMedine: return "Ezanlar"
        case .besmele, .fatiha2, .fatiha5, .ihlas1, .ihlas2, .ihlas3, .ihlas4: return "Besmele ve kısa tilavetler"
        default: return "Türkçe sesli hatırlatmalar"
        }
    }
    var detail: String {
        switch self {
        case .default: return "iPhone'un bildirim sesi"
        case .chime: return "Kısa melodik uyarı"
        case .ezan, .ezanMedine: return "Kısa ezan bildirimi"
        case .besmele: return "Besmelenin tamamı"
        case .fatiha2, .fatiha5, .ihlas1, .ihlas2, .ihlas3, .ihlas4: return "Afâsî · âyetin tamamı"
        default: return "Türkçe · Aydın HD stüdyo seslendirme"
        }
    }

    /// Tüm sesler ücretsiz ve açık.
    var isPremiumSound: Bool {
        false
    }

    /// Bundle'daki dosya adı (nil → sistem varsayılanı).
    var fileName: String? {
        switch self {
        case .default: return nil
        case .besmele: return "notify-besmele.caf"
        case .prayerCall: return "notify-prayerCall.caf"
        case .imsakReminder: return "notify-imsakReminder.caf"
        case .sabahReminder: return "notify-sabahReminder.caf"
        case .ogleReminder: return "notify-ogleReminder.caf"
        case .ikindiReminder: return "notify-ikindiReminder.caf"
        case .aksamReminder: return "notify-aksamReminder.caf"
        case .yatsiReminder: return "notify-yatsiReminder.caf"
        case .iftarReminder: return "notify-iftarReminder.caf"
        case .fridayReminder: return "notify-fridayReminder.caf"
        case .duaReminder: return "notify-duaReminder.caf"
        case .dhikrReminder: return "notify-dhikrReminder.caf"
        case .salawatReminder: return "notify-salawatReminder.caf"
        case .quranReminder: return "notify-quranReminder.caf"
        case .gratitudeReminder: return "notify-gratitudeReminder.caf"
        case .fatiha2: return "notify-fatiha2.caf"
        case .fatiha5: return "notify-fatiha5.caf"
        case .ihlas1: return "notify-ihlas1.caf"
        case .ihlas2: return "notify-ihlas2.caf"
        case .ihlas3: return "notify-ihlas3.caf"
        case .ihlas4: return "notify-ihlas4.caf"
        case .chime: return "chime.caf"
        case .ezan: return "ezan.caf"
        case .ezanMedine: return "ezan-medine.caf"
        }
    }

    /// Bundle'da ses dosyası mevcut mu? (Picker'da yalnızca çalışan sesler gösterilsin diye.)
    /// `.default` dosya gerektirmediği için her zaman kullanılabilir. watchOS özel ses
    /// dosyalarını desteklemediğinden, orada yalnızca `.default` kullanılabilir sayılır
    /// (bkz. `unSound(silent:)` — aynı platform ayrımı).
    var isAvailable: Bool {
        #if os(watchOS)
        return self == .default
        #else
        guard let fileName else { return true }
        return Bundle.main.url(forResource: (fileName as NSString).deletingPathExtension,
                                withExtension: (fileName as NSString).pathExtension) != nil
        #endif
    }

    /// UNNotificationSound. Dosya bundle'da yoksa güvenli şekilde varsayılana döner.
    /// watchOS özel bildirim sesi dosyalarını desteklemiyor (`init(named:)` unavailable) —
    /// o platformda her zaman sistem varsayılanına düşülür.
    func unSound(silent: Bool) -> UNNotificationSound? {
        if silent { return nil }
        #if os(watchOS)
        return .default
        #else
        guard let fileName,
              Bundle.main.url(forResource: (fileName as NSString).deletingPathExtension,
                              withExtension: (fileName as NSString).pathExtension) != nil
        else { return .default }
        return UNNotificationSound(named: UNNotificationSoundName(fileName))
        #endif
    }
}
