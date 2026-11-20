import SwiftData
import SwiftUI

/// Türkçe dublaj (#35): hazır Türkçe metin (çeviri ya da Türkçe ders) tek anlatıcıyla mevcut seslendirme hattından geçirilir.
/// Senaryo yazdırılmaz: paragraflar doğrudan sahnelere bölünür; ses üretimi `GenerationCoordinator.resume` ile arka planda sürer.
struct DubbingView: View {
    var context: LessonContext

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(GenerationCoordinator.self) private var generator
    @State private var scope = -1
    @State private var errorText: String?
    @State private var confirmLong = false
    @State private var starting = false

    private var source: (paragraphs: [TranscriptParagraph], translated: Bool)? { DubbingPlan.source(context.transcript) }

    private var range: ClipRange? {
        scope >= 0 ? StudyText.chapterRange(context.transcript.chapters, index: scope, end: context.contentEnd) : nil
    }

    /// Son kullanılan podcast ayarları; dublaj tek anlatıcı ve Türkçe olur.
    private var settings: PodcastSettings {
        var value = ((try? JSONDecoder().decode(PodcastSettings.self, from: UserDefaults.standard.data(forKey: "lastSettings") ?? Data()))
            ?? PodcastSettings()).forNewAudio
        value.format = .tekAnlatici
        value.language = .tr
        if ![5, 10, 15, 20, 30, 45, 60].contains(value.durationMin) { value.durationMin = 10 }
        value.focus = "Türkçe dublaj"
        return value
    }

    var body: some View {
        StudySheet(title: "Türkçe dublaj") {
            if let source {
                form(source)
            } else {
                ContentUnavailableView {
                    Label("Türkçe metin yok", systemImage: "character.bubble")
                } description: {
                    Text("Dublaj için Türkçe çeviri ya da Türkçe bir ders gerekir. Videoyu “Türkçeye çevir” seçeneğiyle yeniden işleyebilirsin.")
                }
            }
        }
        .onAppear { context.pausePlayback() }
    }

    private func form(_ source: (paragraphs: [TranscriptParagraph], translated: Bool)) -> some View {
        let characters = DubbingPlan.characters(source.paragraphs, range: range)
        let seconds = DubbingPlan.estimatedSeconds(characters: characters)
        let current = settings
        return Form {
            Section {
                Text(source.translated
                     ? "Dersin Türkçe çevirisi tek bir anlatıcıyla seslendirilir ve kütüphanene yeni bir bölüm olarak eklenir."
                     : "Ders zaten Türkçe; metni tek bir anlatıcıyla temiz bir sesle seslendirilir ve kütüphanene yeni bölüm olarak eklenir.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                ScopePicker(chapters: context.sortedChapters, selection: $scope)
                LabeledContent("Metin", value: "\(characters.formatted()) karakter")
                LabeledContent("Tahmini süre", value: seconds.clockText)
                LabeledContent("Ses", value: "\(current.hostA.name) · \(current.engine.title)")
            } footer: {
                Text(current.usesServerSpeech
                     ? "Sunucu sesi günlük podcast hakkından 1 tane kullanır. Ses ve motor ayarı son podcast ayarlarından alınır."
                     : "Ses cihazda üretilir. Ses ve motor ayarı son podcast ayarlarından alınır.")
            }
            if let errorText { Section { Text(errorText).font(.callout).foregroundStyle(.red) } }
            Section {
                Button {
                    if seconds > 30 * 60 { confirmLong = true } else { start(source.paragraphs) }
                } label: {
                    if starting { HStack { ProgressView(); Text("Hazırlanıyor…") } } else { Text("Dublajı başlat").frame(maxWidth: .infinity).font(.headline) }
                }
                .disabled(starting || characters < 20)
            }
        }
        .confirmationDialog("Uzun dublaj", isPresented: $confirmLong, titleVisibility: .visible) {
            Button("Yine de başlat") { start(source.paragraphs) }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Yaklaşık \(seconds.clockText) sürecek; seslendirme uzun sürer. Tek bir bölüm seçmek daha hızlıdır.")
        }
    }

    private func start(_ paragraphs: [TranscriptParagraph]) {
        guard !starting, context.lesson.modelContext != nil else { return }
        errorText = nil
        let current = settings
        do {
            try LocalSpeech.validate(current)
            if current.engine == .apple { _ = try DeviceSpeech.selectedVoice(speaker: .a, language: current.language, swapped: DeviceSpeech.swapsGenders(current)) }
        } catch {
            errorText = error.localizedDescription
            return
        }
        let lessonTitle = context.lesson.title
        let title = "Türkçe dublaj · \(lessonTitle.isEmpty ? "Video dersi" : lessonTitle)"
        guard let script = DubbingPlan.script(title: title, paragraphs: paragraphs, chapters: context.transcript.chapters,
                                              summary: context.transcript.notes?.summary ?? "", range: range) else {
            errorText = "Metin dublaj için çok kısa ya da çok uzun. Tek bir bölüm seçip tekrar dene."
            return
        }
        starting = true
        let episode = Episode(script: script, settings: current, sourceNames: [lessonTitle], jobToken: "")
        episode.jobToken = nil
        // Ders görselleri için ayrı üretim isteği gönderilmesin: yerel bir kapak yeter.
        episode.visuals = VisualPack(cover: .init(title: lessonTitle, subtitle: "Türkçe dublaj", symbol: "speaker.wave.2", theme: "ocean",
                                                  motif: "network", accessibilityLabel: title), diagrams: [], model: "local")
        LessonEpisodes.suppressAutoMaterials(episode)
        modelContext.insert(episode)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(episode)
            EpisodeFiles.remove(episode: episode.id)
            errorText = "Bölüm kaydedilemedi: \(error.localizedDescription)"
            starting = false
            return
        }
        LessonEpisodes.attach(episode.id, toLesson: context.lesson.id, context: modelContext)
        generator.resume(episode, context: modelContext)
        LessonEpisodes.releaseAutoMaterials(episodeID: episode.id, context: modelContext)
        let id = episode.id
        dismiss()
        LessonEpisodes.open(id, from: context)
    }
}
