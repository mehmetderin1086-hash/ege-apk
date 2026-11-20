import Foundation
import Observation

@Observable
final class AppState {
    enum MainTab: String, CaseIterable { case home, courses, study, library, questions, topics, exams, visuals, settings }

    /// Siri/Kestirmeler gibi görünüm dışı girişlerin ulaşabilmesi için tek örnek.
    nonisolated(unsafe) static weak var current: AppState?

    let generator = GenerationCoordinator()
    let player = PlayerController()

    private(set) var server: ServerStatus?
    private(set) var serverError: String?
    private(set) var needsToken = PersonalToken.current == nil
    /// Son başarılı durum yanıtı ve son deneme: ön plana dönüşte bayatlık denetimi için.
    private(set) var lastStatusAt: Date?
    private var lastStatusAttemptAt: Date?
    /// Başka bir ekrandan (tekrar, Siri, bildirim) açılması istenen bölüm; kütüphane bunu tüketir.
    var pendingOpenEpisode: UUID?
    /// Açılması istenen ekran (Siri/bildirim): "review", "notes".
    var pendingRoute: String?
    /// Ayarlar açılınca doğrudan gidilecek sayfa (modül içindeki ayar düğmesinden ya da Ana Sayfa'dan).
    var settingsRoute: SettingsPage?
    /// Ayarlar › Soru Çöz'den yedek geri yükleme isteği; Soru Çöz ekranı dosya seçiciyi açar.
    var questionRestoreRequested = 0
    /// "Ders Podcast’te Aç" ile gelen dosyalar.
    var incomingFiles: [URL] = []
    /// Kısayollar/paylaşım menüsünden gelen video bağlantıları (çok satırlı olabilir): Ders Stüdyosu açılıp işlenir.
    var pendingImportLinks: String?
    /// Takip edilen kanallardan gelen videoların otomatik işleme kuyruğu.
    let importQueue = ImportQueueRunner()
    /// Ana sekme; bildirimler ve bağlantılar sekme değiştirebilir.
    /// Açılışta modül ızgarası (Ana Sayfa) gelir; bildirim ve bağlantılar doğrudan modüle geçer.
    var selectedTab: MainTab = .home
    /// Bir kez gösterilecek bilgi (ör. eski Ders Video uygulamasından taşınan kayıtlar).
    var notice: String?
    /// Kuyruk çubuğuna her dokunuşta artar; Soru Çöz sekmesi toplu video kuyruğunu açar.
    var batchRequested = 0
    /// Asistanın bir modüle verdiği iş (18 Eki 2026): ekler (telefonda kopyalanmış dosyalar) ve/veya metin (konu adı, komut).
    /// İlgili modül ekranı tüketir ve nil yapar.
    var assistantHandoff: AssistantHandoff?

    init() {
        Self.current = self
        pendingImportLinks = ImportInbox.take()
    }

    struct PendingPlayback: Equatable {
        var episodeID: UUID
        var time: Double?
        var play: Bool
    }
    /// `open(_:at:play:)` ile istenen konum/çalma; bölüm ekranı (P5) tüketip nil yapar.
    var pendingPlayback: PendingPlayback?

    /// Bölümü kütüphanede açar; istenirse o ana gider ve çalar.
    func open(_ id: UUID, at time: Double? = nil, play: Bool = false) {
        pendingPlayback = (time != nil || play) ? PendingPlayback(episodeID: id, time: time, play: play) : nil
        selectedTab = .library
        pendingOpenEpisode = id
    }

    func serverSupports(_ feature: String) -> Bool { server?.features?.contains(feature) ?? false }

    /// Durum yeniden sorulmalı mı: son denemeden 10 sn geçmediyse hayır; sunucu bilinmiyorsa evet; son başarı 10 dakikadan eskiyse evet.
    nonisolated static func shouldRefreshStatus(hasServer: Bool, lastSuccess: Date?, lastAttempt: Date?, now: Date) -> Bool {
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < 10 { return false }
        guard hasServer, let lastSuccess else { return true }
        return now.timeIntervalSince(lastSuccess) > 600
    }

    /// Hata sürerken kendiliğinden yeniden deneme aralığı (sn): 5, 15, 45, sonra hep 120.
    nonisolated static func statusRetryDelay(attempt: Int) -> Int {
        let steps = [5, 15, 45, 120]
        return steps[min(max(0, attempt), steps.count - 1)]
    }

    /// Durum isteği hatasının afiş metni. İptal (yeniden deneme görevinin kimliği değişti, görünüm kapandı) hata değildir:
    /// `nil` döner, bilinen durum olduğu gibi kalır.
    nonisolated static func statusFailureMessage(_ error: any Error) -> String? {
        if error is CancellationError { return nil }
        return (error as? APIError)?.message ?? error.localizedDescription
    }

    /// `keepLastKnown`: kendiliğinden yenilemede geçici ağ hatası bilinen sunucu durumunu silmesin (özellikler bir anda kapanmasın).
    func refreshStatus(keepLastKnown: Bool = false) async {
        lastStatusAttemptAt = .now
        do {
            server = try await APIClient.shared.status()
            serverError = nil
            needsToken = false
            lastStatusAt = .now
        } catch {
            guard let message = Self.statusFailureMessage(error) else { return }
            let unauthorized = (error as? APIError)?.isUnauthorized ?? false
            if unauthorized || !keepLastKnown { server = nil }
            serverError = message
            if unauthorized { needsToken = true }
        }
    }

    /// Ön plana dönüşte: durum bayatsa ya da hiç alınamadıysa yeniden sorar.
    func refreshStatusIfStale() async {
        guard Self.shouldRefreshStatus(hasServer: server != nil, lastSuccess: lastStatusAt, lastAttempt: lastStatusAttemptAt, now: .now) else { return }
        await refreshStatus(keepLastKnown: true)
    }

    /// Bağlantı ekranından: adresi ve anahtarı kaydeder, sunucuyu dener.
    func connect(address: String, token: String) async -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == Config.defaultAPIBaseURL.absoluteString {
            UserDefaults.standard.removeObject(forKey: Config.apiBaseURLOverrideKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: Config.apiBaseURLOverrideKey)
        }
        PersonalToken.set(token)
        await refreshStatus()
        return server != nil
    }
}

/// Kısayollar'dan (App Intent) gelen bağlantılar: uygulama henüz açılmamışsa bile kaybolmasın diye UserDefaults'ta bekler.
/// Asistanın modüle verdiği iş: `module` hedef, `files` telefona kopyalanmış ekler, `text` konu/başlık ya da komut ("scan").
nonisolated struct AssistantHandoff: Identifiable, Equatable, Sendable {
    let id = UUID()
    var module: AppState.MainTab
    var files: [URL] = []
    var text: String = ""
    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
}

nonisolated enum ImportInbox {
    static let key = "youtube.importInbox"

    /// Bekleyen metne yenisini satır sonuyla ekler (üzerine yazmaz).
    static func merge(_ existing: String?, _ new: String) -> String {
        [existing, new].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func push(_ text: String) {
        UserDefaults.standard.set(merge(UserDefaults.standard.string(forKey: key), text), forKey: key)
    }

    static func take() -> String? {
        guard let text = UserDefaults.standard.string(forKey: key), !text.isEmpty else { return nil }
        UserDefaults.standard.removeObject(forKey: key)
        return text
    }
}
