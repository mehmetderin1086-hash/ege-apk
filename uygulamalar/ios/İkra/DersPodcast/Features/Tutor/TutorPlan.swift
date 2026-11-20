import Foundation
import SwiftUI

nonisolated struct TutorPlanTask: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var minutes: Int
    var completed = false
    var questionID: String? = nil
    var questionRevision: Int? = nil
    var timingSamples: Int? = nil
    var deckID: UUID? = nil
    var deckCardCount: Int? = nil
    var completedAt: Date? = nil
    var actualSeconds: Double? = nil
    var timerStartedAt: Date? = nil
    var resourceKey: String? {
        if let questionID, let questionRevision { return "question:" + questionID + ":r\(questionRevision)" }
        if let deckID { return "deck:" + deckID.uuidString + ":\(deckCardCount ?? 0)" }
        return nil
    }
}
nonisolated struct TutorPlanDay: Codable, Identifiable, Equatable {
    var date: String
    var tasks: [TutorPlanTask]
    var id: String { date }
}
nonisolated struct TutorSavedPlan: Codable, Identifiable {
    var id = UUID()
    var subject: String
    var topics: String
    var examDate: String
    var dailyMinutes: Int
    var target: String
    var days: [TutorPlanDay]
    var createdAt = Date()
    var backlog: [TutorPlanTask]? = nil
    var rescheduledAt: Date? = nil
    var timingFactor: Double? = nil
    var timingEvidenceCount: Int? = nil
}

nonisolated enum TutorPlanLogic {
    /// A source without a course must not silently become a Mathematics plan.
    /// Only the standalone entry point keeps its historical default.
    static func startingSubject(_ subject: String?, topic: String?, choices: [String]) -> String {
        if subject == nil && topic == nil { return choices.contains("Matematik") ? "Matematik" : "" }
        return validatedSubject(subject ?? "", choices: choices) ?? ""
    }
    static func validatedSubject(_ subject: String, choices: [String]) -> String? {
        let value = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && choices.contains(value) ? value : nil
    }
    /// Resource ids come from the local archive; a generative response cannot invent a deep link.
    static func archiveDays(entries: [QSEntry], dates: [String], budget: Int, subject: String, topics: String, decks: [TutorDeck] = [], completed: Set<String> = [], timingFactor: Double = 1, prerequisites: [QSLearningEvidence.Prerequisite] = []) throws -> [TutorPlanDay] {
        let selectedSubject = QSDocumentSearch.normalized(subject), topicTokens = QSDocumentSearch.tokens(topics)
        let eligible = entries.filter { !$0.question.needsReview && QSDocumentSearch.normalized($0.question.subject) == selectedSubject && !completed.contains("question:" + $0.id + ":r\($0.question.revision)") }
        let matching = eligible.filter { !topicTokens.isDisjoint(with: QSDocumentSearch.tokens($0.question.topic + " " + $0.question.text)) }
        var remaining = matching.isEmpty ? eligible : matching
        let validLinks = prerequisites.filter { link in
            entries.contains { $0.id == link.questionID && $0.question.revision == link.revision } &&
            entries.contains { $0.id == link.prerequisiteID && $0.question.revision == link.prerequisiteRevision }
        }
        var already = Set(entries.filter { entry in
            completed.contains("question:" + entry.id + ":r\(entry.question.revision)") || (entry.currentAttempts.last?.correct == true && entry.currentAttempts.last?.assistanceCount == 0)
        }.map(\.id))
        var expanded = true
        while expanded {
            expanded = false
            for link in validLinks where remaining.contains(where: { $0.id == link.questionID }) && !already.contains(link.prerequisiteID) && !remaining.contains(where: { $0.id == link.prerequisiteID }) {
                guard let prerequisite = eligible.first(where: { $0.id == link.prerequisiteID }) else { throw TutorEngine.Failure(message: "Planın önkoşul sorusu bu derste çalışılabilir değil. Kaynak/önkoşul bağlantısını incele; mevcut plan korundu.") }
                remaining.append(prerequisite); expanded = true
            }
        }
        let checkTasks = remaining.map { TutorPlanTask(title: $0.question.topic, minutes: 1, questionID: $0.id) }
        _ = try LearnPlanScheduling.ordered(checkTasks, links: validLinks, entries: entries)
        var remainingDecks = decks.filter { !$0.cards.isEmpty && QSDocumentSearch.normalized($0.subject) == selectedSubject && !completed.contains("deck:" + $0.id.uuidString + ":\($0.cards.count)") && (topicTokens.isEmpty || !topicTokens.isDisjoint(with: QSDocumentSearch.tokens($0.title))) }.sorted { $0.createdAt < $1.createdAt }
        guard !remaining.isEmpty || !remainingDecks.isEmpty, budget > 0, !dates.isEmpty else { throw TutorEngine.Failure(message: "Seçilen derste çalışılabilir soru veya kart destesi yok. Arşive içerik ekle veya metin planını seç.") }
        var days: [TutorPlanDay] = [], usedFamilies = Set<String>()
        for date in dates.sorted() {
            var tasks: [TutorPlanTask] = [], minutes = 0
            while tasks.count < 8 {
                let ready = remaining.filter { entry in
                    !usedFamilies.contains(QSLearningEvidence.family(entry, entries: entries)) &&
                    validLinks.filter { $0.questionID == entry.id }.allSatisfy { already.contains($0.prerequisiteID) } &&
                    LearnPlanScheduling.minutes(seconds: QSLearningEvidence.estimate(entry, entries: entries).seconds, factor: timingFactor) + minutes <= budget
                }
                let baseMinutes = max(1, Int(ceil(Double(budget - minutes) / min(2, max(0.5, timingFactor)))))
                let priorHeavy = (tasks.last?.minutes ?? 0) >= 8
                let alternate = ready.filter { (LearnPlanScheduling.minutes(seconds: QSLearningEvidence.estimate($0, entries: entries).seconds, factor: timingFactor) >= 8) != priorHeavy }
                let suggestion = QSPersonalLearning.session(entries: alternate.isEmpty ? ready : alternate, minutes: baseMinutes, count: 1)
                let useDeck = tasks.last?.questionID != nil || ready.isEmpty || tasks.isEmpty
                if useDeck, let d = remainingDecks.firstIndex(where: { LearnPlanScheduling.minutes(seconds: $0.cards.count * 30, factor: timingFactor) + minutes <= budget }) {
                    let deck = remainingDecks.remove(at: d)
                    let estimate = LearnPlanScheduling.minutes(seconds: deck.cards.count * 30, factor: timingFactor)
                    tasks.append(.init(title: "Kart tekrarı · " + deck.title, minutes: estimate, timingSamples: 0, deckID: deck.id, deckCardCount: deck.cards.count)); minutes += estimate
                    continue
                }
                guard let id = suggestion.ids.first, let entry = remaining.first(where: { $0.id == id }) else { break }
                let estimate = QSLearningEvidence.estimate(entry, entries: entries), family = QSLearningEvidence.family(entry, entries: entries)
                let cost = LearnPlanScheduling.minutes(seconds: estimate.seconds, factor: timingFactor)
                tasks.append(.init(title: "Soru \(entry.question.number) · " + entry.question.topic, minutes: cost, questionID: entry.id, questionRevision: entry.question.revision, timingSamples: estimate.observations))
                minutes += cost; already.insert(entry.id); usedFamilies.insert(family)
                remaining.removeAll { $0.id == entry.id || QSLearningEvidence.family($0, entries: entries) == family }
            }
            if !tasks.isEmpty { days.append(.init(date: date, tasks: tasks)) }
            if remaining.isEmpty && remainingDecks.isEmpty { break }
        }
        guard !days.isEmpty else { throw TutorEngine.Failure(message: "Mevcut görevler ve önkoşulları günlük bütçeye sığmıyor. Süreyi artır veya daha kısa sorular seç.") }
        return days
    }
    /// Retain completed task identities; move only unfinished work, and expose anything that cannot fit.
    static func rescheduled(_ plan: TutorSavedPlan, dates: [String], entries: [QSEntry], decks: [TutorDeck] = [], now: Date = .now, prerequisites: [QSLearningEvidence.Prerequisite] = []) throws -> TutorSavedPlan {
        guard plan.dailyMinutes > 0, !dates.isEmpty, Set(dates).count == dates.count, dates.allSatisfy({ $0 <= plan.examDate }) else { throw TutorEngine.Failure(message: "Sınav tarihine kadar yeniden dağıtılabilecek gün yok.") }
        let all = plan.days.flatMap(\.tasks) + (plan.backlog ?? [])
        let completed = Set(all.filter(\.completed).compactMap(\.resourceKey))
        var seen = Set<UUID>(), resources = Set<String>()
        let unfinished = try LearnPlanScheduling.ordered(all.filter { task in
            guard !task.completed, seen.insert(task.id).inserted else { return false }
            if let key = task.resourceKey { return !completed.contains(key) && resources.insert(key).inserted }
            return true
        }, links: prerequisites, entries: entries)
        let adjustment = LearnPlanScheduling.adjustment(all)
        var days = plan.days.map { TutorPlanDay(date: $0.date, tasks: $0.tasks.filter(\.completed)) }.filter { !$0.tasks.isEmpty }
        for date in dates.sorted() where !days.contains(where: { $0.date == date }) { days.append(.init(date: date, tasks: [])) }
        var backlog: [TutorPlanTask] = []
        for original in unfinished {
            var task = original
            if let id = task.questionID, let entry = entries.first(where: { $0.id == id }) {
                let timing = QSLearningEvidence.estimate(entry, entries: entries)
                task.minutes = LearnPlanScheduling.minutes(seconds: timing.seconds, factor: adjustment.factor); task.timingSamples = timing.observations
                // A content revision remains visible in the linked task; the user must review it before solving.
            } else if let id = task.deckID, let deck = decks.first(where: { $0.id == id }) {
                task.minutes = LearnPlanScheduling.minutes(seconds: deck.cards.count * 30, factor: adjustment.factor)
            }
            let prerequisitesForTask = prerequisites.filter { link in
                link.questionID == task.questionID && entries.contains { $0.id == link.questionID && $0.question.revision == link.revision } && entries.contains { $0.id == link.prerequisiteID && $0.question.revision == link.prerequisiteRevision }
            }
            let blocked = prerequisitesForTask.contains { link in backlog.contains { $0.questionID == link.prerequisiteID } }
            let earliest = prerequisitesForTask.compactMap { link in days.first { $0.tasks.contains { $0.questionID == link.prerequisiteID } }?.date }.max() ?? dates.min()!
            if !blocked, let index = days.indices.filter({ dates.contains(days[$0].date) && days[$0].date >= earliest }).sorted(by: { days[$0].date < days[$1].date }).first(where: {
                days[$0].tasks.count < 8 && days[$0].tasks.reduce(0, { $0 + $1.minutes }) + task.minutes <= plan.dailyMinutes
            }) { days[index].tasks.append(task) } else { backlog.append(task) }
        }
        var updated = plan; updated.days = days.filter { !$0.tasks.isEmpty }.sorted { $0.date < $1.date }
        updated.backlog = backlog; updated.rescheduledAt = now; updated.timingFactor = adjustment.factor; updated.timingEvidenceCount = adjustment.samples; return updated
    }
    static func dateKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    static func allowedDates(now: Date, exam: Date, calendar: Calendar = .current) -> [String] {
        let start = calendar.startOfDay(for: now), end = calendar.startOfDay(for: exam)
        guard end >= start else { return [] }
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start), date <= end else { return nil }
            return dateKey(date, calendar: calendar)
        }
    }
    static func parse(_ text: String, allowedDates: [String], budget: Int) throws -> [TutorPlanDay] {
        struct WireTask: Decodable { var title: String; var minutes: Int }
        struct WireDay: Decodable { var date: String; var tasks: [WireTask] }
        struct WirePlan: Decodable { var days: [WireDay] }
        var source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.hasPrefix("```") {
            let lines = source.components(separatedBy: .newlines)
            if lines.count >= 3, lines.last?.trimmingCharacters(in: .whitespaces) == "```" {
                source = lines.dropFirst().dropLast().joined(separator: "\n")
            }
        }
        guard budget > 0, !allowedDates.isEmpty,
              let data = source.data(using: .utf8), let plan = try? JSONDecoder().decode(WirePlan.self, from: data),
              !plan.days.isEmpty, plan.days.count <= allowedDates.count,
              Set(plan.days.map(\.date)).count == plan.days.count,
              plan.days.allSatisfy({ allowedDates.contains($0.date) }) else {
            throw TutorEngine.Failure(message: "Plan geçerli günler içermiyor. Yeniden dene; mevcut planın korunuyor.")
        }
        return try plan.days.sorted { $0.date < $1.date }.map { day in
            guard (1...8).contains(day.tasks.count) else {
                throw TutorEngine.Failure(message: "Her günde 1–8 çalışma adımı olmalı. Planı yeniden oluştur.")
            }
            var total = 0
            var tasks: [TutorPlanTask] = []
            for task in day.tasks {
                let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, title.count <= 300, task.minutes > 0, task.minutes <= budget,
                      task.minutes <= budget - total else {
                    throw TutorEngine.Failure(message: "Plan günlük süreyi aşıyor veya geçersiz adım içeriyor. Planı yeniden oluştur.")
                }
                total += task.minutes
                tasks.append(TutorPlanTask(title: title, minutes: task.minutes))
            }
            return TutorPlanDay(date: day.date, tasks: tasks)
        }
    }
}

/// Yapay zekâ planı tamamlanabilir günlük adımlara dönüşür; kutucuklar cihazda kalıcıdır.
struct TutorPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = JSONStore<TutorSavedPlan>("tutor-daily-plans")
    @State private var subject = "Matematik"
    @State private var topics = ""
    @State private var examDate = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
    @State private var minutes = 45
    @State private var target = "80/100"
    @State private var busy = false
    @State private var error: String?
    @State private var request: Task<Void, Never>?
    @State private var selectedID: UUID?
    @State private var showSetup = false
    @State private var questions = QuestionStore.shared
    @State private var linkArchive = true
    @State private var practice: QSPracticeRequest?
    @State private var decks = JSONStore<TutorDeck>("tutor-decks")
    @State private var activeDeck: TutorDeck?
    @State private var includeDecks = true

    init(initialSubject: String? = nil, initialTopic: String? = nil) {
        _subject = State(initialValue: TutorPlanLogic.startingSubject(initialSubject, topic: initialTopic, choices: TutorHub.subjects))
        _topics = State(initialValue: initialTopic ?? "")
        _showSetup = State(initialValue: initialTopic != nil)
    }

    private var current: TutorSavedPlan? {
        store.items.first { $0.id == selectedID } ?? store.items.max { $0.createdAt < $1.createdAt }
    }
    private var dateRange: ClosedRange<Date> {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
        let last = Calendar.current.date(byAdding: .day, value: 180, to: Calendar.current.startOfDay(for: .now)) ?? tomorrow
        return tomorrow...last
    }

    var body: some View {
        NavigationStack {
            Form {
                if current == nil || showSetup { setup }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if busy { Section { ProgressView("Günlük plan hazırlanıyor…") } }
                if let plan = current {
                    Section("Kayıtlı çalışma planı") {
                        Text("\(plan.subject) · Hedef: \(plan.target)").font(.headline)
                        Text(plan.topics)
                        LabeledContent("Sınav tarihi", value: plan.examDate)
                        LabeledContent("Günlük bütçe", value: "\(plan.dailyMinutes) dakika")
                        Text("\(plan.timingEvidenceCount ?? 0) tamamlanmış süre ölçümü · tahmin çarpanı \((plan.timingFactor ?? 1).formatted(.number.precision(.fractionLength(2)))). Az veride başlangıç tahmini korunur.").font(.caption)
                        let tasks = plan.days.flatMap(\.tasks)
                        ProgressView(value: Double(tasks.filter(\.completed).count), total: Double(max(1, tasks.count)))
                        Text("\(tasks.filter(\.completed).count)/\(tasks.count) adım tamamlandı").font(.caption)
                        Button(showSetup ? "Plan oluşturmayı kapat" : "Yeni plan oluştur") { showSetup.toggle() }.disabled(busy)
                        Button("Bitmeyen işleri kalan günlere dağıt", systemImage: "calendar.badge.clock") { redistribute(plan) }.disabled(busy)
                        if let at = plan.rescheduledAt { Text("Son dağıtım: " + at.formatted(date: .abbreviated, time: .shortened)).font(.caption) }
                    }
                    if let backlog = plan.backlog, !backlog.isEmpty {
                        Section("Kalan bütçeye sığmayan işler · \(backlog.count)") {
                            ForEach(backlog) { task in Text(task.title + " · \(task.minutes) dk") }
                            Text("Bu işler silinmedi veya tamamlandı sayılmadı. Sınava kalan süreye sığan işler yukarıdaki günlere dağıtıldı.").font(.caption).foregroundStyle(.orange)
                        }
                    }
                    ForEach(plan.days) { day in
                        Section(day.date) {
                            ForEach(day.tasks) { task in
                                Toggle(isOn: Binding(get: {
                                    store.items.first { $0.id == plan.id }?.days.first { $0.date == day.date }?.tasks.first { $0.id == task.id }?.completed ?? false
                                }, set: { value in setCompleted(plan: plan.id, day: day.date, task: task.id, value: value) })) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(task.title)
                                        Text("Tahmin: \(task.minutes) dk · ölçülen: \(Int(task.actualSeconds ?? 0)) sn").font(.caption).foregroundStyle(.secondary)
                                        if let samples = task.timingSamples { Text(task.deckID == nil ? "\(samples) süre kaydı · okuma ve kontrol payı dahil" : "Kart başına 30 sn başlangıç tahmini; ölçülmüş süre değil").font(.caption2).foregroundStyle(.secondary) }
                                    }
                                }
                                Button(task.timerStartedAt == nil ? "Çalışma süresini başlat" : "Süreyi durdur", systemImage: task.timerStartedAt == nil ? "timer" : "pause.circle") {
                                    if task.timerStartedAt != nil { pauseTimers() } else { startTimer(plan: plan.id, day: day.date, task: task.id) }
                                }.disabled(task.completed)
                                if let id = task.questionID, let entry = questions.entries.first(where: { $0.id == id }) {
                                    if task.questionRevision != entry.question.revision { Text("Soru sürümü değişti; güncel r\(entry.question.revision) açılacak.").font(.caption).foregroundStyle(.orange) }
                                    Button("Bu soruyu çalış", systemImage: "play.circle") { startTimer(plan: plan.id, day: day.date, task: task.id); practice = QSPracticeRequest(ids: [id]) }
                                    NavigationLink("Soru ve çözüm kaydını aç") { QuestionDetail(store: questions, id: id) }
                                    if !entry.question.regions.isEmpty { NavigationLink("PDF / kaynak sayfasına git") { QSDocumentVideoNavigatorView(store: questions, entry: entry) } }
                                } else if task.questionID != nil { Text("Bağlı soru arşivde bulunamadı; başka bir soruyla sessizce değiştirilmedi.").font(.caption).foregroundStyle(.orange) }
                                if let deckID = task.deckID {
                                    if let deck = decks.items.first(where: { $0.id == deckID }) {
                                        Button("Bağlı kart destesini çalış", systemImage: "rectangle.stack") { startTimer(plan: plan.id, day: day.date, task: task.id); activeDeck = deck }
                                        if task.deckCardCount != deck.cards.count { Text("Destenin kart sayısı değişti; güncel deste açılacak.").font(.caption).foregroundStyle(.orange) }
                                    } else { Text("Bağlı kart destesi artık bulunamıyor.").font(.caption).foregroundStyle(.orange) }
                                }
                            }
                            Text("Toplam: \(day.tasks.reduce(0) { $0 + $1.minutes }) dakika").font(.caption)
                        }
                    }
                }
                if store.items.count > 1 {
                    Section("Önceki planlar") {
                        ForEach(store.items.sorted { $0.createdAt > $1.createdAt }) { plan in
                            Button("\(plan.subject) · \(plan.createdAt.formatted(date: .abbreviated, time: .omitted))") {
                                selectedID = plan.id; showSetup = false
                            }
                        }
                    }
                }
            }
            .navigationTitle("Günlük çalışma planım")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
            .onAppear { pauseTimers(countElapsed: false) }
            .onChange(of: scenePhase) { _, phase in if phase != .active { pauseTimers() } }
            .onDisappear { request?.cancel(); pauseTimers() }
            .sheet(item: $practice, onDismiss: { pauseTimers() }) { selection in QSPracticeSession(store: questions, ids: selection.ids) }
            .sheet(item: $activeDeck, onDismiss: { pauseTimers() }) { deck in TutorDeckStudyView(deck: deck) }
        }
    }

    private var setup: some View {
        Section("Planını hazırla") {
            Picker("Ders", selection: $subject) {
                Text("Ders seç").tag("")
                ForEach(TutorHub.subjects, id: \.self) { Text($0).tag($0) }
            }
            if subject.isEmpty {
                Text("Kaynakta ders bilgisi bulunmuyor veya eşleştirilemedi. Planı hazırlamadan önce dersini seç.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextField("Konular ve zorlandığın alanlar", text: $topics, axis: .vertical).lineLimit(3...6)
                .onChange(of: topics) { _, value in if value.count > 2000 { topics = String(value.prefix(2000)) } }
            DatePicker("Sınav tarihi", selection: $examDate, in: dateRange, displayedComponents: .date)
            Stepper("Günlük \(minutes) dakika", value: $minutes, in: 10...240, step: 5)
            TextField("Hedefin (ör. 80/100 veya 30 net)", text: $target)
                .onChange(of: target) { _, value in if value.count > 150 { target = String(value.prefix(150)) } }
            Toggle("Arşivimdeki gerçek sorulara bağla", isOn: $linkArchive)
            if linkArchive { Toggle("Konuyla eşleşen kayıtlı kart destelerini ekle", isOn: $includeDecks) }
            Text(linkArchive ? "Her görev doğrudan bir soru ve varsa PDF sayfasını açar. Süre tahmini kayıtlı çözme sürelerinden gelir; aynı aile bir kez seçilir. Yeterli soru yoksa boş gün uydurulmaz." : "Metin planı model önerisidir; soru / PDF bağlantısı içermez.").font(.caption).foregroundStyle(.secondary)
            Text("Bugünden başlayarak en fazla 7 günlük plan hazırlanır. Sınav tarihini geçmez; her günün toplamı ayırdığın süreyi aşmaz. Tamamladığın adımları işaretleyebilirsin.")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Plan oluştur ve kaydet") { generate() }
                .disabled(busy || TutorPlanLogic.validatedSubject(subject, choices: TutorHub.subjects) == nil || topics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.disabled(busy)
    }

    private func startTimer(plan: UUID, day: String, task: UUID) {
        pauseTimers()
        guard let p = store.items.firstIndex(where: { $0.id == plan }), let d = store.items[p].days.firstIndex(where: { $0.date == day }), let t = store.items[p].days[d].tasks.firstIndex(where: { $0.id == task && !$0.completed }) else { return }
        store.items[p].days[d].tasks[t].timerStartedAt = .now
    }
    private func pauseTimers(countElapsed: Bool = true) {
        let now = Date.now
        var plans = store.items, changed = false
        for p in plans.indices { for d in plans[p].days.indices { for t in plans[p].days[d].tasks.indices {
            guard let began = plans[p].days[d].tasks[t].timerStartedAt else { continue }
            if countElapsed { plans[p].days[d].tasks[t].actualSeconds = (plans[p].days[d].tasks[t].actualSeconds ?? 0) + min(14400, max(0, now.timeIntervalSince(began))) }
            plans[p].days[d].tasks[t].timerStartedAt = nil; changed = true
        } } }
        if changed { store.items = plans }
    }
    private func setCompleted(plan: UUID, day: String, task: UUID, value: Bool) {
        guard let p = store.items.firstIndex(where: { $0.id == plan }),
              let d = store.items[p].days.firstIndex(where: { $0.date == day }),
              let t = store.items[p].days[d].tasks.firstIndex(where: { $0.id == task }) else { return }
        pauseTimers()
        store.items[p].days[d].tasks[t].completed = value
        store.items[p].days[d].tasks[t].completedAt = value ? .now : nil
        if value {
            let completed = store.items[p].days[d].tasks[t]
            LearningContinuity.record(source: .tutor, sourceID: "plan:" + completed.id.uuidString, subject: store.items[p].subject, topic: store.items[p].topics,
                                      correct: nil, seconds: completed.actualSeconds, detail: "Plan görevi tamamlandı: " + completed.title)
        }
    }
    private func redistribute(_ plan: TutorSavedPlan) {
        let parts = plan.examDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let exam = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { error = "Kayıtlı sınav tarihi açılamadı."; return }
        do {
            let dates = TutorPlanLogic.allowedDates(now: .now, exam: exam)
            let updated = try TutorPlanLogic.rescheduled(plan, dates: dates, entries: questions.entries, decks: decks.items, prerequisites: QSLearningEvidenceStore.prerequisites())
            if let index = store.items.firstIndex(where: { $0.id == plan.id }) { store.items[index] = updated }; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func generate() {
        guard let selectedSubject = TutorPlanLogic.validatedSubject(subject, choices: TutorHub.subjects) else {
            error = "Plan oluşturmak için bir ders seç."; return
        }
        let allowed = TutorPlanLogic.allowedDates(now: .now, exam: examDate)
        guard dateRange.contains(examDate), !allowed.isEmpty else { error = "Gelecekteki bir sınav tarihi seç."; return }
        let selectedTopics = topics, selectedTarget = target
        let budget = minutes, exam = TutorPlanLogic.dateKey(examDate)
        if linkArchive {
            do {
                let completed = Set(store.items.filter { $0.subject == selectedSubject && $0.examDate == exam }.flatMap(\.days).flatMap(\.tasks).filter(\.completed).compactMap(\.resourceKey))
                let timing = LearnPlanScheduling.adjustment(store.items.filter { $0.subject == selectedSubject }.flatMap(\.days).flatMap(\.tasks))
                let days = try TutorPlanLogic.archiveDays(entries: questions.entries, dates: allowed, budget: budget, subject: selectedSubject, topics: selectedTopics, decks: includeDecks ? decks.items : [], completed: completed, timingFactor: timing.factor, prerequisites: QSLearningEvidenceStore.prerequisites())
                let plan = TutorSavedPlan(subject: selectedSubject, topics: selectedTopics, examDate: exam, dailyMinutes: budget, target: selectedTarget, days: days, timingFactor: timing.factor, timingEvidenceCount: timing.samples)
                store.items.append(plan); selectedID = plan.id; showSetup = false; error = nil
            } catch { self.error = error.localizedDescription }
            return
        }
        busy = true; error = nil
        request = Task {
            defer { busy = false }
            do {
                let prompt = """
                Ders: \(selectedSubject). Konular ve eksikler: \(selectedTopics).
                Hedef: \(selectedTarget). Sınav tarihi: \(exam). Günlük toplam süre: en fazla \(budget) dakika.
                Bugün: \(allowed[0]). Yalnız şu günlerden oluşan uygulanabilir plan hazırla: \(allowed.joined(separator: ", ")).
                Her gün 1–8 somut çalışma adımı olsun; tekrar ve soru çözümünü uygun biçimde dağıt.
                Her adımın süresi pozitif tam sayı dakika olsun; günlük toplam \(budget) dakikayı aşmasın.
                Yalnız şu şemada geçerli JSON döndür; ek açıklama veya kod çiti ekleme:
                {"days":[{"date":"YYYY-MM-DD","tasks":[{"title":"Somut çalışma adımı","minutes":15}]}]}.
                """
                let text = try await TutorEngine.reply(mode: .plan, subject: selectedSubject, level: "Öğrencinin belirttiği hedef",
                                                      messages: [TutorMessage(role: "user", text: prompt)])
                try Task.checkCancellation()
                let days = try TutorPlanLogic.parse(text, allowedDates: allowed, budget: budget)
                let plan = TutorSavedPlan(subject: selectedSubject, topics: selectedTopics, examDate: exam,
                                          dailyMinutes: budget, target: selectedTarget, days: days)
                store.items.append(plan); selectedID = plan.id; showSetup = false
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}
