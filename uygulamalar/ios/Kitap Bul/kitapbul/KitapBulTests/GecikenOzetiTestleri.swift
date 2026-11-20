import Testing
import Foundation
@testable import _01

/// Gecikenler özeti bildiriminin gün gün sayım planı (bildirim merkezine dokunmadan).
struct GecikenOzetiTestleri {
    private var takvim: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    private func tarih(_ gun: Int, saat: Int) -> Date {
        takvim.date(from: DateComponents(year: 2026, month: 10, day: gun, hour: saat))!
    }

    @Test func herSabahOGunItibariylaGecikenlerSayilir() {
        // Dün vadesi dolan bugün gecikmiştir; bugün vadesi dolan yarın, ayın 12'sindeki 13'ünde gecikir
        let vadeler = [tarih(9, saat: 12), tarih(10, saat: 12), tarih(12, saat: 12)]
        let plan = LoanReminders.gecikenOzetPlani(vadeler: vadeler, simdi: tarih(10, saat: 8), gunSayisi: 7, calendar: takvim)
        #expect(plan.map(\.sayi) == [1, 2, 2, 3, 3, 3, 3])
        #expect(plan.first?.tarih == tarih(10, saat: 9))
        #expect(plan.last?.tarih == tarih(16, saat: 9))
    }

    @Test func saatiGecmisBugunAtlanir() {
        let vadeler = [tarih(9, saat: 12), tarih(10, saat: 12)]
        let plan = LoanReminders.gecikenOzetPlani(vadeler: vadeler, simdi: tarih(10, saat: 10), gunSayisi: 7, calendar: takvim)
        #expect(plan.map(\.sayi) == [2, 2, 2, 2, 2, 2])
        #expect(plan.first?.tarih == tarih(11, saat: 9))
    }

    @Test func varsayilanPencereBildirimHavuzunuAzTuketir() {
        let plan = LoanReminders.gecikenOzetPlani(vadeler: [tarih(1, saat: 12)], simdi: tarih(10, saat: 8), calendar: takvim)
        #expect(plan.count == LoanReminders.ozetGunSayisi && LoanReminders.ozetGunSayisi <= 3)
    }

    @Test func gecikenYoksaBildirimKurulmaz() {
        #expect(LoanReminders.gecikenOzetPlani(vadeler: [], simdi: tarih(10, saat: 8), calendar: takvim).isEmpty)
        // Vadesi bir haftadan uzak ödünç bu pencerede gecikmez
        #expect(LoanReminders.gecikenOzetPlani(vadeler: [tarih(25, saat: 12)], simdi: tarih(10, saat: 8), gunSayisi: 7, calendar: takvim).isEmpty)
        // Bugün vadesi dolan, bugün gecikmiş sayılmaz (ActiveLoan.isOverdue ile aynı ölçüt)
        let plan = LoanReminders.gecikenOzetPlani(vadeler: [tarih(10, saat: 0)], simdi: tarih(10, saat: 8), gunSayisi: 2, calendar: takvim)
        #expect(plan.map(\.sayi) == [1] && plan.first?.tarih == tarih(11, saat: 9))
    }
}
