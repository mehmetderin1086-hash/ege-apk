import SwiftData
import SwiftUI

/// "Bugün tekrar et": vadesi gelen kartlar, açık yanlışlar, günü gelen yoklamalar ve tekrar bekleyen sorular tek akışta.
nonisolated struct StudyTodayPlan: Equatable, Sendable {
    enum Step: String, CaseIterable, Identifiable, Sendable {
        case cards, mistakes, probes
        var id: String { rawValue }
        var title: String {
            switch self { case .cards: "Tekrar kartları"; case .mistakes: "Yanlış defteri"; case .probes: "Yoklamalar" }
        }
        var symbol: String {
            switch self { case .cards: "rectangle.on.rectangle.angled"; case .mistakes: "xmark.circle"; case .probes: "checklist.checked" }
        }
        func detail(_ count: Int) -> String {
            switch self {
            case .cards: "\(count) kartın tekrar zamanı geldi"
            case .mistakes: "\(count) yanlış henüz doğruya çevrilmedi"
            case .probes: "\(count) bölümün hatırlama yoklaması bekliyor"
            }
        }
    }
    var counts: [Step: Int] = [:]
    /// Bugün yapılacak iş olan adımlar, sabit sırayla.
    var steps: [Step] { Step.allCases.filter { (counts[$0] ?? 0) > 0 } }
    var total: Int { counts.values.reduce(0, +) }
    /// Bu oturumda henüz açılmamış, işi kalan ilk adım (`remaining`: şu anki sayılar).
    func next(visited: Set<Step>, remaining: StudyTodayPlan) -> Step? { steps.first { !visited.contains($0) && (remaining.counts[$0] ?? 0) > 0 } }
}

/// Çalış sekmesindeki ilerleme özeti: seri, haftalık süre ve ders bazlı durum.
nonisolated enum StudyProgress {
    struct CourseRow: Identifiable, Equatable, Sendable {
        var id: UUID
        var name: String
        var colorHex: String
        var items: Int
        /// Dersin bölüm ve videolarının ortalama dinlenme/izlenme yüzdesi.
        var percent: Int
        var dueCards: Int
    }
    struct Item: Sendable { var id: UUID; var courseID: UUID?; var fraction: Double }

    /// Bugünden (bugün henüz çalışılmadıysa dünden) geriye, en az bir dakika çalışılan ardışık gün sayısı.
    static func streak(_ seconds: [String: Double], now: Date = .now, calendar: Calendar = .current) -> Int {
        var date = now
        if (seconds[ListeningDay.key(for: date)] ?? 0) < 60 { date = calendar.date(byAdding: .day, value: -1, to: date) ?? date }
        var count = 0
        while (seconds[ListeningDay.key(for: date)] ?? 0) >= 60, count < 3650 {
            count += 1
            date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        }
        return count
    }
    /// Son yedi günün (bugün dahil) toplam dakikası.
    static func weekMinutes(_ seconds: [String: Double], now: Date = .now, calendar: Calendar = .current) -> Int {
        let total = (0..<7).reduce(0.0) { sum, back in sum + (seconds[ListeningDay.key(for: calendar.date(byAdding: .day, value: -back, to: now) ?? now)] ?? 0) }
        return Int((total / 60).rounded())
    }
    /// Derse bağlı bölüm ve videolardan ders satırları; içeriği olmayan ders listelenmez. En çok tekrar bekleyen üstte.
    static func courses(_ courses: [(id: UUID, name: String, colorHex: String)], items: [Item], dueCardItems: [UUID]) -> [CourseRow] {
        courses.compactMap { course in
            let own = items.filter { $0.courseID == course.id }
            guard !own.isEmpty else { return nil }
            let ids = Set(own.map(\.id))
            let average = own.reduce(0.0) { $0 + min(1, max(0, $1.fraction)) } / Double(own.count)
            return CourseRow(id: course.id, name: course.name, colorHex: course.colorHex, items: own.count, percent: Int((average * 100).rounded()), dueCards: dueCardItems.filter(ids.contains).count)
        }.sorted { ($0.dueCards, $1.percent, $0.name) > ($1.dueCards, $0.percent, $1.name) }
    }
}

/// Bugünkü tekrar akışı: adımlar sırayla açılır; biri kapatılınca sıradaki kendiliğinden gelir.
struct TodayReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var cards: [ReviewCard]
    @Query private var mistakes: [MistakeEntry]
    @Query(filter: #Predicate<EpisodeProbe> { $0.completedAt == nil }) private var openProbes: [EpisodeProbe]
    @State private var step: StudyTodayPlan.Step?
    /// Bu oturumda açılmış adımlar (akış aynı adıma ikinci kez dönmez).
    @State private var visited = Set<StudyTodayPlan.Step>()
    @State private var running = false
    /// Akış başlarkenki plan: bir adım bitince sayısı sıfırlansa da listede "tamamlandı" olarak kalır.
    @State private var initial: StudyTodayPlan?

    private var live: StudyTodayPlan {
        StudyTodayPlan(counts: [
            .cards: cards.filter(\.isDue).count,
            .mistakes: mistakes.filter { !$0.resolved }.count,
            .probes: ProbeScheduler.dueEpisodeCount(openProbes.map { (episodeID: $0.episodeID, due: $0.dueDate) }, endOfToday: ProbeScheduler.endOfDay(.now)),
        ])
    }

    var body: some View {
        let plan = initial ?? live, now = live
        NavigationStack {
            List {
                if plan.steps.isEmpty {
                    ContentUnavailableView("Bugün tekrar bekleyen bir şey yok", systemImage: "checkmark.seal.fill",
                                           description: Text("Yeni kartlar ve yanlışlar biriktikçe burada görünür."))
                } else {
                    Section {
                        ForEach(plan.steps) { item in
                            let left = now.counts[item] ?? 0
                            Button { visited.insert(item); step = item } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: left == 0 ? "checkmark.circle.fill" : item.symbol).font(.title3)
                                        .foregroundStyle(left == 0 ? Color.green : Color.accentColor).frame(width: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title).font(.headline).foregroundStyle(Color.primary)
                                        Text(left == 0 ? "Tamamlandı" : item.detail(left)).font(.caption).foregroundStyle(Color.secondary)
                                    }
                                }
                            }
                        }
                    } footer: { Text("Adımlar sırayla açılır. Birini kapatınca sıradaki kendiliğinden gelir; istediğin an bırakabilirsin.") }
                    Section {
                        if now.total == 0 {
                            Label("Bugünkü tekrar tamam. Eline sağlık!", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                        } else {
                            Button { start() } label: { Label(visited.isEmpty ? "Tekrara başla" : "Devam et", systemImage: "play.fill") }
                                .buttonStyle(PrimaryButtonStyle()).listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                        }
                    }
                }
            }
            .navigationTitle("Bugün tekrar et").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
            .onAppear { if initial == nil { initial = live } }
            .sheet(item: $step, onDismiss: advance) { item in
                switch item {
                case .cards: ReviewView()
                case .mistakes: MistakeBookView()
                case .probes: ProbeListView()
                }
            }
        }
    }

    /// İşi kalan ilk adımı açar; hepsi bu oturumda açıldıysa baştan dolaşır.
    private func start() {
        guard let plan = initial else { return }
        if plan.next(visited: visited, remaining: live) == nil { visited = [] }
        guard let next = plan.next(visited: visited, remaining: live) else { return }
        running = true; visited.insert(next); step = next
    }
    /// Bir adım kapatılınca, akış sürüyorsa sıradaki adım kısa bir aradan sonra açılır.
    private func advance() {
        guard running, let plan = initial, let next = plan.next(visited: visited, remaining: live) else { running = false; return }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            if running, step == nil { visited.insert(next); step = next }
        }
    }
}
