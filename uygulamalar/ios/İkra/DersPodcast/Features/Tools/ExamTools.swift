import Charts
import SwiftData
import SwiftUI

// MARK: - Deneme takibi

struct MockExamsView: View {
    @State private var store = JSONStore<MockExam>("mock-exams")
    @State private var editing: MockExam?
    /// Grafikte gösterilen ders; nil = toplam net.
    @State private var lesson: String?

    private var sorted: [MockExam] { store.items.sorted { $0.date > $1.date } }

    var body: some View {
        let lessons = MockExamStats.lessons(store.items)
        // Seçili ders listedeki yazılışıyla eşlenir (en yeni deneme silinince yazılış değişebilir); listeden düştüyse toplama dönülür.
        let shownLesson = lesson.flatMap { chosen in lessons.first { AnswerMatch.normalize($0) == AnswerMatch.normalize(chosen) } }
        let points = MockExamStats.series(store.items, lesson: shownLesson)
        ToolScaffold(title: "Deneme takibi") {
            List {
                if store.items.count >= 2 {
                    Section("Net grafiği") {
                        if !lessons.isEmpty {
                            Picker("Ders", selection: Binding(get: { shownLesson }, set: { lesson = $0 })) {
                                Text("Toplam").tag(String?.none)
                                ForEach(lessons, id: \.self) { Text($0).tag(String?.some($0)) }
                            }
                        }
                        Chart(Array(points.enumerated()), id: \.offset) { point in
                            LineMark(x: .value("Tarih", point.element.date), y: .value("Net", point.element.net))
                            PointMark(x: .value("Tarih", point.element.date), y: .value("Net", point.element.net))
                        }
                        .frame(height: 160)
                        let nets = points.map { $0.net }
                        if !nets.isEmpty {
                            LabeledContent("Ortalama", value: (nets.reduce(0, +) / Double(nets.count)).shortText)
                            LabeledContent("En iyi", value: (nets.max() ?? 0).shortText)
                        }
                    }
                }
                Section {
                    if store.items.isEmpty {
                        Text("Henüz deneme yok. Sağ üstteki + ile ilk denemeni ekle.").foregroundStyle(.secondary)
                    }
                    ForEach(sorted) { exam in
                        Button { editing = exam } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(exam.title.isEmpty ? "Deneme" : exam.title).font(.headline)
                                Text(exam.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                                Text("Net: \(exam.net.shortText)").font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                            }
                        }
                        .tint(.primary)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { sorted[$0].id }
                        store.items.removeAll { ids.contains($0.id) }
                    }
                }
            }
            // Yeni deneme, son denemenin dersleri ve ceza kuralıyla açılır.
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("Ekle", systemImage: "plus") { editing = .next(after: sorted.first) } } }
            .sheet(item: $editing) { exam in
                MockExamEditor(exam: exam) { saved in
                    if let i = store.items.firstIndex(where: { $0.id == saved.id }) { store.items[i] = saved } else { store.items.append(saved) }
                }
            }
        }
    }
}

private struct MockExamEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var exam: MockExam
    @State private var confirmDiscard = false
    /// Açılıştaki hâl: girilen bir şey var mı buna göre anlaşılır (aşağı çekme ve "Vazgeç" girilenleri sormadan silmesin).
    private let original: MockExam
    private let onSave: (MockExam) -> Void

    init(exam: MockExam, onSave: @escaping (MockExam) -> Void) {
        _exam = State(initialValue: exam)
        original = exam
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Deneme adı", text: $exam.title)
                    DatePicker("Tarih", selection: $exam.date, displayedComponents: .date)
                    Picker("Yanlışlar", selection: $exam.penalty) {
                        Text("Götürmez").tag(0)
                        Text("4 yanlış 1 doğruyu götürür").tag(4)
                        Text("3 yanlış 1 doğruyu götürür").tag(3)
                    }
                }
                ForEach($exam.rows) { $row in
                    Section {
                        TextField("Ders / test adı", text: $row.name)
                        HStack(spacing: 8) {
                            NumberField(label: "Doğru", value: $row.correct)
                            NumberField(label: "Yanlış", value: $row.wrong)
                            NumberField(label: "Boş", value: $row.blank)
                        }
                        LabeledContent("Net", value: ExamMath.net(correct: row.correct, wrong: row.wrong, penalty: exam.penalty).shortText)
                        if exam.rows.count > 1 {
                            Button("Dersi sil", systemImage: "trash", role: .destructive) {
                                let id = row.id
                                dropFocus()
                                Task { exam.rows.removeAll { $0.id == id } }
                            }
                        }
                    }
                }
                Section {
                    Button("Ders ekle", systemImage: "plus") { exam.rows.append(MockExam.Row()) }
                    LabeledContent("Toplam net", value: exam.net.shortText).font(.headline)
                }
            }
            .navigationTitle("Deneme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { if exam != original { confirmDiscard = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button("Kaydet") { onSave(exam); dismiss() } }
            }
            .interactiveDismissDisabled(exam != original)
            .confirmationDialog("Girilenler silinsin mi?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Değişiklikleri sil", role: .destructive) { dismiss() }
                Button("Düzenlemeye dön", role: .cancel) {}
            }
            .debugNarrowScreen()
        }
    }
}

// MARK: - Not ortalaması

struct GradesView: View {
    @State private var store = JSONStore<GradeCourse>("grades")
    @State private var newName = ""
    @State private var asking = false

    var body: some View {
        @Bindable var store = store
        ToolScaffold(title: "Not ortalaması") {
            List {
                let averages = store.items.compactMap { GradeMath.average($0.pairs) }
                if !averages.isEmpty {
                    Section { LabeledContent("Genel ortalama", value: (averages.reduce(0, +) / Double(averages.count)).shortText).font(.headline) }
                }
                Section {
                    if store.items.isEmpty { Text("Ders ekle, notlarını ve yüzdelerini gir; finalden kaç alman gerektiğini gör.").foregroundStyle(.secondary) }
                    ForEach($store.items) { $course in
                        NavigationLink {
                            GradeCourseDetail(course: $course)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(course.name)
                                Text(GradeMath.average(course.pairs).map { "Ortalama \($0.shortText)" } ?? "Not girilmedi")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { store.items.remove(atOffsets: $0) }
                }
            }
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("Ders ekle", systemImage: "plus") { newName = ""; asking = true } } }
            .alert("Yeni ders", isPresented: $asking) {
                TextField("Ders adı", text: $newName)
                Button("Ekle") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { store.items.append(GradeCourse(name: name)) }
                }
                Button("Vazgeç", role: .cancel) {}
            }
        }
    }
}

private struct GradeCourseDetail: View {
    @Binding var course: GradeCourse

    var body: some View {
        Form {
            Section("Notlar") {
                ForEach($course.entries) { $entry in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Sınav adı (vize, final…)", text: $entry.title)
                        HStack(spacing: 8) {
                            DecimalField(label: "Not", value: $entry.score)
                            DecimalField(label: "Yüzde %", value: $entry.weight)
                        }
                    }
                }
                .onDelete { offsets in
                    // Odaktaki sayı alanı silinen satıra geri yazmasın: önce klavyeyi kapat, sonra sil.
                    let ids = offsets.map { course.entries[$0].id }
                    dropFocus()
                    Task { course.entries.removeAll { ids.contains($0.id) } }
                }
                Button("Not ekle", systemImage: "plus") { course.entries.append(GradeCourse.Entry()) }
            }
            Section("Hedef") {
                Stepper("Hedef ortalama: \(Int(course.target))", value: $course.target, in: 0...100, step: 5)
            }
            Section("Sonuç") {
                let total = course.entries.reduce(0) { $0 + $1.weight }
                LabeledContent("Girilen yüzde", value: "%\(total.shortText)")
                if let average = GradeMath.average(course.pairs) { LabeledContent("Şu anki ortalama", value: average.shortText) }
                if total > 100.0001 {
                    Text("Yüzdelerin toplamı 100'ü geçiyor.").foregroundStyle(.red)
                } else if let needed = GradeMath.needed(course.pairs, target: course.target) {
                    if needed > 100 {
                        Text("Kalan sınavlardan 100 alsan da hedefe ulaşılamıyor (gereken \(needed.shortText)).").foregroundStyle(.red)
                    } else if needed <= 0 {
                        Text("Hedef şimdiden garanti. 🎉").foregroundStyle(.green)
                    } else {
                        Text("Kalan %\((100 - total).shortText)'lik kısımdan ortalama **\(needed.shortText)** alman gerekiyor.")
                    }
                }
            }
        }
        .navigationTitle(course.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Klavyeyi kapatır (odaktaki alan değerini işler).
private func dropFocus() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

private struct DecimalField: View {
    var label: String
    @Binding var value: Double

    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            // NumberField gibi: 0 boş gösterilir, yazılan rakam eski "0"ın yanına eklenmez.
            TextField(label, value: Binding<Double?>(get: { value == 0 ? nil : value }, set: { value = max(0, $0 ?? 0) }), format: .number, prompt: Text("0"))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - Devamsızlık

struct AbsencesView: View {
    @Query(sort: \Course.createdAt) private var courses: [Course]
    @State private var store = JSONStore<AbsenceCourse>("absences")
    @State private var newName = ""
    @State private var asking = false

    var body: some View {
        @Bindable var store = store
        ToolScaffold(title: "Devamsızlık") {
            List {
                if store.items.isEmpty { Text("Derslerini ekle; her devamsızlıkta + ile işaretle. Sınıra yaklaşınca uyarırım.").foregroundStyle(.secondary) }
                ForEach($store.items) { $course in AbsenceRow(course: $course) }
                    .onDelete { store.items.remove(atOffsets: $0) }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Ekle", systemImage: "plus") {
                        Button("Yeni ders adı yaz") { newName = ""; asking = true }
                        ForEach(courses.filter { c in !store.items.contains { $0.name == c.name } }) { course in
                            Button(course.name) { store.items.append(AbsenceCourse(name: course.name)) }
                        }
                    }
                }
            }
            .alert("Ders", isPresented: $asking) {
                TextField("Ders adı", text: $newName)
                Button("Ekle") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { store.items.append(AbsenceCourse(name: name)) }
                }
                Button("Vazgeç", role: .cancel) {}
            }
        }
    }
}

/// Bir dersin devamsızlık satırı: özet, sayaç ve tarih listesi (geçmiş güne ekleme, belirli günü silme).
private struct AbsenceRow: View {
    @Binding var course: AbsenceCourse
    @State private var pickedDate = Date.now
    @State private var showingDates = false

    var body: some View {
        let count = course.days.count
        let level = AbsenceMath.level(count: count, limit: course.limit)
        let summary = AbsenceMath.summary(count: count, limit: course.limit)
        let color: Color = level == .ok ? .green : level == .warning ? .orange : .red
        let groups = AbsenceMath.grouped(course.days)
        VStack(alignment: .leading, spacing: 6) {
            Text(course.name).font(.headline)
            ProgressView(value: min(1, Double(count) / Double(max(1, course.limit))))
                .tint(color)
                .accessibilityLabel("\(course.name) devamsızlık").accessibilityValue(summary)
            Label(summary, systemImage: level == .ok ? "checkmark.circle" : "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(level == .ok ? Color.secondary : color)
            Stepper("Devamsızlık") {
                course.days.append(DayKey.key())
            } onDecrement: {
                // En yeni günün bir kaydı silinir (geçmiş güne eklenen kayıt dizinin sonunda olabilir).
                if let newest = groups.first { course.days = AbsenceMath.removingOne(newest.day, from: course.days) }
            }
            Stepper("Sınır: \(course.limit)", value: $course.limit, in: 1...200)
            DisclosureGroup("Tarihler", isExpanded: $showingDates) {
                VStack(alignment: .leading, spacing: 8) {
                    if groups.isEmpty { Text("Henüz devamsızlık yok.").foregroundStyle(.secondary) }
                    ForEach(groups) { group in
                        let label = DayKey.shortLabel(group.day)
                        HStack(spacing: 8) {
                            Text(group.count > 1 ? "\(label) ×\(group.count)" : label).frame(maxWidth: .infinity, alignment: .leading)
                            Button { course.days = AbsenceMath.removingOne(group.day, from: course.days) } label: { Text("Sil").frame(minHeight: 30) }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("\(label) devamsızlığını sil")
                        }
                    }
                    DatePicker("Başka gün", selection: $pickedDate, in: ...Date.now, displayedComponents: .date)
                    Button { course.days.append(DayKey.key(pickedDate)) } label: { Label("Bu günü ekle", systemImage: "plus").frame(minHeight: 30) }
                        .buttonStyle(.bordered)
                }
                .font(.subheadline)
                .padding(.top, 6)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Sınav geri sayımı

struct CountdownsView: View {
    @Query(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @Query private var courses: [Course]
    @State private var store = JSONStore<Countdown>("countdowns")
    @State private var title = ""
    @State private var date = Date.now.addingTimeInterval(30 * 86_400)

    private struct Row: Identifiable { var id: UUID; var title: String; var subtitle: String; var date: Date; var custom: Bool }

    private var rows: [Row] {
        let today = Calendar.current.startOfDay(for: .now)
        let exams = assignments.filter { $0.kind == .exam && !$0.isDone && $0.dueDate >= today }.map { a in
            Row(id: a.id, title: a.title, subtitle: courses.first { $0.id == a.courseID }?.name ?? "Derslerim", date: a.dueDate, custom: false)
        }
        let own = store.items.filter { $0.date >= today }.map { Row(id: $0.id, title: $0.title, subtitle: "Kendi sayacım", date: $0.date, custom: true) }
        return (exams + own).sorted { $0.date < $1.date }
    }

    var body: some View {
        ToolScaffold(title: "Geri sayım") {
            List {
                Section {
                    if rows.isEmpty { Text("Yaklaşan sınav yok. Derslerim'e sınav ekle ya da aşağıdan kendi sayacını oluştur.").foregroundStyle(.secondary) }
                    ForEach(rows) { row in
                        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: row.date)).day ?? 0
                        HStack(spacing: 12) {
                            VStack(spacing: 0) {
                                Text("\(days)").font(.system(.title, design: .rounded).bold().monospacedDigit())
                                Text("gün").font(.caption2)
                            }
                            .frame(minWidth: 54).padding(.vertical, 6)
                            .foregroundStyle(.white)
                            .background(days <= 3 ? Color.red : days <= 14 ? .orange : Theme.blueInk, in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title).font(.headline)
                                Text(row.subtitle).font(.caption).foregroundStyle(.secondary)
                                Text(row.date.formatted(date: .long, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions { if row.custom { Button("Sil", role: .destructive) { store.items.removeAll { $0.id == row.id } } } }
                    }
                }
                let past = store.items.filter { $0.date < Calendar.current.startOfDay(for: .now) }
                if !past.isEmpty {
                    Section("Geçmiş") {
                        ForEach(past) { item in
                            Text("\(item.title) · \(item.date.formatted(date: .abbreviated, time: .omitted))").foregroundStyle(.secondary)
                                .swipeActions { Button("Sil", role: .destructive) { store.items.removeAll { $0.id == item.id } } }
                        }
                    }
                }
                Section("Yeni sayaç") {
                    TextField("Ne için? (YKS, final haftası…)", text: $title)
                    DatePicker("Tarih", selection: $date, in: Date.now..., displayedComponents: .date)
                    Button("Ekle") {
                        store.items.append(Countdown(title: title.trimmingCharacters(in: .whitespaces), date: date))
                        title = ""
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Soru takibi

struct QuestionLogView: View {
    @Query(sort: \Course.createdAt) private var courses: [Course]
    @State private var store = JSONStore<QuestionLog>("questions")
    /// Son yazılan ders hatırlanır: art arda aynı derse kayıt girilirken yeniden yazılmaz.
    @AppStorage("tools.questions.course") private var course = ""
    @State private var solved = 0
    @State private var wrong = 0
    /// Kaydın yazılacağı gün (dün çözülüp girilmeyenler de eklenebilsin).
    @State private var date = Date.now

    var body: some View {
        let days = QuestionStats.dayTotals(store.items, days: 14)
        let totals = QuestionStats.byCourse(store.items)
        ToolScaffold(title: "Soru takibi") {
            List {
                Section("Çözdüklerim") {
                    TextField("Ders (isteğe bağlı)", text: $course)
                    if !courses.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack { ForEach(courses) { c in Button(c.name) { course = c.name }.buttonStyle(.bordered).controlSize(.small) } }
                        }
                    }
                    DatePicker("Gün", selection: $date, in: ...Date.now, displayedComponents: .date)
                    HStack(spacing: 8) {
                        NumberField(label: "Çözülen", value: $solved)
                        NumberField(label: "Yanlış", value: $wrong)
                    }
                    // Bugün dışında bir gün seçiliyse düğme gününü söyler (yanlış güne sessizce yazılmasın).
                    Button(Calendar.current.isDateInToday(date) ? "Kaydet" : "Kaydet · \(DayKey.shortLabel(DayKey.key(date)))") {
                        store.items.append(QuestionLog(day: DayKey.key(date), course: course.trimmingCharacters(in: .whitespaces), solved: solved, wrong: min(wrong, solved)))
                        solved = 0; wrong = 0
                    }
                    .disabled(solved <= 0)
                }
                Section("Son 14 gün") {
                    Chart(days) { BarMark(x: .value("Gün", $0.date, unit: .day), y: .value("Soru", $0.solved)) }
                        .frame(height: 140)
                    let all = store.items.reduce(0) { $0 + $1.solved }, wrongAll = store.items.reduce(0) { $0 + $1.wrong }
                    LabeledContent("Bugün", value: "\(days.last?.solved ?? 0) soru")
                    LabeledContent("14 gün", value: "\(days.reduce(0) { $0 + $1.solved }) soru")
                    LabeledContent("Toplam", value: "\(all) soru")
                    if all > 0 { LabeledContent("Doğruluk", value: "%\(Int((Double(all - wrongAll) / Double(all) * 100).rounded()))") }
                }
                // Hiç ders adı yazılmadıysa tek "Derssiz" satırı toplamı yineler; gösterilmez.
                if totals.contains(where: { $0.course != QuestionStats.noCourse }) {
                    Section("Derslere göre") {
                        ForEach(totals) { total in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(total.course)
                                Text("\(total.solved) soru · %\(total.accuracy) doğru").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Kayıtlar") {
                    ForEach(store.items.reversed()) { log in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(log.solved) soru\(log.wrong > 0 ? " · \(log.wrong) yanlış" : "")")
                            Text([log.course, DayKey.shortLabel(log.day)].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                        .swipeActions { Button("Sil", role: .destructive) { store.items.removeAll { $0.id == log.id } } }
                    }
                }
            }
        }
    }
}

// MARK: - Soru kronometresi

struct QuestionTimerView: View {
    @State private var startedAt: Date?
    @State private var laps: [Double] = []
    @State private var lastLapAt: Date?
    @State private var target = 90
    @State private var saved = false
    @State private var wrongCount = 0
    /// "Bitir"e basılan an: süren soru sayılacaksa süresi onay penceresinde beklenen zamanı içermesin.
    @State private var finishAskedAt: Date?

    var body: some View {
        let stats = LapStats(laps: laps, target: Double(target))
        ToolScaffold(title: "Soru kronometresi") {
            ScrollView {
                VStack(spacing: 18) {
                    TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                        let current = lastLapAt.map { timeline.date.timeIntervalSince($0) } ?? 0
                        VStack(spacing: 4) {
                            Text("Bu soru").font(.subheadline).foregroundStyle(.secondary)
                            Text(max(0, current).clockText)
                                .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(startedAt != nil && current > Double(target) ? .red : .primary)
                            if let startedAt { Text("Toplam \(timeline.date.timeIntervalSince(startedAt).clockText)").font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                    Stepper("Soru başı hedef: \(target) sn", value: $target, in: 15...600, step: 15)
                    if startedAt == nil {
                        Button("Başla") {
                            startedAt = .now; lastLapAt = .now; laps = []; saved = false; wrongCount = 0
                            // Kâğıtta soru çözülürken ekran kilitlenmesin.
                            UIApplication.shared.isIdleTimerDisabled = true
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    } else {
                        Button("Soru bitti → sıradaki") {
                            let now = Date.now
                            if let lastLapAt { laps.append(now.timeIntervalSince(lastLapAt)) }
                            lastLapAt = now
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .sensoryFeedback(.impact, trigger: laps.count)
                        if !laps.isEmpty {
                            Button("Son soruyu geri al", systemImage: "arrow.uturn.backward") {
                                if let previous = LapStats.undoLast(laps: &laps, lastLapAt: lastLapAt) { lastLapAt = previous }
                            }
                            .buttonStyle(.bordered)
                        }
                        Button("Bitir", role: .destructive) { finishAskedAt = .now }.buttonStyle(.bordered)
                    }
                    if stats.count > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(stats.count) soru · ortalama \(Int(stats.average.rounded())) sn").font(.headline)
                            Text("En hızlı \(Int(stats.fastest.rounded())) sn · en yavaş \(Int(stats.slowest.rounded())) sn · hedefi aşan \(stats.overTarget)")
                                .font(.footnote).foregroundStyle(.secondary)
                            if startedAt == nil {
                                if !saved { NumberField(label: "Yanlış", value: $wrongCount).frame(maxWidth: 140) }
                                Button(saved ? "Soru takibine eklendi" : "Soru takibine ekle") {
                                    dropFocus()
                                    JSONStore<QuestionLog>("questions").items.append(QuestionLog(course: "", solved: laps.count, wrong: min(wrongCount, laps.count)))
                                    saved = true
                                }
                                .buttonStyle(.bordered).disabled(saved)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            // Oturum sürerken sayfayı aşağı çekmek turları silmesin ("Kapat" yine çalışır).
            .interactiveDismissDisabled(startedAt != nil)
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            .confirmationDialog("Oturum bitsin mi?", isPresented: Binding(get: { finishAskedAt != nil }, set: { if !$0 { finishAskedAt = nil } }), titleVisibility: .visible) {
                Button("Süren soruyu da say ve bitir") { finish(countCurrent: true) }
                Button("Saymadan bitir") { finish(countCurrent: false) }
                Button("Devam et", role: .cancel) {}
            }
        }
    }

    private func finish(countCurrent: Bool) {
        if countCurrent, let lastLapAt { laps.append(max(0, (finishAskedAt ?? .now).timeIntervalSince(lastLapAt))) }
        startedAt = nil; lastLapAt = nil; finishAskedAt = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
