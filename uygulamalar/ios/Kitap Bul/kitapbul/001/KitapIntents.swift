import Foundation
import AppIntents
import SwiftData

/// Siri, Kısayollar ve Spotlight'tan uygulamayı açmadan kullanılan işlemler.
/// Veriler uygulamanın kendi kabından okunur; uygulama henüz açılmadıysa kap burada kurulur.
enum IntentVeri {
    /// Katalog güvenli açılış bekliyor (yarım geçiş günlüğü, bozuk işaretçi ya da açılamayan depo).
    /// Siri bunu kendi başına çözmez; kullanıcıdan uygulamayı açmasını ister.
    struct GuvenliAcilisBekliyor: Error {}
    static let beklemeIletisi: IntentDialog = "Katalog güvenli açılış bekliyor; Kitap Bul'u açın"

    /// Uygulama ile AYNI güvenli kap açıcıdan geçer: yarım geçiş günlüğü varsa kap açılmaz,
    /// böylece Siri geri alınmamış yarım bir kataloğa yazamaz.
    static func context() throws -> ModelContext {
        if let shared = KitapVeritabani.shared { return ModelContext(shared) }
        guard !ArchiveSwitchJournal.hasMarker() else { throw GuvenliAcilisBekliyor() }
        let container: ModelContainer
        do { container = try StoreRecovery.openVerifiedContainer(sync: true) }
        catch { throw GuvenliAcilisBekliyor() }
        KitapVeritabani.shared = container
        return ModelContext(container)
    }

    /// Adı ya da yazarı eşleşen kitaplar (aksansız arama anahtarı üzerinden).
    static func bul(_ metin: String, context: ModelContext, limit: Int = 5) throws -> [CatalogBook] {
        let terim = CatalogMatcher.normalize(metin)
        guard !terim.isEmpty else { return [] }
        var descriptor = FetchDescriptor<CatalogBook>(predicate: #Predicate { $0.searchKey?.contains(terim) ?? false })
        descriptor.fetchLimit = 40
        let adaylar = try context.fetch(descriptor)
        // Adı tam eşleşenler öne
        return Array(adaylar
            .filter { !$0.isWithdrawn }
            .sorted { (CatalogMatcher.normalize($0.title) == terim ? 0 : 1) < (CatalogMatcher.normalize($1.title) == terim ? 0 : 1) }
            .prefix(limit))
    }

    static func durum(_ kitap: CatalogBook, loans: [ActiveLoan], copies: [BookCopy] = [], reservations: [Reservation] = []) -> String {
        let bosta = SchoolLibraryService.stock(for: kitap, loans: loans, copies: copies, reservations: reservations).available
        let yer = kitap.konumMetni ?? "yeri kayıtlı değil"
        return "“\(kitap.title)” — \(yer); " + (bosta > 0 ? "\(bosta) nüsha verilebilir." : "şu an verilebilir nüsha yok.")
    }
}

extension AppIntent {
    /// Güvenli kapı açılışı beklerken sistemin 'uygulamada devam et' akışını başlatır.
    @MainActor func katalogBaglami() throws -> ModelContext {
        do { return try IntentVeri.context() }
        catch is IntentVeri.GuvenliAcilisBekliyor {
            throw needsToContinueInForegroundError(IntentVeri.beklemeIletisi, alwaysConfirm: false)
        }
    }
}

struct KitapBulIntent: AppIntent {
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    static let title: LocalizedStringResource = "Kitap Bul"
    static let description = IntentDescription("Katalogda kitabı arar; yerini ve boşta olup olmadığını söyler.")

    @Parameter(title: "Kitap adı ya da yazar")
    var arama: String

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$arama) kitabını bul")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try katalogBaglami()
        let bulunan = try IntentVeri.bul(arama, context: context, limit: 3)
        guard !bulunan.isEmpty else {
            return .result(dialog: "“\(arama)” katalogda bulunamadı.")
        }
        let loans = try context.fetch(FetchDescriptor<ActiveLoan>())
        let copies = try context.fetch(FetchDescriptor<BookCopy>())
        let reservations = try context.fetch(FetchDescriptor<Reservation>())
        let metin = bulunan.map { IntentVeri.durum($0, loans: loans, copies: copies, reservations: reservations) }.joined(separator: "\n")
        return .result(dialog: IntentDialog(stringLiteral: metin))
    }
}

struct GecikenOdunclerIntent: AppIntent {
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }
    static let title: LocalizedStringResource = "Geciken Ödünçler"
    static let description = IntentDescription("Teslim tarihi geçmiş ödünçleri sayar ve ilk birkaçını söyler.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        let context = try katalogBaglami()
        let simdi = Calendar.current.startOfDay(for: .now)
        let geciken = (try context.fetch(FetchDescriptor<ActiveLoan>()))
            .filter { $0.dueDate < simdi }
            .sorted { $0.dueDate < $1.dueDate }
        guard !geciken.isEmpty else {
            return .result(value: 0, dialog: "Geciken ödünç yok. 🎉")
        }
        let ilkler = geciken.prefix(3).map { "\($0.studentName): \($0.bookTitleSnapshot)" }.joined(separator: "; ")
        let ek = geciken.count > 3 ? " ve \(geciken.count - 3) tane daha" : ""
        return .result(value: geciken.count, dialog: IntentDialog(stringLiteral: "\(geciken.count) geciken ödünç var: \(ilkler)\(ek)."))
    }
}

struct KitapEkleIntent: AppIntent {
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }
    static let title: LocalizedStringResource = "Kitap Ekle"
    static let description = IntentDescription("Kataloğa hızlıca kitap ekler; varsa adedini artırır. Eksik bilgiler sonra tamamlanır.")

    @Parameter(title: "Kitap adı")
    var baslik: String

    @Parameter(title: "Yazar", default: "")
    var yazar: String

    @Parameter(title: "Adet", default: 1, inclusiveRange: (1, 999))
    var adet: Int

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$baslik) kitabını ekle") {
            \.$yazar
            \.$adet
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try katalogBaglami()
        var kaydi = SesliKitapKaydi()
        kaydi.title = baslik.trimmingCharacters(in: .whitespacesAndNewlines)
        kaydi.author = yazar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : yazar
        kaydi.quantity = adet
        guard kaydi.hasBookContent else {
            return .result(dialog: "Kitap adı boş olamaz.")
        }
        let katalog = try context.fetch(FetchDescriptor<CatalogBook>())
        let sonuc = try VoiceBookSaver.save(kaydi, in: context, catalog: katalog)
        // Kapak/ISBN/kategori, uygulama açıldığında zenginleştirme kuyruğundan tamamlanır
        EnrichmentQueue.enqueue(sonuc.book.id)
        return .result(dialog: IntentDialog(stringLiteral: sonuc.message))
    }
}

struct KitapKisayollari: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: KitapBulIntent(),
            phrases: [
                "\(.applicationName) ile kitap bul",
                "\(.applicationName) kitap ara",
                "Find a book in \(.applicationName)"
            ],
            shortTitle: "Kitap Bul",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: GecikenOdunclerIntent(),
            phrases: [
                "\(.applicationName) geciken ödünçler",
                "\(.applicationName) gecikme var mı",
                "Overdue loans in \(.applicationName)"
            ],
            shortTitle: "Geciken Ödünçler",
            systemImageName: "exclamationmark.circle"
        )
        AppShortcut(
            intent: KitapEkleIntent(),
            phrases: [
                "\(.applicationName) kitap ekle",
                "\(.applicationName) ile yeni kitap kaydet",
                "Add a book to \(.applicationName)"
            ],
            shortTitle: "Kitap Ekle",
            systemImageName: "plus.circle"
        )
    }
}
