import AVFoundation
import SwiftData
import SwiftUI

// Öğretmenin sesinden özet (#20): ana noktaların çevresindeki kesitler ders sesinden birleştirilip yeni bir bölüm olur.

nonisolated enum TeacherAudio {
    enum ExportError: LocalizedError {
        case noAudio, nothingToExport, failed
        var errorDescription: String? {
            switch self {
            case .noAudio: "Ders sesi okunamadı."
            case .nothingToExport: "Birleştirilecek kesit bulunamadı."
            case .failed: "Özet sesi oluşturulamadı."
            }
        }
    }

    /// Kesitleri `source` sesinden kesip aralarında `gap` sn sessizlikle birleştirir ve m4a olarak yazar.
    /// Sesin gerçek süresine göre kısaltılan/atlanan kesitler yüzünden asıl eklenen kesitleri ve birleşik sesin
    /// süresini (sn) döndürür; zaman çizelgesi bu kesitlerden kurulmalıdır. Ağır iş: ana iş parçacığı dışında.
    @concurrent
    static func export(source: URL, clips: [ClipRange], gap: Double, to output: URL) async throws -> (clips: [ClipRange], duration: Double) {
        let asset = AVURLAsset(url: source)
        guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first else { throw ExportError.noAudio }
        let total = try await asset.load(.duration).seconds
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ExportError.failed
        }
        let gapTime = CMTime(seconds: gap, preferredTimescale: 600)
        var cursor = CMTime.zero
        var inserted: [ClipRange] = []
        for clip in clips {
            try Task.checkCancellation()
            let end = total.isFinite && total > 0 ? min(clip.end, total) : clip.end
            guard end - clip.start >= 0.5 else { continue }
            let range = CMTimeRange(start: CMTime(seconds: clip.start, preferredTimescale: 600),
                                    end: CMTime(seconds: end, preferredTimescale: 600))
            // Kesitler arasına açık sessizlik: boşluk örtük bırakılmaz.
            if !inserted.isEmpty {
                track.insertEmptyTimeRange(CMTimeRange(start: cursor, duration: gapTime))
                cursor = cursor + gapTime
            }
            try track.insertTimeRange(range, of: sourceTrack, at: cursor)
            cursor = cursor + range.duration
            inserted.append(ClipRange(start: clip.start, end: end))
        }
        guard !inserted.isEmpty else { throw ExportError.nothingToExport }
        try? FileManager.default.removeItem(at: output)
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else { throw ExportError.failed }
        try await session.export(to: output, as: .m4a)
        try Task.checkCancellation()
        // Süre, yazılan dosyadan okunur (hesapla değil).
        let written = try await AVURLAsset(url: output).load(.duration).seconds
        return (inserted, written.isFinite && written > 0 ? written : max(0, cursor.seconds))
    }
}

/// Ders sesinden/metninden üretilen bölümlerin kütüphaneye eklenmesi (özet ve dublaj ortak).
enum LessonEpisodes {
    /// Ders kaydına bölümü bağlar (ders await sırasında silinmiş olabilir: kimlikle yeniden çekilir).
    static func attach(_ episodeID: UUID, toLesson lessonID: UUID, context: ModelContext) {
        if let live = VideoLessonView.liveLesson(id: lessonID, in: context), !live.episodeIDs.contains(episodeID) {
            live.episodeIDs = live.episodeIDs + [episodeID]
        }
        try? context.save()
    }

    /// Dublaj bölümünde ek sunucu çağrıları olmasın: hazır olunca `GenerationCoordinator` boş olanlar için
    /// çalışma paketi ve slayt üretir. Boş (nöbetçi) paket/slayt bunu atlatır; `releaseAutoMaterials` sonradan kaldırır.
    /// (Senaryo doğrulaması boş `sourceNotes` ile atlanır; görsel isteği yerel kapakla.)
    static func suppressAutoMaterials(_ episode: Episode) {
        episode.study = StudyPack(quiz: [], flashcards: [], concepts: nil, formulas: nil)
        episode.slides = []
    }

    /// Üretim bitince (hazır ya da hata) nöbetçi boş paket/slaytları kaldırır; böylece kullanıcı isterse Çalış sekmesinden
    /// kendisi üretebilir. Üretimin hazır sonrası görevleri çalıştıktan sonra, kısa bekleyişle.
    static func releaseAutoMaterials(episodeID: UUID, context: ModelContext) {
        Task {
            func live() -> Episode? {
                var descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.id == episodeID })
                descriptor.fetchLimit = 1
                guard let episode = try? context.fetch(descriptor).first, episode.modelContext != nil, !episode.isDeleted else { return nil }
                return episode
            }
            for _ in 0..<5400 {   // en çok ~3 saat
                try? await Task.sleep(for: .seconds(2))
                guard let episode = live() else { return }
                if episode.status != .generating { break }
            }
            try? await Task.sleep(for: .seconds(4))
            guard let episode = live() else { return }
            if episode.study?.quiz.isEmpty == true, episode.study?.flashcards.isEmpty == true { episode.study = nil }
            if episode.slides?.isEmpty == true { episode.slides = nil }
            try? context.save()
        }
    }

    /// Bölümü kütüphanede açar; ders stüdyosunu kapatır.
    static func open(_ episodeID: UUID, from context: LessonContext) {
        context.closeStudio?()
        AppState.current?.selectedTab = .library
        AppState.current?.pendingOpenEpisode = episodeID
    }
}

struct TeacherSummaryView: View {
    var context: LessonContext

    private enum Stage { case plan, building, done(UUID), failed(String) }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var stage: Stage = .plan
    @State private var limitMinutes = 10
    @State private var download = LessonAudioDownload()
    @State private var audioReady = false
    @State private var task: Task<Void, Never>?

    private var paragraphs: [TranscriptParagraph] { context.transcript.paragraphs }
    private var points: [NoteKeyPoint] { context.transcript.notes?.keyPoints ?? [] }

    private var clips: [ClipRange] {
        let planned = ClipPlanner.plan(times: points.map(\.time), paragraphs: paragraphs, maxTotal: Double(limitMinutes) * 60)
        return TeacherSummaryPlan.usable(planned, paragraphs: paragraphs)
    }

    /// Süre sınırı yüzünden özete girmeyen ana nokta var mı (sınırsız planın süresiyle karşılaştırılır).
    private func isTrimmed(_ current: [ClipRange]) -> Bool {
        let all = TeacherSummaryPlan.usable(
            ClipPlanner.plan(times: points.map(\.time), paragraphs: paragraphs, maxTotal: .greatestFiniteMagnitude), paragraphs: paragraphs)
        return current.reduce(0) { $0 + $1.duration } + 0.5 < all.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        StudySheet(title: "Öğretmenin sesinden özet") {
            switch stage {
            case .plan: planView
            case .building: StudyLoadingView(message: "Özet sesi hazırlanıyor…", onCancel: { task?.cancel(); stage = .plan })
            case .done(let id): doneView(id)
            case .failed(let message): StudyErrorView(message: message, retry: { stage = .plan })
            }
        }
        .onAppear {
            context.pausePlayback()
            audioReady = context.lesson.hasAudioFile
        }
        .onDisappear {
            task?.cancel()
            download.cancel()
        }
    }

    private var planView: some View {
        let current = clips
        return List {
            Section {
                Text("Dersin ana noktalarının geçtiği yerler öğretmenin kendi sesinden kesilip tek bir bölümde birleştirilir; tekrar için kısa bir dinleme.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if points.isEmpty {
                Section { Text("Bu derste ana nokta yok; özet için ders notu gerekir.").foregroundStyle(.secondary) }
            } else if !audioReady {
                audioSection
            } else {
                Section {
                    Picker("En çok", selection: $limitMinutes) {
                        ForEach([5, 10, 15, 25], id: \.self) { Text("\($0) dk").tag($0) }
                    }
                    .modifier(AccessiblePickerStyle())
                    LabeledContent("Kesit", value: "\(current.count)")
                    LabeledContent("Süre", value: TeacherSummaryPlan.totalDuration(current).clockText)
                } header: {
                    Text("Özet süresi")
                } footer: {
                    if !current.isEmpty, isTrimmed(current) {
                        Text("Ana noktaların tümü sığmadı; kesitler derse yayılarak seçildi.")
                    }
                }
                if current.isEmpty {
                    Section { Text("Bu süre sınırına sığan kesit yok.").foregroundStyle(.secondary) }
                } else {
                    Section("Kesitler") {
                        ForEach(Array(current.enumerated()), id: \.offset) { _, clip in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(TranscriptFormat.timestamp(clip.start)) – \(TranscriptFormat.timestamp(clip.end))")
                                    .font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(.tint)
                                Text(StudyText.excerpt(ClipPlanner.paragraphs(in: clip, from: paragraphs).first?.text ?? "", maxChars: 110))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                    Section {
                        Button("Özet sesini oluştur") { build(current) }
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                    }
                }
            }
        }
    }

    /// Ders sesi indirilmemişse: indirme önerisi (mevcut indirme akışı).
    @ViewBuilder
    private var audioSection: some View {
        Section {
            switch download.phase {
            case .idle, .failed:
                Text("Öğretmenin sesinden kesit almak için dersin sesi cihaza indirilmiş olmalı.").font(.callout)
                if case .failed(let message) = download.phase { Text(message).font(.caption).foregroundStyle(.red) }
                if context.lesson.duration > LessonAudioDownload.maxDuration {
                    Text("Video 3 saatten uzun; sesi uygulamaya indirilemiyor.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Dersin sesini indir", systemImage: "arrow.down.circle") {
                        download.start(lesson: context.lesson, context: modelContext) { _ in audioReady = true }
                    }
                }
            case .preparing:
                HStack { ProgressView(); Text("Sunucu sesi hazırlıyor…").font(.callout) }
                Button("Vazgeç", role: .cancel) { download.cancel() }
            case .receiving(let fraction, _):
                if let fraction { ProgressView(value: fraction) } else { ProgressView() }
                Text("Ses indiriliyor…").font(.callout)
                Button("Vazgeç", role: .cancel) { download.cancel() }
            case .saving:
                HStack { ProgressView(); Text("Kaydediliyor…").font(.callout) }
            }
        }
    }

    private func doneView(_ id: UUID) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(.green)
            Text("Özet bölümü hazır").font(.title3.bold())
            Text("Kütüphanene yeni bölüm olarak eklendi; zaman çizelgesiyle dinleyebilirsin.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Kütüphanede aç") {
                dismiss()
                LessonEpisodes.open(id, from: context)
            }
            .buttonStyle(PrimaryButtonStyle())
            Button("Kapat") { dismiss() }.buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxHeight: .infinity)
    }

    private func build(_ clips: [ClipRange]) {
        guard let source = context.lesson.audioURL, context.lesson.hasAudioFile, context.lesson.modelContext != nil else {
            stage = .failed("Dersin sesi bulunamadı. Sesi yeniden indirmeyi dene.")
            audioReady = false
            return
        }
        stage = .building
        let lessonID = context.lesson.id
        let title = "Öğretmenin sesinden özet · \(context.lesson.title)"
        let notes = context.transcript.notes
        let chapters = context.transcript.chapters
        let paragraphs = self.paragraphs
        let episode = Episode(script: PodcastScript(title: title, summary: "", keyPoints: [], chapters: [], sourceNotes: ""),
                              settings: PodcastSettings(speechProvider: "apple"), sourceNames: [context.lesson.title], jobToken: "")
        let output = episode.directory.appending(path: "podcast.m4a")
        task = Task {
            do {
                let exported = try await TeacherAudio.export(source: source, clips: clips, gap: TeacherSummaryPlan.gap, to: output)
                try Task.checkCancellation()
                // Çizelge ve senaryo, sese gerçekten giren kesitlerden kurulur.
                let plan = TeacherSummaryPlan.build(clips: exported.clips, paragraphs: paragraphs, chapters: chapters,
                                                    fallbackTitle: "Ana noktalar")
                guard !plan.timeline.turns.isEmpty else { throw TeacherAudio.ExportError.nothingToExport }
                var timeline = plan.timeline
                timeline.duration = exported.duration > 0 ? exported.duration : timeline.duration
                episode.scriptData = (try? JSONEncoder().encode(PodcastScript(
                    title: title, summary: notes?.summary ?? "", keyPoints: (notes?.keyPoints ?? []).prefix(10).map(\.text),
                    chapters: plan.chapters, sourceNotes: ""))) ?? episode.scriptData
                episode.title = title
                episode.scenesTotal = plan.chapters.reduce(0) { $0 + $1.scenes.count }
                episode.scenesDone = episode.scenesTotal
                episode.audioFileName = "podcast.m4a"
                episode.timeline = timeline
                episode.duration = timeline.duration
                episode.jobToken = nil
                episode.status = .ready
                modelContext.insert(episode)
                try modelContext.save()
                LessonEpisodes.attach(episode.id, toLesson: lessonID, context: modelContext)
                stage = .done(episode.id)
            } catch {
                // Kayıt başarısızsa eklenen bölüm de silinir (yarım kayıt kalmasın).
                if episode.modelContext != nil {
                    modelContext.delete(episode)
                    try? modelContext.save()
                }
                EpisodeFiles.remove(episode: episode.id)
                if let message = StudyError.message(error) { stage = .failed(message) } else { stage = .plan }
            }
        }
    }
}
