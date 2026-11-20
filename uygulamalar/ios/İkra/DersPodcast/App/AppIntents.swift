import AppIntents

/// Eski kısayol (kullanıcının kurduğu otomasyonlar bozulmasın diye intent olarak kalır; kısayol listesinde `ResumePlaybackIntent` var).
/// Uygulamayı açar ve ilgili ekrana yönlendirir (kütüphane `pendingRoute`'u tüketir).
struct PlayLatestEpisodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Son podcast'i çal"
    static let description = IntentDescription("En son dinlediğin ders podcast'ini kaldığı yerden çalar.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { AppState.current?.pendingRoute = "playLatest" }
        return .result()
    }
}

struct OpenReviewIntent: AppIntent {
    static let title: LocalizedStringResource = "Bugünkü tekrarları aç"
    static let description = IntentDescription("Aralıklı tekrar kartlarını açar.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { AppState.current?.pendingRoute = "review" }
        return .result()
    }
}

struct NewPodcastIntent: AppIntent {
    static let title: LocalizedStringResource = "Yeni ders podcast'i oluştur"
    static let description = IntentDescription("Yeni podcast oluşturma ekranını açar.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { AppState.current?.pendingRoute = "new" }
        return .result()
    }
}

/// Kısayollar ya da paylaş menüsü (Kestirme: "URL'leri kabul et") üzerinden: bağlantıyı Ders Stüdyosu'na ekler.
/// Uygulama açılır; içe aktarma ekranı bağlantıyla hazır gelir. Paylaşım uzantısı değil, App Intent.
struct AddLessonIntent: AppIntent {
    static let title: LocalizedStringResource = "Ders Podcast’e ders ekle"
    static let description = IntentDescription("Bir video ya da oynatma listesi bağlantısını Ders Stüdyosu'na ekler: transkript, ders notu ve kareler hazırlanır.")
    static let openAppWhenRun = true

    @Parameter(title: "Bağlantı", description: "YouTube, Vimeo ya da Dailymotion bağlantısı", requestValueDialog: "Hangi bağlantıyı ekleyeyim?")
    var url: URL

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$url) bağlantısını derslere ekle")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = url.absoluteString
        guard !ImportLinks.parse(text).isEmpty else {
            return .result(dialog: "Bu geçerli bir video bağlantısı gibi görünmüyor.")
        }
        await MainActor.run {
            ImportInbox.push(text)
            // Uygulama henüz kurulmadıysa bağlantı gelen kutusunda kalır; AppState açılışta alır.
            // Bekleyen bağlantının üzerine yazılmaz: ikinci paylaşım "\n" ile eklenir.
            if let state = AppState.current, let taken = ImportInbox.take() {
                state.pendingImportLinks = ImportInbox.merge(state.pendingImportLinks, taken)
            }
        }
        return .result(dialog: "Bağlantı Ders Podcast’e eklendi.")
    }
}

/// En çok 10 kısayol; her ifadede uygulama adı geçer, metin parametresi ifadeye girmez.
/// "Sürdür" eski "son podcast'imi çal" kısayolunun yerini alır (arka planda çalar, uygulamayı açmaz).
struct DersPodcastShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ResumePlaybackIntent(),
                    phrases: ["\(.applicationName) ile son podcast'imi çal",
                              "\(.applicationName) devam et",
                              "\(.applicationName) çal",
                              "\(.applicationName) sürdür"],
                    shortTitle: "Podcast'i sürdür", systemImageName: "play.circle")
        AppShortcut(intent: OpenReviewIntent(),
                    phrases: ["\(.applicationName) tekrarlarımı aç",
                              "\(.applicationName) ile tekrar yap"],
                    shortTitle: "Tekrarları aç", systemImageName: "rectangle.stack")
        AppShortcut(intent: AddLessonIntent(),
                    phrases: ["\(.applicationName) ile ders ekle",
                              "\(.applicationName) ile video ekle"],
                    shortTitle: "Derse video ekle", systemImageName: "play.rectangle.on.rectangle")
        AppShortcut(intent: NewPodcastIntent(),
                    phrases: ["\(.applicationName) ile yeni podcast oluştur"],
                    shortTitle: "Yeni podcast", systemImageName: "plus.circle")
        AppShortcut(intent: BookmarkPlaybackIntent(),
                    phrases: ["\(.applicationName) burayı işaretle",
                              "\(.applicationName) ile işaretle"],
                    shortTitle: "İşaretle", systemImageName: "bookmark")
        AppShortcut(intent: TakeNoteIntent(),
                    phrases: ["\(.applicationName) ile not al",
                              "\(.applicationName) not al"],
                    shortTitle: "Not al", systemImageName: "square.and.pencil")
        AppShortcut(intent: SkipBack15Intent(),
                    phrases: ["\(.applicationName) 15 saniye geri",
                              "\(.applicationName) ile geri sar"],
                    shortTitle: "15 sn geri", systemImageName: "gobackward.15")
        AppShortcut(intent: NextChapterIntent(),
                    phrases: ["\(.applicationName) sonraki konu",
                              "\(.applicationName) ile sonraki konuya geç"],
                    shortTitle: "Sonraki konu", systemImageName: "forward.end")
        AppShortcut(intent: PlayEpisodeIntent(),
                    phrases: ["\(.applicationName) ile \(\.$episode) bölümünü çal",
                              "\(.applicationName) ile bölüm çal"],
                    shortTitle: "Bölümü çal", systemImageName: "waveform")
    }
}
