import SwiftData
import SwiftUI
import UserNotifications

/// Plan: gün özeti, ders programı, görevler ve derslerin tek çalışma alanı.
struct CoursesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Course.createdAt) private var stored: [Course]
    private var courses: [Course] { DebugArg.value("coursesEmpty") != nil ? [] : stored }
    @Query private var lessons: [Lesson]
    @Query(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @Query private var videoLessons: [VideoLesson]
    @Query private var channels: [FollowedChannel]
    @AppStorage(StudyPlan.key) private var studyPlanData = Data()
    @State private var now = Date.now
    // Existing debug values stay compatible: 0 = program, 1 = tasks, 2 = courses; 3 = overview.
    @State private var section = DebugArg.value("coursesSection").flatMap { Int($0) }.map { min(3, max(0, $0)) } ?? 3
    @State private var mebOpen = DebugArg.value("mebOpen") != nil
    @State private var showNewCourse = false
    @State private var showNewLesson = false
    @State private var showNewAssignment = false
    @State private var showPlan = false
    @State private var showFocus = false
    @State private var showDone = false
    @State private var editingCourse: Course?
    @State private var editingLesson: Lesson?
    @State private var editingAssignment: Assignment?
    @State private var courseToDelete: Course?

    private var plan: StudyPlan? { try? JSONDecoder().decode(StudyPlan.self, from: studyPlanData) }
    private var openAssignments: [Assignment] { assignments.filter { !$0.isDone } }
    private var todayLessons: [Lesson] {
        lessons.filter { $0.weekday == Calendar.current.component(.weekday, from: now) }.sorted { $0.startMinute < $1.startMinute }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Plan bölümü", selection: $section) {
                    Text("Özet").tag(3)
                    Text("Program").tag(0)
                    Text("Görevler").tag(1)
                    Text("Dersler").tag(2)
                }
                .modifier(AccessiblePickerStyle())
                .padding(.horizontal, 20).padding(.vertical, 10)
                switch section {
                case 0: schedule
                case 1: assignmentList
                case 2: courseList
                default: overview
                }
            }
            .background(Theme.canvas)
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $mebOpen) { MEBLibraryView() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { HomeButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Ders ekle", systemImage: "book.badge.plus") { showNewCourse = true }
                        Button("Programa saat ekle", systemImage: "calendar.badge.plus") { showNewLesson = true }.disabled(courses.isEmpty)
                        Button("Ödev veya sınav ekle", systemImage: "checklist") { showNewAssignment = true }.disabled(courses.isEmpty)
                    } label: { Image(systemName: "plus").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Plana ekle")
                }
                ToolbarItem(placement: .topBarTrailing) { ModuleMenu(module: .courses) { EmptyView() } }
            }
            .sheet(isPresented: $showNewCourse) { CourseEditor() }
            .sheet(isPresented: $showNewLesson) { LessonEditor(courses: courses) }
            .sheet(isPresented: $showNewAssignment) { AssignmentEditor(courses: courses) }
            .sheet(isPresented: $showPlan) { StudyPlanView() }
            .sheet(isPresented: $showFocus) { FocusTimerView() }
            .sheet(item: $editingCourse) { CourseEditor(course: $0) }
            .sheet(item: $editingLesson) { LessonEditor(courses: courses, lesson: $0) }
            .sheet(item: $editingAssignment) { AssignmentEditor(courses: courses, assignment: $0) }
            .onChange(of: scenePhase) { _, phase in if phase == .active { now = .now } }
            .confirmationDialog("“\(courseToDelete?.name ?? "Ders")” silinsin mi?",
                                isPresented: Binding(get: { courseToDelete != nil }, set: { if !$0 { courseToDelete = nil } }),
                                titleVisibility: .visible) {
                if let course = courseToDelete { Button("Dersi sil", role: .destructive) { delete(course) } }
                Button("Vazgeç", role: .cancel) {}
            } message: { Text(courseToDelete.map(deletionSummary) ?? "") }
        }
    }

    private var overview: some View {
        let columns = typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return List {
            ScreenHero(eyebrow: now.formatted(.dateTime.day().month(.wide).weekday(.wide)),
                       title: "Bugünün planı",
                       subtitle: "\(todayLessons.count) ders saati · \(openAssignments.count) açık görev",
                       symbol: "calendar") {
                if plan != nil {
                    Label(planDetail, systemImage: "target").font(.headline).foregroundStyle(Theme.yellow)
                }
            }
            .overviewRow()
            LazyVGrid(columns: columns, spacing: 12) {
                BigActionButton(title: "Odak oturumu", symbol: "timer", style: .yellow) { showFocus = true }
                BigActionButton(title: plan?.examName ?? "Sınav hedefi ekle", symbol: "target", style: .blue) { showPlan = true }
            }
            .overviewRow()
            SectionTitle(title: "Bugünkü dersler").overviewRow()
            if todayLessons.isEmpty {
                Text("Bugün programda ders yok.").font(.subheadline.weight(.medium)).foregroundStyle(.primary.opacity(0.72))
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).okuSurface().overviewRow()
            } else {
                ForEach(todayLessons) { lessonRow($0).padding(.horizontal, 14).padding(.vertical, 6).okuSurface().overviewRow() }
            }
            SectionTitle(title: "Yaklaşan görevler").overviewRow()
            if openAssignments.isEmpty {
                Label("Bekleyen görev yok", systemImage: "checkmark.circle").font(.subheadline.weight(.medium)).foregroundStyle(.primary.opacity(0.72))
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).okuSurface().overviewRow()
            } else {
                ForEach(Array(openAssignments.prefix(3))) { assignmentRow($0).overviewRow() }
            }
            if courses.isEmpty {
                Button { showNewCourse = true } label: {
                    BigRow(title: "İlk dersini ekle", detail: "Programını ve görevlerini derslere bağla", symbol: "plus.circle", tone: .yellow)
                }.buttonStyle(PressableCardStyle(reduceMotion: false)).overviewRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var planDetail: String {
        guard let plan else { return "Sınav tarihine göre günlük çalışma planı" }
        if plan.examDate < Calendar.current.startOfDay(for: now) { return "Sınav tarihi geçti · Hedefini güncelle" }
        return (plan.daysLeft == 0 ? "Sınav bugün" : "\(plan.daysLeft) gün kaldı") + " · Günde \(plan.dailyMinutes) dk"
    }

    private var firstCourseSection: some View {
        Section {
            Button { showNewCourse = true } label: {
                OkuRouteLabel(title: "İlk dersini ekle", detail: "Programını ve görevlerini derslere bağla", symbol: "plus.circle")
            }.buttonStyle(.plain).listRowInsets(EdgeInsets())
        }
    }

    // MARK: Program

    private static let weekdays = [2, 3, 4, 5, 6, 7, 1]
    private static func weekdayName(_ w: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        return symbols[(w - 1) % 7].capitalized
    }

    private var schedule: some View {
        List {
            if courses.isEmpty { firstCourseSection }
            ForEach(Self.weekdays, id: \.self) { day in
                let items = lessons.filter { $0.weekday == day }.sorted { $0.startMinute < $1.startMinute }
                if !items.isEmpty {
                    Section(Self.weekdayName(day)) { ForEach(items) { lessonRow($0) } }
                }
            }
            if !courses.isEmpty {
                Section {
                    Button("Programa ders saati ekle", systemImage: "calendar.badge.plus") { showNewLesson = true }.frame(minHeight: 44)
                } footer: {
                    if lessons.isEmpty { Text("Ders saatlerin haftanın günlerine göre burada sıralanır.") }
                }
            }
        }.scrollContentBackground(.hidden)
    }

    private func lessonRow(_ lesson: Lesson) -> some View {
        Button { editingLesson = lesson } label: {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .top, spacing: 14))) {
                Text(String(format: "%02d:%02d", lesson.startMinute / 60, lesson.startMinute % 60))
                    .font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name(of: lesson.courseID)).font(.headline).foregroundStyle(Color.primary)
                    Text(lesson.room.isEmpty ? "\(lesson.durationMinutes) dk" : "\(lesson.durationMinutes) dk · \(lesson.room)")
                        .font(.subheadline).foregroundStyle(Color.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.vertical, 4).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Ders saatini düzenler")
        .swipeActions { Button("Sil", role: .destructive) { context.delete(lesson); try? context.save() } }
        .contextMenu {
            Button("Saati düzenle", systemImage: "pencil") { editingLesson = lesson }
            Button("Program saatini sil", systemImage: "trash", role: .destructive) { context.delete(lesson); try? context.save() }
        }
    }

    // MARK: Ödevler

    private var assignmentList: some View {
        List {
            if courses.isEmpty { firstCourseSection }
            Section("Bekleyenler · \(openAssignments.count)") {
                if openAssignments.isEmpty {
                    Label("Bekleyen ödev veya sınav yok", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                }
                ForEach(openAssignments) { assignmentRow($0) }
                if !courses.isEmpty { Button("Ödev veya sınav ekle", systemImage: "plus") { showNewAssignment = true }.frame(minHeight: 44) }
            }
            let done = assignments.filter(\.isDone)
            if !done.isEmpty {
                Section {
                    DisclosureGroup("Tamamlananlar (\(done.count))", isExpanded: $showDone) {
                        ForEach(done) { assignmentRow($0) }
                    }
                }
            }
        }.scrollContentBackground(.hidden)
    }

    private func assignmentRow(_ a: Assignment) -> some View {
        AssignmentRow(assignment: a, courseName: a.courseID == nil ? nil : name(of: a.courseID), color: color(of: a.courseID)) { editingAssignment = a }
    }

    // MARK: Dersler

    private var courseList: some View {
        List {
            if courses.isEmpty { firstCourseSection }
            if !courses.isEmpty {
                Section("Derslerin · \(courses.count)") {
                    ForEach(courses) { course in
                        HStack(alignment: .center, spacing: 8) {
                            NavigationLink { CourseVideosView(course: course) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(course.name).font(.headline).foregroundStyle(Color.primary)
                                    Text(courseDetail(course)).font(.subheadline).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.vertical, 4)
                            }
                            Menu {
                                Button("Dersi düzenle", systemImage: "pencil") { editingCourse = course }
                                Button("Dersi sil", systemImage: "trash", role: .destructive) { courseToDelete = course }
                            } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }
                            .accessibilityLabel(course.name + ", seçenekler")
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Sil", systemImage: "trash", role: .destructive) { courseToDelete = course }
                        }
                        .swipeActions(edge: .leading) {
                            Button("Düzenle", systemImage: "pencil") { editingCourse = course }.tint(.blue)
                        }
                    }
                    Button("Ders ekle", systemImage: "plus") { showNewCourse = true }.frame(minHeight: 44)
                }
            }
            Section("Ders kaynakları") {
                Button { mebOpen = true } label: {
                    OkuRouteLabel(title: "MEB ders kaynakları", detail: "Kitaplar, temalar ve öğretim programları", symbol: "books.vertical")
                }.buttonStyle(.plain).listRowInsets(EdgeInsets())
            }
        }.scrollContentBackground(.hidden)
    }

    private func courseDetail(_ course: Course) -> String {
        let taskCount = openAssignments.filter { $0.courseID == course.id }.count
        let videoCount = videoLessons.filter { $0.courseID == course.id }.count
        let lessonCount = lessons.filter { $0.courseID == course.id }.count
        return "\(lessonCount) ders saati · \(taskCount) görev · \(videoCount) video"
    }

    private func deletionSummary(_ course: Course) -> String {
        CourseDeletion.summary(lessons: lessons.filter { $0.courseID == course.id }.count,
                               assignments: assignments.filter { $0.courseID == course.id }.count,
                               videos: videoLessons.filter { $0.courseID == course.id }.count,
                               channels: channels.filter { $0.courseID == course.id }.count)
    }

    private func delete(_ course: Course) {
        lessons.filter { $0.courseID == course.id }.forEach { context.delete($0) }
        assignments.filter { $0.courseID == course.id }.forEach { $0.courseID = nil }
        videoLessons.filter { $0.courseID == course.id }.forEach { $0.courseID = nil }
        channels.filter { $0.courseID == course.id }.forEach { $0.courseID = nil }
        context.delete(course)
        try? context.save()
    }

    private func name(of id: UUID?) -> String { courses.first { $0.id == id }?.name ?? "Ders" }
    private func color(of id: UUID?) -> Color { Course.color(courses.first { $0.id == id }?.colorHex ?? "#999999") }
}

private extension View {
    /// Plan özetindeki liste satırı: kart görünümünü kendi çizer, liste zemini ve ayırıcı görünmez.
    func overviewRow() -> some View {
        listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// Ders silme onayının metni: neyin silineceği, neyin derssiz kalacağı.
nonisolated enum CourseDeletion {
    static func summary(lessons: Int, assignments: Int, videos: Int, channels: Int = 0) -> String {
        var parts: [String] = []
        if lessons > 0 { parts.append("\(lessons) program saati silinir") }
        let orphans = [(assignments, "ödev/sınav"), (videos, "video"), (channels, "kanal")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
        if let last = orphans.last {
            let head = orphans.dropLast().joined(separator: ", ")
            parts.append((head.isEmpty ? last : "\(head) ve \(last)") + " derssiz kalır")
        }
        return parts.isEmpty ? "Bu derse bağlı program saati, ödev ya da video yok." : parts.joined(separator: "; ") + "."
    }
}

/// Son tarih metni, yönüyle: gecikme yalnız renkten anlaşılmasın ("2 gün gecikti", "Yarın 09:00", "3 gün kaldı · Cum").
/// Gün ve ay kısaltmaları takvimin yerelinden gelir.
nonisolated enum AssignmentDue {
    static func text(due: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
        switch days {
        // Dün için ayrı metin yok: "Dün bitti" ödev bitirildi diye de okunuyordu.
        case ..<0: return "\(-days) gün gecikti"
        case 0: return "Bugün \(clock(due, calendar: calendar))"
        case 1: return "Yarın \(clock(due, calendar: calendar))"
        case 2...6: return "\(days) gün kaldı · \(symbol(calendar.shortWeekdaySymbols, calendar.component(.weekday, from: due)))"
        default: return "\(dayMonth(due, calendar: calendar)) · \(days) gün kaldı"
        }
    }

    /// Tamamlanmış ödevde yalnız tarih ("14 Eki"); başka yıldaysa yılıyla.
    static func dateText(due: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let year = calendar.component(.year, from: due)
        return year == calendar.component(.year, from: now) ? dayMonth(due, calendar: calendar) : "\(dayMonth(due, calendar: calendar)) \(year)"
    }

    private static func clock(_ date: Date, calendar: Calendar) -> String {
        String(format: "%02d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
    }

    private static func dayMonth(_ date: Date, calendar: Calendar) -> String {
        "\(calendar.component(.day, from: date)) \(symbol(calendar.shortMonthSymbols, calendar.component(.month, from: date)))"
    }

    /// Takvim bileşeni 1'den başlar; dizin dışı kalırsa boş döner.
    private static func symbol(_ symbols: [String], _ component: Int) -> String {
        symbols.indices.contains(component - 1) ? symbols[component - 1] : ""
    }
}

private struct AssignmentRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Bindable var assignment: Assignment
    /// Dersi olmayan ödevde nil.
    var courseName: String?
    var color: Color
    var onEdit: () -> Void
    @State private var episodeExists = false

    private var kindName: String { assignment.kind == .exam ? "Sınav" : assignment.kind == .project ? "Proje" : "Ödev" }

    /// "<ders> · <tür> · <son tarih>" tek metin: dar ekranda parçalar ayrı sütunlara bölünmeden paragraf gibi sarılır.
    private var meta: String {
        let due = assignment.isDone ? AssignmentDue.dateText(due: assignment.dueDate) : AssignmentDue.text(due: assignment.dueDate)
        return "\(courseName ?? "Ders") · \(kindName) · \(due)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                assignment.isDone.toggle()
                try? context.save()
                if assignment.isDone {
                    Reminders.cancel(assignment.id)
                } else if Reminders.isWanted(assignment.id) {
                    // Tamamlandı işareti geri alındı: hatırlatma isteniyorsa yeniden kurulur.
                    Reminders.schedule(for: assignment, courseName: courseName)
                }
            } label: {
                Image(systemName: assignment.isDone ? "checkmark.circle.fill" : "circle").font(.title2)
                    .foregroundStyle(assignment.isDone ? .green : .secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(assignment.title)
            .accessibilityValue(assignment.isDone ? "Tamamlandı" : "Tamamlanmadı")
            .accessibilityHint("Görevin tamamlanma durumunu değiştirir")
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(assignment.title).font(.headline).strikethrough(assignment.isDone).fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
                        if assignment.isOverdue { Image(systemName: "exclamationmark.circle").accessibilityHidden(true) }
                        Text(meta)
                    }
                    .font(.caption).foregroundStyle(assignment.isOverdue ? .red : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Düzenlemek için dokun")
            // #50: bölüm silinmişse düğme gizlenir ve bağ temizlenir.
            if let id = assignment.episodeID, episodeExists {
                Button("Dinle", systemImage: "play.circle") { app.selectedTab = .library; app.pendingOpenEpisode = id }
                    .labelStyle(.iconOnly).font(.title3).buttonStyle(.borderless)
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .task(id: assignment.episodeID) {
            guard let id = assignment.episodeID else { episodeExists = false; return }
            var d = FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })
            d.fetchLimit = 1
            // Getirme hatası "bölüm yok" sayılmaz: bağ yalnız başarılı getirme 0 döndürünce temizlenir.
            let count: Int
            do { count = try context.fetchCount(d) } catch { episodeExists = true; return }
            episodeExists = count > 0
            if !episodeExists { assignment.episodeID = nil; try? context.save() }
        }
        .swipeActions {
            Button("Sil", role: .destructive) { Reminders.forget(assignment.id); context.delete(assignment); try? context.save() }
        }
        .swipeActions(edge: .leading) { Button("Düzenle", systemImage: "pencil", action: onEdit).tint(.blue) }
        .contextMenu {
            Button("Düzenle", systemImage: "pencil", action: onEdit)
            Button("Görevi sil", systemImage: "trash", role: .destructive) {
                Reminders.forget(assignment.id); context.delete(assignment); try? context.save()
            }
        }
    }
}

extension Course {
    static let palette = ["#6B4CF2", "#F2734C", "#2E9E6B", "#1E88E5", "#E53970", "#F2B705", "#00897B", "#8E24AA"]
    /// `palette` ile aynı sırada: renk dairelerinin erişilebilirlik etiketi.
    static let paletteNames = ["Mor", "Turuncu", "Yeşil", "Mavi", "Pembe", "Sarı", "Turkuaz", "Eflatun"]

    static func color(_ hex: String) -> Color {
        let n = UInt32(hex.dropFirst(), radix: 16) ?? 0x999999
        return Color(red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255)
    }

    static func colorName(_ hex: String) -> String {
        guard let index = palette.firstIndex(where: { $0.caseInsensitiveCompare(hex) == .orderedSame }), paletteNames.indices.contains(index) else { return "Renk" }
        return paletteNames[index]
    }
}

struct CourseEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    private let course: Course?
    @State private var name: String
    @State private var colorHex: String

    /// `course` verilirse o kayıt düzenlenir; verilmezse yeni ders eklenir.
    init(course: Course? = nil) {
        self.course = course
        _name = State(initialValue: course?.name ?? "")
        _colorHex = State(initialValue: course?.colorHex ?? Course.palette[0])
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Ders adı (örn. Biyoloji)", text: $name)
                Section("Renk") {
                    // Sekiz daire tek satıra sığmaz (320 nokta): uyarlanır ızgara alt satıra geçer.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                        ForEach(Course.palette, id: \.self) { hex in
                            let selected = hex == colorHex
                            Button { colorHex = hex } label: {
                                Circle().fill(Course.color(hex)).frame(width: 32, height: 32)
                                    .overlay {
                                        if selected {
                                            Image(systemName: "checkmark").font(.footnote.weight(.heavy)).foregroundStyle(.white)
                                                .shadow(color: .black.opacity(0.5), radius: 1)
                                        }
                                    }
                                    .padding(4)
                                    .overlay { if selected { Circle().stroke(Color.primary, lineWidth: 2) } }
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Course.colorName(hex))
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(Theme.canvas)
            .navigationTitle(course == nil ? "Yeni ders" : "Dersi düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(course == nil ? "Ekle" : "Kaydet") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        if let course {
                            course.name = trimmed
                            course.colorHex = colorHex
                        } else {
                            context.insert(Course(name: trimmed, colorHex: colorHex))
                        }
                        try? context.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct LessonEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var courses: [Course]
    private let lesson: Lesson?
    @State private var courseID: UUID?
    @State private var weekday: Int
    @State private var time: Date
    @State private var duration: Int
    @State private var room: String

    /// `lesson` verilirse o program saati düzenlenir; verilmezse yenisi eklenir.
    init(courses: [Course], lesson: Lesson? = nil) {
        self.courses = courses
        self.lesson = lesson
        let start = lesson?.startMinute ?? 540
        _courseID = State(initialValue: lesson?.courseID ?? courses.first?.id)
        _weekday = State(initialValue: lesson?.weekday ?? 2)
        _time = State(initialValue: Calendar.current.date(bySettingHour: start / 60, minute: start % 60, second: 0, of: .now) ?? .now)
        _duration = State(initialValue: lesson?.durationMinutes ?? 40)
        _room = State(initialValue: lesson?.room ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Ders", selection: $courseID) {
                    ForEach(courses) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Gün", selection: $weekday) {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1].capitalized).tag($0) }
                }
                DatePicker("Saat", selection: $time, displayedComponents: .hourAndMinute)
                Stepper("\(duration) dakika", value: $duration, in: 20...180, step: 10)
                TextField("Derslik (isteğe bağlı)", text: $room)
            }
            .scrollContentBackground(.hidden).background(Theme.canvas)
            .navigationTitle(lesson == nil ? "Program saati" : "Program saatini düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if courseID == nil { courseID = courses.first?.id } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lesson == nil ? "Ekle" : "Kaydet") {
                        guard let courseID else { return }
                        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                        let start = (c.hour ?? 9) * 60 + (c.minute ?? 0)
                        if let lesson {
                            lesson.courseID = courseID
                            lesson.weekday = weekday
                            lesson.startMinute = start
                            lesson.durationMinutes = duration
                            lesson.room = room
                        } else {
                            context.insert(Lesson(courseID: courseID, weekday: weekday, startMinute: start, durationMinutes: duration, room: room))
                        }
                        try? context.save()
                        dismiss()
                    }
                    .disabled(courseID == nil)
                }
            }
        }
    }
}

struct AssignmentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Episode.createdAt, order: .reverse) private var episodes: [Episode]
    var courses: [Course]
    private let assignment: Assignment?
    @State private var title: String
    @State private var kind: Assignment.Kind
    @State private var courseID: UUID?
    @State private var episodeID: UUID?
    @State private var due: Date
    @State private var remind: Bool

    /// `assignment` verilirse o kayıt düzenlenir; verilmezse yenisi eklenir.
    init(courses: [Course], assignment: Assignment? = nil) {
        self.courses = courses
        self.assignment = assignment
        _title = State(initialValue: assignment?.title ?? "")
        _kind = State(initialValue: assignment?.kind ?? .homework)
        // Var olan ödevde "dersi yok" seçimi korunur; yenide ilk ders önerilir.
        _courseID = State(initialValue: assignment == nil ? courses.first?.id : assignment?.courseID)
        _episodeID = State(initialValue: assignment?.episodeID)
        _due = State(initialValue: assignment?.dueDate ?? Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
        _remind = State(initialValue: assignment.map { Reminders.isWanted($0.id) } ?? true)
    }

    /// Son 30 bölüm; bağlı bölüm daha eskiyse listede kalsın (seçim boş görünmesin).
    private var episodeOptions: [Episode] {
        let recent = Array(episodes.prefix(30))
        guard let episodeID, !recent.contains(where: { $0.id == episodeID }),
              let linked = episodes.first(where: { $0.id == episodeID }) else { return recent }
        return recent + [linked]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Başlık", text: $title)
                    Picker("Tür", selection: $kind) {
                        Text("Ödev").tag(Assignment.Kind.homework)
                        Text("Sınav").tag(Assignment.Kind.exam)
                        Text("Proje").tag(Assignment.Kind.project)
                    }
                    Picker("Ders", selection: $courseID) {
                        Text("—").tag(UUID?.none)
                        ForEach(courses) { Text($0.name).tag(Optional($0.id)) }
                    }
                    DatePicker("Son tarih", selection: $due, displayedComponents: [.date, .hourAndMinute])
                    Picker("İlgili bölüm", selection: $episodeID) {
                        Text("—").tag(UUID?.none)
                        ForEach(episodeOptions) { Text($0.title).tag(Optional($0.id)) }
                    }
                }
                Section {
                    Toggle("Bir gün önce hatırlat", isOn: $remind)
                } footer: {
                    if remind { Text(Reminders.note(due: due)) }
                }
            }
            .scrollContentBackground(.hidden).background(Theme.canvas)
            .navigationTitle(assignment == nil ? "Ödev / sınav" : "Ödevi düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // Küme tutulmadan önce kurulmuş hatırlatma: bekleyen bildirim varsa anahtar açık başlasın (kaydedince silinmesin).
                guard let assignment, !remind, !assignment.isDone else { return }
                if await Reminders.hasPending(assignment.id) { remind = true }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(assignment == nil ? "Ekle" : "Kaydet") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let target: Assignment
        if let assignment {
            assignment.title = title
            assignment.kindRaw = kind.rawValue
            assignment.dueDate = due
            assignment.courseID = courseID
            assignment.episodeID = episodeID
            target = assignment
        } else {
            target = Assignment(title: title, kind: kind, dueDate: due, courseID: courseID, episodeID: episodeID)
            context.insert(target)
        }
        try? context.save()
        // Tarih ya da başlık değişmiş olabilir: eski bildirim kalkar, isteniyorsa yeni tarihe göre kurulur.
        Reminders.cancel(target.id)
        Reminders.setWanted(target.id, remind)
        if remind, !target.isDone { Reminders.schedule(for: target, courseName: courses.first { $0.id == courseID }?.name) }
        dismiss()
    }
}

/// Ödev/sınav için yerel bildirim: bir gün önce 18:00; o saat geçtiyse son tarihten 2 saat önce.
enum Reminders {
    /// Hatırlatma istenen ödev kimlikleri: tamamlandı işareti geri alınınca ya da tarih değişince yeniden kurmak için.
    nonisolated static let remindKey = "assignments.remind"

    nonisolated static func identifier(_ id: UUID) -> String { "assignment-\(id.uuidString)" }

    nonisolated static func isWanted(_ id: UUID, defaults: UserDefaults = .standard) -> Bool {
        (defaults.stringArray(forKey: remindKey) ?? []).contains(id.uuidString)
    }

    nonisolated static func setWanted(_ id: UUID, _ wanted: Bool, defaults: UserDefaults = .standard) {
        var ids = Set(defaults.stringArray(forKey: remindKey) ?? [])
        if wanted { ids.insert(id.uuidString) } else { ids.remove(id.uuidString) }
        defaults.set(ids.sorted(), forKey: remindKey)
    }

    static func cancel(_ id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(id)])
    }

    /// Ödev silindi: bildirim kalkar, kimlik kümeden çıkar.
    static func forget(_ id: UUID) {
        cancel(id)
        setWanted(id, false)
    }

    static func hasPending(_ id: UUID) async -> Bool {
        let wanted = identifier(id)
        return await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier).contains(wanted)
    }

    /// Hatırlatma anı: önceki gün 18:00 gelecekteyse o; geçtiyse ve son tarihe 2 saatten fazla varsa son tarihten 2 saat önce; yoksa nil.
    nonisolated static func fireDate(due: Date, now: Date = .now, calendar: Calendar = .current) -> Date? {
        if let early = dayBefore(due, calendar: calendar), early > now { return early }
        let late = due.addingTimeInterval(-lastCall)
        return late > now ? late : nil
    }

    /// Bildirim başlığı ve metni. Başlıktaki "Bugün/Yarın" bildirimin geldiği güne göredir.
    nonisolated static func content(title: String, isExam: Bool, courseName: String?, fire: Date, due: Date,
                                    calendar: Calendar = .current) -> (title: String, body: String) {
        let day = calendar.isDate(fire, inSameDayAs: due) ? "Bugün" : "Yarın"
        let advice = due.timeIntervalSince(fire) <= lastCall
            ? "Son tarihe 2 saat kaldı."
            : courseName == nil ? "Bugün kısa bir tekrar yap." : "Bugün 25 dakikalık bir tekrar yap."
        return ("\(day) \(isExam ? "sınav" : "teslim"): \(title)", courseName.map { "\($0) · \(advice)" } ?? advice)
    }

    /// Düzenleyicideki açıklama: hatırlatma ne zaman gelecek ya da neden kurulamıyor.
    nonisolated static func note(due: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        guard due > now else { return "Son tarih geçmiş; hatırlatma kurulmaz." }
        guard let fire = fireDate(due: due, now: now, calendar: calendar) else { return "Son tarihe 2 saatten az kaldı; hatırlatma kurulmaz." }
        return fire == dayBefore(due, calendar: calendar) ? "Bir gün önce 18:00'de hatırlatılır."
            : "Bir gün öncesi geçti; son tarihten 2 saat önce hatırlatılır."
    }

    private nonisolated static let lastCall: TimeInterval = 2 * 3600

    private nonisolated static func dayBefore(_ due: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: -1, to: due).flatMap { calendar.date(bySettingHour: 18, minute: 0, second: 0, of: $0) }
    }

    static func schedule(for a: Assignment, courseName: String?) {
        let due = a.dueDate
        guard let fire = fireDate(due: due) else { return }
        // Değerler şimdi alınır: görev izin beklerken kayıt silinmiş olabilir.
        let id = a.id
        let text = content(title: a.title, isExam: a.kind == .exam, courseName: courseName, fire: fire, due: due)
        Task {
            let center = UNUserNotificationCenter.current()
            _ = await NotificationGate.request(center, options: [.alert, .sound, .badge])
            let content = UNMutableNotificationContent()
            content.title = text.title
            content.body = text.body
            content.sound = .default
            content.userInfo = ["route": "study"]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            try? await center.add(UNNotificationRequest(identifier: identifier(id), content: content,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }
}

/// Bir dersin bağlı video dersleri (oynatma listesinden gelenler liste sırasıyla); dokununca ders ekranı açılır.
struct CourseVideosView: View {
    var course: Course

    @Query(sort: \VideoLesson.createdAt) private var videoLessons: [VideoLesson]
    @State private var open: LessonTarget?
    @State private var showEdit = false

    private struct LessonTarget: Identifiable { var id: UUID }

    private var mine: [VideoLesson] { videoLessons.filter { $0.courseID == course.id } }

    var body: some View {
        List {
            if mine.isEmpty {
                Text("Bu derse bağlı video yok. Bir YouTube dersini açıp Araçlar → ‘Derse bağla ve etiketler’i seç ya da oynatma listesini içe aktar.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(mine) { lesson in
                Button { open = LessonTarget(id: lesson.id) } label: { VideoLessonRow(lesson: lesson) }
                    .buttonStyle(.plain)
            }
        }
        .navigationTitle(course.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Düzenle") { showEdit = true } } }
        .sheet(isPresented: $showEdit) { CourseEditor(course: course) }
        .sheet(item: $open) { target in VideoLibraryView(openLesson: target.id) }
    }
}
