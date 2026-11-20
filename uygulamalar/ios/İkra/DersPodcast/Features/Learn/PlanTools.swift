import PDFKit
import SwiftData
import SwiftUI
import UserNotifications

// MARK: - Öneri 12: kütüphaneye soru

struct LibraryAskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(PlayerController.self) private var player
    @Query(sort: \Episode.createdAt, order: .reverse) private var episodes: [Episode]
    @Query(sort: \VideoLesson.createdAt, order: .reverse) private var videoLessons: [VideoLesson]
    @State private var question = ""
    @State private var recorder = SpeechRecorder()
    @State private var answer: LibraryAnswerV2?
    @State private var loading = false
    @State private var error: String?
    /// Video atfına dokununca ders o dakikada açılır.
    @State private var videoTarget: VideoCitationTarget?

    private struct VideoCitationTarget: Identifiable { var id: UUID }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ör. Osmotik basınç hangi derste anlatıldı?", text: $question, axis: .vertical)
                        .lineLimit(2...4)
                    HStack {
                        Button {
                            Task {
                                if recorder.isRecording { question = await recorder.stop() } else { await recorder.start() }
                            }
                        } label: {
                            Label(recorder.isRecording ? "Bitir" : "Sesli sor", systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.fill")
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        Button("Sor") { Task { await ask() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(question.trimmingCharacters(in: .whitespaces).count < 3 || loading)
                    }
                    if recorder.isRecording { Text(recorder.transcript).font(.caption).foregroundStyle(.secondary) }
                    // Mikrofon ya da konuşma tanıma izni kapalıyken ve kayıt başlatılamayınca düğme tepkisiz görünmesin.
                    if let message = recorder.error { Text(message).font(.footnote).foregroundStyle(.red) }
                } footer: {
                    Text("Tüm bölümlerinin kaynak notlarında ve YouTube derslerinin transkriptinde arar; cevap yalnızca kendi belgelerine dayanır.")
                }
                if loading { HStack { ProgressView(); Text("Kütüphanen taranıyor…") } }
                if let error { Text(error).foregroundStyle(.red) }
                if let answer {
                    Section("Cevap") {
                        Text(answer.answer)
                        // `speak` aynı metin okunurken yeniden istenince durdurur: düğme durumu göstersin.
                        let reading = SpeechOut.shared.isSpeaking && SpeechOut.shared.spokenText == answer.answer
                        Button(reading ? "Durdur" : "Sesli oku", systemImage: reading ? "stop.circle" : "speaker.wave.2") {
                            Task { await SpeechOut.shared.speak(answer.answer) }
                        }
                    }
                    if !answer.citations.isEmpty {
                        Section("Bölümlerde") {
                            ForEach(answer.citations, id: \.self) { citation in
                                if citation.isVideo {
                                    videoCitationRow(citation)
                                } else if let episodeId = citation.episodeId, let episode = episodes.first(where: { $0.id == episodeId }) {
                                    let time = Self.time(for: LibraryCitation(episodeId: episodeId, chapterIndex: citation.chapterIndex, quote: citation.quote), in: episode)
                                    Button {
                                        player.load(episode, context: context, autoplay: false)
                                        if let time { player.seek(to: time) }
                                        player.play()
                                        AppState.current?.pendingOpenEpisode = episode.id
                                        dismiss()
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(episode.title).font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(1)
                                                Spacer()
                                                if let time { Text(time.clockText).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                                            }
                                            Text("“\(citation.quote)”").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Kütüphaneye sor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { recorder.cancel(); dismiss() } } }
            .sheet(item: $videoTarget) { target in VideoLibraryView(openLesson: target.id) }
            // Okuma sahipsiz görevle başlar: sayfa kapanınca (aşağı çekme dahil) sussun, açık mikrofon kalmasın.
            .onDisappear {
                SpeechOut.shared.stop()
                recorder.cancel()
            }
        }
    }

    /// Video atfı: ders adı + dakika + alıntı; dokununca ders o dakikada açılır.
    @ViewBuilder
    private func videoCitationRow(_ citation: LibraryCitationV2) -> some View {
        if let id = citation.videoId, let lesson = videoLessons.first(where: { $0.id == id }) {
            Button {
                if let time = citation.time, time > 0 { lesson.lastPosition = time; try? context.save() }
                videoTarget = VideoCitationTarget(id: id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Label(lesson.title, systemImage: "play.rectangle").font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(2)
                        Spacer(minLength: 6)
                        if let time = citation.time { Text(VideoTime.string(time)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    }
                    if !citation.quote.isEmpty {
                        Text("“\(citation.quote)”").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
            }
        }
    }

    /// Alıntının transkriptte geçtiği an; bulunamazsa ilgili konunun başı.
    static func time(for citation: LibraryCitation, in episode: Episode) -> Double? {
        guard let timeline = episode.timeline else { return nil }
        let tr = Locale(identifier: "tr")
        let words = citation.quote.lowercased(with: tr).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 4 }
        // En çok anahtar kelimeyi içeren tur.
        let best = timeline.turns.max { a, b in
            let la = a.text.lowercased(with: tr), lb = b.text.lowercased(with: tr)
            return words.filter { la.contains($0) }.count < words.filter { lb.contains($0) }.count
        }
        if let best, words.contains(where: { best.text.lowercased(with: tr).contains($0) }) { return best.start }
        return citation.chapterIndex.flatMap { i in timeline.chapters.first { $0.id == i }?.start }
    }

    private func ask() async {
        loading = true
        error = nil
        defer { loading = false }
        var budget = 120_000
        var payload: [LibraryAskEpisode] = []
        for episode in episodes where episode.status == .ready {
            guard payload.count < 40, budget > 500, let script = episode.script else { continue }
            let notes = String(script.sourceNotes.prefix(min(4000, budget)))
            budget -= notes.count
            payload.append(LibraryAskEpisode(id: episode.id, title: episode.title, notes: notes,
                                             chapters: (episode.timeline?.chapters ?? []).map { LibraryAskChapter(index: $0.id, title: $0.title) }))
        }
        let snapshots = videoLessons.prefix(LibraryAskPayload.maxVideos).map {
            LessonSnapshot(id: $0.id, title: $0.title, channel: $0.channel, transcriptData: $0.transcriptData)
        }
        let videos = await LibraryAskPayload.build(snapshots)
        guard !payload.isEmpty || !videos.isEmpty else {
            error = "Kütüphanende henüz hazır bölüm ya da video dersi yok."
            return
        }
        do {
            answer = try await APIClient.shared.libraryAsk(LibraryAskRequestV2(question: String(question.prefix(500)), language: "tr",
                                                                               episodes: payload, videos: videos.isEmpty ? nil : videos))
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Öneri 13: günlük antrenman

struct DailyWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(PlayerController.self) private var player
    @Query(sort: \Episode.createdAt, order: .reverse) private var episodes: [Episode]
    @Query private var cards: [ReviewCard]
    @State private var step = 0
    @State private var showCards = false
    @State private var showSocratic = false

    private var listenEpisode: Episode? {
        episodes.filter { $0.status == .ready && !$0.isFinished }
            .max { ($0.lastPlayedAt ?? $0.createdAt) < ($1.lastPlayedAt ?? $1.createdAt) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Yaklaşık 20 dakikalık karma oturum. Adımları sırayla yap; kulaklıkla yürürken bile olur.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                WorkoutStep(number: 1, done: step > 0, title: "Sesli kart tekrarı",
                            detail: "\(cards.filter(\.isDue).count) kart bekliyor") {
                    showCards = true
                }
                WorkoutStep(number: 2, done: step > 1, title: "10 dakika dinle",
                            detail: listenEpisode?.title ?? "Dinlenecek bölüm yok") {
                    guard let episode = listenEpisode else { step = max(step, 2); return }
                    player.load(episode, context: context, autoplay: true)
                    player.setSleepTimer(minutes: 10)
                    step = max(step, 2)
                    AppState.current?.pendingOpenEpisode = episode.id
                    dismiss()
                }
                WorkoutStep(number: 3, done: step > 2, title: "3 Sokratik soru",
                            detail: listenEpisode.map { "\($0.title) bölümünden" } ?? "Quiz'i olan bir bölüm gerekir") {
                    showSocratic = true
                }
                .disabled(listenEpisode?.study?.quiz.isEmpty ?? true)
            }
            .navigationTitle("Günlük antrenman")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
            .sheet(isPresented: $showCards, onDismiss: { step = max(step, 1) }) { VoiceReviewView() }
            .sheet(isPresented: $showSocratic, onDismiss: { step = max(step, 3) }) {
                if let episode = listenEpisode { SocraticView(episode: episode, limit: 3) }
            }
            .onAppear { step = UserDefaults.standard.string(forKey: "workout.day") == ListeningDay.key() ? UserDefaults.standard.integer(forKey: "workout.step") : 0 }
            .onChange(of: step) { _, value in
                UserDefaults.standard.set(ListeningDay.key(), forKey: "workout.day")
                UserDefaults.standard.set(value, forKey: "workout.step")
            }
        }
    }
}

private struct WorkoutStep: View {
    var number: Int, done: Bool, title: String, detail: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(done ? AnyShapeStyle(.green) : AnyShapeStyle(Theme.gradient)).frame(width: 34, height: 34)
                    if done { Image(systemName: "checkmark").foregroundStyle(.white).bold() }
                    else { Text("\(number)").foregroundStyle(.white).bold() }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
    }
}

// MARK: - Öneri 14: sınav tarihine göre plan

nonisolated struct StudyPlan: Codable {
    var examName: String
    var examDate: Date
    var dailyMinutes: Int

    static let key = "studyPlan"
    static var current: StudyPlan? {
        get { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(StudyPlan.self, from: $0) } }
        set { UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: key) }
    }

    var daysLeft: Int {
        max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now),
                                               to: Calendar.current.startOfDay(for: examDate)).day ?? 0)
    }
}

extension StudyPlan {
    /// Koç'un günlük hedefi (`CoachHome`/`GoalEditor` ile aynı anahtar).
    nonisolated static let dailyGoalKey = "coach.dailyGoalMinutes"

    /// İki düzenleyicinin (Hedef, Çalışma planı) ortak kaydı: planı yazar ya da siler; plan varsa günlük hedef de aynı dakikaya çekilir.
    nonisolated static func store(_ plan: StudyPlan?, defaults: UserDefaults = .standard) {
        guard let plan else { defaults.removeObject(forKey: key); return }
        guard let data = try? JSONEncoder().encode(plan) else { return }
        defaults.set(data, forKey: key)
        defaults.set(plan.dailyMinutes, forKey: dailyGoalKey)
    }

    /// Düzenleyicinin başlangıç tarihi: kayıt yoksa 30 gün sonrası; geçmiş tarih bugüne çekilir
    /// (alt sınırlı seçici bugünü gösterirken bağlı değer geçmişte kalmasın).
    nonisolated static func editableDate(_ stored: Date?, now: Date = .now, calendar: Calendar = .current) -> Date {
        guard let stored else { return calendar.date(byAdding: .day, value: 30, to: now) ?? now }
        return stored < calendar.startOfDay(for: now) ? now : stored
    }
}

/// Plan hesabı: kalan dinlenmemiş süre + kartlar günlere dağıtılır; son 3 gün sınav simülasyonu ve tekrar.
enum StudyPlanner {
    struct Day: Identifiable { var id: Date { date }; var date: Date; var items: [String] }

    /// Plana sığma özeti: çalışma günlerine yerleşen dakika, sınava yetişmeyen bölümler ve hepsini sığdıran en küçük günlük süre.
    nonisolated struct Fit: Equatable, Sendable {
        var plannedMinutes: Int
        var leftoverCount: Int
        var leftoverMinutes: Int
        var suggestedDailyMinutes: Int?
    }

    /// Dinlenecek bölümler (hazır ve bitmemiş), oluşturulma sırasıyla; dakika en az 1.
    static func queue(_ episodes: [Episode]) -> [(title: String, minutes: Int)] {
        episodes.filter { $0.status == .ready && !$0.isFinished }
            .sorted { $0.createdAt < $1.createdAt }
            .map { (title: $0.title, minutes: max(1, Int(($0.duration - $0.lastPosition) / 60))) }
    }

    /// Dinleme günleri: son günler (en çok 3, kalan sürenin dörtte biri) prova ve zayıf konulara kalır.
    nonisolated static func studyDays(daysLeft: Int) -> Int {
        let left = max(1, daysLeft)
        return max(1, left - min(3, left / 4))
    }

    /// Bir günün payı (dağıtımın çekirdeği; `days` ve `fit` paylaşır): günlük bütçe sıfırdan büyükken sıradaki bölüm alınır,
    /// son alınan bütçeyi aşabilir. Dönen: `start`tan itibaren o güne yerleşen bölüm sayısı.
    nonisolated static func dayShare(_ minutes: [Int], from start: Int, budget: Int) -> Int {
        var budget = budget
        var index = max(0, start)
        while budget > 0, index < minutes.count {
            budget -= minutes[index]
            index += 1
        }
        return index - max(0, start)
    }

    /// `remaining` (bölüm dakikaları, sırayla) `studyDays` güne günde `dailyMinutes` ile dağıtılınca ne kalır.
    /// Artan varsa öneri, 15'er artırılarak aynı dağıtımla denenen ve artanı sıfırlayan en küçük günlük süredir
    /// (`maxDaily`'ye kadar yoksa nil).
    nonisolated static func fit(remaining: [Int], studyDays: Int, dailyMinutes: Int, maxDaily: Int = 240) -> Fit {
        func placed(_ daily: Int) -> Int {
            var index = 0
            for _ in 0..<max(0, studyDays) where index < remaining.count {
                index += dayShare(remaining, from: index, budget: daily)
            }
            return index
        }
        let done = placed(dailyMinutes)
        let leftover = remaining[done...]
        var suggestion: Int?
        if !leftover.isEmpty {
            var daily = dailyMinutes + 15
            while daily <= maxDaily, suggestion == nil {
                if placed(daily) == remaining.count { suggestion = daily }
                daily += 15
            }
        }
        return Fit(plannedMinutes: remaining[..<done].reduce(0, +), leftoverCount: leftover.count,
                   leftoverMinutes: leftover.reduce(0, +), suggestedDailyMinutes: suggestion)
    }

    static func days(plan: StudyPlan, episodes: [Episode], dueCards: Int) -> [Day] {
        let left = max(1, plan.daysLeft)
        let studyDays = Self.studyDays(daysLeft: plan.daysLeft)
        let queue = Self.queue(episodes)
        let minutes = queue.map { $0.minutes }
        var cursor = 0
        var result: [Day] = []
        for offset in 0..<min(left, 60) {
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: .now) else { continue }
            var items: [String] = []
            if offset < studyDays {
                let count = dayShare(minutes, from: cursor, budget: plan.dailyMinutes)
                for next in queue[cursor..<cursor + count] { items.append("Dinle: \(next.title) (\(next.minutes) dk)") }
                cursor += count
                items.append(offset == 0 ? "Tekrar: \(dueCards) kart" : "Tekrar: günlük kartlar")
            } else {
                items.append("Sınav simülasyonu (karışık, süreli)")
                items.append("Zayıf konular: eksik kapatma podcast'i")
            }
            result.append(Day(date: date, items: items))
        }
        return result
    }

    /// Kullanıcı plan ekranından "kaydet ve hatırlat" dediyse true; plan silinince kapanır.
    static let notifyKey = "studyPlan.notify"
    static let notificationWindow = 14

    /// Sıradaki en çok 14 sabahın (08:00) bildirim kayıtları; saati geçmiş gün atlanır. Kimlik: "plan-yyyy-MM-dd".
    static func notificationPlan(days: [Day], examName: String, now: Date = .now, calendar: Calendar = .current)
        -> [(id: String, components: DateComponents, title: String, body: String)] {
        var out: [(id: String, components: DateComponents, title: String, body: String)] = []
        for day in days where out.count < notificationWindow {
            var components = calendar.dateComponents([.year, .month, .day], from: day.date)
            components.hour = 8
            guard let fire = calendar.date(from: components), fire > now else { continue }
            let id = String(format: "plan-%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
            out.append((id: id, components: components, title: "\(examName) planı · bugün", body: day.items.joined(separator: " · ")))
        }
        return out
    }

    /// Plan bildirimlerini güncel plan, bölüm ve kartlarla yeniden kurar. Plan yoksa ya da sınav geçmişse bekleyenleri kaldırır.
    /// `requestPermission` yalnız plan ekranındaki "kaydet ve hatırlat"ta true; diğer çağrılar (Hedef düzenleyici, Koç açılışı)
    /// izin sormaz ve yalnız kullanıcı daha önce hatırlatma istemişse kurar. Pencere 14 gün olduğundan Koç her açılışta uzatır.
    static func refreshNotifications(context: ModelContext, requestPermission: Bool) async {
        let center = UNUserNotificationCenter.current()
        let defaults = UserDefaults.standard
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("plan-") }
        guard let plan = StudyPlan.current, plan.examDate >= Calendar.current.startOfDay(for: .now) else {
            if !pending.isEmpty { center.removePendingNotificationRequests(withIdentifiers: pending) }
            if StudyPlan.current == nil { defaults.removeObject(forKey: notifyKey) }
            return
        }
        if requestPermission {
            defaults.set(true, forKey: notifyKey)
            guard await NotificationGate.request(center, options: [.alert, .sound]) else { return }
        } else {
            if !defaults.bool(forKey: notifyKey) {
                // Eski kurulumda bayrak yoktur: bekleyen plan bildirimi varsa kullanıcı hatırlatma istemiş sayılır.
                guard !pending.isEmpty else { return }
                defaults.set(true, forKey: notifyKey)
            }
            let status = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional else { return }
        }
        let episodes = (try? context.fetch(FetchDescriptor<Episode>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let dueCards = ((try? context.fetch(FetchDescriptor<ReviewCard>())) ?? []).filter(\.isDue).count
        let items = notificationPlan(days: days(plan: plan, episodes: episodes, dueCards: dueCards), examName: plan.examName)
        // Aynı kimlikli istek üzerine yazılır; önce ekleyip sonra artanları silmek arada bildirimsiz boşluk bırakmaz.
        for item in items {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.userInfo = ["route": "plan"]
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: item.components, repeats: false)))
        }
        let kept = Set(items.map(\.id))
        let stale = pending.filter { !kept.contains($0) }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
    }
}

struct StudyPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Episode.createdAt) private var episodes: [Episode]
    @Query private var cards: [ReviewCard]
    @State private var name = StudyPlan.current?.examName ?? ""
    @State private var date = StudyPlan.editableDate(StudyPlan.current?.examDate)
    @State private var minutes = StudyPlan.current?.dailyMinutes ?? 45
    @State private var saved = StudyPlan.current != nil

    private var plan: StudyPlan { StudyPlan(examName: name.isEmpty ? "Sınav" : name, examDate: date, dailyMinutes: minutes) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Sınavın adı (ör. KPSS)", text: $name)
                    DatePicker("Tarih", selection: $date, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                    Stepper("Günlük dinleme: \(minutes) dk", value: $minutes, in: 15...240, step: 15)
                    Button(saved ? "Planı güncelle" : "Planı kaydet ve hatırlat") {
                        StudyPlan.store(plan)
                        saved = true
                        Task { await StudyPlanner.refreshNotifications(context: context, requestPermission: true) }
                    }
                    if saved {
                        Button("Planı sil", role: .destructive) {
                            StudyPlan.store(nil)
                            saved = false
                            Task { await StudyPlanner.refreshNotifications(context: context, requestPermission: false) }
                        }
                    }
                } header: {
                    Text("Sınav")
                } footer: {
                    Text("Her sabah 08:00'de o günün planı bildirim olarak gelir. Son günler sınav provası ve zayıf konulara ayrılır.")
                }
                Section {
                    fitNote
                    ForEach(days) { day in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(day.date.formatted(.dateTime.weekday(.wide).day().month())).font(.subheadline.bold())
                            ForEach(day.items, id: \.self) { item in
                                Text("• " + item).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("\(plan.daysLeft) gün kaldı")
                }
            }
            .navigationTitle("Çalışma planı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
        }
    }

    private var days: [StudyPlanner.Day] { StudyPlanner.days(plan: plan, episodes: episodes, dueCards: cards.filter(\.isDue).count) }

    private var fit: StudyPlanner.Fit {
        StudyPlanner.fit(remaining: StudyPlanner.queue(episodes).map { $0.minutes },
                         studyDays: StudyPlanner.studyDays(daysLeft: plan.daysLeft), dailyMinutes: minutes)
    }

    /// Sınava sığmayan içerik sessizce plandan düşmesin: artan bölümler ve hepsini sığdıran günlük süre gösterilir.
    @ViewBuilder
    private var fitNote: some View {
        let fit = self.fit
        if fit.leftoverCount > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Label("\(fit.leftoverCount) bölüm (\(fit.leftoverMinutes) dk) bu tempoyla sınava yetişmiyor.", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                if let suggested = fit.suggestedDailyMinutes {
                    Button("Günlük süreyi \(suggested) dk yap") { minutes = suggested }
                        .buttonStyle(.bordered)
                } else {
                    Text("Günlük süre yetmiyor: bölüm ele ya da tarihi gözden geçir.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } else if fit.plannedMinutes > 0 {
            Text("Dinlenecek toplam \(fit.plannedMinutes) dk.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Öneri 15: Anki'ye aktarma

enum AnkiExport {
    /// Anki "Metin dosyasından içe aktar" biçimi: sekmeyle ayrılmış ön/arka/etiket; başlık direktifleriyle.
    static func file(cards: [ReviewCard]) throws -> URL {
        func clean(_ s: String) -> String {
            s.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: "<br>")
        }
        var text = "#separator:tab\n#html:true\n#tags column:3\n"
        for card in cards {
            let tag = card.episodeTitle.components(separatedBy: .whitespacesAndNewlines).joined(separator: "_").prefix(60)
            text += "\(clean(card.front))\t\(clean(card.back))\tDersPodcast \(tag)\n"
        }
        let url = URL.temporaryDirectory.appending(path: "DersPodcast-kartlar.txt")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - Öneri 16: haftalık tekrar podcast'i

enum WeeklyRecap {
    static let enabledKey = "weeklyRecap.auto"
    static let lastKey = "weeklyRecap.lastWeek"
    /// #31: son üretim zamanı (Date).
    static let lastRunKey = "weeklyRecap.lastRunAt"

    static var weekKey: String { weekKey(for: .now) }

    nonisolated static func weekKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(c.yearForWeekOfYear ?? 0)-\(c.weekOfYear ?? 0)"
    }

    /// Eski sürümden geçiş: eski sürüm yalnız pazar üretip o haftanın `yıl-hafta` anahtarını yazardı. Anahtarın pazarı
    /// son üretim sayılır (pazartesi başlayan takvimde pazar haftanın sonudur; gelecekteyse şimdi). Çözülemeyen anahtar
    /// ihtiyatla en son pazar sayılır: güncelleme sonrası birkaç gün içinde ikinci bir haftalık tekrar üretilmesin.
    nonisolated static func migratedLastRun(legacyKey: String, now: Date, calendar: Calendar = .current) -> Date {
        let fallback = lastSundayStart(before: now, calendar: calendar)
        let parts = legacyKey.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 2, let year = parts[0], let week = parts[1], year > 0, (1...53).contains(week) else { return fallback }
        var components = DateComponents()
        components.yearForWeekOfYear = year
        components.weekOfYear = week
        components.weekday = 1   // pazar
        guard let sunday = calendar.date(from: components).map(calendar.startOfDay),
              weekKey(for: sunday, calendar: calendar) == legacyKey else { return fallback }
        return min(sunday, now)
    }

    /// En son pazar 00:00 (bugün pazarsa bugünün başı). Haftanın ilk günü ayarından bağımsızdır (weekday 1 = pazar).
    nonisolated static func lastSundayStart(before now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let back = (calendar.component(.weekday, from: today) + 6) % 7
        return calendar.date(byAdding: .day, value: -back, to: today) ?? today
    }

    /// Son üretim en son pazar 00:00'dan önceyse (ya da hiç yoksa) sıra gelmiştir; kaçırılan pazar pazartesi de yakalanır.
    nonisolated static func isDue(now: Date, lastRunAt: Date?, calendar: Calendar = .current) -> Bool {
        guard let lastRunAt else { return true }
        return lastRunAt < lastSundayStart(before: now, calendar: calendar)
    }

    /// Bu hafta dinlenen bölümlerin özetleri ve notlarından 10 dakikalık, önce yoklayan tekrar bölümü.
    static func create(context: ModelContext, generator: GenerationCoordinator) async throws -> Episode {
        let keys = Set((0..<7).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: .now) }.map { ListeningDay.key(for: $0) })
        let days = (try? context.fetch(FetchDescriptor<ListeningDay>())) ?? []
        let ids = Set(days.filter { keys.contains($0.day) }.flatMap(StatsView.ids))
        let episodes = ((try? context.fetch(FetchDescriptor<Episode>())) ?? []).filter { ids.contains($0.id) && $0.status == .ready }
        guard !episodes.isEmpty else {
            throw APIError(status: 0, code: "empty", message: "Bu hafta dinlenen bölüm yok.")
        }
        var text = "BU HAFTA DİNLENEN BÖLÜMLER\n\n"
        for e in episodes.prefix(10) {
            guard let s = e.script else { continue }
            text += "## \(e.title)\nÖzet: \(s.summary)\nAnahtar noktalar: \(s.keyPoints.joined(separator: "; "))\nNotlar: \(s.sourceNotes.prefix(4000))\n\n"
        }
        let last = try? JSONDecoder().decode(PodcastSettings.self, from: UserDefaults.standard.data(forKey: "lastSettings") ?? Data())
        let parent = episodes.max { ($0.lastPlayedAt ?? .distantPast) < ($1.lastPlayedAt ?? .distantPast) }?.id
        var settings = RecapGenerator.settings(from: last, kind: "weekly", parent: parent)
        settings.durationMin = 10
        settings.format = last?.format ?? .sohbet
        settings.depth = .dengeli
        settings.focus = "Haftalık tekrar"
        settings.customInstructions = "Bu bir haftalık tekrar bölümü: bu hafta dinlenen \(episodes.count) bölümün en önemli noktalarını bağlantılarıyla birlikte toparla, bölümler arası ilişkileri vurgula."
        settings.extras.recapQuestions = true
        let episode = try await generator.start(sources: [ImportedSource(name: "Haftalık tekrar · \(Date.now.formatted(date: .abbreviated, time: .omitted))", kind: .text(text))],
                                                settings: settings, context: context)
        UserDefaults.standard.set(weekKey, forKey: lastKey)
        UserDefaults.standard.set(Date.now, forKey: lastRunKey)
        return episode
    }

    /// Açıksa: son üretim en son pazardan önceyse üret (pazar kaçırılsa da sonraki açılışta).
    static func runIfDue(context: ModelContext, generator: GenerationCoordinator) async {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: lastRunKey) == nil, let legacy = defaults.string(forKey: lastKey) {
            defaults.set(migratedLastRun(legacyKey: legacy, now: .now), forKey: lastRunKey)
        }
        guard UserDefaults.standard.bool(forKey: enabledKey),
              isDue(now: .now, lastRunAt: UserDefaults.standard.object(forKey: lastRunKey) as? Date) else { return }
        do {
            _ = try await create(context: context, generator: generator)
        } catch let error as APIError where error.code == "empty" {
            // Bu hafta dinlenen yok: bir dahaki pazara kadar yeniden denenmesin.
            UserDefaults.standard.set(Date.now, forKey: lastRunKey)
        } catch {}
    }
}

// MARK: - Öneri 17: kitabı bölümlere ayır

enum BookSplitter {
    /// PDF içindekiler tablosunun ilk düzeyinden bölüm aralıkları (en az 2 bölüm ve 2 sayfa).
    static func chapters(of url: URL) -> [(title: String, range: ClosedRange<Int>)] {
        guard let document = PDFDocument(url: url), let root = document.outlineRoot, root.numberOfChildren >= 2 else { return [] }
        var starts: [(String, Int)] = []
        for i in 0..<root.numberOfChildren {
            guard let item = root.child(at: i), let page = item.destination?.page else { continue }
            let index = document.index(for: page) + 1
            starts.append(((item.label ?? "Bölüm \(i + 1)").trimmingCharacters(in: .whitespacesAndNewlines), index))
        }
        starts.sort { $0.1 < $1.1 }
        var result: [(String, ClosedRange<Int>)] = []
        for (i, start) in starts.enumerated() {
            let end = (i + 1 < starts.count ? starts[i + 1].1 - 1 : document.pageCount)
            if end >= start.1 { result.append((start.0, start.1...end)) }
        }
        return result.count >= 2 ? result.map { (title: $0.0, range: $0.1) } : []
    }
}
