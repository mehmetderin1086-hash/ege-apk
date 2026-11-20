import SwiftData
import SwiftUI
import UserNotifications

/// Aralıklı tekrar oturumu: vadesi gelen kartlar.
struct ReviewView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppState.self) private var app
    @Environment(GenerationCoordinator.self) private var generator
    @Query(sort: \ReviewCard.due) private var cards: [ReviewCard]

    @AppStorage(LearningAdaptiveReview.minutesKey) private var reviewMinutes = 15
    @State private var answerTime = LearningActiveTime()
    /// Display objects have their own context, with autosave disabled. Primary writes use a fresh transaction context.
    @State private var displayContext: ModelContext?
    @State private var committedSchedules: [UUID: ReviewCard.Schedule] = [:]
    @State private var reviewError: String?
    @State private var historyNotice: String?
    @State private var session: [ReviewCard] = []
    @State private var index = 0
    @State private var revealed = false
    /// Bu turda not verilen kartlar ("Bilemedim" sonrası yeniden gelen kart bir kez sayılır).
    @State private var reviewedIDs: Set<UUID> = []
    @State private var lastAction: LastAction?
    @State private var creating = false
    @State private var createError: String?
    @State private var weakDuration = 5
    @State private var ankiURL: URL?
    @State private var reported = false
    @State private var bookSource: BookAnchor?

    private struct BookAnchor: Identifiable {
        var bookID: String
        var title: String
        var page: Int
        var id: String { "\(bookID):\(page)" }
    }

    private var dueCards: [ReviewCard] { cards.filter { (committedSchedules[$0.id]?.due ?? $0.due) <= .now } }
    /// Bir turdaki en çok kart. Yalnız Debug: `-reviewBatch=2` ile küçültülür ("Devam et" akışını az kartla denemek için).
    private var batch: Int { DebugArg.value("reviewBatch").flatMap { Int($0) }.map { max(1, $0) } ?? LearningAdaptiveReview.batch(minutes: reviewMinutes, seconds: LearningEvidenceStore.shared.events.filter { $0.source == .card }.suffix(60).compactMap(\.seconds), maximum: ReviewSummary.batch) }
    private var weakCards: [ReviewCard] { cards.filter { card in
        guard let schedule = committedSchedules[card.id] else { return card.isWeak }
        guard schedule.repetitions < 2 else { return false }
        if let last = schedule.lastLapseAt { return last > Date.now.addingTimeInterval(-30 * 86_400) }
        return schedule.lapses >= 1 || (schedule.repetitions == 0 && card.kind == .quiz)
    } }

    /// Son verilen not: tek adım geri alınabilir.
    private struct LastAction {
        var change: LearningCardSession.Change
        var reinsertedAt: Int?
        /// Kart bu turda ilk kez sayıldı (geri alınınca sayıdan düşer).
        var counted: Bool
    }

    var body: some View {
        NavigationStack {
            Group {
                if session.isEmpty {
                    overview
                } else if index < session.count {
                    cardView(session[index])
                } else {
                    finished
                }
            }
            .sheet(item: $ankiURL) { url in ShareSheet(items: [url]) }
            .fullScreenCover(item: $bookSource) { source in
                BookSourceView(bookID: source.bookID, title: source.title, page: source.page)
            }
            .background(Theme.canvas)
            .navigationTitle("Kartlarla tekrar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                if !session.isEmpty, index < session.count {
                    ToolbarItem(placement: .principal) {
                        Text("\(index + 1) / \(session.count)").font(.subheadline.monospacedDigit())
                    }
                }
                if !session.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Son notu geri al", systemImage: "arrow.uturn.backward") { undo() }
                            .disabled(lastAction == nil)
                    }
                }
            }
            .debugNarrowScreen()
            .safeAreaInset(edge: .bottom) {
                if let message = reviewError ?? historyNotice {
                    Text(message).font(.footnote).foregroundStyle(reviewError == nil ? Color.secondary : .red)
                        .padding().frame(maxWidth: .infinity).background(.regularMaterial)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in answerTime.setActive(phase == .active && !session.isEmpty && index < session.count && bookSource == nil) }
        .onChange(of: bookSource?.id) { _, source in answerTime.setActive(source == nil && scenePhase == .active && !session.isEmpty && index < session.count) }
        .onDisappear { answerTime.setActive(false) }
        .onAppear { answerTime.setActive(scenePhase == .active && !session.isEmpty && index < session.count && bookSource == nil) }
    }

    // MARK: - Genel bakış

    private var overview: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("\(dueCards.count) kart").font(.largeTitle.bold()).foregroundStyle(.tint)
                    Text(dueCards.isEmpty ? "Bugünkü tekrarların tamam." : "Bugün tekrar zamanı gelenler")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)
                Stepper("Bu oturum: \(reviewMinutes) dakika", value: $reviewMinutes, in: 3...60, step: 3)
                Text("Oturum boyutu son cevap sürelerine göre ayarlanır; kalan kartların tarihi değişmez.").font(.caption).foregroundStyle(.secondary)

                Button {
                    startSession()
                } label: {
                    Label("\(min(batch, dueCards.count)) kartla başla", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle(enabled: !dueCards.isEmpty))
                .disabled(dueCards.isEmpty)

                (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))) {
                    StatTile(value: "\(cards.count)", title: "Toplam kart")
                    StatTile(value: "\(cards.filter { (committedSchedules[$0.id]?.repetitions ?? $0.repetitions) >= 3 }.count)", title: "Öğrenildi")
                    StatTile(value: "\(weakCards.count)", title: "Zayıf")
                }

                weakTopicsCard

                Button {
                    ankiURL = try? AnkiExport.file(cards: cards)
                } label: {
                    Label("Kartları Anki'ye aktar (\(cards.count))", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(cards.isEmpty)

                Text("Kitap defterinden, kendi yazdığın kartlardan ve podcast çalışmalarından gelen kartlar burada toplanır. Kitap kartlarında cevabı açtıktan sonra kaynak sayfaya dönebilirsin.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        }
    }

    private var weakTopicsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Eksik kapatma podcast'i", systemImage: "waveform.badge.magnifyingglass")
                .font(.headline)
            Text(weakCards.count >= 2
                 ? "Yanlış yaptığın veya zorlandığın \(weakCards.count) konudan, sınav provası tarzında kısa bir bölüm üret."
                 : "Quizde yanlış yaptığın ya da \"Bilemedim\" dediğin kartlar biriktikçe buradan özel bir bölüm üretebilirsin.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("Süre", selection: $weakDuration) {
                Text("5 dk").tag(5)
                Text("10 dk").tag(10)
                Text("15 dk").tag(15)
            }
            .modifier(AccessiblePickerStyle())
            Button {
                Task { await createWeakTopicsEpisode() }
            } label: {
                HStack {
                    if creating { ProgressView() }
                    Text(creating ? "Senaryo yazılıyor…" : "Podcast'i oluştur")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(weakCards.count < 2 || creating)
            if let createError { Text(createError).font(.caption).foregroundStyle(.red) }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Kart

    private func cardView(_ card: ReviewCard) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 2) {
                Text(card.episodeTitle)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                memoryLine(card)
            }
            .padding(.top, 8)
            .padding(.horizontal, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label(card.kind == .quiz ? "Quiz sorusu" : "Kart", systemImage: card.kind == .quiz ? "questionmark.circle" : "rectangle.on.rectangle")
                        .font(.caption.bold())
                        .foregroundStyle(.tint)
                    if let figureID = card.figureID {
                        CardFigure(episodeID: card.episodeID, figureID: figureID, number: LabelCard.number(from: card.front),
                                   answer: card.back, revealed: revealed)
                    }
                    Text(card.front).font(.title3.weight(.semibold))
                    if revealed {
                        Divider()
                        Text(card.back).font(.body)
                        ClipListenButton(card: card)
                        if let time = card.episodeTime {
                            Button {
                                listen(card, at: time)
                            } label: {
                                Label("O anı dinle (\(ListenAnchor.clock(time)))", systemImage: "headphones")
                            }
                            .buttonStyle(.bordered)
                        }
                        if let page = card.sourcePage {
                            if let bookID = card.sourceBookID {
                                Button {
                                    bookSource = BookAnchor(bookID: bookID, title: card.episodeTitle, page: page)
                                } label: {
                                    Label("Kitapta aç · sayfa \(page)", systemImage: "book")
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(minHeight: 44, alignment: .leading)
                                }
                                .buttonStyle(.bordered)
                                .accessibilityHint("\(card.episodeTitle) kitabının kaynak sayfasını açar")
                                .accessibilityIdentifier("review.bookSource")
                            } else {
                                Text("Kaynak: sayfa \(page)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, 16)
            }

            if revealed {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 8) {
                    ForEach(ReviewGrade.allCases, id: \.self) { grade in
                        Button {
                            apply(grade, to: card)
                        } label: {
                            VStack(spacing: 2) {
                                Text(grade.title).font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
                                Text(nextText(card, grade)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(color(grade).opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.primary)
                            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(color(grade), lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            } else {
                Button("Cevabı göster") { withAnimation(.smooth) { revealed = true } }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 12)
    }

    /// #32: karışık tur; art arda iki kart aynı bölümden gelmez. Tur en çok `batch` karttır, kalanı "Devam et" ile gelir.
    private func startSession() {
        let reader = ModelContext(context.container); reader.autosaveEnabled = false
        do {
            let fresh = try reader.fetch(FetchDescriptor<ReviewCard>(sortBy: [SortDescriptor(\.due)]))
            displayContext = reader
            committedSchedules = Dictionary(uniqueKeysWithValues: fresh.map { ($0.id, $0.schedule) })
            session = MemoryModel.interleave(Array(fresh.filter(\.isDue).prefix(batch)), key: \.episodeID)
        } catch { reviewError = "Kartlar açılamadı: " + error.localizedDescription; return }
        reviewError = nil; historyNotice = nil
        answerTime.restart(active: scenePhase == .active && !session.isEmpty)
        index = 0
        revealed = false
        reviewedIDs = []
        lastAction = nil
        reported = false
    }

    private var finished: some View {
        let copy = ReviewSummary.text(done: reviewedIDs.count, left: dueCards.count, batch: batch)
        return VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(Theme.gradient)
                .accessibilityHidden(true)
            Text(copy.title).font(.title2.bold()).multilineTextAlignment(.center)
            Text(copy.detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let next = copy.continueTitle {
                Button(next) { startSession() }.buttonStyle(PrimaryButtonStyle())
                Button("Bugünlük yeter") { dismiss() }.buttonStyle(.bordered)
            } else {
                Button("Tamam") { dismiss() }.buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .onAppear {
            guard !reported, !reviewedIDs.isEmpty else { return }
            reported = true
            PodcastEvent.post(PodcastEvent.reviewFinished, count: reviewedIDs.count)
        }
    }

    /// "Hatırlama %83 · sınav günü %61"
    @ViewBuilder private func memoryLine(_ card: ReviewCard) -> some View {
        if let now = card.recallProbability() {
            let exam = StudyPlan.current.flatMap { $0.examDate > .now ? card.recallProbability(at: $0.examDate) : nil }
            Text("Hatırlama %\(Int((now * 100).rounded()))" + (exam.map { " · sınav günü %\(Int(($0 * 100).rounded()))" } ?? ""))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// #33: podcast kartının anı (kesit olarak çalınır).
    private func listen(_ card: ReviewCard, at time: Double) {
        guard let player = AppState.current?.player else { return }
        let clip = PodcastClip(episodeID: card.episodeID, start: max(0, time - 3), end: time + 45,
                               reason: "Kart: \(card.front.prefix(60))", questionKey: card.front)
        player.playClips([clip], context: context) { _ in }
    }

    private func apply(_ grade: ReviewGrade, to card: ReviewCard) {
        let change: LearningCardSession.Change
        do {
            change = try LearningCardSession.apply(cardID: card.id, expected: card.schedule, grade: grade,
                seconds: answerTime.seconds(), retention: LearningAdaptiveReview.target(for: card), container: context.container)
        } catch { reviewError = "Not kaydedilemedi; bu kartta kaldın. " + error.localizedDescription; return }
        reviewError = nil
        historyNotice = change.evidencePending ? "Not ve tekrar tarihi kaydedildi. Öğrenme geçmişi bağlantısı sonraki açılışta tamamlanacak." : nil
        // This is an isolated display object, never an unsaved model from another screen.
        card.schedule = change.after
        committedSchedules[card.id] = change.after
        let counted = reviewedIDs.insert(card.id).inserted
        var reinsertedAt: Int?
        if grade == .again {
            // Bu oturumda bir kez daha göster; komşuları başka bölümden olsun.
            let at = MemoryModel.reinsertIndex(card.episodeID, in: session.map(\.episodeID), after: index)
            session.insert(card, at: at)
            reinsertedAt = at
        }
        lastAction = LastAction(change: change, reinsertedAt: reinsertedAt, counted: counted)
        revealed = false
        answerTime.restart(active: scenePhase == .active && index + 1 < session.count)
        withAnimation(.smooth) { index += 1 }
    }

    /// Son notu geri alır: kartın zamanlaması eski hâline döner, o notun günlük kaydı silinir, kart cevabı açık geri gelir.
    private func undo() {
        guard let last = lastAction, index > 0 else { return }
        do {
            try LearningCardSession.undo(last.change, container: context.container)
        } catch { reviewError = "Son not geri alınamadı; yeniden deneyebilirsin. " + error.localizedDescription; return }
        reviewError = nil; historyNotice = nil; lastAction = nil
        for card in session where card.id == last.change.cardID { card.schedule = last.change.before }
        committedSchedules[last.change.cardID] = last.change.before
        answerTime.restart(active: scenePhase == .active)
        if let at = last.reinsertedAt, session.indices.contains(at), session[at].id == last.change.cardID { session.remove(at: at) }
        if last.counted { reviewedIDs.remove(last.change.cardID) }
        revealed = true
        withAnimation(.smooth) { index -= 1 }
    }

    private func nextText(_ card: ReviewCard, _ grade: ReviewGrade) -> String {
        grade == .again ? "tekrar" : "\(card.nextInterval(grade, retention: LearningAdaptiveReview.target(for: card))) gün"
    }

    private func color(_ grade: ReviewGrade) -> Color {
        switch grade {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }

    // MARK: - Eksik kapatma podcast'i (öneri 7)

    private func createWeakTopicsEpisode() async {
        creating = true
        createError = nil
        defer { creating = false }

        let weak = Array(weakCards.prefix(25))
        var text = "ZAYIF KONULAR — dinleyicinin daha önce yanlış yaptığı veya zorlandığı konular:\n\n"
        for (i, card) in weak.enumerated() {
            text += "\(i + 1). Soru/kavram: \(card.front)\n   Doğru bilgi: \(card.back)\n\n"
        }
        // İlgili bölümlerin kaynak notları: anlatım belgeye dayalı kalsın.
        let ids = Set(weak.map(\.episodeID))
        let episodes = (try? context.fetch(FetchDescriptor<Episode>())) ?? []
        for episode in episodes where ids.contains(episode.id) {
            if let notes = episode.script?.sourceNotes, !notes.isEmpty {
                text += "\n--- Kaynak notları: \(episode.title) ---\n\(notes.prefix(8000))\n"
            }
        }

        // #31: önce yoklayan eksik kapatma; ana bölümün serisi taşınmaz.
        let parent = Dictionary(grouping: weak, by: \.episodeID).max { $0.value.count < $1.value.count }?.key
        let last = try? JSONDecoder().decode(PodcastSettings.self, from: UserDefaults.standard.data(forKey: "lastSettings") ?? Data())
        var settings = RecapGenerator.settings(from: last, kind: "gap", parent: parent)
        settings.durationMin = weakDuration
        settings.format = .sinavProvasi
        settings.depth = .dengeli
        settings.focus = "Dinleyicinin yanlış yaptığı ve zorlandığı konular"
        settings.customInstructions = "Bu bir eksik kapatma bölümü: yalnızca listelenen zayıf konuları işle, her birinde neden karıştırıldığını ve doğru bilgiyi netleştir."
        settings.extras.commonMistakes = true
        settings.extras.recapQuestions = true

        do {
            let episode = try await generator.start(sources: [ImportedSource(name: "Zayıf konular", kind: .text(text))],
                                                    settings: settings, context: context)
            app.pendingOpenEpisode = episode.id
            dismiss()
        } catch {
            createError = error.localizedDescription
        }
    }
}

private struct StatTile: View {
    var value: String
    var title: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.bold().monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Tur sonu ekranının metinleri (saf; testlenir).
nonisolated enum ReviewSummary {
    /// Bir turdaki en çok kart.
    static let batch = 40

    struct Copy: Equatable, Sendable {
        var title: String
        var detail: String
        /// Bekleyen kart varsa sıradaki turu başlatan düğmenin adı.
        var continueTitle: String?
    }

    static func text(done: Int, left: Int, batch: Int = ReviewSummary.batch) -> Copy {
        guard left > 0 else { return Copy(title: "Bugünlük bu kadar!", detail: "\(done) kart tekrar edildi.") }
        return Copy(title: "Bu tur bitti", detail: "\(done) kart tekrar edildi · \(left) kart daha bekliyor",
                    continueTitle: "Devam et (\(min(left, batch)) kart)")
    }
}

// MARK: - Kart ekleme ve bildirim

enum ReviewDeck {
    /// Bir bölümün kartlarını tekrar destesine ekler (aynı ön yüz tekrar eklenmez).
    /// `chapters`: kart başına konu indeksi (study-v2; yoksa boş).
    static func add(flashcards: [Flashcard], episode: Episode, context: ModelContext, chapters: [Int?] = []) {
        let id = episode.id
        var existing = Set(((try? context.fetch(FetchDescriptor<ReviewCard>(predicate: #Predicate { $0.episodeID == id }))) ?? []).map(\.front))
        let timeline = episode.timeline
        // `insert`: aynı pakette iki kez gelen ön yüz de tek kart olur.
        for (i, card) in flashcards.enumerated() where existing.insert(card.front).inserted {
            let new = ReviewCard(episodeID: episode.id, episodeTitle: episode.title, kind: .flashcard,
                                 front: card.front, back: card.back, sourcePage: nil)
            new.origin = "flashcard"
            if let chapter = chapters[safe: i] ?? nil {
                new.chapterIndex = chapter
                new.episodeTime = ListenAnchor.time(turnIndex: nil, chapterIndex: chapter, timeline: timeline)
            }
            context.insert(new)
        }
        try? context.save()
        ReviewReminder.ensureScheduled()
    }

    /// Yanlış soru → kart (konu, an ve köken ile). Kaynakla doğrulanamamış soru (#34) desteye girmez.
    /// Kart zaten varsa yenisi eklenmez; ileri tarihe planlıysa bugüne çekilir (soru yeniden yanlış yapıldı).
    static func addWrong(_ item: QuizItem, episode: Episode, context: ModelContext, origin: String = "quiz", now: Date = .now) {
        guard item.verified != false else { return }
        let id = episode.id, question = item.question
        let existing = (try? context.fetch(FetchDescriptor<ReviewCard>(predicate: #Predicate { $0.episodeID == id && $0.front == question }))) ?? []
        if !existing.isEmpty {
            var changed = false
            for card in existing where card.due > now {
                card.due = now
                changed = true
            }
            if changed { try? context.save() }
            return
        }
        let answer = QuestionKind.expectedAnswer(item)
        let back = item.explanation.isEmpty || item.explanation == answer ? answer : "\(answer)\n\n\(item.explanation)"
        let card = ReviewCard(episodeID: episode.id, episodeTitle: episode.title, kind: .quiz,
                              front: item.question, back: back, sourcePage: item.sourcePage)
        card.origin = origin
        card.chapterIndex = item.chapterIndex
        card.episodeTime = ListenAnchor.time(for: item, timeline: episode.timeline)
        context.insert(card)
        try? context.save()
        ReviewReminder.ensureScheduled()
    }
}

enum ReviewReminder {
    static let identifier = "daily-review"

    /// Her akşam 20:00'de yerel hatırlatma (izin bir kez istenir).
    static func ensureScheduled() {
        WeeklyDigest.ensureScheduled()
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = await NotificationGate.request(center, options: [.alert, .sound, .badge])
            guard granted else { return }
            let pending = await center.pendingNotificationRequests()
            guard !pending.contains(where: { $0.identifier == identifier }) else { return }
            let content = UNMutableNotificationContent()
            content.title = "Tekrar zamanı"
            content.body = "Bugünkü kartların seni bekliyor. Birkaç dakikalık tekrar, öğrendiklerini kalıcı yapar."
            content.sound = .default
            content.userInfo = ["route": "review"]
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 20, minute: 0), repeats: true)
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }
}

/// Etiket kartının şekli (#33). Cevaptan önce etiketler LabelQuiz'deki gibi maskelenir ve sorulan numara vurgulanır;
/// kutular bulunamazsa şekil cevabı ele vermesin diye yalnız "Cevabı göster"den sonra görünür.
private struct CardFigure: View {
    var episodeID: UUID
    var figureID: String
    var number: Int?
    var answer: String
    var revealed: Bool
    @State private var image: UIImage?
    @State private var labels: [FigureLabel] = []

    private var target: FigureLabel? { LabelCard.target(in: labels, number: number, answer: answer) }
    private var canShow: Bool { revealed || target != nil }

    var body: some View {
        Group {
            if let image, canShow {
                Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
                    .overlay { GeometryReader { geo in boxes(in: geo.size) } }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(revealed ? "Kartın şekli" : "Kartın şekli, etiketler gizli; \(number ?? 0) numaralı yapı işaretli")
            } else if image != nil {
                Label("Şekil cevapla birlikte gösterilecek.", systemImage: "photo")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: "\(episodeID)-\(figureID)") {
            let dir = EpisodeFiles.directory(for: episodeID)
            image = await DeckAssets.thumbnail(dir.appending(path: "figure_\(figureID).png"))
            labels = LabelCard.cachedLabels(episodeID: episodeID, figureID: figureID)
        }
    }

    /// Cevaptan önce: bütün etiketler örtülür, sorulan numara renkli; sonra yalnız sorulan yapı çerçevelenir.
    @ViewBuilder private func boxes(in size: CGSize) -> some View {
        let targetID = target?.id
        ForEach(labels) { label in
            let r = CGRect(x: label.box.minX * size.width, y: label.box.minY * size.height,
                           width: label.box.width * size.width, height: label.box.height * size.height)
            let isTarget = label.id == targetID
            Group {
                if revealed {
                    if isTarget { RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: 2.5) }
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isTarget ? Color.accentColor : Color.gray.opacity(0.85))
                        .overlay {
                            if isTarget {
                                Text("\(label.id + 1)").font(.system(size: max(9, min(15, r.height * 0.7)), weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
            }
            .frame(width: max(r.width + 6, 20), height: max(r.height + 4, 16))
            .position(x: r.midX, y: r.midY)
        }
    }
}
