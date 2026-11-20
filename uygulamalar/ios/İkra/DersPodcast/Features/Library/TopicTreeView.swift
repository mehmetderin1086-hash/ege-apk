import SwiftData
import SwiftUI

/// #35: ders → ünite → konu ağacı (saf mantık; test edilir).
nonisolated enum TopicTree {
    struct EpisodeSnapshot: Sendable {
        var id: UUID
        var title: String
        var course: String?
        var chapters: [String]
        var concepts: [String]
    }

    struct TopicNode: Identifiable, Hashable, Sendable {
        var name: String
        var refs: [TopicTag.Ref]
        var mastery: Double?
        var id: String { name }
    }

    struct UnitNode: Identifiable, Hashable, Sendable {
        var name: String
        var topics: [TopicNode]
        var mastery: Double?
        var id: String { name }
    }

    struct SubjectNode: Identifiable, Hashable, Sendable {
        var name: String
        var units: [UnitNode]
        var mastery: Double?
        var id: String { name }
    }

    static let maxEpisodes = 60
    static let maxConcepts = 30

    /// İstek (sunucu sınırları istemcide kırpılır).
    static func request(_ episodes: [EpisodeSnapshot]) -> TopicsRequest {
        TopicsRequest(episodes: episodes.prefix(maxEpisodes).map { e in
            TopicsRequest.Item(id: e.id.uuidString.lowercased(), title: String(e.title.prefix(200)), course: e.course.map { String($0.prefix(120)) },
                               chapters: e.chapters.prefix(60).enumerated().map { TopicsRequest.Chapter(i: $0.offset, title: String($0.element.prefix(200))) },
                               concepts: e.concepts.prefix(maxConcepts).map { String($0.prefix(120)) })
        })
    }

    /// Yanıt → bölüm başına etiketler (yalnız istekte olan kimlikler).
    static func tags(from response: TopicsResponse, known: Set<UUID>) -> [UUID: [TopicTag]] {
        var out: [UUID: [TopicTag]] = [:]
        for s in response.subjects {
            for u in s.units {
                for t in u.topics {
                    for ref in t.refs {
                        guard let id = UUID(uuidString: ref.episodeId), known.contains(id) else { continue }
                        let tag = TopicTag(subject: s.name, unit: u.name, topic: t.name, chapterIndex: ref.chapter)
                        if !(out[id] ?? []).contains(tag) { out[id, default: []].append(tag) }
                    }
                }
            }
        }
        return out
    }

    /// Etiketlerden ağaç; ustalık = konudaki bölüm-konu puanlarının ortalaması (puan yoksa nil).
    static func build(_ tagged: [(episodeID: UUID, tags: [TopicTag])], scores: [TopicTag.Ref: Double]) -> [SubjectNode] {
        var map: [String: [String: [String: [TopicTag.Ref]]]] = [:]
        for (id, tags) in tagged {
            for t in tags {
                let ref = TopicTag.Ref(episodeID: id, chapter: t.chapterIndex)
                var refs = map[t.subject, default: [:]][t.unit, default: [:]][t.topic, default: []]
                if !refs.contains(ref) { refs.append(ref) }
                map[t.subject, default: [:]][t.unit, default: [:]][t.topic] = refs
            }
        }
        func average(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        return map.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { subject in
            let units = map[subject]!.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { unit in
                let topics = map[subject]![unit]!.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { topic in
                    let refs = map[subject]![unit]![topic]!
                    return TopicNode(name: topic, refs: refs, mastery: average(refs.compactMap { scores[$0] }))
                }
                return UnitNode(name: unit, topics: topics, mastery: average(topics.compactMap(\.mastery)))
            }
            return SubjectNode(name: subject, units: units, mastery: average(units.compactMap(\.mastery)))
        }
    }

    /// En zayıf konu (puanı olanlar arasında).
    static func weakest(_ subjects: [SubjectNode]) -> TopicNode? {
        subjects.flatMap { $0.units.flatMap(\.topics) }.filter { $0.mastery != nil }.min { ($0.mastery ?? 1) < ($1.mastery ?? 1) }
    }

    static func percent(_ v: Double?) -> String { v.map { "%\(Int(($0 * 100).rounded()))" } ?? "—" }

    /// Konunun geçtiği yerler, bölüm adıyla (sıra korunur). Bölümü silinmiş başvuru düşer.
    static func refTitles(_ refs: [TopicTag.Ref], titles: [UUID: String]) -> [(ref: TopicTag.Ref, title: String)] {
        refs.compactMap { ref in titles[ref.episodeID].map { (ref: ref, title: $0) } }
    }
}

extension TopicTag {
    nonisolated struct Ref: Hashable, Sendable {
        var episodeID: UUID
        var chapter: Int?
    }
}

/// Karıştırılan çiftler (son analiz; `coach.` önekli olduğu için yedeğe girer).
enum TopicConfusables {
    static let key = "coach.topics.confusables"
    static var current: [TopicsResponse.Confusable] {
        get { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([TopicsResponse.Confusable].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }
}

/// #35 Konularım: ustalık ağacı, en zayıf konuya tek dokunuş, karıştırdıkların.
struct TopicTreeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Environment(GenerationCoordinator.self) private var generator
    @Environment(\.modelContext) private var context
    @Query(sort: \Episode.createdAt, order: .reverse) private var episodes: [Episode]
    @Query private var courses: [Course]
    @State private var subjects: [TopicTree.SubjectNode] = []
    @State private var confusables = TopicConfusables.current
    @State private var loading = false
    @State private var error: String?
    @State private var quizEpisode: Episode?
    @State private var probeEpisode: ProbeTarget?
    @State private var discrimination: Discrimination?
    @State private var generating: String?

    private struct ProbeTarget: Identifiable { var id: UUID }
    private struct Discrimination: Identifiable {
        var a: String, b: String, notes: String
        var id: String { a + "|" + b }
    }

    private var ready: [Episode] { episodes.filter { $0.status == .ready } }

    var body: some View {
        Group {
            List {
                if !app.serverSupports("learn2") {
                    ContentUnavailableView("Konularım kullanılamıyor", systemImage: "point.3.connected.trianglepath.dotted",
                                           description: Text("Sunucu bu özelliği henüz desteklemiyor ya da şu an ulaşılamıyor."))
                } else {
                    Section {
                        Button {
                            Task { await analyze() }
                        } label: {
                            HStack { if loading { ProgressView() }; Text(subjects.isEmpty ? "Konuları çıkar" : "Konuları güncelle") }
                                .frame(minHeight: 44)
                        }
                        .disabled(loading || ready.isEmpty)
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    } footer: {
                        Text("\(min(ready.count, TopicTree.maxEpisodes)) bölüm ders → ünite → konu ağacına yerleştirilir; ustalık quiz, hatırlama ve kart sonuçlarından hesaplanır.")
                    }
                    if let weak = TopicTree.weakest(subjects), let ref = weak.refs.first {
                        Section("En zayıf konun") {
                            Text("\(weak.name) · \(TopicTree.percent(weak.mastery))").font(.headline)
                            ViewThatFits(in: .horizontal) {
                                HStack { weakButtons(ref) }
                                VStack(alignment: .leading) { weakButtons(ref) }
                            }
                        }
                    }
                    let titles = Dictionary(episodes.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
                    ForEach(subjects) { subject in
                        Section {
                            ForEach(subject.units) { unit in
                                DisclosureGroup {
                                    ForEach(unit.topics) { topic in
                                        let places = TopicTree.refTitles(topic.refs, titles: titles)
                                        if places.count > 1 {
                                            // Konu birden çok yerde geçiyor: hangisinin dinleneceği seçilir.
                                            Menu {
                                                ForEach(places, id: \.ref) { place in
                                                    Button(placeLabel(place)) { listen(place.ref) }
                                                }
                                            } label: {
                                                topicLabel(topic, places: places.count)
                                            }
                                            .accessibilityHint("Dinlenecek kısmı seç")
                                        } else {
                                            Button { listen(places.first?.ref ?? topic.refs.first) } label: { topicLabel(topic, places: 1) }
                                                .accessibilityHint("Bu kısmı dinle")
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(unit.name)
                                        Spacer(minLength: 8)
                                        Text(TopicTree.percent(unit.mastery)).font(.caption.monospacedDigit()).foregroundStyle(color(unit.mastery))
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Text(subject.name)
                                Spacer()
                                Text(TopicTree.percent(subject.mastery))
                            }
                        }
                    }
                    if !confusables.isEmpty {
                        Section("Karıştırdıkların") {
                            ForEach(confusables, id: \.self) { pair in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(pair.a) – \(pair.b)").font(.subheadline.bold())
                                    Text(pair.why).font(.caption).foregroundStyle(.secondary)
                                    ViewThatFits(in: .horizontal) {
                                        HStack { pairButtons(pair) }
                                        VStack(alignment: .leading) { pairButtons(pair) }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Konularım")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
            .task { rebuild() }
            // Çalışma sayfası kapanınca yüzdeler ve "en zayıf konu" yeniden hesaplanır (ekranı kapatıp açmak gerekmesin).
            .sheet(item: $quizEpisode, onDismiss: rebuild) { e in
                NavigationStack {
                    StudyView(episode: e, initialMode: .quiz)
                        .navigationTitle(e.title)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { quizEpisode = nil } } }
                }
            }
            .sheet(item: $probeEpisode, onDismiss: rebuild) { t in NavigationStack { ProbeSessionView(episodeID: t.id) } }
            .sheet(item: $discrimination, onDismiss: rebuild) { d in NavigationStack { DiscriminationQuizView(a: d.a, b: d.b, notes: d.notes) } }
            .overlay {
                if let generating {
                    ProgressView(generating).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    @ViewBuilder private func weakButtons(_ ref: TopicTag.Ref) -> some View {
        Button("Quiz", systemImage: "checklist") { quizEpisode = episodes.first { $0.id == ref.episodeID } }
            .buttonStyle(.bordered).frame(minHeight: 44)
        Button("Hatırla", systemImage: "brain") { probeEpisode = ProbeTarget(id: ref.episodeID) }
            .buttonStyle(.bordered).frame(minHeight: 44)
        Button("Bu kısmı dinle", systemImage: "play.fill") { listen(ref) }
            .buttonStyle(.borderedProminent).frame(minHeight: 44)
    }

    @ViewBuilder private func pairButtons(_ pair: TopicsResponse.Confusable) -> some View {
        Button("Ayırt et", systemImage: "arrow.left.arrow.right") {
            discrimination = Discrimination(a: pair.a, b: pair.b, notes: notes(for: pair))
        }
        .buttonStyle(.bordered).frame(minHeight: 44)
        Button("Farkı ne? bölümü", systemImage: "waveform.badge.plus") { Task { await makeEpisode(pair) } }
            .buttonStyle(.bordered).frame(minHeight: 44)
            .disabled(generating != nil)
    }

    private func topicLabel(_ topic: TopicTree.TopicNode, places: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.name).foregroundStyle(.primary).multilineTextAlignment(.leading)
                if places > 1 { Text("\(places) yerde geçiyor").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            Text(TopicTree.percent(topic.mastery)).font(.caption.monospacedDigit()).foregroundStyle(color(topic.mastery))
            if places > 1 {
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
    }

    /// Menü öğesi: bölüm adı; kısım biliniyorsa onun başlığıyla (aynı bölümün iki kısmı ayırt edilsin).
    private func placeLabel(_ place: (ref: TopicTag.Ref, title: String)) -> String {
        guard let chapter = place.ref.chapter,
              let name = episodes.first(where: { $0.id == place.ref.episodeID })?.timeline?.chapters.first(where: { $0.id == chapter })?.title,
              !name.isEmpty else { return place.title }
        return "\(place.title) · \(name)"
    }

    private func color(_ v: Double?) -> Color {
        guard let v else { return .secondary }
        return v < 0.5 ? .red : v < 0.75 ? .orange : .green
    }

    private func rebuild() {
        let tagged = ready.map { (episodeID: $0.id, tags: $0.topics) }.filter { !$0.tags.isEmpty }
        var scores: [TopicTag.Ref: Double] = [:]
        for (id, tags) in tagged {
            for chapter in Set(tags.compactMap(\.chapterIndex)) {
                scores[TopicTag.Ref(episodeID: id, chapter: chapter)] = Mastery.chapterScore(episodeID: id, chapter: chapter, context: context)
            }
        }
        subjects = TopicTree.build(tagged, scores: scores)
    }

    private func analyze() async {
        loading = true
        error = nil
        defer { loading = false }
        let snapshots = ready.prefix(TopicTree.maxEpisodes).map { e in
            TopicTree.EpisodeSnapshot(id: e.id, title: e.title, course: e.courseID.flatMap { id in courses.first { $0.id == id }?.name },
                                      chapters: e.timeline?.chapters.map(\.title) ?? e.script?.chapters.map(\.title) ?? [],
                                      concepts: e.concepts.map(\.name))
        }
        do {
            let response = try await APIClient.shared.topics(TopicTree.request(Array(snapshots)))
            let tags = TopicTree.tags(from: response, known: Set(snapshots.map(\.id)))
            for e in ready where snapshots.contains(where: { $0.id == e.id }) { e.topics = tags[e.id] ?? [] }
            try? context.save()
            confusables = Array(response.confusables.prefix(10))
            TopicConfusables.current = confusables
            rebuild()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func listen(_ ref: TopicTag.Ref?) {
        guard let ref else { return }
        let start = ref.chapter.flatMap { c in episodes.first { $0.id == ref.episodeID }?.timeline?.chapters.first { $0.id == c }?.start }
        dismiss()
        app.open(ref.episodeID, at: start, play: true)
    }

    /// Ayırt etme için not: çiftin geçtiği bölümlerin özeti ve ilgili konu turları (≤15k).
    private func notes(for pair: TopicsResponse.Confusable) -> String {
        var text = "\(pair.a) ile \(pair.b): \(pair.why)\n"
        for ref in pair.refs {
            guard let id = UUID(uuidString: ref.episodeId), let e = episodes.first(where: { $0.id == id }) else { continue }
            text += "\n# \(e.title)\n\(e.script?.summary ?? "")\n"
            if let timeline = e.timeline {
                let turns = timeline.turns.filter { ref.chapter == nil || $0.chapterIndex == ref.chapter }
                text += turns.map(\.text).joined(separator: "\n")
            }
            if text.count > 15_000 { break }
        }
        return String(text.prefix(15_000))
    }

    /// "Farkı ne?" bölümü: kullanıcı talimatından ayrı yönergeyle, türev olarak işaretlenir.
    private func makeEpisode(_ pair: TopicsResponse.Confusable) async {
        generating = "“Farkı ne?” bölümü yazılıyor…"
        defer { generating = nil }
        var settings = ((try? JSONDecoder().decode(PodcastSettings.self, from: UserDefaults.standard.data(forKey: "lastSettings") ?? Data())) ?? PodcastSettings()).reusable
        settings.durationMin = 10
        settings.directives = [String("Bu bölüm “\(pair.a)” ile “\(pair.b)” arasındaki farkı anlatır: önce ikisinin ortak noktaları, sonra temel farklar, sık karıştırma tuzakları ve ayırt etme ipuçları. Sonda dinleyiciye iki kavramı ayırt ettiren üç kısa soru sorulur.".prefix(800))]
        let parent = pair.refs.lazy.compactMap { UUID(uuidString: $0.episodeId) }.first
        settings.derivation = Derivation(kind: "discriminate", parentEpisodeID: parent, sourceLessonID: nil, sourceVideoTime: nil,
                                         courseID: parent.flatMap { id in episodes.first { $0.id == id }?.courseID })
        do {
            let episode = try await generator.start(sources: [ImportedSource(name: "\(pair.a) – \(pair.b)", kind: .text(notes(for: pair)))],
                                                    settings: settings, context: context)
            dismiss()
            app.open(episode.id)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
