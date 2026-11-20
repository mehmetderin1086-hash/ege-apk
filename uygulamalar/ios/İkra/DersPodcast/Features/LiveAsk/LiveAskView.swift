import AVFAudio
import Speech
import SwiftData
import SwiftUI

/// #30: sesli soru (soru cihazda yazıya dökülür, cevabı Claude yazar, cihaz sesi okur). Görüntülenen bölümün (çalan değil) konusu bağlam olur; her cevap `LiveExchange` olarak saklanır,
/// geçmiş görünür. Kapanınca podcast yalnız oturumdan önce çalıyorsa sürer. "Bana anlat" yalnız `learn2` varken:
/// bu modda konuyu dinleyici anlatır, sunucu meraklı öğrenci gibi soru sorar (sunucu `liveTeachInstruction`).
struct LiveAskView: View {
    var episode: Episode
    /// Görüntülenen konu; nil ise çalan bölümse oynatıcının konusu, değilse 0.
    var chapterIndex: Int? = nil
    @Environment(AppState.self) private var app
    @Environment(PlayerController.self) private var player
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var session = LiveSession()
    @State private var mode = "ask"
    @State private var wasPlaying = false
    @State private var resumed = false
    /// Yalnız bu bölümün kayıtları: sorgu bölüme süzülür (bütün kayıtlar her çizimde elenmez).
    @Query private var exchanges: [LiveExchange]

    init(episode: Episode, chapterIndex: Int? = nil) {
        self.episode = episode
        self.chapterIndex = chapterIndex
        _exchanges = Query(filter: LiveAskContext.exchangeFilter(episodeID: episode.id), sort: \.createdAt)
    }

    private var supportsTeach: Bool { app.serverSupports("learn2") }
    /// Geçmiş ya da açık tur varken küre küçülüp durum metninin yanına geçer: 320 nokta ekranda döküme yer kalır.
    private var compact: Bool { !exchanges.isEmpty || session.isTurnOpen }
    /// Mikrofon ya da konuşma tanıma izni reddedilmiş: yeniden başlatmak aynı hatayla biter, kullanıcı Ayarlar'a yönlendirilir.
    private var micDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied || [.denied, .restricted].contains(SFSpeechRecognizer.authorizationStatus())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if supportsTeach {
                    Picker("Mod", selection: Binding(get: { mode }, set: { restart(mode: $0) })) {
                        Text("Soru sor").tag("ask")
                        Text("Bana anlat").tag("teach")
                    }
                    .modifier(AccessiblePickerStyle())
                    .padding(.horizontal, 16)
                }
                statusHeader

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(exchanges) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    if !item.question.isEmpty {
                                        Bubble(title: LiveAskContext.userBubbleTitle(mode: item.mode), text: item.question, color: .secondary)
                                    }
                                    Bubble(title: hostName, text: item.answer, color: Theme.hostColor(.a))
                                }
                                .id(item.id)
                            }
                            if session.isTurnOpen {
                                if !session.userText.isEmpty {
                                    Bubble(title: mode == "teach" ? "Sen anlatıyorsun" : "Sen", text: session.userText, color: .secondary)
                                }
                                if !session.answerText.isEmpty {
                                    Bubble(title: hostName, text: session.answerText, color: Theme.hostColor(.a))
                                }
                                Color.clear.frame(height: 1).id("live")
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .onChange(of: session.userText) { _, _ in proxy.scrollTo("live", anchor: .bottom) }
                    .onChange(of: session.answerText) { _, _ in proxy.scrollTo("live", anchor: .bottom) }
                    .onChange(of: exchanges.count) { _, _ in if let last = exchanges.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                    .onAppear { if let last = exchanges.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
                .frame(maxHeight: .infinity)

                if session.state == .listening {
                    Button(session.isWaitingForAnswer ? "Yanıt bekleniyor…" : (mode == "teach" ? "Anlattım, sıra sende" : "Soruyu gönder")) {
                        Task { await session.submitQuestion() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.isWaitingForAnswer)
                    .accessibilityIdentifier("submitLiveQuestion")
                }
                if session.isEnded { endedButton }
                Button {
                    session.stop()
                    resumeIfNeeded()
                    dismiss()
                } label: {
                    Text(session.isEnded ? "Podcast'e dön" : "Bitir ve podcast'e dön")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .navigationTitle("Sesli soru")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if session.state == .listening || session.state == .answering {
                    ToolbarItem(placement: .topBarTrailing) { RemainingClock(session: session) }
                }
            }
        }
        .interactiveDismissDisabled(!session.isEnded && session.state != .idle)
        .task {
            #if DEBUG
            seedDemoIfRequested()
            #endif
            wasPlaying = player.isPlaying
            player.suspendForLiveSession()
            session.onExchange = { question, answer in save(question: question, answer: answer) }
            await session.start(request)
        }
        .onDisappear {
            session.stop()
            resumeIfNeeded()
        }
    }

    /// Küre ve durum metni. Kimlik korunur (tek düzen, iki yerleşim): küçülme ve yer değiştirme canlandırılır.
    /// Öncelik bu blokta: metin kendi yüksekliğini alır, kalan yer döküme kalır; alttaki düğmeler ekranda kalır.
    private var statusHeader: some View {
        let compact = self.compact
        let layout = compact ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 16))
        return layout {
            Orb(session: session, compact: compact)
            VStack(alignment: compact ? .leading : .center, spacing: compact ? 4 : 6) {
                Text(statusTitle).font(compact ? .headline : .title3.bold())
                Text(statusDetail).font(.subheadline).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(compact ? .leading : .center)
            .frame(maxWidth: .infinity, alignment: compact ? .leading : .center)
        }
        .padding(.horizontal, compact ? 16 : 24)
        .layoutPriority(1)
        .animation(.default, value: compact)
    }

    /// Oturum bitince (süre sınırı, hata) sayfadan çıkmadan yeniden başlatma; mikrofon izni yoksa Ayarlar.
    @ViewBuilder private var endedButton: some View {
        switch LiveAskContext.endedAction(micDenied: micDenied, mode: mode) {
        case .openSettings:
            Button("Ayarları aç", systemImage: "gear") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case let .restart(title):
            Button(title, systemImage: "arrow.clockwise") { Task { await session.start(request) } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("restartLiveSession")
        }
    }

    private var hostName: String { episode.settings?.displayName(for: .a) ?? "Sunucu" }

    /// Görüntülenen konu.
    private var chapter: Int {
        chapterIndex ?? (player.episode?.id == episode.id ? player.currentChapterIndex : 0)
    }

    private var statusTitle: String {
        switch session.state {
        case .idle, .connecting: "Hazırlanıyor…"
        case .listening:
            if session.isWaitingForAnswer { mode == "teach" ? "\(hostName) hazırlanıyor…" : "Yanıt bekleniyor…" }
            else { mode == "teach" ? "Seni dinliyorum" : "Dinliyorum" }
        case .answering: mode == "teach" ? "\(hostName) soruyor" : "\(hostName) cevaplıyor"
        case .ended: "Oturum bitti"
        }
    }

    private var statusDetail: String {
        switch session.state {
        case .idle, .connecting: "Mikrofon ve konuşma tanıma hazırlanıyor."
        case .listening:
            if mode == "teach" {
                session.isWaitingForAnswer
                    ? (session.userText.isEmpty ? "\(hostName) söze başlamak üzere." : "\(hostName) dinlediklerine göre bir soru hazırlıyor.")
                    : "Konuyu sen anlat; \(hostName) öğrenci gibi soru sorar. Susunca sıra ona geçer; beklemeden Anlattım’a da dokunabilirsin."
            } else if session.isWaitingForAnswer { "Sorun gönderildi. Cevap hazırlanıyor." }
            else { "Sorunu sesli sor. Susunca kendiliğinden gönderilir; beklemeden Soruyu gönder’e de dokunabilirsin." }
        case .answering:
            mode == "teach" ? "Soruları yalnızca belgendeki bilgilere dayanır." : "Cevap yalnızca belgendeki bilgilere dayanır."
        case let .ended(message):
            message ?? (mode == "teach" ? "İstediğin zaman konuyu yeniden anlatabilirsin." : "İstediğin zaman yeni bir soru sorabilirsin.")
        }
    }

    /// Oturumdan önce çalıyorsa podcast sürer (bir kez).
    private func resumeIfNeeded() {
        guard wasPlaying, !resumed else { return }
        resumed = true
        player.play()
    }

    private func restart(mode new: String) {
        guard new != mode else { return }
        // Önce durdur: süren dinleme ve okuma kapanır; tamamlanan sorular zaten kaydedilmiştir.
        session.stop()
        mode = new
        Task { await session.start(request) }
    }

    private func save(question: String, answer: String) {
        // "Bana anlat"ta soru alanı dinleyicinin anlatımıdır; açılış turunda (kullanıcı metni yok) boş kalır.
        let item = LiveExchange(episodeID: episode.id, episodeTitle: episode.title, question: question, answer: answer,
                                chapterIndex: chapter, time: player.episode?.id == episode.id ? player.currentTime : nil, mode: mode)
        context.insert(item)
        try? context.save()
    }

    private var request: VoiceAskRequest {
        LiveAskContext.request(episode: episode, chapterIndex: chapter, mode: mode, history: exchanges, learn2: supportsTeach)
    }

    #if DEBUG
    /// Yalnız Debug `-liveAskDemo`: sunucu olmadan geçmişli (küçük küreli) düzeni görmek için bu bölüme bir kez üç örnek kayıt ekler.
    private func seedDemoIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-liveAskDemo"), exchanges.isEmpty else { return }
        let samples = [("Kornea neden saydamdır?", "Kornea damarsızdır ve lifleri düzenli dizilir; ışık saçılmadan geçer."),
                       ("Işık ilk nerede kırılır?", "Işık göze girerken önce korneada kırılır, ardından mercek odağı ince ayarlar."),
                       ("", "Sert tabaka öne doğru incelip saydamlaşarak korneayı oluşturur. Bunu kendi cümlelerinle anlatır mısın?")]
        for (index, sample) in samples.enumerated() {
            context.insert(LiveExchange(episodeID: episode.id, episodeTitle: episode.title, question: sample.0, answer: sample.1,
                                        chapterIndex: chapter, time: nil, mode: index == 2 ? "teach" : "ask"))
        }
        try? context.save()
    }
    #endif
}

/// Oturum bitince sayfadan çıkmadan yapılabilecek eylem.
nonisolated enum LiveEndedAction: Equatable, Sendable {
    case openSettings
    /// Yeniden başlatma düğmesinin başlığı.
    case restart(String)
}

/// #30: canlı soru isteği (saf; test edilir). Bağlam görüntülenen bölümün `timeline`'ından alınır.
enum LiveAskContext {
    static func request(episode: Episode, chapterIndex: Int, mode: String, history: [LiveExchange], learn2: Bool) -> VoiceAskRequest {
        let timeline = episode.timeline
        let chapterTurns = timeline?.turns.filter { $0.chapterIndex == chapterIndex } ?? []
        let chapterText = chapterTurns.map(\.text).joined(separator: "\n")
        var request = VoiceAskRequest(
            title: clip(episode.title, utf16: 300),
            sourceNotes: clip(episode.script?.sourceNotes ?? "", utf16: 15_000),
            chapterTitle: clip(timeline?.chapters[safe: chapterIndex]?.title ?? "", utf16: 300),
            chapterText: clip(chapterText, utf16: 8_000),
            host: episode.settings?.hostA ?? Host(name: "Elif", voice: "Kore"))
        // Yeni alanlar yalnız sunucu `learn2` ilan ediyorsa (eski sunucu aynı isteği görür).
        if learn2 {
            request.mode = mode
            let recent = history.suffix(6).map { LiveQA(q: clip($0.question, utf16: 500), a: clip($0.answer, utf16: 1500)) }
            request.history = recent.isEmpty ? nil : Array(recent)
        }
        return request
    }

    /// "Bana anlat": ilk sözü yapay zekâ alır. Oturum açılınca bu kısa söz gönderilir; model istemdeki gibi kendini
    /// öğrenci olarak tanıtıp konuyu anlatmanı ister. "Soru sor"da nil.
    static func openingTurn(mode: String?) -> String? {
        LiveSession.openingTurn(mode: mode)
    }

    /// Bölümün canlı soru kayıtları için sorgu süzgeci (görünüm ve test aynı yüklemi kullanır).
    static func exchangeFilter(episodeID: UUID) -> Predicate<LiveExchange> {
        let id: UUID? = episodeID
        return #Predicate<LiveExchange> { $0.episodeID == id }
    }

    /// Geçmişteki kullanıcı balonunun başlığı: "Bana anlat"ta konuyu dinleyici anlatmıştır.
    static func userBubbleTitle(mode: String?) -> String { mode == "teach" ? "Sen anlattın" : "Sen" }

    /// Biten oturumda gösterilecek düğme. Mikrofon ya da konuşma tanıma izni reddedilmişse (`micDenied`) yeniden başlatmak
    /// yine aynı hatayla biter: kullanıcı Ayarlar'a yönlendirilir.
    nonisolated static func endedAction(micDenied: Bool, mode: String) -> LiveEndedAction {
        if micDenied { return .openSettings }
        return .restart(mode == "teach" ? "Yeniden anlat" : "Yeni soru sor")
    }

    /// Sunucu (zod `.max`, JS `.length`) uzunluğu UTF-16 birimiyle sayar; Swift `prefix` ise grafem sayar
    /// (emoji/birleşik harf sınırı aşar → 400). Grafem bölünmeden UTF-16 sınırına kadar kırpar.
    static func clip(_ text: String, utf16 limit: Int) -> String {
        guard text.utf16.count > limit else { return text }
        var out = ""
        var used = 0
        for character in text {
            let size = character.utf16.count
            guard used + size <= limit else { break }
            out.append(character)
            used += size
        }
        return out
    }
}

private struct Bubble: View {
    var title: String
    var text: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold()).foregroundStyle(color)
            Text(text).font(.body)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// `level` burada okunur: zamanlayıcının 100 ms'lik güncellemeleri yalnız küreyi yeniden çizer, sayfanın gövdesini değil.
private struct Orb: View {
    var session: LiveSession
    var compact = false

    var body: some View {
        let answering = session.state == .answering
        let active = answering || session.state == .listening
        let level = session.level
        let side: CGFloat = compact ? 64 : 150
        TimelineView(.animation(paused: !active)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = answering ? 0.08 * sin(t * 6) : Double(level) * 0.35
            ZStack {
                Circle()
                    .fill(answering ? Theme.warmGradient : Theme.gradient)
                    .opacity(0.25)
                    .scaleEffect(1.25 + pulse * 1.4)
                Circle()
                    .fill(answering ? Theme.warmGradient : Theme.gradient)
                    .scaleEffect(1 + pulse)
                Image(systemName: answering ? "waveform" : "mic.fill")
                    .font(.system(size: compact ? 22 : 44, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: side, height: side)
            .opacity(active ? 1 : 0.5)
        }
        .padding(compact ? 8 : 30)
        .accessibilityHidden(true)
    }
}

/// Kalan süre ayrı görünümde okunur: saniyelik güncelleme sayfanın gövdesini yeniden hesaplatmaz.
private struct RemainingClock: View {
    var session: LiveSession

    var body: some View {
        Text(Double(session.remainingSeconds).clockText)
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
    }
}
