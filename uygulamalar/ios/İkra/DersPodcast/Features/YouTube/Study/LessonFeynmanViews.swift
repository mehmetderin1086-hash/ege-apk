import SwiftData
import SwiftUI

// Feynman: kendi cümlelerinle anlat (#25) ve başka bir videoyla karşılaştır (#27).

/// Feynman anlatım taslakları (UserDefaults; ders + konu başına bir taslak). Sayfa kapanınca ya da anlatım
/// düzeltilmek istenince yazılan metin kaybolmasın diye tutulur.
nonisolated enum FeynmanDrafts {
    static let key = "lesson.feynmanDrafts"
    /// En çok bu kadar taslak saklanır; aşılınca en eskiler düşer.
    static let limit = 20
    /// Değerlendirmeye giden (ve taslakta saklanan) en uzun anlatım.
    static let maxLength = 5000

    struct Draft: Codable, Equatable, Sendable {
        var text: String
        var date: Date
    }

    static func id(lesson: UUID, topic: Int) -> String { "\(lesson.uuidString)|\(topic)" }

    static func all(defaults: UserDefaults = .standard) -> [String: Draft] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: Draft].self, from: $0) } ?? [:]
    }

    static func load(lesson: UUID, topic: Int, defaults: UserDefaults = .standard) -> String {
        all(defaults: defaults)[id(lesson: lesson, topic: topic)]?.text ?? ""
    }

    /// Boş metin kaydı siler; metin `maxLength`'e kırpılır. Değişmeyen metin yeniden yazılmaz.
    static func save(_ text: String, lesson: UUID, topic: Int, now: Date = .now, defaults: UserDefaults = .standard) {
        var drafts = all(defaults: defaults)
        let slot = id(lesson: lesson, topic: topic)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard drafts.removeValue(forKey: slot) != nil else { return }
        } else {
            let clipped = String(text.prefix(maxLength))
            guard drafts[slot]?.text != clipped else { return }
            drafts[slot] = Draft(text: clipped, date: now)
            if drafts.count > limit {
                let oldest = drafts.sorted { ($0.value.date, $0.key) < ($1.value.date, $1.key) }.prefix(drafts.count - limit)
                for entry in oldest { drafts[entry.key] = nil }
            }
        }
        write(drafts, defaults: defaults)
    }

    static func clear(lesson: UUID, topic: Int, defaults: UserDefaults = .standard) {
        var drafts = all(defaults: defaults)
        guard drafts.removeValue(forKey: id(lesson: lesson, topic: topic)) != nil else { return }
        write(drafts, defaults: defaults)
    }

    /// Konu değişimi: alandaki metin ESKİ konunun yuvasında saklanır, alana yazılacak olan yeni konunun taslağı döner
    /// (taslağı yoksa boş); yeni konunun kayıtlı taslağı ezilmez. Alan zaten yeni konunun taslağına eşitse
    /// (açılışta konu atanıp taslağı yüklendiğinde) hiçbir yuvaya dokunulmaz.
    static func switchTopic(_ text: String, from old: Int, to selected: Int, lesson: UUID, now: Date = .now,
                            defaults: UserDefaults = .standard) -> String {
        guard old != selected else { return text }
        let stored = load(lesson: lesson, topic: selected, defaults: defaults)
        guard stored != text else { return text }
        save(text, lesson: lesson, topic: old, now: now, defaults: defaults)
        return stored
    }

    private static func write(_ drafts: [String: Draft], defaults: UserDefaults) {
        if drafts.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(drafts) {
            defaults.set(data, forKey: key)
        }
    }
}

struct LessonFeynmanView: View {
    var context: LessonContext
    var chapter: Int?

    /// -1 = tüm ders.
    @State private var topic = -1
    @State private var answer = ""
    @State private var voice = false
    @State private var recorder = SpeechRecorder()
    @State private var phase: StudyPhase<StudyFeynmanResult> = .idle
    @State private var task: Task<Void, Never>?
    @State private var hint: String?
    @State private var confirmClear = false

    static let maxAnswer = FeynmanDrafts.maxLength
    static let minAnswer = 20

    var body: some View {
        StudySheet(title: "Feynman") {
            switch phase {
            case .idle, .failed: input
            case .loading: StudyLoadingView(message: "Anlatımın dersle karşılaştırılıyor…", onCancel: { task?.cancel(); phase = .idle })
            case .loaded(let result): resultView(result)
            }
        }
        .onAppear {
            context.pausePlayback()
            if let chapter, context.sortedChapters.indices.contains(chapter) { topic = chapter }
            if answer.isEmpty { answer = FeynmanDrafts.load(lesson: context.lesson.id, topic: topic) }
        }
        .onChange(of: topic) { old, selected in
            // Her konunun taslağı ayrıdır: yazılan metin eski konuda kalır, alana yeni konunun taslağı gelir.
            let next = FeynmanDrafts.switchTopic(answer, from: old, to: selected, lesson: context.lesson.id)
            if next != answer { answer = next }
        }
        .task(id: answer) {
            // Her tuşta değil, yazma durunca kaydet.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            FeynmanDrafts.save(answer, lesson: context.lesson.id, topic: topic)
        }
        .onDisappear {
            task?.cancel()
            recorder.cancel()
            FeynmanDrafts.save(answer, lesson: context.lesson.id, topic: topic)
        }
        .confirmationDialog("Anlatımın silinsin mi?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Temizle", role: .destructive) {
                answer = ""
                FeynmanDrafts.clear(lesson: context.lesson.id, topic: topic)
                phase = .idle
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Yazdığın metin geri getirilemez.")
        }
    }

    private var input: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Konuyu hiç bilmeyen birine anlatır gibi kendi cümlelerinle yaz ya da sesle anlat. Anlatımın dersle karşılaştırılıp eksik ve hatalı noktalar gösterilir.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Picker("Konu", selection: $topic) {
                    Text("Tüm ders").tag(-1)
                    ForEach(Array(context.sortedChapters.enumerated()), id: \.offset) { index, chapter in
                        Text(chapter.title).tag(index)
                    }
                }
                .pickerStyle(.menu)
                Picker("Anlatım biçimi", selection: $voice) {
                    Text("Yaz").tag(false)
                    Text("Sesle").tag(true)
                }
                .modifier(AccessiblePickerStyle())
                if voice {
                    RecordPanel(recorder: recorder, hint: "Anlatmaya başlamak için dokun") { text in
                        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !spoken.isEmpty { answer = answer.isEmpty ? spoken : answer + " " + spoken }
                        voice = false
                    }
                    .frame(maxWidth: .infinity)
                }
                TextEditor(text: $answer)
                    .frame(minHeight: 160)
                    .padding(8)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if answer.isEmpty {
                            Text("Anlatımını buraya yaz…").foregroundStyle(.tertiary).padding(16).allowsHitTesting(false)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(answer.count) / \(Self.maxAnswer)").font(.caption.monospacedDigit())
                        .foregroundStyle(answer.count > Self.maxAnswer ? Color.red : Color.secondary)
                    if answer.count > Self.maxAnswer {
                        Label("İlk \(Self.maxAnswer) karakter değerlendirilir", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if case .failed(let message) = phase { Text(message).font(.callout).foregroundStyle(.red) }
                if let hint { Text(hint).font(.callout).foregroundStyle(.orange) }
                Button("Değerlendir") { evaluate() }
                    .buttonStyle(PrimaryButtonStyle(enabled: answer.trimmingCharacters(in: .whitespacesAndNewlines).count >= Self.minAnswer))
            }
            .padding(16)
        }
    }

    private func evaluate() {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minAnswer else {
            hint = "Anlatım çok kısa kaldı. Biraz daha ayrıntılı anlat."
            return
        }
        hint = nil
        recorder.cancel()
        let reference = StudyText.reference(context.transcript, chapter: topic >= 0 ? topic : nil, end: context.contentEnd)
        guard !reference.isEmpty else {
            phase = .failed("Karşılaştırılacak ders metni bulunamadı.")
            return
        }
        let title = topic >= 0 && context.sortedChapters.indices.contains(topic)
            ? "\(context.lesson.title) — \(context.sortedChapters[topic].title)" : context.lesson.title
        phase = .loading
        let request = StudyFeynmanRequest(title: title, reference: reference, answer: String(trimmed.prefix(Self.maxAnswer)))
        task = Task {
            do {
                let result = try await APIClient.shared.studyFeynman(request)
                try Task.checkCancellation()
                phase = .loaded(result)
            } catch {
                if let message = StudyError.message(error) { phase = .failed(message) }
            }
        }
    }

    private func resultView(_ result: StudyFeynmanResult) -> some View {
        let tint: Color = result.score >= 75 ? .green : result.score >= 45 ? .orange : .red
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Text("\(result.score)").font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(tint)
                    ProgressView(value: Double(result.score), total: 100).tint(tint)
                }
                if !result.feedback.isEmpty { Text(result.feedback).font(.body).fixedSize(horizontal: false, vertical: true) }
                section("Doğru anlattıkların", items: result.covered, symbol: "checkmark.circle.fill", tint: .green)
                section("Eksik kalanlar", items: result.missing, symbol: "circle.dashed", tint: .orange)
                section("Hatalı noktalar", items: result.wrong, symbol: "exclamationmark.triangle.fill", tint: .red)
                DisclosureGroup("Senin anlatımın") {
                    Text(String(answer.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxAnswer)))
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.top, 6)
                }
                .font(.subheadline.bold())
                // Metin korunur: eksikleri görüp anlatımı geliştirmek için baştan yazmak gerekmez.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { retryButtons }
                    VStack(alignment: .leading, spacing: 8) { retryButtons }
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var retryButtons: some View {
        Button("Anlatımını düzelt", systemImage: "pencil") { phase = .idle }
            .buttonStyle(.borderedProminent)
        Button("Temizle ve baştan yaz", systemImage: "trash", role: .destructive) { confirmClear = true }
            .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func section(_ title: String, items: [String], symbol: String, tint: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.bold())
                StudyBulletList(items: items, symbol: symbol, tint: tint)
            }
        }
    }
}

// MARK: - Karşılaştırma (#27)

struct CompareLessonsView: View {
    var context: LessonContext

    private struct Other: Identifiable {
        var id: UUID
        var title: String
        var data: Data
    }

    @Query(sort: \VideoLesson.createdAt, order: .reverse) private var lessons: [VideoLesson]
    @State private var query = ""
    @State private var other: Other?
    @State private var phase: StudyPhase<StudyComparison> = .idle
    @State private var task: Task<Void, Never>?

    private var candidates: [VideoLesson] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return lessons.filter { lesson in
            lesson.id != context.lesson.id && lesson.transcriptData != nil
                && (q.isEmpty || TranscriptFormat.contains(TranscriptFormat.searchKey(q), in: TranscriptFormat.searchKey(lesson.title + " " + lesson.channel)))
        }
    }

    var body: some View {
        StudySheet(title: "Karşılaştır") {
            Group {
                switch phase {
                case .idle: picker
                case .loading: StudyLoadingView(message: "İki ders karşılaştırılıyor…", onCancel: { task?.cancel(); phase = .idle })
                case .failed(let message): StudyErrorView(message: message, retry: { phase = .idle })
                case .loaded(let result): resultView(result)
                }
            }
        }
        .onDisappear { task?.cancel() }
    }

    private var picker: some View {
        List {
            Section {
                ForEach(candidates) { lesson in
                    Button { compare(with: lesson) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lesson.title).font(.callout.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                            if !lesson.channel.isEmpty { Text(lesson.channel).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                    }
                }
            } header: {
                Text("“\(context.lesson.title)” ile karşılaştırılacak dersi seç")
                    .textCase(nil).lineLimit(3)
            } footer: {
                if candidates.isEmpty { Text("Karşılaştırılacak başka bir işlenmiş ders yok.") }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Ders ara")
    }

    private func compare(with lesson: VideoLesson) {
        guard let data = lesson.transcriptData else { return }
        let picked = Other(id: lesson.id, title: lesson.title, data: data)
        other = picked
        let mine = StudyCompareSide(title: context.lesson.title, text: StudyText.lessonText(context.transcript, maxChars: 80_000))
        phase = .loading
        task = Task {
            do {
                guard let transcript = await LessonFiles.decodeTranscript(picked.data) else {
                    phase = .failed("Seçilen dersin transkripti okunamadı.")
                    return
                }
                let theirs = StudyCompareSide(title: picked.title, text: StudyText.lessonText(transcript, maxChars: 80_000))
                guard theirs.text.count > 1, mine.text.count > 1 else {
                    phase = .failed("Karşılaştırmak için iki dersin de metni olmalı.")
                    return
                }
                let result = try await APIClient.shared.studyCompare(StudyCompareRequest(a: mine, b: theirs))
                try Task.checkCancellation()
                phase = .loaded(result)
            } catch {
                if let message = StudyError.message(error) { phase = .failed(message) }
            }
        }
    }

    private func resultView(_ result: StudyComparison) -> some View {
        let titleA = context.lesson.title
        let titleB = other?.title ?? "Diğer ders"
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("A: \(titleA)", systemImage: "a.circle.fill").font(.caption).lineLimit(2)
                    Label("B: \(titleB)", systemImage: "b.circle.fill").font(.caption).lineLimit(2)
                }
                .foregroundStyle(.secondary)
                if !result.summary.isEmpty { Text(result.summary).font(.body).fixedSize(horizontal: false, vertical: true) }
                block("İkisinde de var", items: result.common, symbol: "equal.circle.fill", tint: .blue)
                block("Yalnızca A'da", items: result.onlyA, symbol: "a.circle.fill", tint: .green)
                block("Yalnızca B'de", items: result.onlyB, symbol: "b.circle.fill", tint: .orange)
                if !result.better.isEmpty {
                    Text("Konu konu hangisi daha iyi anlatıyor").font(.subheadline.bold())
                    ForEach(Array(result.better.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.topic).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 6)
                                Text(item.winner == "a" ? "A" : item.winner == "b" ? "B" : "—")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(item.winner == "a" ? Color.green.opacity(0.2) : Color.orange.opacity(0.2)))
                            }
                            if !item.why.isEmpty { Text(item.why).font(.caption).foregroundStyle(.secondary) }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                Button("Başka ders seç") { phase = .idle }.buttonStyle(.bordered)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func block(_ title: String, items: [String], symbol: String, tint: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.bold())
                StudyBulletList(items: items, symbol: symbol, tint: tint)
            }
        }
    }
}
