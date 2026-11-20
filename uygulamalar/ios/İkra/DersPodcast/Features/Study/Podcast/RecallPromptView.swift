import SwiftData
import SwiftUI

/// #29 Anlatarak hatırla: 45 sn sesli anlatım (yalnız ön planda) → `/v1/recall-check` →
/// eksik ve yanlışlar "Bu kısmı dinle" ile; takip sorusu da sesle cevaplanır. `learn2` gerekir.
struct RecallPromptView: View {
    var episode: Episode
    var chapter: Int
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    /// Kilitliyken mikrofon açılmaz (yalnız bu akış; sesli kart tekrarı kilitliyken de dinler).
    @State private var recorder = SpeechRecorder(foregroundOnly: true)
    @State private var secondsLeft = RecallPromptView.limit
    @State private var recordingID: UUID?
    @State private var checking = false
    @State private var result: RecallCheckResult?
    @State private var response = ""
    @State private var followUpAnswer: String?
    @State private var followUpFeedback: String?
    @State private var error: String?
    /// Gönderilemeyen anlatım ve takip cevabı: hata sonrası yeniden kayıt gerekmeden yeniden gönderilir.
    @State private var pendingText: String?
    @State private var pendingFollowUp: String?

    static let limit = 45

    private var chapterTitle: String {
        episode.timeline?.chapters.first { $0.id == chapter }?.title ?? episode.script?.chapters[safe: chapter]?.title ?? "Bu konu"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(chapterTitle).font(.title3.bold())
                    if let result {
                        resultView(result)
                    } else if checking {
                        HStack { ProgressView(); Text("Anlattıkların konuyla karşılaştırılıyor…") }
                    } else if let pendingText {
                        retryCard(pendingText, restartTitle: "Baştan anlat") {
                            await check(pendingText)
                        } restart: {
                            self.pendingText = nil
                            error = nil
                        }
                    } else {
                        Text("\(RecallPromptView.limit) saniyede aklında kalanları kendi cümlelerinle anlat. Eksik ve yanlış noktalar, anlatıldıkları anla birlikte listelenecek.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if recorder.isRecording {
                            Text("\(secondsLeft) sn").font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(secondsLeft <= 10 ? AnyShapeStyle(.orange) : AnyShapeStyle(Theme.gradient))
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel("\(secondsLeft) saniye kaldı")
                        }
                        RecordPanel(recorder: recorder, hint: "Anlatmaya başlamak için dokun") { text in
                            Task { await check(text) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    if let error { Text(error).font(.callout).foregroundStyle(.red) }
                }
                .padding(20)
            }
            .navigationTitle("Anlatarak hatırla")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(result == nil ? "Vazgeç" : "Bitti") { recorder.cancel(); LearningCenter.shared.sheet = nil }
                }
            }
        }
        .onChange(of: recorder.isRecording) { _, recording in
            if recording { secondsLeft = Self.limit; recordingID = UUID(); error = nil }
        }
        .task(id: recordingID) {
            guard recordingID != nil else { return }
            while recorder.isRecording, secondsLeft > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                secondsLeft -= 1
            }
            if recorder.isRecording, secondsLeft <= 0 {
                let text = await recorder.stop()
                if followUpAnswer == nil, result != nil { await answerFollowUp(text) } else { await check(text) }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Ekran kilitlendi: mikrofon kapanır, anlatım yeniden başlatılabilir.
            guard phase == .background, recorder.isRecording else { return }
            recorder.cancel()
            error = "Ekran kilitlenince kayıt durdu. Yeniden başlatabilirsin."
        }
        .onDisappear { recorder.cancel() }
    }

    @ViewBuilder private func resultView(_ result: RecallCheckResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(result.score)").font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(result.score >= 60 ? .green : .orange)
                Text(result.feedback).font(.callout)
            }
            if !result.covered.isEmpty {
                section("Hatırladıkların", symbol: "checkmark.circle", color: .green) {
                    ForEach(result.covered, id: \.self) { Text($0).font(.callout) }
                }
            }
            if !result.missing.isEmpty {
                section("Eksik kalanlar", symbol: "circle.dashed", color: .orange) {
                    ForEach(Array(result.missing.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.point).font(.callout)
                            listenButton(turn: item.turnIndex)
                        }
                    }
                }
            }
            if !result.wrong.isEmpty {
                section("Yanlış hatırladıkların", symbol: "exclamationmark.triangle", color: .red) {
                    ForEach(Array(result.wrong.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.claim).font(.callout).strikethrough().foregroundStyle(.secondary)
                            Text(item.correction).font(.callout)
                            listenButton(turn: item.turnIndex)
                        }
                    }
                }
            }
            if let question = result.followUp {
                section("Takip sorusu", symbol: "arrow.turn.down.right", color: .accentColor) {
                    Text(question).font(.callout.weight(.semibold))
                    if let followUpFeedback {
                        Text(followUpFeedback).font(.callout)
                    } else if checking {
                        ProgressView()
                    } else if let pendingFollowUp {
                        retryCard(pendingFollowUp, restartTitle: "Yeniden cevapla") {
                            await answerFollowUp(pendingFollowUp)
                        } restart: {
                            self.pendingFollowUp = nil
                            error = nil
                        }
                    } else {
                        RecordPanel(recorder: recorder, hint: "Sesle cevaplamak için dokun") { text in
                            Task { await answerFollowUp(text) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, symbol: String, color: Color, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.subheadline.bold()).foregroundStyle(color)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    /// İstek hata verdi: söylenen metin durur; aynı metin yeniden gönderilir ya da baştan kaydedilir.
    private func retryCard(_ text: String, restartTitle: String, resend: @escaping @MainActor () async -> Void,
                           restart: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Gönderilemedi. Söylediklerin duruyor:", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
            Text(text).font(.callout).lineLimit(6)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { retryButtons(restartTitle, resend: resend, restart: restart) }
                VStack(alignment: .leading, spacing: 8) { retryButtons(restartTitle, resend: resend, restart: restart) }
            }
            .controlSize(.large)
        }
    }

    @ViewBuilder private func retryButtons(_ restartTitle: String, resend: @escaping @MainActor () async -> Void,
                                           restart: @escaping () -> Void) -> some View {
        Button("Yeniden gönder", systemImage: "arrow.clockwise") { Task { await resend() } }.buttonStyle(.borderedProminent)
        Button(restartTitle, systemImage: "mic", action: restart).buttonStyle(.bordered)
    }

    @ViewBuilder private func listenButton(turn: Int?) -> some View {
        if let time = ListenAnchor.time(turnIndex: turn, chapterIndex: turn == nil ? chapter : nil, timeline: episode.timeline) {
            Button {
                recorder.cancel()
                LearningCenter.shared.sheet = nil
                LearningLinks.listen(episodeID: episode.id, at: time)
            } label: {
                Label(ListenAnchor.label(time), systemImage: "headphones").font(.caption)
            }
            .buttonStyle(.bordered)
        }
    }

    private func request(_ text: String, followUp: RecallFollowUp?) -> RecallCheckRequest {
        RecallCheckRequest(title: String((episode.script?.title ?? episode.title).prefix(300)),
                           sourceNotes: String((episode.script?.sourceNotes ?? "").prefix(15_000)),
                           chapterTitle: String(chapterTitle.prefix(300)),
                           chapterTurns: LearnPayload.chapterTurns(episode.timeline, chapter: chapter),
                           response: String(text.prefix(5000)), followUp: followUp)
    }

    private func check(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 10 else { error = "Anlatım çok kısa kaldı ya da sesin duyulmadı. Tekrar dene."; return }
        response = trimmed
        checking = true
        error = nil
        defer { checking = false }
        do {
            let checked = try await APIClient.shared.recallCheck(request(trimmed, followUp: nil))
            result = checked
            pendingText = nil
            var entry = RecallLog.Entry(source: "recall", question: "Anlatarak hatırla: \(chapterTitle)")
            entry.answerText = trimmed
            entry.score = Double(checked.score) / 100
            entry.isCorrect = checked.score >= 60
            entry.chapterIndex = chapter
            RecallLog.record(entry, episode: episode, context: context)
        } catch {
            pendingText = trimmed
            self.error = error.localizedDescription
        }
    }

    private func answerFollowUp(_ text: String) async {
        guard let result, let question = result.followUp else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { error = "Sesini duyamadım. Tekrar dene."; return }
        followUpAnswer = trimmed
        checking = true
        error = nil
        defer { checking = false }
        do {
            let checked = try await APIClient.shared.recallCheck(request(response, followUp: RecallFollowUp(question: String(question.prefix(500)),
                                                                                                             answer: String(trimmed.prefix(3000)))))
            followUpFeedback = checked.feedback
            pendingFollowUp = nil
            var entry = RecallLog.Entry(source: "recall", question: question)
            entry.answerText = trimmed
            entry.score = Double(checked.score) / 100
            entry.isCorrect = checked.score >= 60
            entry.chapterIndex = chapter
            RecallLog.record(entry, episode: episode, context: context)
        } catch {
            followUpAnswer = nil
            pendingFollowUp = trimmed
            self.error = error.localizedDescription
        }
    }
}
