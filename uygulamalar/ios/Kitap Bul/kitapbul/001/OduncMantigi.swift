import Foundation
import SwiftData
import UserNotifications
import CryptoKit
import Security

// MARK: - Ödünç merkezi: iade, uzatma, kayıp, rezervasyon

enum OduncMerkezi {
    static let enFazlaUzatma = 2
    /// İadede ayrıca işaretlenebilen hasar durumları (`BookCopy.conditions` alt kümesi).
    static let hasarliIadeDurumlari = ["Yıpranmış", "Onarım gerekli"]

    struct OduncHatasi: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Ödünç ekranlarında tarih, cihaz dilinden bağımsız olarak Türkçe yazılır (Ana Sayfa ile aynı).
    static let tarihBicimi = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale(identifier: "tr_TR"))
    static let tarihSaatBicimi = Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "tr_TR"))

    /// Son günden bu yana geçen takvim günü: son gün bugünse 0, henüz gelmediyse eksi.
    static func gecikmeGunu(sonGun: Date, now: Date = .now) -> Int {
        let takvim = Calendar.current
        return takvim.dateComponents([.day], from: takvim.startOfDay(for: sonGun), to: takvim.startOfDay(for: now)).day ?? 0
    }

    /// Ödünç satırındaki son gün metni: "12 gün gecikti", "Bugün son gün" ya da "Son gün: 3 Eki 2026".
    static func sonGunMetni(_ sonGun: Date, now: Date = .now) -> String {
        let gecikme = gecikmeGunu(sonGun: sonGun, now: now)
        if gecikme > 0 { return "\(gecikme) gün gecikti" }
        if gecikme == 0 { return "Bugün son gün" }
        return "Son gün: " + sonGun.formatted(tarihBicimi)
    }

    /// Çok nüshalı ödüncü iade alır; geçmişe yazar, hatırlatmayı iptal eder ve bekleyen
    /// rezervasyon varsa sıradaki öğrenciye haber verir.
    /// - Returns: rezervasyon bildirimi metni (varsa)
    @discardableResult
    static func iadeAl(_ loan: ActiveLoan, context: ModelContext, now: Date = .now) -> String? {
        do { return try SchoolLibraryService.returnLoan(loan, context: context, now: now) }
        catch { AppLog.write("İade kaydedilemedi"); return "İade kaydedilemedi: \(error.localizedDescription)" }
    }

    /// Sıradaki (en eski, açık, henüz haber verilmemiş) rezervasyonu işaretler ve bildirim kurar.
    @discardableResult
    static func rezervasyonuBildir(bookID: UUID, title: String, context: ModelContext, now: Date = .now) -> String? {
        guard let sirada = siradakiRezervasyon(bookID: bookID, context: context), sirada.notifiedAt == nil else { return nil }
        sirada.notifiedAt = now
        sirada.expiresAt = ReservationPolicy.ayarliBitis(from: now)
        do { try context.save() } catch { context.rollback(); return "Rezervasyon kaydedilemedi: \(error.localizedDescription)" }
        return notifyReadyReservation(sirada, title: title)
    }

    static func notifyReadyReservation(_ sirada: Reservation, title: String) -> String {
        let metin = "“\(title)” geri geldi: \(sirada.studentName)\(sirada.studentClass.isEmpty ? "" : " (\(sirada.studentClass))") için ayrıldı."
        bildirimGonder(baslik: "Rezervasyon hazır", govde: metin, kimlik: "rez-\(sirada.id.uuidString)")
        AppLog.write("Rezervasyon bildirildi")
        return metin
    }

    /// Henüz haber verilmemiş en eski açık rezervasyon (haber verilenler sırayı tıkamaz).
    static func siradakiRezervasyon(bookID: UUID, context: ModelContext) -> Reservation? {
        let id = bookID
        var descriptor = FetchDescriptor<Reservation>(
            predicate: #Predicate { $0.bookID == id && !$0.isClosed && $0.notifiedAt == nil },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    static func acikRezervasyonlar(bookID: UUID, context: ModelContext) -> [Reservation] {
        let id = bookID
        return (try? context.fetch(FetchDescriptor<Reservation>(
            predicate: #Predicate { $0.bookID == id && !$0.isClosed },
            sortBy: [SortDescriptor(\.createdAt)]
        ))) ?? []
    }

    /// Rezervasyon ekler; aynı öğrencinin aynı kitaba açık rezervasyonu varsa tekrar eklemez.
    @discardableResult
    static func rezerveEt(book: CatalogBook, student: String, className: String, context: ModelContext,
                         studentID: UUID? = nil, memberID: UUID? = nil, resolveKnownStudent: Bool = true,
                         operationID: UUID? = nil) throws -> Reservation {
        do {
            return try SchoolLibraryService.reserve(book: book, person: student, className: className, context: context,
                studentID: studentID, memberID: memberID, resolveKnownStudent: resolveKnownStudent, operationID: operationID)
        } catch let error as SchoolLibraryService.OperationError { throw OduncHatasi(message: error.message) }
    }

    /// Süre uzatma: kademe kuralı süresi kadar (yoksa varsayılan), en fazla 2 kez; kitabı
    /// bekleyen rezervasyon varsa uzatılmaz.
    @discardableResult
    static func uzat(_ loan: ActiveLoan, context: ModelContext, defaultDays: Int = 15, now: Date = .now,
                    operationID: UUID? = nil, expectedDueDate: Date? = nil, expectedExtensionCount: Int? = nil) throws -> Date {
        do {
            return try SchoolLibraryService.extendLoan(loan, context: context, defaultDays: defaultDays, now: now,
                operationID: operationID, expectedDueDate: expectedDueDate, expectedExtensionCount: expectedExtensionCount)
        } catch let error as SchoolLibraryService.OperationError { throw OduncHatasi(message: error.message) }
    }

    /// Kayıp bildirimi: ödünç kapanır, kitabın adedi düşer (tek nüshaysa "Kayıp" nedeniyle
    /// koleksiyondan düşülür), geçmişe yazılır ve paylaşılabilir tutanak metni döner.
    static func kayipBildir(_ loan: ActiveLoan, context: ModelContext, now: Date = .now) -> String {
        do { return try SchoolLibraryService.reportLost(loan, context: context, now: now) }
        catch { AppLog.write("Kayıp kaydedilemedi"); return "Kayıp kaydedilemedi: \(error.localizedDescription)" }
    }

    static func kayipTutanagi(kitapAdi: String, yazar: String, isbn: String, demirbas: String,
                              ogrenci: String, sinif: String, verilis: Date, tarih: Date) -> String {
        let bicim = Date.FormatStyle(date: .long, time: .omitted).locale(Locale(identifier: "tr_TR"))
        return """
        KAYIP KİTAP TUTANAĞI
        Tarih: \(tarih.formatted(bicim))

        Kitap: \(kitapAdi)\(yazar.isEmpty ? "" : " — \(yazar)")
        ISBN: \(isbn.isEmpty ? "-" : isbn)    Demirbaş No: \(demirbas.isEmpty ? "-" : demirbas)
        Ödünç alan: \(ogrenci)\(sinif.isEmpty ? "" : " (\(sinif))")
        Veriliş tarihi: \(verilis.formatted(bicim))

        Yukarıda bilgileri yazılı kitabın kaybolduğu öğrenci/veli beyanıyla tespit edilmiştir. \
        Kitabın aynısı ya da okul yönetimince uygun görülen eşdeğeri kütüphaneye teslim edilecektir.

        Kütüphane Sorumlusu                Öğrenci / Veli
        """
    }

    /// Veliye gönderilecek nazik mesaj şablonu: son günü geçmişse gecikme, geçmemişse
    /// hatırlatma metni. Gecikme, ekranlardaki gibi takvim günüyle sayılır. Ders kitabı için
    /// ayrı şablon kullanılır (`kind == "textbook"`).
    static func veliMesaji(ogrenci: String, sinif: String, kitap: String, sonGun: Date, okul: String = "", kind: String = "library", now: Date = .now) -> String {
        let bicim = Date.FormatStyle(date: .long, time: .omitted).locale(Locale(identifier: "tr_TR"))
        let gecikme = max(0, gecikmeGunu(sonGun: sonGun, now: now))
        let okulAdi = okul.trimmingCharacters(in: .whitespacesAndNewlines)
        let okulSatiri = okulAdi.isEmpty ? "Okul Kütüphanesi" : "\(okulAdi) Kütüphanesi"
        let kisi = "\(ogrenci)\(sinif.isEmpty ? "" : " (\(sinif))")"
        if kind == "textbook" {
            let durum = gecikme > 0
                ? "\(sonGun.formatted(bicim)) tarihinde teslim etmeliydi (\(gecikme) gün geçti). Ders kitabının en kısa sürede kütüphaneye teslim edilmesini rica ederiz."
                : "\(sonGun.formatted(bicim)) tarihine kadar teslim etmelidir. Ders kitabının zamanında kütüphaneye teslim edilmesini rica ederiz."
            return """
            Sayın Veli,
            Öğrenciniz \(kisi) için okulumuzdan verilen “\(kitap)” ders kitabını \
            \(durum) Kitap kaybolduysa lütfen bize bildirin.
            Teşekkürler,
            \(okulSatiri)
            Kütüphane sorumlusu
            """
        }
        let durum = gecikme > 0
            ? "\(sonGun.formatted(bicim)) tarihinde iade etmeliydi (\(gecikme) gün gecikti). Kitabın en kısa sürede kütüphaneye getirilmesini rica ederiz."
            : "\(sonGun.formatted(bicim)) tarihine kadar iade etmelidir. Kitabın zamanında kütüphaneye getirilmesini rica ederiz."
        return """
        Sayın Veli,
        Öğrenciniz \(kisi) kütüphanemizden aldığı “\(kitap)” kitabını \
        \(durum) Kitap kaybolduysa lütfen bize bildirin.
        Teşekkürler,
        \(okulSatiri)
        Kütüphane sorumlusu
        """
    }

    /// Bir sınıfın geciken ödünçleri için öğrenci başına bir blokluk toplu veli mesajı.
    /// Aynı öğrencinin birden çok kitabı tek blokta kitap listesiyle gelir; ders kitabı ayrı şablonla yazılır.
    static func sinifVeliMesajlari(_ loans: [ActiveLoan], okul: String = "", now: Date = .now) -> String {
        let sirali = loans.sorted { ($0.studentName, $0.dueDate) < ($1.studentName, $1.dueDate) }
        var gruplar: [(anahtar: String, loans: [ActiveLoan])] = []
        for loan in sirali {
            let anahtar = loan.memberID.map { "m:" + $0.uuidString } ?? loan.studentID.map { "s:" + $0.uuidString } ?? CatalogMatcher.normalize(loan.studentName) + "|" + loan.studentClass
            if let i = gruplar.firstIndex(where: { $0.anahtar == anahtar }) { gruplar[i].loans.append(loan) } else { gruplar.append((anahtar, [loan])) }
        }
        return gruplar.map { grup in
            let ilk = grup.loans[0]
            let numara = (ilk.studentNumberSnapshot ?? "").isEmpty ? "" : "\nOkul no: \(ilk.studentNumberSnapshot ?? "")"
            if grup.loans.count == 1 {
                return veliMesaji(ogrenci: ilk.studentName, sinif: ilk.studentClass, kitap: ilk.bookTitleSnapshot, sonGun: ilk.dueDate, okul: okul, kind: ilk.kind, now: now) + numara
            }
            let liste = grup.loans.map { "• \($0.bookTitleSnapshot) (\(OduncMerkezi.sonGunMetni($0.dueDate, now: now)))" }.joined(separator: "\n")
            let okulAdi = okul.trimmingCharacters(in: .whitespacesAndNewlines)
            return """
            Sayın Veli,
            Öğrenciniz \(ilk.studentName)\(ilk.studentClass.isEmpty ? "" : " (\(ilk.studentClass))") kütüphanemizden aldığı aşağıdaki kitapların iade tarihi gelmiş ya da geçmiştir. Kitapların en kısa sürede kütüphaneye getirilmesini rica ederiz.
            \(liste)\(numara)
            Teşekkürler,
            \(okulAdi.isEmpty ? "Okul Kütüphanesi" : "\(okulAdi) Kütüphanesi")
            Kütüphane sorumlusu
            """
        }.joined(separator: "\n\n— — —\n\n")
    }

    private static func bildirimGonder(baslik: String, govde: String, kimlik: String) {
        Task {
            await LoanReminders.requestPermissionIfNeeded()
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = baslik
            content.body = govde
            content.sound = .default
            let request = UNNotificationRequest(identifier: kimlik, content: content,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
            try? await center.add(request)
        }
    }
}

// MARK: - Kiosk PIN'i

/// PIN özetinin saklandığı yer. Üretimde Keychain; testler bellek içi sahte kullanır.
protocol KioskPINDeposu {
    func oku() -> Data?
    func yaz(_ veri: Data) throws
    func sil()
}

struct KioskPINAnahtarlik: KioskPINDeposu {
    static let servis = "com.mehmetderin.kitapbul.kiosk"
    private var sorgu: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.servis, kSecAttrAccount as String: "pin"]
    }
    func oku() -> Data? {
        var sorgu = sorgu
        sorgu[kSecReturnData as String] = true
        sorgu[kSecMatchLimit as String] = kSecMatchLimitOne
        var sonuc: CFTypeRef?
        guard SecItemCopyMatching(sorgu as CFDictionary, &sonuc) == errSecSuccess else { return nil }
        return sonuc as? Data
    }
    func yaz(_ veri: Data) throws {
        let guncelle = SecItemUpdate(sorgu as CFDictionary, [kSecValueData as String: veri] as CFDictionary)
        if guncelle == errSecSuccess { return }
        var ekle = sorgu
        ekle[kSecValueData as String] = veri
        ekle[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let durum = SecItemAdd(ekle as CFDictionary, nil)
        guard durum == errSecSuccess else { throw SchoolLibraryService.OperationError(message: "PIN güvenli depoya yazılamadı (kod \(durum)). Eski PIN korunuyor.") }
    }
    func sil() { SecItemDelete(sorgu as CFDictionary) }
}

/// Kiosktan çıkış PIN'i. Düz metin saklanmaz: Keychain'de rastgele tuzlu SHA-256 özeti tutulur.
/// Değiştirilmemiş varsayılan (1234) ya da geçersiz PIN'le kiosk açılmaz; önce yeni PIN belirlenir.
///
/// Göç: eski sürümler PIN'i `UserDefaults["kioskPIN"]` anahtarında düz metin tutardı. Geçerli bir eski değer
/// görülürse özeti yazılır, geri okunup doğrulanır ve ancak o zaman düz metin silinir. Keychain yazılamazsa
/// düz metin korunur ve `dogrula` ona düşer; kiosk kilitli kalmaz. Eski Ayarlar ekranı düz metni yeniden
/// yazarsa bir sonraki çağrıda yeni PIN olarak özete çevrilir.
enum KioskPIN {
    static let anahtar = "kioskPIN"
    static let varsayilan = "1234"
    static var depo: KioskPINDeposu = KioskPINAnahtarlik()

    static func gecerli(_ pin: String) -> Bool { sorun(pin) == nil }

    /// PIN neden kabul edilmiyor; uygunsa `nil`. `tekrar` verilirse iki girişin aynı olması da aranır.
    static func sorun(_ pin: String, tekrar: String? = nil) -> String? {
        guard (4...8).contains(pin.count), pin.allSatisfy({ ("0"..."9").contains($0) }) else { return "PIN 4–8 rakamdan oluşmalı." }
        guard pin != varsayilan else { return "1234 herkesçe bilinir; başka bir PIN seçin." }
        if let tekrar, tekrar != pin { return "İki PIN aynı değil." }
        return nil
    }

    private static func ozet(_ pin: String, tuz: Data) -> Data {
        Data(SHA256.hash(data: tuz + Data(pin.utf8)))
    }

    /// Kayıt biçimi: 1 bayt sürüm + 16 bayt tuz + 32 bayt özet.
    private static func kayitCoz(_ veri: Data?) -> (tuz: Data, ozet: Data)? {
        guard let veri, veri.count == 49, veri.first == 1 else { return nil }
        return (veri.subdata(in: 1..<17), veri.subdata(in: 17..<49))
    }

    /// Eski düz metin değeri özete taşır (idempotent).
    static func gocEt(defaults: UserDefaults = .standard) {
        guard let eski = defaults.string(forKey: anahtar), !eski.isEmpty else { return }
        guard gecerli(eski) else {
            // Geçersiz/varsayılan düz metin PIN sayılmaz; yeni PIN belirlenir.
            if kayitCoz(depo.oku()) != nil { defaults.removeObject(forKey: anahtar) }
            return
        }
        do {
            try kaydetKeychain(eski)
            guard kayitCozDogrula(eski) else { return }
            defaults.removeObject(forKey: anahtar)
        } catch {
            AppLog.write("Kiosk PIN'i güvenli depoya taşınamadı; eski değer korunuyor")
        }
    }

    private static func kayitCozDogrula(_ pin: String) -> Bool {
        guard let kayit = kayitCoz(depo.oku()) else { return false }
        return ozet(pin, tuz: kayit.tuz) == kayit.ozet
    }

    private static func kaydetKeychain(_ pin: String) throws {
        var tuz = Data(count: 16)
        let durum = tuz.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard durum == errSecSuccess else { throw SchoolLibraryService.OperationError(message: "PIN için rastgele tuz üretilemedi.") }
        try depo.yaz(Data([1]) + tuz + ozet(pin, tuz: tuz))
    }

    /// Yeni PIN'i kaydeder. Geçersizse hata atar; başarıda eski düz metin değer silinir.
    static func kaydet(_ pin: String, defaults: UserDefaults = .standard) throws {
        if let sorun = sorun(pin) { throw SchoolLibraryService.OperationError(message: sorun) }
        try kaydetKeychain(pin)
        guard kayitCozDogrula(pin) else {
            depo.sil()
            throw SchoolLibraryService.OperationError(message: "PIN kaydedildi ama geri okunamadı; eski PIN korunuyor.")
        }
        defaults.removeObject(forKey: anahtar)
    }

    /// Kiosk için geçerli bir PIN belirlenmiş mi (özet ya da henüz taşınamamış geçerli düz metin).
    static func ayarli(defaults: UserDefaults = .standard) -> Bool {
        gocEt(defaults: defaults)
        if kayitCoz(depo.oku()) != nil { return true }
        return defaults.string(forKey: anahtar).map(gecerli) ?? false
    }

    static func dogrula(_ girilen: String, defaults: UserDefaults = .standard) -> Bool {
        gocEt(defaults: defaults)
        if let kayit = kayitCoz(depo.oku()) { return ozet(girilen, tuz: kayit.tuz) == kayit.ozet }
        // Keychain boşsa ya da taşınamadıysa geçerli eski değere düşülür; yoksa PIN'siz çıkış yoktur.
        guard let eski = defaults.string(forKey: anahtar), gecerli(eski) else { return false }
        return girilen == eski
    }
}

// MARK: - Rezervasyon ayırma süresi

/// "Ayırma süresi N okul günü": hafta sonu ve tanımlı tatil aralıkları sayılmaz; bitiş,
/// başlangıçla aynı saatte N. okul gününün sonunda olur (Cuma 14:00 + 2 gün = Salı 14:00).
enum ReservationPolicy {
    nonisolated static let gunAnahtari = "reservationHoldSchoolDays"
    nonisolated static let tatilAnahtari = "reservationHolidayRanges"
    nonisolated static let varsayilanGun = 2
    nonisolated static let gunAraligi = 1...14

    nonisolated struct Tatil: Codable, Equatable, Identifiable {
        var id = UUID()
        var baslangic: Date
        var bitis: Date
        var aralik: DateInterval { DateInterval(start: min(baslangic, bitis), end: max(baslangic, bitis)) }
    }

    nonisolated static func holdExpiry(from now: Date, schoolDays: Int, holidays: [DateInterval] = [], calendar: Calendar = .current) -> Date {
        let hedef = max(1, min(schoolDays, 60))
        func okulGunu(_ gun: Date) -> Bool {
            let haftaGunu = calendar.component(.weekday, from: gun)
            guard haftaGunu != 1 && haftaGunu != 7 else { return false }
            return !holidays.contains { calendar.startOfDay(for: $0.start) <= gun && gun <= calendar.startOfDay(for: $0.end) }
        }
        var sayilan = 0
        var gun = calendar.startOfDay(for: now)
        // En kötü durumda (uzun tatil) sonsuz döngüye girmemek için üst sınır.
        for _ in 0..<800 {
            guard let sonraki = calendar.date(byAdding: .day, value: 1, to: gun) else { break }
            gun = sonraki
            if okulGunu(gun) { sayilan += 1 }
            if sayilan >= hedef { break }
        }
        let saat = calendar.dateComponents([.hour, .minute, .second], from: now)
        return calendar.date(bySettingHour: saat.hour ?? 0, minute: saat.minute ?? 0, second: saat.second ?? 0, of: gun)
            ?? now.addingTimeInterval(Double(hedef) * 86_400)
    }

    @MainActor
    static func ayarliGun(defaults: UserDefaults = .standard) -> Int {
        let deger = defaults.object(forKey: gunAnahtari) as? Int ?? varsayilanGun
        return min(max(deger, gunAraligi.lowerBound), gunAraligi.upperBound)
    }

    @MainActor
    static func ayarliTatiller(defaults: UserDefaults = .standard) -> [Tatil] {
        guard let veri = defaults.data(forKey: tatilAnahtari) else { return [] }
        let cozucu = JSONDecoder(); cozucu.dateDecodingStrategy = .iso8601
        return (try? cozucu.decode([Tatil].self, from: veri)) ?? []
    }

    @MainActor
    static func tatilleriKaydet(_ tatiller: [Tatil], defaults: UserDefaults = .standard) {
        let kodlayici = JSONEncoder(); kodlayici.dateEncodingStrategy = .iso8601
        if let veri = try? kodlayici.encode(tatiller) { defaults.set(veri, forKey: tatilAnahtari) }
    }

    /// Kullanıcının ayarlarıyla ayırma bitişi.
    @MainActor
    static func ayarliBitis(from now: Date, defaults: UserDefaults = .standard) -> Date {
        holdExpiry(from: now, schoolDays: ayarliGun(defaults: defaults), holidays: ayarliTatiller(defaults: defaults).map(\.aralik))
    }
}

// MARK: - Yetki kapısı

/// `requireAdmin` fırlatan yolların ortak girişi: yönetici değilse önce Face ID/parola istenir,
/// onay gelmezse işlem hiç başlamaz. Aynı hata iletisi her ekranda aynıdır.
enum YetkiKapisi {
    static func yoneticiyleCalistir<T>(neden: String = "Bu işlem için yönetici kimliğinizi doğrulayın",
                                       _ islem: () throws -> T) async throws -> T {
        if !YetkiDurumu.shared.yonetici {
            guard await YetkiDurumu.shared.yoneticiOl(neden: neden) else {
                throw SchoolLibraryService.OperationError(message: YetkiDurumu.shared.hata ?? "Bu işlem yönetici kimliği gerektirir.")
            }
        }
        return try islem()
    }
}

// MARK: - Ödünç kotası

/// Kişi başı ödünç sınırı: sınıfa uyan kademe kuralı, yoksa genel sınır (0 = sınırsız);
/// ayar açıksa gecikmiş kitabı olan öğrenciye yeni kitap verilmez.
enum OduncKotasi {
    static let genelSinirAnahtari = "maxLoansPerPerson"
    static let gecikmeEngeliAnahtari = "blockOverdueBorrowers"

    static func denetle(kisi: String, sinif: String, loans: [ActiveLoan], now: Date = .now,
                        kurallar: [GradeLoanRule]? = nil,
                        genelSinir: Int = UserDefaults.standard.integer(forKey: genelSinirAnahtari),
                        gecikmeEngeli: Bool = UserDefaults.standard.bool(forKey: gecikmeEngeliAnahtari),
                        studentID: UUID? = nil, memberID: UUID? = nil) throws {
        let elindeki = loans.filter { loan in
            if let memberID { return loan.memberID == memberID }
            if let studentID, loan.studentID != nil { return loan.studentID == studentID && loan.memberID == nil }
            return loan.memberID == nil && (studentID == nil || loan.identitySource != "manual")
                && CatalogMatcher.normalize(loan.studentName) == CatalogMatcher.normalize(kisi) && (sinif.isEmpty || loan.studentClass == sinif)
        }
        // Ekranlardaki "gecikmiş" ölçütüyle aynı: son gün bitmeden engellenmez
        if gecikmeEngeli, let geciken = elindeki.first(where: { $0.dueDate < Calendar.current.startOfDay(for: now) }) {
            throw OduncMerkezi.OduncHatasi(message: "\(kisi) önce gecikmiş “\(geciken.bookTitleSnapshot)” kitabını iade etmeli.")
        }
        let sinir = GradeLoanRuleStore.explicitRule(for: sinif, rules: kurallar)?.maxConcurrentLoans ?? genelSinir
        if sinir > 0, elindeki.count >= sinir {
            throw OduncMerkezi.OduncHatasi(message: "\(kisi) en fazla \(sinir) kitap alabilir (şu an \(elindeki.count)).")
        }
    }
}

// MARK: - Okuma puanı

/// Tamamlandığı bildirilen okuma puanı: zamanında iade 10, gecikmeli iade 3. Bilgisi
/// olmayan iade, ders kitabı, üye ve kimliksiz eski hareket sayılmaz. Aynı kitabı üst üste
/// alıp vermek puan şişirmesin diye her kitap kişi başına en fazla bir kez sayılır.
enum OkumaPuani {
    struct Satir: Identifiable, Equatable {
        var id: String { anahtar }
        let anahtar: String
        let ad: String
        let puan: Int
        let kitapSayisi: Int
        var studentID: UUID? = nil
        var classSnapshot: String? = nil
    }

    static func puan(for kisi: String, events: [LoanEvent]) -> Int {
        let anahtar = CatalogMatcher.normalize(kisi)
        let matches = siralama(events).filter { CatalogMatcher.normalize($0.ad) == anahtar }
        return matches.count == 1 ? matches[0].puan : 0
    }

    static func puan(for studentID: UUID, events: [LoanEvent]) -> Int {
        siralama(events).first { $0.studentID == studentID }?.puan ?? 0
    }

    static func siralama(_ events: [LoanEvent], kisiler: Set<String>? = nil) -> [Satir] {
        var enIyi: [String: [UUID: Int]] = [:]
        var adlar: [String: String] = [:]
        var kimlikler: [String: UUID] = [:]
        var siniflar: [String: String] = [:]
        var enYeni: [String: Date] = [:]
        for event in events where event.kind == .returned && event.readingCompleted == true && event.loanKind != "textbook" && event.studentID != nil && event.memberID == nil && event.identitySource != "manual" {
            let adAnahtari = CatalogMatcher.normalize(event.person)
            let anahtar = event.studentID?.uuidString ?? (adAnahtari + ((event.classSnapshot ?? "").isEmpty ? "" : "|" + (event.classSnapshot ?? "")))
            guard !adAnahtari.isEmpty, kisiler.map({ $0.contains(anahtar) || $0.contains(adAnahtari) }) ?? true else { continue }
            kimlikler[anahtar] = event.studentID
            // Sınıf ve ad girdinin sırasına bağlı değildir: en yeni olay kazanır (çok yıllık öğrenci).
            if enYeni[anahtar].map({ event.date >= $0 }) ?? true {
                enYeni[anahtar] = event.date
                siniflar[anahtar] = event.classSnapshot
                adlar[anahtar] = event.person
            }
            let deger = event.wasLate ? 3 : 10
            enIyi[anahtar, default: [:]][event.bookID] = max(enIyi[anahtar]?[event.bookID] ?? 0, deger)
        }
        return enIyi.map { anahtar, kitaplar in
            Satir(anahtar: anahtar, ad: adlar[anahtar] ?? anahtar, puan: kitaplar.values.reduce(0, +), kitapSayisi: kitaplar.count, studentID: kimlikler[anahtar], classSnapshot: siniflar[anahtar])
        }
        .sorted { $0.puan != $1.puan ? $0.puan > $1.puan : $0.ad.localizedStandardCompare($1.ad) == .orderedAscending }
    }
}

// MARK: - Sınıf atlatma

enum SinifAtlatma {
    /// "5-A" → "6-A", "9/B" → "10/B", "11A" → "12A". Son kademedeyse `nil` (mezun).
    /// Sayı içermeyen sınıf adları olduğu gibi kalır.
    static func sonrakiSinif(_ sinif: String, sonKademe: Int) -> String? {
        let karakterler = Array(sinif)
        guard let bas = karakterler.firstIndex(where: \.isNumber) else { return sinif }
        var son = bas
        while son < karakterler.count, karakterler[son].isNumber { son += 1 }
        guard let kademe = Int(String(karakterler[bas..<son])) else { return sinif }
        if kademe >= sonKademe { return nil }
        return String(karakterler[..<bas]) + String(kademe + 1) + String(karakterler[son...])
    }

    struct Plan: Identifiable, Equatable {
        var id: UUID { ogrenci.id }
        let ogrenci: Student
        /// nil = mezun (listeden çıkarılır)
        let yeniSinif: String?
    }

    static func plan(_ ogrenciler: [Student], sonKademe: Int) -> [Plan] {
        ogrenciler.map { ogrenci in
            // Sınıfı boş öğrenci yerinde kalır (mezun sayılmaz)
            let sonraki = ogrenci.className.isEmpty ? "" : sonrakiSinif(ogrenci.className, sonKademe: sonKademe)
            return Plan(ogrenci: ogrenci, yeniSinif: sonraki)
        }
    }

    /// Planı uygular: öğrenci listesi güncellenir, mezunlar çıkarılır, etkin ödünçlerin
    /// sınıf bilgisi de yenilenir (mezunların ödünçleri raporda görünmeye devam eder).
    @discardableResult
    static func uygula(_ plan: [Plan], context: ModelContext) -> (atlayan: Int, mezun: Int) {
        do { return try uygulaVerified(plan, context: context) }
        catch { AppLog.write("Sınıf atlatma uygulanamadı; eski defter korundu"); return (0, 0) }
    }

    static func uygulaVerified(_ plan: [Plan], context: ModelContext) throws -> (atlayan: Int, mezun: Int) {
        try SchoolLibraryService.requireAdmin()
        let previous = try StudentStore.allVerified()
        let previousGraduates = try GraduatedStudentStore.allVerified()
        let planIDs = Set(plan.map { $0.ogrenci.id })
        guard planIDs.count == plan.count, planIDs == Set(previous.map(\.id)),
              plan.allSatisfy({ row in previous.contains(where: { $0.id == row.ogrenci.id && $0 == row.ogrenci }) }) else {
            throw SchoolLibraryService.OperationError(message: "Öğrenci listesi plan hazırlandıktan sonra değişti; sınıf atlatma planını yeniden açın.")
        }
        let loans = try context.fetch(FetchDescriptor<ActiveLoan>())
        var next: [Student] = []
        var changed = 0, graduates = 0
        var classesByID: [UUID: String] = [:]
        var graduatesByID = Dictionary(uniqueKeysWithValues: previousGraduates.map { ($0.id, $0) })
        var legacy: [String: [String]] = [:]
        func key(_ name: String, _ className: String) -> String { CatalogMatcher.normalize(name) + "|" + className }
        for row in plan {
            let newClass = row.yeniSinif ?? "Mezun"
            classesByID[row.ogrenci.id] = newClass
            legacy[key(row.ogrenci.name, row.ogrenci.className), default: []].append(newClass)
            if let newClass = row.yeniSinif {
                var student = row.ogrenci
                if newClass != student.className { changed += 1 }
                student.className = newClass; next.append(student)
            } else {
                graduates += 1
                graduatesByID[row.ogrenci.id] = GraduatedStudent(student: row.ogrenci, graduatedAt: .now)
            }
        }
        var metadataWritten = false
        do {
            try GraduatedStudentStore.replaceAllVerified(Array(graduatesByID.values)); metadataWritten = true
            try StudentStore.replaceAllVerified(next); metadataWritten = true
            for loan in loans {
                if let id = loan.studentID, let newClass = classesByID[id] { loan.studentClass = newClass }
                else if loan.studentID == nil, loan.memberID == nil, loan.identitySource != "manual", let targets = legacy[key(loan.studentName, loan.studentClass)] {
                    if targets.count == 1 { loan.studentClass = targets[0] }
                    else { loan.needsIdentityReview = true }
                }
            }
            // Sıradaki öğrencinin yeni sınıfı rezervasyonda da görünür (mezunlar "Mezun" olur).
            for rezervasyon in try context.fetch(FetchDescriptor<Reservation>()) where !rezervasyon.isClosed && rezervasyon.memberID == nil {
                if let id = rezervasyon.studentID, let newClass = classesByID[id] { rezervasyon.studentClass = newClass }
            }
            try context.save()
        } catch {
            context.rollback()
            if metadataWritten {
                do { try StudentStore.replaceAllVerified(previous); try GraduatedStudentStore.replaceAllVerified(previousGraduates) }
                catch { throw SchoolLibraryService.OperationError(message: "Sınıf geçişi kaydedilemedi; öğrenci defteri geri alma yazımı da başarısız. Arşivden kurtarma gerekir.") }
            }
            throw error
        }
        AppLog.write("Sınıf atlatma: \(changed) öğrenci, \(graduates) mezun")
        return (changed, graduates)
    }

}

// MARK: - Öğrenci CSV sütun eşleme

enum OgrenciCSVEslestirme {
    static func satirlar(_ data: Data) -> [[String]] {
        guard let metin = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return [] }
        let temiz = metin.replacingOccurrences(of: "\u{FEFF}", with: "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let ilk = temiz.split(separator: "\n").first.map(String.init) ?? ""
        let ayirici: Character = ilk.contains(";") ? ";" : (ilk.contains("\t") ? "\t" : ",")
        let characters = Array(temiz)
        var result: [[String]] = [], row: [String] = [], value = "", quoted = false, index = 0
        func appendValue() { row.append(value.trimmingCharacters(in: .whitespacesAndNewlines)); value = "" }
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted, index + 1 < characters.count, characters[index + 1] == "\"" { value.append("\""); index += 1 }
                else { quoted.toggle() }
            } else if character == ayirici, !quoted { appendValue() }
            else if character == "\n", !quoted { appendValue(); result.append(row); row = [] }
            else { value.append(character) }
            index += 1
        }
        if !value.isEmpty || !row.isEmpty { appendValue(); result.append(row) }
        return result
    }

    /// Başlıktan sütunları tahmin eder: ad / numara / sınıf.
    static func tahmin(_ baslik: [String]) -> (ad: Int?, no: Int?, sinif: Int?) {
        // Sözcük bazlı eşleme; önce numara ve sınıf bulunur, ad sütunu bunların dışından seçilir
        let sozcukler = baslik.map { CatalogMatcher.normalize($0).split { !$0.isLetter && !$0.isNumber }.map(String.init) }
        func bul(_ anahtarlar: Set<String>, haric: Set<Int>) -> Int? {
            sozcukler.indices.first { !haric.contains($0) && !anahtarlar.isDisjoint(with: sozcukler[$0]) }
        }
        let no = bul(["numara", "numarasi", "no", "number", "numarası"], haric: [])
        let sinif = bul(["sinif", "sinifi", "sube", "subesi", "class"], haric: Set([no].compactMap { $0 }))
        let dolu = Set([no, sinif].compactMap { $0 })
        let ad = bul(["ad", "adi", "adsoyad", "soyad", "soyadi", "isim", "name", "ogrenci"], haric: dolu)
        return (ad, no, sinif)
    }

    /// Seçilen sütunlarla öğrencileri üretir (mükerrer ve adsız satırlar atlanır).
    static func ogrenciler(_ satirlar: [[String]], ad: Int, no: Int?, sinif: Int?, baslikVar: Bool) -> [Student] {
        func hucre(_ satir: [String], _ i: Int?) -> String {
            guard let i, satir.indices.contains(i) else { return "" }
            return satir[i]
        }
        return satirlar.dropFirst(baslikVar ? 1 : 0).compactMap { satir in
            let adi = hucre(satir, ad)
            guard !adi.isEmpty else { return nil }
            return Student(name: adi, number: hucre(satir, no), className: hucre(satir, sinif))
        }
    }
}
