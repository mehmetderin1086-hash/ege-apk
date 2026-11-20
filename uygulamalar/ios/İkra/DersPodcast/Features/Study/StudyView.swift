import SwiftData
import SwiftUI

struct StudyView: View {
    @Bindable var episode: Episode
    @Environment(\.modelContext) private var context
    @State private var mode: Mode
    @State private var loading = false
    @State private var error: String?
    /// Quiz ilerlemesi burada tutulur: başka sekmeye geçip dönünce tur kaldığı sorudan sürer.
    @State private var quizRound: QuizRound?
    /// Bölümün bütün soruları, çözme sırasıyla ("Tekrar çöz" bunu kullanır).
    @State private var quizOrder: [QuizItem] = []

    enum Mode: String, CaseIterable, Identifiable {
        case coach = "Antrenör", summary = "Özet", quiz = "Quiz", cards = "Kartlar", map = "Harita", words = "Kelimeler", visuals = "Görseller"
        var id: String { rawValue }
    }

    init(episode: Episode, initialMode: Mode = .summary) {
        _episode = Bindable(wrappedValue: episode)
        _mode = State(initialValue: Self.startMode(debug: DebugArg.value("studyMode"), initial: initialMode))
    }

    /// Açılış sekmesi. `-studyMode=quiz` (yalnız Debug) çağıranın isteğini ezer; tanınmayan ad yok sayılır.
    static func startMode(debug: String?, initial: Mode) -> Mode {
        Mode.allCases.first { "\($0)" == debug } ?? initial
    }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 8) {
                // "Görseller" yalnız daha önce görseli üretilmiş bölümlerde görünür.
                ForEach(Mode.allCases.filter { $0 != .visuals || episode.visuals != nil }) { item in
                    Button(item.rawValue) { mode = item }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(mode == item ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(.quaternary.opacity(0.6)), in: Capsule())
                        .foregroundStyle(mode == item ? .white : .primary)
                }
              }
            }
            .padding(.horizontal, 16)

            switch mode {
            case .coach: CoachHub(episode: episode)
            case .summary: SummaryView(script: episode.script)
            case .visuals: LessonVisualsView(episode: episode)
            case .words: VocabView(episode: episode)
            case .quiz, .cards, .map:
                if let study = episode.study {
                    switch mode {
                    case .quiz:
                        QuizView(episode: episode, quiz: study.quiz, round: $quizRound, order: $quizOrder)
                    case .cards:
                        FlashcardsView(cards: study.flashcards)
                    default:
                        if episode.concepts.isEmpty {
                            ContentUnavailableView {
                                Label("Harita yok", systemImage: "point.3.connected.trianglepath.dotted")
                            } description: {
                                Text("Bu bölümün çalışma paketi kavram haritası olmadan üretilmiş.")
                            } actions: {
                                Button("Yeniden oluştur") { Task { await generate() } }.buttonStyle(.bordered).disabled(loading)
                            }
                        } else {
                            ConceptMapView(concepts: episode.concepts, episodeID: episode.id)
                        }
                    }
                } else {
                    generatePrompt
                }
            }
        }
        .onChange(of: mode) { old, _ in
            // Cevaplanmış soruda sekme değişirse dönüşte aynı soru yeniden sorulmasın (günlüğe çift kayıt düşmesin).
            if old == .quiz, quizRound?.answered == true { quizRound?.advance() }
        }
        .onChange(of: episode.id) {
            quizRound = nil
            quizOrder = []
        }
    }

    private var generatePrompt: some View {
        // Otomatik hazırlık (ya da başka ekrandan başlatılan üretim) sürüyorsa ikinci istek gönderilmez.
        let building = loading || StudyBuilds.shared.active.contains(episode.id)
        return VStack(spacing: 16) {
            Spacer()
            Image(systemName: mode == .quiz ? "checklist" : mode == .map ? "point.3.connected.trianglepath.dotted" : "rectangle.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundStyle(Theme.gradient)
            Text(mode == .quiz ? "Bu bölümden quiz oluştur" : mode == .map ? "Kavram haritası oluştur" : "Tekrar kartları oluştur")
                .font(.headline)
            Text("Quiz, kartlar ve kavram haritası birlikte üretilir; yalnızca belgendeki bilgilere dayanır. Kartlar tekrar destene eklenir.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if building {
                ProgressView("Hazırlanıyor…")
                if !loading {
                    Text("Otomatik hazırlık sürüyor; birazdan burada görünecek.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else {
                if let error {
                    Text(error).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center).padding(.horizontal, 24)
                }
                Button("Oluştur") { Task { await generate() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 48)
            }
            Spacer()
        }
    }

    private func generate() async {
        guard episode.script != nil else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            try await StudyMaterials.buildStudyPack(episode, context: context)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct LessonVisualsView: View {
    @Bindable var episode: Episode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let visuals = episode.visuals {
                    GeneratedCoverView(cover: visuals.cover, size: 280)
                        .frame(maxWidth: .infinity)
                    ForEach(Array(visuals.diagrams.enumerated()), id: \.offset) { _, diagram in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(diagram.title).font(.title3.bold())
                            Text(diagram.caption).font(.callout).foregroundStyle(.secondary)
                            if let encoded = diagram.imageData, let image = GeneratedImageCache.image(encoded) {
                                Image(uiImage: image).resizable().scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .accessibilityLabel(diagram.caption)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: diagram.layout == "comparison" ? 145 : 260), alignment: .top)], alignment: .leading, spacing: 12) {
                                ForEach(Array(diagram.steps.enumerated()), id: \.offset) { index, step in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Image(systemName: step.symbol).font(.title2).foregroundStyle(Theme.gradient)
                                            Spacer()
                                            if diagram.layout == "flow" { Text("\(index + 1)").font(.headline.monospacedDigit()).foregroundStyle(.secondary) }
                                        }
                                        Text(step.title).font(.headline)
                                        Text(step.detail).font(.callout)
                                        if diagram.layout == "flow", index < diagram.steps.count - 1 {
                                            Image(systemName: "arrow.down").foregroundStyle(.secondary).accessibilityLabel("Sonraki adım")
                                        }
                                    }
                                    .padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                    }
                } else {
                    // Kapak ve ders görseli üretimi kaldırıldı (10 Eki 2026); daha önce üretilmiş görseller burada görünmeyi sürdürür.
                    ContentUnavailableView("Bu bölümün görseli yok", systemImage: "photo.stack", description: Text("Bu bölüm için kapak ya da ders şeması üretilmemiş."))
                }
            }
            .padding(16)
        }
    }
}

private struct SummaryView: View {
    var script: PodcastScript?

    var body: some View {
        ScrollView {
            if let script {
                VStack(alignment: .leading, spacing: 18) {
                    Text(script.summary)
                        .font(.body)
                    if !script.keyPoints.isEmpty {
                        Text("Akılda kalması gerekenler")
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(script.keyPoints.enumerated()), id: \.offset) { i, point in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(i + 1)")
                                        .font(.caption.bold())
                                        .frame(width: 22, height: 22)
                                        .background(Theme.gradient, in: Circle())
                                        .foregroundStyle(.white)
                                    Text(point).font(.callout)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .textSelection(.enabled)
            }
        }
    }
}

/// Quiz (#24, #27, #34): kolaydan zora, tür tür sorular, eminlik, "Bu kısmı dinle" ve "Yeni sorular".
/// Tur durumu `StudyView`'de yaşar; sonuç turun kendi sorularından hesaplanır.
private struct QuizView: View {
    @Bindable var episode: Episode
    var quiz: [QuizItem]
    @Binding var round: QuizRound?
    @Binding var order: [QuizItem]
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @State private var loadingMore = false
    @State private var moreError: String?

    private var policy: ListeningPolicy { ListeningMode.current.policy }

    var body: some View {
        Group {
            if let round, let item = round.current {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ProgressView(value: Double(round.index), total: Double(max(1, round.total)))
                        QuestionCard(item: item, header: "Soru \(round.index + 1) / \(round.total)", episode: episode,
                                     showConfidence: policy.confidence) { outcome in
                            record(item, outcome)
                        }
                        .id("\(round.index)-\(item.question)")
                        if round.answered {
                            Button(round.index + 1 < round.total ? "Sonraki soru" : "Sonucu gör") { self.round?.advance() }
                                .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                    .padding(16)
                }
            } else if let round, round.finished {
                result(round)
            } else {
                ContentUnavailableView("Soru yok", systemImage: "questionmark.circle")
            }
        }
        .onAppear { sync(quiz) }
        .onChange(of: quiz) { _, new in sync(new) }
    }

    private func result(_ round: QuizRound) -> some View {
        let timeline = round.wrong.isEmpty ? nil : episode.timeline
        let anchored = round.wrong.contains { ListenAnchor.time(for: $0, timeline: timeline) != nil }
        let note = round.passed ? "Harika! Konuya hâkimsin."
            : round.wrong.isEmpty ? "Biraz daha çalışıp yeniden dene."
            : anchored ? "Aşağıdaki yanlışlarında \"Bu kısmı dinle\" ile ilgili yere dön, sonra yeniden dene."
            : "Yanlışlarına aşağıdan bak, sonra yeniden dene."
        return ScrollView {
            VStack(spacing: 16) {
                Image(systemName: round.passed ? "star.circle.fill" : "arrow.clockwise.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.gradient)
                    .accessibilityHidden(true)
                Text("\(round.total) soruda \(round.correct) doğru")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(note)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if !round.wrong.isEmpty {
                    Button("Yalnız yanlışları çöz (\(round.wrong.count))") { self.round = QuizRound(items: round.wrong) }
                        .buttonStyle(.borderedProminent)
                }
                Button(round.total == order.count ? "Tekrar çöz" : "Tümünü çöz (\(order.count))") { self.round = QuizRound(items: order) }
                    .buttonStyle(.bordered)
                moreButton
                if !round.wrong.isEmpty { wrongList(round.wrong, timeline: timeline) }
            }
            .padding(24)
        }
    }

    private func wrongList(_ wrong: [QuizItem], timeline: Timeline?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Yanlışların").font(.headline)
            ForEach(Array(wrong.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 8) {
                    Label(item.question, systemImage: "xmark.circle")
                        .font(.subheadline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let time = ListenAnchor.time(for: item, timeline: timeline) {
                        Button {
                            LearningLinks.listen(episodeID: episode.id, at: time)
                        } label: {
                            Label(ListenAnchor.label(time), systemImage: "headphones")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var moreButton: some View {
        if app.serverSupports("learn2") {
            Button {
                Task { await loadMore() }
            } label: {
                HStack { if loadingMore { ProgressView() }; Label("Yeni sorular", systemImage: "sparkles") }
            }
            .buttonStyle(.bordered)
            .disabled(loadingMore)
            if let moreError { Text(moreError).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center) }
        }
    }

    private func sync(_ quiz: [QuizItem]) {
        let synced = QuizRound.sync(order: order, round: round, quiz: quiz)
        if synced.order != order { order = synced.order }
        if synced.round != round { round = synced.round }
    }

    private func record(_ item: QuizItem, _ outcome: QuestionOutcome) {
        // Soru bu turda zaten sayıldıysa günlüğe ve yanlış defterine ikinci kez yazılmaz.
        guard round?.answered == false else { return }
        round?.record(item, isCorrect: outcome.isCorrect)
        RecallLog.record(RecallLog.entry(item, source: "quiz", outcome: outcome), episode: episode, context: context)
        if outcome.isCorrect == false {
            ReviewDeck.addWrong(item, episode: episode, context: context)
            let mine = outcome.chosenIndex.flatMap { item.options[safe: $0] } ?? outcome.answerText ?? ""
            MistakeBook.record(item, myAnswer: mine, episode: episode, source: "quiz", context: context)
        }
    }

    /// #34: kaynaktan yeni sorular (öncekilerden kaçınarak); yalnız yeni sorulardan ayrı bir tur başlar.
    private func loadMore() async {
        guard let script = episode.script, let study = episode.study else { return }
        loadingMore = true
        moreError = nil
        defer { loadingMore = false }
        do {
            let fresh = try await APIClient.shared.quizMore(QuizMoreRequest(
                title: String(script.title.prefix(300)), sourceNotes: String(script.sourceNotes.prefix(15_000)),
                transcriptTurns: LearnPayload.transcriptTurns(episode.timeline), count: 10,
                kinds: LearnPayload.allKinds, avoid: LearnPayload.avoid(study.quiz)))
            guard !episode.isDeleted, episode.modelContext != nil else { return }
            // Beklerken bölüm yeniden üretildiyse sorular eski metne aittir: atılır.
            guard episode.script == script else { return }
            // Paket yeniden oluşmuş olabilir: yeni sorular güncel pakete eklenir (eski kopya yazılmaz).
            guard var current = episode.study else { return }
            let known = Set(current.quiz.map(\.question))
            let added = fresh.filter { !known.contains($0.question) }
            guard !added.isEmpty else { moreError = "Yeni soru çıkmadı; biraz sonra tekrar dene."; return }
            current.quiz += added
            episode.study = current
            try? context.save()
            let sorted = QuestionPicker.easyFirst(added)
            order += sorted
            round = QuizRound(items: sorted)
        } catch {
            moreError = error.localizedDescription
        }
    }
}

private struct FlashcardsView: View {
    var cards: [Flashcard]
    @State private var flipped: Set<Int> = []
    @State private var current = 0

    var body: some View {
        if cards.isEmpty {
            ContentUnavailableView("Kart yok", systemImage: "rectangle.on.rectangle")
        } else {
            VStack(spacing: 14) {
                TabView(selection: $current) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { i, card in
                        CardFace(text: flipped.contains(i) ? card.back : card.front, isBack: flipped.contains(i))
                            .rotation3DEffect(.degrees(flipped.contains(i) ? 360 : 0), axis: (0, 1, 0))
                            .onTapGesture {
                                withAnimation(.spring(duration: 0.45)) {
                                    if flipped.contains(i) { flipped.remove(i) } else { flipped.insert(i) }
                                }
                            }
                            .padding(.horizontal, 24)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                Text("\(current + 1) / \(cards.count) · çevirmek için dokun")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
        }
    }
}

private struct CardFace: View {
    var text: String
    var isBack: Bool

    var body: some View {
        // Kısa metin ortada durur; karta sığmayan metin kart içinde kayar (kırpılmaz).
        ViewThatFits(in: .vertical) {
            label
            ScrollView { label }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: 320)
        .background(isBack ? AnyShapeStyle(.background.secondary) : AnyShapeStyle(Theme.gradient),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .foregroundStyle(isBack ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityValue(isBack ? "Arka yüz" : "Ön yüz")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Çevirmek için çift dokun")
    }

    private var label: some View {
        Text(text)
            .font(isBack ? .body : .title3.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}
