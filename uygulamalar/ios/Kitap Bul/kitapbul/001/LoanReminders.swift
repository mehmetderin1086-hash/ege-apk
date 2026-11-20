import Foundation
import SwiftData
import UserNotifications

/// Ödünç iade tarihi için telefon bildirimi kurar/iptal eder.
/// İlk kullanımda izin ister; izin verilmezse sessizce atlanır (uygulama çalışmaya devam eder).
enum LoanReminders {
    static func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// İade günü sabah 9'da hatırlatma kurar (tarih geçmişse hemen bildirir).
    static func schedule(bookID: UUID, title: String, person: String, dueDate: Date) {
        Task {
            await requestPermissionIfNeeded()
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = "Kitap iade günü"
            content.body = "\(title.isEmpty ? "Kitap" : title) — \(person) iade etmeli."
            content.sound = .default

            var components = Calendar.current.dateComponents([.year, .month, .day], from: dueDate)
            components.hour = 9
            let fireDate = Calendar.current.date(from: components) ?? dueDate

            let trigger: UNNotificationTrigger
            if fireDate > .now {
                trigger = UNCalendarNotificationTrigger(
                    dateMatching: Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute], from: fireDate
                    ),
                    repeats: false
                )
            } else {
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            }

            let request = UNNotificationRequest(
                identifier: identifier(for: bookID),
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    static func cancel(bookID: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier(for: bookID)])
    }

    private static func identifier(for bookID: UUID) -> String {
        "loan-\(bookID.uuidString)"
    }

    // MARK: - Gecikenler özeti

    private static let ozetOnEki = "gecikme-ozeti-"
    /// Özet kaç gün ileriye kurulur. iOS uygulama başına 64 bekleyen bildirim tutar ve iade günü
    /// bildirimleri de aynı havuzdadır; üç gün bir hafta sonunu kapsar, havuzu da az tüketir.
    nonisolated static let ozetGunSayisi = 3
    private static var ozetGorevi: Task<Void, Never>?

    /// İade günü bildirimi tek seferliktir; kitap gelmezse sonraki günlerde hatırlatan olmaz.
    /// Bu plan, önümüzdeki `gunSayisi` günün her sabahı için o gün itibarıyla vadesi geçmiş
    /// ödünç sayısını verir (`ActiveLoan.isOverdue` ile aynı ölçüt: vade, günün başından önce).
    /// Saati geçmiş bugün ve sayısı 0 olan günler plana girmez.
    nonisolated static func gecikenOzetPlani(
        vadeler: [Date], simdi: Date, gunSayisi: Int = ozetGunSayisi, saat: Int = 9, calendar: Calendar = .current
    ) -> [(tarih: Date, sayi: Int)] {
        let bugun = calendar.startOfDay(for: simdi)
        return (0..<gunSayisi).compactMap { fark in
            guard let gun = calendar.date(byAdding: .day, value: fark, to: bugun),
                  let tarih = calendar.date(bySettingHour: saat, minute: 0, second: 0, of: gun),
                  tarih > simdi else { return nil }
            let sayi = vadeler.filter { $0 < gun }.count
            return sayi > 0 ? (tarih, sayi) : nil
        }
    }

    /// Gecikenler özetini güncel ödünçlere göre yeniden kurar: `ozetGunSayisi` gün boyunca her sabah 9'da
    /// tek bildirim ("N kitabın iade tarihi geçti"). Uygulama her açıldığında ve her ödünç
    /// hareketinde yenilenir; izin yoksa sessizce atlanır (burada izin istenmez).
    /// Ders kitabı dağıtımları iade günü bildirimindeki gibi kapsam dışıdır.
    static func gecikenOzetiniYenile(context: ModelContext, simdi: Date = .now) {
        // Testler uygulamanın içinde koşar; izin verilmiş simülatörde gerçek bildirimleri yeniden yazmasın
        guard !MainTabView.testOrtami else { return }
        // Ödünçler çağrı anında okunur; art arda hareketlerde yalnız sonuncusu bildirim kurar
        guard let loans = try? context.fetch(FetchDescriptor<ActiveLoan>()) else { return }
        // Widget özeti de her hareketle yenilenir; ders kitabı dağıtımı kütüphane sayılarına karışmaz.
        let kutuphane = loans.filter { $0.kind != "textbook" }
        _ = WidgetSnapshotStore.publish(
            geciken: LoanKindFilter.gecikenKutuphane(loans: loans, now: simdi).count,
            bugunIade: kutuphane.filter { Calendar.current.isDate($0.dueDate, inSameDayAs: simdi) }.count,
            sonArsiv: AutoArchive.lastArchiveDate, now: simdi)
        let plan = gecikenOzetPlani(vadeler: loans.filter { $0.kind != "textbook" }.map(\.dueDate), simdi: simdi)
        let onceki = ozetGorevi
        onceki?.cancel()
        ozetGorevi = Task {
            // İptal, sürmekte olan `add` çağrısını geri almaz: önceki görev bitmeden yenisi
            // kurmaya başlamaz ki eski sayı güncel planın üstüne yazılmasın
            await onceki?.value
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }
            let eski = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(ozetOnEki) }
            guard !Task.isCancelled else { return }
            center.removePendingNotificationRequests(withIdentifiers: eski)

            for (tarih, sayi) in plan {
                guard !Task.isCancelled else { return }
                let content = UNMutableNotificationContent()
                content.title = "Geciken kitaplar"
                content.body = "\(sayi) kitabın iade tarihi geçti. Kimlerde olduğunu Ödünç sekmesinde görebilirsiniz."
                content.sound = .default
                let bilesenler = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: tarih)
                let request = UNNotificationRequest(
                    identifier: ozetOnEki + "\(bilesenler.year ?? 0)-\(bilesenler.month ?? 0)-\(bilesenler.day ?? 0)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: bilesenler, repeats: false)
                )
                try? await center.add(request)
            }
        }
    }
}
