import SwiftData
import SwiftUI

/// Gün → çalışılan dakika (odak oturumları + dinleme).
private func minutesByDay(sessions: [StudySession], listening: [ListeningDay]) -> [String: Double] {
    var map: [String: Double] = [:]
    for session in sessions where session.kind == "focus" { map[DayKey.key(session.startedAt), default: 0] += session.seconds / 60 }
    for day in listening { map[day.day, default: 0] += day.seconds / 60 }
    return map
}

// MARK: - Rozetler

struct BadgesView: View {
    @Query private var cards: [ReviewCard]
    @Query private var mistakes: [MistakeEntry]
    @Query private var sessions: [StudySession]
    @Query private var listening: [ListeningDay]
    @Query private var episodes: [Episode]
    @Query private var lessons: [VideoLesson]
    @Query private var notes: [CornellNote]
    @Query(filter: #Predicate<RecallAttempt> { $0.source == "review" }) private var reviewAttempts: [RecallAttempt]

    private var badges: [Badge] {
        let minutes = minutesByDay(sessions: sessions, listening: listening)
        let questions = JSONStore<QuestionLog>("questions").items.reduce(0) { $0 + $1.solved }
        let stats = BadgeStats(
            cards: cards.count,
            matureCards: cards.filter { $0.intervalDays >= 21 }.count,
            // Kayıt sayısı azalmaz ("Bilemedim" kartın tekrar sayısını sıfırlar); eski kartlar için kart sayaçları da alt sınırdır.
            reviews: max(reviewAttempts.count, cards.reduce(0) { $0 + $1.repetitions + $1.lapses }),
            resolvedMistakes: mistakes.filter(\.resolved).count,
            focusMinutes: Int(sessions.filter { $0.kind == "focus" }.reduce(0) { $0 + $1.seconds } / 60),
            listenedMinutes: Int(listening.reduce(0) { $0 + $1.seconds } / 60),
            bestStreak: Streak.best(days: Set(minutes.filter { $0.value >= 1 }.keys)),
            episodes: episodes.count,
            videoLessons: lessons.count,
            notes: notes.count,
            mockExams: JSONStore<MockExam>("mock-exams").items.count,
            solvedQuestions: questions)
        return Badges.all(stats)
    }

    var body: some View {
        let all = badges
        ToolScaffold(title: "Rozetler") {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(all.filter(\.earned).count) / \(all.count) rozet kazanıldı").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], spacing: 10) {
                        ForEach(all) { badge in
                            VStack(spacing: 6) {
                                Image(systemName: badge.symbol).font(.title)
                                    .foregroundStyle(badge.earned ? AnyShapeStyle(tierColor(badge)) : AnyShapeStyle(.tertiary))
                                Text(badge.title).font(.caption.bold()).multilineTextAlignment(.center)
                                Text(badge.detail).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                if badge.earned {
                                    Label("Kazanıldı", systemImage: "checkmark").font(.caption2).foregroundStyle(.green)
                                } else {
                                    ProgressView(value: badge.progress)
                                    Text("\(badge.value) / \(badge.goal)").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, minHeight: 140)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                            .opacity(badge.earned ? 1 : 0.75)
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private func tierColor(_ badge: Badge) -> Color {
        badge.id.hasSuffix("-0") ? .brown : badge.id.hasSuffix("-1") ? .gray : .yellow
    }
}

// MARK: - Çalışma haritası

struct StudyHeatMapView: View {
    @Query private var sessions: [StudySession]
    @Query private var listening: [ListeningDay]
    @State private var selected: Date?

    private static let weeks = 16

    var body: some View {
        let minutes = minutesByDay(sessions: sessions, listening: listening)
        let active = Set(minutes.filter { $0.value >= 1 }.keys)
        let grid = HeatMap.grid(weeks: Self.weeks)
        ToolScaffold(title: "Çalışma haritası") {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 3) {
                        ForEach(grid.indices, id: \.self) { column in
                            VStack(spacing: 3) {
                                ForEach(0..<7, id: \.self) { row in
                                    let date = grid[column][row]
                                    let level = date.map { HeatMap.level(minutes: minutes[DayKey.key($0)] ?? 0) } ?? -1
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(level < 0 ? Color.clear : level == 0 ? Color.gray.opacity(0.18) : Color.green.opacity(0.25 + Double(level) * 0.1875))
                                        .aspectRatio(1, contentMode: .fit)
                                        .overlay { if let date, date == selected { RoundedRectangle(cornerRadius: 3).stroke(.primary, lineWidth: 1.5) } }
                                        .onTapGesture { selected = date }
                                }
                            }
                        }
                    }
                    if let selected {
                        Text("\(selected.formatted(date: .complete, time: .omitted)): \(Int((minutes[DayKey.key(selected)] ?? 0).rounded())) dakika")
                            .font(.subheadline)
                    } else {
                        Text("Bir güne dokun: o gün kaç dakika çalıştığını gör.").font(.footnote).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 0) {
                        stat("Şu anki seri", "\(Streak.current(days: active)) gün")
                        Divider()
                        stat("En uzun seri", "\(Streak.best(days: active)) gün")
                        Divider()
                        stat("Çalışılan gün (\(Self.weeks) hafta)", "\(grid.joined().compactMap { $0 }.filter { active.contains(DayKey.key($0)) }.count)")
                        Divider()
                        stat("Bu hafta", "\(Int((grid.last ?? []).compactMap { $0 }.reduce(0) { $0 + (minutes[DayKey.key($1)] ?? 0) }.rounded())) dk")
                        Divider()
                        stat("En dolu gün", "\(Int((minutes.values.max() ?? 0).rounded())) dk")
                    }
                    .padding(.horizontal, 12)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                    Text("Odak oturumları ve dinleme süreleri sayılır. Koyu yeşil = 90 dakika ve üstü.").font(.caption).foregroundStyle(.secondary)
                }
                .padding(16)
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Text(value).bold()
        }
        .font(.subheadline)
        .padding(.vertical, 10)
    }
}
