import Photos
import SwiftUI

// #36: Çeviri ya da orijinal altyazıyı videoya gömen sunucu işi; sonuç Fotoğraflar'a kaydedilir ya da paylaşılır.

nonisolated enum SubtitleBuilder {
    /// Bir altyazı satırının en çok karakteri (ekranda iki satıra sığar).
    static let maxCueCharacters = 84
    static let minCueDuration = 0.8
    /// Sunucuya gidecek SRT için üst sınır (karakter).
    static let maxSRTCharacters = 600_000

    struct Cue: Equatable, Sendable {
        var start: Double
        var end: Double
        var text: String
    }

    /// Paragrafı cümle sınırlarında ≤ `maxCueCharacters` parçalara böler; süre karakter oranında dağıtılır.
    static func cues(text: String, start: Double, end: Double) -> [Cue] {
        let clean = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !clean.isEmpty else { return [] }
        let chunks = chunk(clean)
        let span = max(end - start, Double(chunks.count) * minCueDuration)
        let total = Double(chunks.reduce(0) { $0 + $1.count })
        var cursor = start
        return chunks.map { chunk in
            let length = span * Double(chunk.count) / max(1, total)
            defer { cursor += length }
            return Cue(start: cursor, end: cursor + max(length, minCueDuration), text: chunk)
        }
    }

    /// Cümlelere, sığmayan cümleleri kelime sınırında böler; kısa cümleler birleştirilir.
    static func chunk(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if ".!?…".contains(character) { sentences.append(current); current = "" }
        }
        if !current.isEmpty { sentences.append(current) }
        var chunks: [String] = []
        var line = ""
        func flush() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { chunks.append(trimmed) }
            line = ""
        }
        for sentence in sentences {
            for word in sentence.split(separator: " ", omittingEmptySubsequences: true) {
                if line.isEmpty {
                    line = String(word)
                } else if line.count + 1 + word.count <= maxCueCharacters {
                    line += " " + word
                } else {
                    flush()
                    line = String(word)
                }
            }
            // Cümle bittiğinde satır yeterince doluysa yeni satıra geç.
            if line.count >= maxCueCharacters * 2 / 3 { flush() }
        }
        flush()
        return chunks
    }

    /// Paragraflardan SRT (çeviri için; çeviride kelime zamanı yok).
    static func srt(paragraphs: [TranscriptParagraph]) -> String {
        render(paragraphs.flatMap { cues(text: $0.text, start: $0.start, end: $0.end) })
    }

    /// Orijinal: kısa parçalar olan `segments` varsa onlar, yoksa paragraflar.
    static func srt(original transcript: VideoTranscript) -> String {
        if !transcript.segments.isEmpty {
            return render(transcript.segments.map { Cue(start: $0.start, end: max($0.end, $0.start + minCueDuration), text: $0.text) })
        }
        return srt(paragraphs: transcript.paragraphs)
    }

    /// Seçime göre SRT: çeviri paragrafları ya da orijinal. Büyük transkriptlerde ana iş parçacığı dışında üretilir.
    @concurrent
    static func build(transcript: VideoTranscript, translated: Bool) async -> String {
        if translated, let translation = transcript.translation, !translation.paragraphs.isEmpty {
            return srt(paragraphs: translation.paragraphs)
        }
        return srt(original: transcript)
    }

    /// Ucuz denetim (SRT üretmeden): altyazı yapılacak metin var mı.
    static func hasContent(transcript: VideoTranscript, translated: Bool) -> Bool {
        if translated, !(transcript.translation?.paragraphs.isEmpty ?? true) { return true }
        return !transcript.segments.isEmpty || !transcript.paragraphs.isEmpty
    }

    static func render(_ cues: [Cue]) -> String {
        var out = ""
        var number = 0
        var total = 0
        for cue in cues {
            let text = cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            number += 1
            let block = "\(number)\n\(VideoTime.srt(cue.start)) --> \(VideoTime.srt(cue.end))\n\(text)\n\n"
            if total + block.count > maxSRTCharacters { break }
            total += block.count
            out += block
        }
        return out
    }
}

/// Hazırlanan altyazılı videonun önbellekteki yeri: `Caches/Subtitled/<dersID>.mp4` + yanında ayarları tutan `<dersID>.json`.
/// Sayfa kapatılıp açıldığında dakikalar süren iş baştan çalışmasın diye son sonuç buradan bulunur.
nonisolated enum SubtitledCache {
    struct Meta: Codable, Equatable, Sendable {
        var translated: Bool
        var quality: Int
        var createdAt: Date
    }

    static func folder(root: URL = .cachesDirectory) -> URL {
        root.appending(path: "Subtitled", directoryHint: .isDirectory)
    }

    static func url(lesson: UUID, root: URL = .cachesDirectory) -> URL {
        folder(root: root).appending(path: "\(lesson.uuidString).mp4")
    }

    static func metaURL(lesson: UUID, root: URL = .cachesDirectory) -> URL {
        folder(root: root).appending(path: "\(lesson.uuidString).json")
    }

    /// Önceden hazırlanmış dosya (boş dosya sayılmaz). Meta eksik ya da bozuksa yalnız dosya döner.
    static func existing(lesson: UUID, root: URL = .cachesDirectory) -> (url: URL, meta: Meta?)? {
        let file = url(lesson: lesson, root: root)
        guard let size = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64, size > 0 else { return nil }
        let meta = (try? Data(contentsOf: metaURL(lesson: lesson, root: root))).flatMap { try? JSONDecoder().decode(Meta.self, from: $0) }
        return (file, meta)
    }

    static func saveMeta(_ meta: Meta, lesson: UUID, root: URL = .cachesDirectory) {
        guard let data = try? JSONEncoder().encode(meta) else { return }
        try? FileManager.default.createDirectory(at: folder(root: root), withIntermediateDirectories: true)
        try? data.write(to: metaURL(lesson: lesson, root: root), options: .atomic)
    }

    /// "Türkçe çeviri · 480p" (göreli tarihi görünüm ekler).
    static func summary(_ meta: Meta) -> String {
        "\(meta.translated ? "Türkçe çeviri" : "Orijinal altyazı") · \(meta.quality)p"
    }
}

struct SubtitledVideoView: View {
    var context: LessonContext

    @Environment(\.dismiss) private var dismiss
    @State private var runner = MediaJobRunner()
    @State private var useTranslation = true
    @State private var quality = 480
    @State private var resultURL: URL?
    @State private var resultMeta: SubtitledCache.Meta?
    @State private var checkedCache = false
    @State private var confirmClose = false
    @State private var savedToPhotos = false
    @State private var saveError: String?
    @State private var showShare = false
    @State private var preparing = false

    private var lesson: VideoLesson { context.lesson }
    private var hasTranslation: Bool { !(context.transcript.translation?.paragraphs.isEmpty ?? true) }
    private var canBuild: Bool { !lesson.url.isEmpty && !lesson.videoID.hasPrefix("upload-") }

    /// Her çizimde SRT üretilmez: yalnız ucuz boşluk denetimi (SRT `start()`'ta kurulur).
    private var hasSubtitleText: Bool {
        SubtitleBuilder.hasContent(transcript: context.transcript, translated: useTranslation && hasTranslation)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !canBuild {
                    Section {
                        Label("Bu ders yüklediğin bir kayıttan oluştu; altyazı gömülecek bir video yok.", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if let resultURL {
                    resultSection(resultURL)
                } else {
                    Section {
                        if hasTranslation {
                            Picker("Altyazı", selection: $useTranslation) {
                                Text("Türkçe çeviri").tag(true)
                                Text("Orijinal").tag(false)
                            }
                            .modifier(AccessiblePickerStyle())
                            .disabled(runner.isRunning)
                        } else {
                            LabeledContent("Altyazı", value: "Orijinal")
                        }
                        Picker("Kalite", selection: $quality) {
                            Text("360p").tag(360)
                            Text("480p").tag(480)
                        }
                        .modifier(AccessiblePickerStyle())
                        .disabled(runner.isRunning)
                    } footer: {
                        Text(hasTranslation ? "Videoyu sunucu indirir, altyazıyı videoya gömer ve sana gönderir."
                                            : "Bu derste Türkçe çeviri yok; orijinal transkript altyazı olur. Çeviri için videoyu ‘Türkçe’ye çevir’ seçeneğiyle işle.")
                    }
                    progressSection
                }
            }
            .navigationTitle("Altyazılı video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { if runner.isRunning { confirmClose = true } else { dismiss() } }
                }
            }
            .onAppear {
                guard !checkedCache else { return }
                checkedCache = true
                useTranslation = hasTranslation
                // Önceki oturumda hazırlanan dosya duruyorsa doğrudan sonucu göster.
                if canBuild, let cached = SubtitledCache.existing(lesson: lesson.id) {
                    resultURL = cached.url
                    resultMeta = cached.meta
                }
            }
            .onDisappear { runner.cancel() }
            .interactiveDismissDisabled(runner.isRunning)
            .confirmationDialog("İşlem sürüyor", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("Durdur ve kapat", role: .destructive) {
                    runner.cancel()
                    dismiss()
                }
                Button("Devam et", role: .cancel) {}
            } message: {
                Text("Sayfayı kapatırsan altyazılı videonun hazırlanması durur.")
            }
            .sheet(isPresented: $showShare) {
                if let resultURL { ShareSheet(items: [resultURL]) }
            }
        }
        .debugNarrowScreen()
    }

    @ViewBuilder
    private var progressSection: some View {
        Section {
            switch runner.phase {
            case .idle, .failed:
                Button {
                    start()
                } label: {
                    Label("Hazırla", systemImage: "captions.bubble.fill").font(.headline).frame(maxWidth: .infinity)
                }
                .disabled(!hasSubtitleText || preparing)
                if case .failed(let message) = runner.phase {
                    Label(message, systemImage: "xmark.octagon").font(.footnote).foregroundStyle(.red)
                } else if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red)
                }
            case .server, .download, .done:
                VStack(alignment: .leading, spacing: 8) {
                    Text(runner.phase == .download ? "Telefona indiriliyor" : "Sunucuda hazırlanıyor").font(.subheadline.weight(.semibold))
                    ProgressView(value: runner.progress)
                    HStack {
                        Text(runner.phase == .download && runner.totalBytes > 0
                             ? "\(ByteFormat.string(runner.receivedBytes)) / \(ByteFormat.string(runner.totalBytes))"
                             : runner.message)
                            .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                        Spacer()
                        Text("%\(Int((runner.progress * 100).rounded()))").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                Button("Durdur", systemImage: "stop.circle", role: .destructive) { runner.cancel() }
                    .disabled(!runner.isRunning)
            }
        }
    }

    private func resultSection(_ url: URL) -> some View {
        Section {
            Label("Altyazılı video hazır", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            if let resultMeta {
                Text("\(SubtitledCache.summary(resultMeta)) · \(resultMeta.createdAt.formatted(.relative(presentation: .named)))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let bytes = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 {
                LabeledContent("Boyut", value: ByteFormat.string(bytes))
            }
            ForEach(runner.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            }
            Button {
                Task { await saveToPhotos(url) }
            } label: {
                Label(savedToPhotos ? "Fotoğraflar’a kaydedildi" : "Fotoğraflar’a kaydet", systemImage: savedToPhotos ? "checkmark" : "photo.badge.plus")
            }
            .disabled(savedToPhotos)
            Button("Paylaş", systemImage: "square.and.arrow.up") { showShare = true }
            if let saveError { Label(saveError, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red) }
            // Dosya silinmez: yeni video inene kadar eskisi önbellekte kalır.
            Button("Yeniden hazırla", systemImage: "arrow.clockwise") {
                resultURL = nil
                resultMeta = nil
                saveError = nil
                savedToPhotos = false
                runner.reset()
            }
        } footer: {
            Text("Farklı altyazı ya da kalite için yeniden hazırlayabilirsin; yenisi inene kadar bu video durur.")
        }
    }

    private func start() {
        guard !preparing else { return }
        saveError = nil
        savedToPhotos = false
        preparing = true
        let transcript = context.transcript
        let translated = useTranslation && hasTranslation
        let url = lesson.url
        let title = lesson.title
        let quality = quality
        let id = lesson.id
        Task {
            let srt = await SubtitleBuilder.build(transcript: transcript, translated: translated)
            preparing = false
            guard !srt.isEmpty else {
                saveError = "Altyazı metni boş; video hazırlanamadı."
                return
            }
            let request = MediaStartRequest(kind: .subtitled, url: url, quality: quality, srt: srt, lessonTitle: title,
                                            allowOther: ImportLinks.needsAllowOther(url) ? true : nil)
            try? FileManager.default.createDirectory(at: SubtitledCache.folder(), withIntermediateDirectories: true)
            runner.begin(request, destination: SubtitledCache.url(lesson: id)) { url in
                let meta = SubtitledCache.Meta(translated: translated, quality: quality, createdAt: .now)
                SubtitledCache.saveMeta(meta, lesson: id)
                resultMeta = meta
                resultURL = url
            }
        }
    }

    private func saveToPhotos(_ url: URL) async {
        saveError = nil
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveError = "Fotoğraflar’a ekleme izni verilmedi. Ayarlar’dan izin verebilirsin."
            return
        }
        do {
            try await Self.addToPhotos(url)
            savedToPhotos = true
        } catch {
            saveError = "Fotoğraflar’a kaydedilemedi: \(error.localizedDescription)"
        }
    }

    private nonisolated static func addToPhotos(_ url: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}
