import SwiftUI

// MARK: - Alışkanlık takibi

struct HabitsView: View {
    @State private var store = JSONStore<Habit>("habits")
    @State private var newName = ""
    @State private var pendingDelete: Habit?
    @State private var renaming: UUID?
    @State private var renameText = ""

    var body: some View {
        @Bindable var store = store
        let week = HabitWeek.days()
        ToolScaffold(title: "Alışkanlıklar") {
            List {
                Section {
                    if store.items.isEmpty { Text("Her gün yapmak istediğin küçük şeyleri ekle: 20 sayfa kitap, 10 paragraf, erken yatmak…").foregroundStyle(.secondary) }
                    ForEach($store.items) { $habit in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(habit.name).font(.headline)
                                Spacer(minLength: 4)
                                let streak = Streak.current(days: habit.days)
                                if streak > 0 { Label("\(streak)", systemImage: "flame.fill").font(.subheadline.bold()).foregroundStyle(.orange) }
                            }
                            HStack(spacing: 4) {
                                ForEach(week, id: \.self) { date in
                                    let key = DayKey.key(date), done = habit.days.contains(key), isToday = date == week.last
                                    Button {
                                        if done { habit.days.remove(key) } else { habit.days.insert(key) }
                                    } label: {
                                        VStack(spacing: 2) {
                                            Text(HabitWeek.label(date)).font(.caption2).fontWeight(isToday ? .bold : .regular)
                                                .foregroundStyle(isToday ? .primary : .secondary)
                                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                                .font(.title3).foregroundStyle(done ? .green : .secondary)
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        // Kalın Yazı açıkken kalınlık ayırt etmez: bugünün sütunu zeminle de belli olsun.
                                        .background(Color.accentColor.opacity(isToday ? 0.14 : 0), in: RoundedRectangle(cornerRadius: 8))
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(isToday ? "Bugün" : date.formatted(date: .abbreviated, time: .omitted)) \(done ? "yapıldı" : "yapılmadı")")
                                    .accessibilityAddTraits(done ? .isSelected : [])
                                }
                            }
                            Text("En uzun seri: \(Streak.best(days: habit.days)) gün · toplam \(habit.days.count) gün").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .sensoryFeedback(.selection, trigger: habit.days)
                        .contextMenu {
                            Button("Yeniden adlandır", systemImage: "pencil") { renameText = habit.name; renaming = habit.id }
                        }
                    }
                    .onDelete { offsets in
                        // Haftalarca işaretlenmiş kayıt tek kaydırmayla gitmesin; yeni eklenen onaysız silinir.
                        let targets = offsets.map { store.items[$0] }
                        let quick = Set(targets.filter { $0.days.count < 7 }.map(\.id))
                        if !quick.isEmpty { store.items.removeAll { quick.contains($0.id) } }
                        pendingDelete = targets.first { $0.days.count >= 7 }
                    }
                }
                Section("Yeni alışkanlık") {
                    TextField("Örn. 20 sayfa kitap", text: $newName)
                    Button("Ekle") {
                        store.items.append(Habit(name: newName.trimmingCharacters(in: .whitespaces)))
                        newName = ""
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Alışkanlık silinsin mi?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible, presenting: pendingDelete) { habit in
                Button("Sil", role: .destructive) { store.items.removeAll { $0.id == habit.id } }
                Button("Vazgeç", role: .cancel) {}
            } message: { habit in
                Text("“\(habit.name)” ve \(habit.days.count) günlük kaydı silinecek.")
            }
            .alert("Yeniden adlandır", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { id in
                TextField("Alışkanlık adı", text: $renameText)
                Button("Vazgeç", role: .cancel) {}
                Button("Kaydet") {
                    let name = renameText.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty, let i = store.items.firstIndex(where: { $0.id == id }) { store.items[i].name = name }
                }
            }
        }
    }
}

// MARK: - Hedefler

struct GoalsView: View {
    @State private var store = JSONStore<StudyGoal>("goals")
    @State private var title = ""
    /// Boş bırakılırsa 5.
    @State private var target: Int?
    @State private var hasDeadline = false
    @State private var deadline = Date.now.addingTimeInterval(7 * 86_400)
    /// "Sayı gir" penceresi açık olan hedef.
    @State private var entering: UUID?
    @State private var amountText = ""

    var body: some View {
        @Bindable var store = store
        ToolScaffold(title: "Hedefler") {
            List {
                Section {
                    if store.items.isEmpty { Text("Sayılabilir hedef koy: “Bu hafta 5 deneme”, “300 paragraf sorusu”.").foregroundStyle(.secondary) }
                    ForEach($store.items) { $goal in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(goal.title).font(.headline)
                                Spacer(minLength: 4)
                                if goal.done >= goal.target { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) }
                            }
                            ProgressView(value: min(1, Double(goal.done) / Double(max(1, goal.target))))
                            Stepper("\(goal.done) / \(goal.target)", value: $goal.done, in: 0...GoalMath.maxCount)
                            // Büyük hedefte tek tek artırmak yerine: hızlı ekleme ve doğrudan sayı.
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) { quickButtons($goal) }
                                VStack(alignment: .leading, spacing: 6) { quickButtons($goal) }
                            }
                            .buttonStyle(.bordered)
                            status(goal)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { store.items.remove(atOffsets: $0) }
                }
                Section("Yeni hedef") {
                    TextField("Hedef", text: $title)
                    LabeledContent("Kaç kez") {
                        TextField("Kaç kez", value: $target, format: .number, prompt: Text("5"))
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    Toggle("Son gün belirle", isOn: $hasDeadline)
                    if hasDeadline { DatePicker("Son gün", selection: $deadline, displayedComponents: .date) }
                    Button("Ekle") {
                        store.items.append(StudyGoal(title: title.trimmingCharacters(in: .whitespaces), target: min(GoalMath.maxCount, max(1, target ?? 5)),
                                                     deadline: hasDeadline ? deadline : nil))
                        title = ""; target = nil
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("İlerleme gir", isPresented: Binding(get: { entering != nil }, set: { if !$0 { entering = nil } }), presenting: entering) { id in
                TextField("Sayı", text: $amountText).keyboardType(.numberPad)
                Button("Üstüne ekle") { enter(id) { $0 + $1 } }
                Button("Toplam bu olsun") { enter(id) { _, typed in typed } }
                Button("Vazgeç", role: .cancel) {}
            } message: { id in
                if let goal = store.items.first(where: { $0.id == id }) { Text("“\(goal.title)”: şu an \(goal.done) / \(goal.target).") }
            }
        }
    }

    @ViewBuilder private func quickButtons(_ goal: Binding<StudyGoal>) -> some View {
        ForEach([5, 10], id: \.self) { step in
            Button { goal.wrappedValue.done = min(GoalMath.maxCount, goal.wrappedValue.done + step) } label: {
                Text("+\(step)").frame(minWidth: 26, minHeight: 30)
            }
        }
        Button { amountText = ""; entering = goal.wrappedValue.id } label: {
            Label("Sayı gir", systemImage: "number").frame(minHeight: 30)
        }
    }

    @ViewBuilder private func status(_ goal: StudyGoal) -> some View {
        switch GoalMath.status(done: goal.done, target: goal.target, deadline: goal.deadline) {
        case .done:
            Text("Tamamlandı").font(.caption).foregroundStyle(.green)
        case .overdue(let missing):
            Text("Süresi geçti · \(missing) eksik").font(.caption).foregroundStyle(.red)
        case .remaining(let days, let perDay):
            let last = goal.deadline?.formatted(date: .abbreviated, time: .omitted) ?? ""
            Text(days == 0 ? "Son gün bugün · \(perDay) eksik" : "Son gün: \(last) · \(days) gün kaldı · günde ~\(perDay)")
                .font(.caption).foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }

    /// Uyarıdaki sayıyı hedefe işler: `combine(şimdiki, yazılan)` yeni ilerlemedir.
    private func enter(_ id: UUID, _ combine: (Int, Int) -> Int) {
        guard let typed = GoalMath.count(from: amountText), let i = store.items.firstIndex(where: { $0.id == id }) else { return }
        store.items[i].done = min(GoalMath.maxCount, max(0, combine(store.items[i].done, typed)))
    }
}

// MARK: - Öncelik matrisi (Eisenhower)

struct TodoMatrixView: View {
    @State private var store = JSONStore<TodoItem>("todos")
    @State private var title = ""
    @State private var urgent = false
    @State private var important = true

    private static let quadrants: [(urgent: Bool, important: Bool, title: String, color: Color)] = [
        (true, true, "Hemen yap · acil ve önemli", .red),
        (false, true, "Planla · önemli, acil değil", .blue),
        (true, false, "Kısa tut · acil, önemli değil", .orange),
        (false, false, "Bırak · ne acil ne önemli", .gray),
    ]

    var body: some View {
        ToolScaffold(title: "Öncelik matrisi") {
            List {
                Section("Yeni iş") {
                    TextField("Ne yapılacak?", text: $title)
                    Toggle("Acil", isOn: $urgent)
                    Toggle("Önemli", isOn: $important)
                    Button("Ekle") {
                        store.items.append(TodoItem(title: title.trimmingCharacters(in: .whitespaces), urgent: urgent, important: important))
                        title = ""
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(Self.quadrants, id: \.title) { quadrant in
                    let items = store.items.filter { $0.urgent == quadrant.urgent && $0.important == quadrant.important }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { item in
                                Button {
                                    if let i = store.items.firstIndex(where: { $0.id == item.id }) { store.items[i].done.toggle() }
                                } label: {
                                    HStack(alignment: .firstTextBaseline) {
                                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle").foregroundStyle(item.done ? .green : quadrant.color)
                                        Text(item.title).strikethrough(item.done).foregroundStyle(item.done ? .secondary : .primary)
                                    }
                                }
                                .buttonStyle(.plain)
                                .swipeActions { Button("Sil", role: .destructive) { store.items.removeAll { $0.id == item.id } } }
                            }
                        } header: {
                            Text(quadrant.title).foregroundStyle(quadrant.color)
                        }
                    }
                }
                if store.items.contains(where: \.done) {
                    Button("Tamamlananları temizle", role: .destructive) { store.items.removeAll(where: \.done) }
                }
            }
        }
    }
}

// MARK: - Öğrenme günlüğü

struct JournalView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = JSONStore<JournalEntry>("journal")
    @State private var draft = JournalEntry(day: JournalView.todayKey)
    @State private var savedNote = false

    private static let moods = ["😞", "😕", "😐", "🙂", "😄"]
    /// Yalnız Debug: `-journalDay=2026-10-07` bugünü değiştirir (dünden devreden notu simülatörde görmek için).
    private static var todayKey: String { DebugArg.value("journalDay") ?? DayKey.key() }

    var body: some View {
        ToolScaffold(title: "Öğrenme günlüğü") {
            List {
                Section("Bugün") {
                    if let carry = JournalLogic.carryOver(store.items, todayKey: draft.day) {
                        Label("\(JournalLogic.isYesterday(carry.day, todayKey: draft.day) ? "Dünden planın" : "Önceki planın"): \(carry.tomorrow)", systemImage: "arrow.turn.down.right")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Picker("Nasıl geçti?", selection: $draft.mood) {
                        ForEach(1...5, id: \.self) { Text(Self.moods[$0 - 1]).tag($0) }
                    }
                    .modifier(AccessiblePickerStyle())
                    TextField("Bugün ne öğrendim?", text: $draft.learned, axis: .vertical).lineLimit(2...6)
                    TextField("Nerede zorlandım?", text: $draft.hard, axis: .vertical).lineLimit(1...4)
                    TextField("Yarın ilk işim", text: $draft.tomorrow, axis: .vertical).lineLimit(1...3)
                    Button(savedNote ? "Kaydedildi" : "Kaydet") { save() }
                }
                let past = store.items.filter { $0.day != draft.day }.sorted { $0.day > $1.day }
                if !past.isEmpty {
                    Section("Geçmiş") {
                        ForEach(past) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(Self.moods[max(1, min(5, entry.mood)) - 1]) \(DayKey.date(entry.day)?.formatted(date: .complete, time: .omitted) ?? entry.day)").font(.subheadline.bold())
                                if !entry.learned.isEmpty { Text(entry.learned) }
                                if !entry.hard.isEmpty { Text("Zorlandığım: \(entry.hard)").font(.footnote).foregroundStyle(.secondary) }
                                if !entry.tomorrow.isEmpty { Text("Ertesi gün: \(entry.tomorrow)").font(.footnote).foregroundStyle(.secondary) }
                            }
                            .swipeActions { Button("Sil", role: .destructive) { store.items.removeAll { $0.id == entry.id } } }
                        }
                    }
                }
            }
            .onAppear { if let today = store.items.first(where: { $0.day == draft.day }) { draft = today } }
            .onChange(of: draft) { savedNote = false }
            // Yazma durunca kendiliğinden kaydet: uygulama arka planda sonlandırılırsa girdi kaybolmasın.
            .task(id: draft) {
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled { autosave() }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { startNewDayIfNeeded() } else { autosave() } }
            // "Kapat" ya da aşağı çekme yazılanı silmesin.
            .onDisappear { autosave() }
        }
    }

    private func autosave() {
        guard !savedNote else { return }
        let stored = store.items.first { $0.day == draft.day }
        if JournalLogic.needsSave(draft, stored: stored) { save() } else if stored == draft { savedNote = true }
    }

    /// Ekran gece yarısından sonra açık kaldıysa yazılanlar dünün girdisine eklenmesin: dünkü kaydedilir, bugünün taslağı açılır.
    private func startNewDayIfNeeded() {
        let today = Self.todayKey
        guard draft.day != today else { return }
        autosave()
        draft = store.items.first { $0.day == today } ?? JournalEntry(day: today)
    }

    private func save() {
        if let i = store.items.firstIndex(where: { $0.day == draft.day }) { store.items[i] = draft } else { store.items.append(draft) }
        savedNote = true
    }
}

// MARK: - Konu tekrar takvimi (1-3-7-14-30)

struct RevisionPlanView: View {
    @State private var store = JSONStore<RevisionTopic>("revisions")
    @State private var title = ""
    @State private var course = ""

    static var dueCount: Int { JSONStore<RevisionTopic>("revisions").items.filter { RevisionPlan.isDue($0.nextDue) }.count }

    var body: some View {
        let due = store.items.filter { RevisionPlan.isDue($0.nextDue) }
        let upcoming = store.items.filter { $0.nextDue != nil && !RevisionPlan.isDue($0.nextDue) }.sorted { ($0.nextDue ?? .now) < ($1.nextDue ?? .now) }
        let finished = store.items.filter { $0.nextDue == nil }
        ToolScaffold(title: "Konu tekrar takvimi") {
            List {
                Section("Bugün çalıştığım konu") {
                    TextField("Konu (örn. Hücre zarı)", text: $title)
                    TextField("Ders (isteğe bağlı)", text: $course)
                    Button("Takvime ekle") {
                        store.items.append(RevisionTopic(title: title.trimmingCharacters(in: .whitespaces), course: course.trimmingCharacters(in: .whitespaces)))
                        title = ""
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    Text("Konu 1, 3, 7, 14 ve 30. günlerde tekrar için önüne gelir.").font(.caption).foregroundStyle(.secondary)
                }
                if !due.isEmpty {
                    Section("Bugün tekrar et") {
                        ForEach(due) { topic in
                            row(topic)
                            Button("Tekrar ettim", systemImage: "checkmark") { advance(topic) }
                        }
                    }
                }
                if !upcoming.isEmpty { Section("Yaklaşan") { ForEach(upcoming) { row($0) } } }
                if !finished.isEmpty { Section("Tamamlanan") { ForEach(finished) { row($0) } } }
            }
        }
    }

    private func row(_ topic: RevisionTopic) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(topic.title).font(.headline)
            let step = "Tekrar \(min(topic.doneSteps + 1, RevisionPlan.intervals.count))/\(RevisionPlan.intervals.count)"
            Text([topic.course, topic.nextDue.map { "\(step) · \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "5 tekrar bitti"]
                .filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
        }
        .swipeActions { Button("Sil", role: .destructive) { store.items.removeAll { $0.id == topic.id } } }
    }

    private func advance(_ topic: RevisionTopic) {
        guard let i = store.items.firstIndex(where: { $0.id == topic.id }) else { return }
        store.items[i].doneSteps += 1
        store.items[i].anchor = .now
    }
}

// MARK: - Okuma takibi

struct ReadingView: View {
    @State private var store = JSONStore<ReadingBook>("books")
    @State private var title = ""
    /// Boş bırakılırsa 200.
    @State private var pages: Int?
    /// "Sayfayı gir" penceresi açık olan kitap.
    @State private var entering: UUID?
    @State private var pageText = ""

    var body: some View {
        @Bindable var store = store
        ToolScaffold(title: "Okuma takibi") {
            List {
                Section {
                    if store.items.isEmpty { Text("Okuduğun kitabı ya da ders kitabını ekle; her gün kaldığın sayfayı gir.").foregroundStyle(.secondary) }
                    ForEach($store.items) { $book in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(book.title).font(.headline)
                                Spacer(minLength: 4)
                                if book.currentPage >= book.totalPages { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) }
                            }
                            ProgressView(value: min(1, Double(book.currentPage) / Double(max(1, book.totalPages))))
                            Stepper("Sayfa \(book.currentPage) / \(book.totalPages)") {
                                book.setPage(book.currentPage + 1)
                            } onDecrement: {
                                book.setPage(book.currentPage - 1)
                            }
                            Button { pageText = ""; entering = book.id } label: {
                                Label("Sayfayı gir", systemImage: "number").frame(minHeight: 30)
                            }
                            .buttonStyle(.bordered)
                            let today = book.log[DayKey.key()] ?? 0
                            Text("Bugün \(today) sayfa · okuma serisi \(Streak.current(days: Set(book.log.filter { $0.value > 0 }.keys))) gün")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { store.items.remove(atOffsets: $0) }
                }
                Section("Yeni kitap") {
                    TextField("Kitap adı", text: $title)
                    LabeledContent("Sayfa sayısı") {
                        TextField("Sayfa sayısı", value: $pages, format: .number, prompt: Text("200"))
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    Button("Ekle") {
                        store.items.append(ReadingBook(title: title.trimmingCharacters(in: .whitespaces), totalPages: min(10_000, max(1, pages ?? 200))))
                        title = ""; pages = nil
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Kaldığın sayfa", isPresented: Binding(get: { entering != nil }, set: { if !$0 { entering = nil } }), presenting: entering) { id in
                TextField("Sayfa", text: $pageText).keyboardType(.numberPad)
                Button("Vazgeç", role: .cancel) {}
                Button("Kaydet") {
                    if let page = GoalMath.count(from: pageText), let i = store.items.firstIndex(where: { $0.id == id }) { store.items[i].setPage(page) }
                }
            } message: { id in
                if let book = store.items.first(where: { $0.id == id }) { Text("“\(book.title)”: şu an \(book.currentPage) / \(book.totalPages).") }
            }
        }
    }
}

// MARK: - Motivasyon duvarı

struct QuotesView: View {
    @State private var store = JSONStore<OwnQuote>("quotes")
    @State private var text = ""
    @State private var shown = ""

    private var pool: [String] { StudyMotivation.motivations + store.items.map(\.text) }

    var body: some View {
        ToolScaffold(title: "Motivasyon duvarı") {
            List {
                Section {
                    VStack(spacing: 14) {
                        Image(systemName: "quote.opening").font(.title).foregroundStyle(.white.opacity(0.8))
                        Text(shown).font(.title3.weight(.semibold)).multilineTextAlignment(.center).foregroundStyle(.white)
                        Button("Başka bir söz") { shown = pool.filter { $0 != shown }.randomElement() ?? shown }
                            .buttonStyle(.bordered).tint(.white)
                    }
                    .frame(maxWidth: .infinity).padding(20)
                    .background(Theme.gradient, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .listRowInsets(EdgeInsets())
                }
                Section("Kendi sözlerim") {
                    TextField("Seni harekete geçiren cümle", text: $text, axis: .vertical)
                    Button("Ekle") {
                        store.items.append(OwnQuote(text: text.trimmingCharacters(in: .whitespacesAndNewlines)))
                        text = ""
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    ForEach(store.items) { Text($0.text) }
                        .onDelete { store.items.remove(atOffsets: $0) }
                }
            }
            .onAppear { if shown.isEmpty { shown = StudyMotivation.motivation() } }
        }
    }
}
