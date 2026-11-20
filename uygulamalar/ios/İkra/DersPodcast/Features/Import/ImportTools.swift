import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Öneri 15: web sayfası ve YouTube

struct LinkImportSheet: View {
    var onAdd: (ImportedSource) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var loading = false
    @State private var error: String?
    @State private var showStudio = false

    private var isYouTube: Bool {
        guard let host = URL(string: link.trimmingCharacters(in: .whitespaces))?.host()?.lowercased() else { return false }
        return host.contains("youtube.com") || host.contains("youtu.be")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Panodan yapıştır", systemImage: "doc.on.clipboard") {
                        if let pasted = UIPasteboard.general.string { link = pasted.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                } footer: {
                    Text(isYouTube ? "YouTube videosundaki konuşmalar yazıya dökülür (uzun videolar 1–2 dakika sürebilir)."
                                   : "Makalenin ana metni menü ve reklamlar ayıklanarak alınır.")
                }
                if isYouTube {
                    Section {
                        Button {
                            showStudio = true
                        } label: {
                            Label("YouTube Ders Stüdyosu’nda aç (zaman damgalı transkript, notlar, kareler)",
                                  systemImage: "play.rectangle.on.rectangle")
                        }
                    } footer: {
                        Text("Video ‘YouTube dersleri’ne kaydedilir; transkripti bu podcast’e de kaynak olarak eklenir (oynatma listesinde her video ayrı kaynak olur). Aşağıdaki ‘Ekle’ yalnızca düz metni alır.")
                    }
                }
                Section {
                    Button {
                        Task { await fetch() }
                    } label: {
                        HStack { if loading { ProgressView() }; Text(loading ? "Alınıyor…" : "Ekle") }
                    }
                    .disabled(loading || URL(string: link)?.scheme?.hasPrefix("http") != true)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Bağlantıdan ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } } }
            .sheet(isPresented: $showStudio) {
                // Oynatma listesinde işlenen tüm dersler kaynak olur (yalnızca ilki değil).
                YouTubeImportView(initialURL: link.trimmingCharacters(in: .whitespacesAndNewlines),
                                  onFinish: { addLessons([$0]) },
                                  onFinishBatch: { addLessons($0) })
            }
        }
    }

    /// Stüdyoda hazırlanan derslerin transkriptlerini kaynak olarak ekler (çözme ana iş parçacığı dışında).
    private func addLessons(_ lessons: [VideoLesson]) {
        let names = lessons.map { $0.title.isEmpty ? link : $0.title }
        let datas = lessons.map(\.transcriptData)
        showStudio = false
        Task {
            let texts = await LessonFiles.plainTexts(datas)
            for (name, text) in zip(names, texts) where text.count > 40 {
                onAdd(ImportedSource(name: name, kind: .text(text)))
            }
            dismiss()
        }
    }

    private func fetch() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let result = try await APIClient.shared.extract(ExtractRequest(kind: isYouTube ? "youtube" : "url",
                                                                         url: link.trimmingCharacters(in: .whitespaces)))
            guard result.text.count > 40 else { throw APIError(status: 0, code: "empty", message: "Bu bağlantıdan okunabilir metin çıkmadı.") }
            onAdd(ImportedSource(name: result.title.isEmpty ? link : result.title, kind: .text(result.text)))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Öneri 16: ders kaydından podcast

/// Ders kaydı sınırları (saf; test edilir).
nonisolated enum LectureLimit {
    /// `maxBytes`'a `bitrate` (bit/sn) ile sığan kayıt süresi (sn), emniyet payıyla: tek dosya sunucu sınırını aşmasın diye
    /// kayıt bu sürede yeni parçaya geçer. 13,5 MiB ve 32 kbps için yaklaşık 53 dk.
    static func segmentSeconds(maxBytes: Int, bitrate: Int = 32_000, safety: Double = 0.9) -> Double {
        guard maxBytes > 0, bitrate > 0 else { return 0 }
        return Double(maxBytes) * 8 / Double(bitrate) * min(max(safety, 0), 1)
    }

    /// Yaklaşık 2 saniyeden kısa parça (ör. kayıt parça sınırının hemen ardından bitirildi) gönderilmez.
    static func isNegligible(bytes: Int, bitrate: Int = 32_000) -> Bool { bytes < bitrate / 8 * 2 }

    /// "Vazgeç" onay ister mi: süren ve birkaç saniyeyi aşmış kayıt tek dokunuşla bırakılmaz.
    static func needsDiscardConfirmation(isRecording: Bool, elapsed: TimeInterval) -> Bool { isRecording && elapsed > 5 }

    /// Sınırı aşan dosyanın hata metni. Süre verilmez: süre dosyanın bit hızına bağlıdır (128 kbps MP3'te yaklaşık 14 dk).
    static func tooLargeMessage(bytes: Int, maxBytes: Int, recorded: Bool) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        let limit = ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .file)
        return recorded
            ? "Kayıt \(size); tek parçada en fazla \(limit) gönderilebilir."
            : "Ses dosyası \(size); en fazla \(limit) gönderilebilir. Dosyayı bölüp parçaları ayrı ayrı ekle."
    }
}

/// Kalıcı ders kaydı dosyaları (Application Support/Recordings). Kayıt kendiliğinden silinmez: yazıya dökme başarısız
/// olursa ya da metin podcast'e dönüşmeden kaybolursa ses yeniden gönderilebilir; silmek kullanıcının kararıdır.
nonisolated enum LectureRecordings {
    nonisolated struct File: Equatable, Sendable {
        var url: URL
        var modified: Date
        var bytes: Int
    }

    /// Bir kayıt: aynı kök adlı parçalar (uzun kayıt parçalara bölünür), parça sırasıyla.
    nonisolated struct Session: Identifiable, Equatable, Sendable {
        var stem: String
        var parts: [URL]
        var modified: Date
        var bytes: Int
        var id: String { stem }
    }

    static var directory: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func stem(now: Date = .now) -> String {
        "ders-kaydi-" + now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "-")
    }

    /// İlk parçanın adı eski kayıtlarla aynıdır ("kök.m4a"); sonrakiler "kök-p2.m4a", "kök-p3.m4a"…
    static func fileName(stem: String, part: Int) -> String { part <= 1 ? "\(stem).m4a" : "\(stem)-p\(part).m4a" }

    /// Dosya adından kök ad ve parça numarası (ek yoksa 1).
    static func parse(_ url: URL) -> (stem: String, part: Int) {
        let name = url.deletingPathExtension().lastPathComponent
        guard let mark = name.range(of: "-p", options: .backwards), let part = Int(name[mark.upperBound...]), part > 1 else { return (name, 1) }
        return (String(name[..<mark.lowerBound]), part)
    }

    /// Klasördeki kayıt dosyaları (.m4a), en yeni önce.
    static func files(in directory: URL) -> [File] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls.filter { $0.pathExtension.lowercased() == "m4a" }.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return File(url: url, modified: values?.contentModificationDate ?? .distantPast, bytes: values?.fileSize ?? 0)
        }
        .sorted { ($0.modified, $0.url.lastPathComponent) > ($1.modified, $1.url.lastPathComponent) }
    }

    /// Klasörde duran kayıt dosyaları, en yeni önce.
    static func pending(in directory: URL) -> [URL] { files(in: directory).map(\.url) }

    /// Dosyaları kayıtlara gruplar (saf; test edilir): en yeni kayıt önce, parçalar numara sırasıyla.
    static func sessions(_ files: [File]) -> [Session] {
        var byStem: [String: [(part: Int, file: File)]] = [:]
        for file in files {
            let parsed = parse(file.url)
            byStem[parsed.stem, default: []].append((parsed.part, file))
        }
        return byStem.map { stem, items in
            Session(stem: stem, parts: items.sorted { $0.part < $1.part }.map { $0.file.url },
                    modified: items.map { $0.file.modified }.max() ?? .distantPast, bytes: items.reduce(0) { $0 + $1.file.bytes })
        }
        .sorted { ($0.modified, $0.stem) > ($1.modified, $1.stem) }
    }

    /// Gösterim sırası (saf; test edilir): gönderilmemiş kayıtlar önce; her grupta verilen sıra korunur.
    static func ordered(_ sessions: [Session], sent: Set<String>) -> [Session] {
        sessions.filter { !sent.contains($0.stem) } + sessions.filter { sent.contains($0.stem) }
    }

    static let sentKey = "lectureRecordings.sent"

    /// Yazıya dökülüp kaynak olarak eklenmiş kayıtların kök adları.
    static func sent(in defaults: UserDefaults = .standard) -> Set<String> { Set(defaults.stringArray(forKey: sentKey) ?? []) }

    static func markSent(_ stem: String, in defaults: UserDefaults = .standard) {
        var stems = sent(in: defaults)
        if stems.insert(stem).inserted { defaults.set(stems.sorted(), forKey: sentKey) }
    }

    static func forget(_ stem: String, in defaults: UserDefaults = .standard) {
        var stems = sent(in: defaults)
        guard stems.remove(stem) != nil else { return }
        if stems.isEmpty { defaults.removeObject(forKey: sentKey) } else { defaults.set(stems.sorted(), forKey: sentKey) }
    }

    /// Kaydın satırda gösterilen durumu. `legacy`: gönderim durumu izlenmeye başlamadan önce klasörde duran kayıt.
    nonisolated enum Status: Equatable, Sendable {
        case unsent, legacy, sent

        var title: String {
            switch self {
            case .unsent: "Gönderilmemiş kayıt"
            case .legacy: "Önceki kayıt"
            case .sent: "Yazıya dökülmüş kayıt"
            }
        }

        var symbol: String {
            switch self {
            case .unsent: "tray.and.arrow.up"
            case .legacy: "clock.arrow.circlepath"
            case .sent: "checkmark.circle"
            }
        }

        /// Durumu bilinmeyen kayıt yanlışlıkla ikinci kez gönderilmesin diye açıklama.
        var note: String? { self == .legacy ? "Bu sürümden önce kaydedildi; daha önce yazıya dökülmüş olabilir." : nil }
    }

    static let legacyKey = "lectureRecordings.legacy"

    /// Gönderim durumu izlenmeye başlamadan önce klasörde duran kayıtların kök adları. Önceki sürüm yazıya dökülen kaydı
    /// da klasörde bırakırdı ve durumunu tutmazdı: bunlar "gönderilmemiş" sayılmaz. Anahtar yokken (ilk çağrı) o an
    /// klasörde duran, `sent`'te olmayan kayıtlar bir kez yazılır; sonraki kayıtlar bu kümeye girmez. Boş küme de
    /// yazılır: anahtarın yokluğu "henüz bakılmadı" demektir.
    static func legacy(existing stems: [String], in defaults: UserDefaults = .standard) -> Set<String> {
        if let saved = defaults.stringArray(forKey: legacyKey) { return Set(saved) }
        let legacy = Set(stems).subtracting(sent(in: defaults))
        defaults.set(legacy.sorted(), forKey: legacyKey)
        return legacy
    }

    /// Durum (saf; test edilir): yazıya dökülen kayıt, önceki sürümden kalmış olsa da "yazıya dökülmüş"tür.
    static func status(_ stem: String, sent: Set<String>, legacy: Set<String>) -> Status {
        sent.contains(stem) ? .sent : legacy.contains(stem) ? .legacy : .unsent
    }

    /// Yalnız kullanıcının onayıyla çağrılır.
    static func delete(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }
}

@Observable
final class LectureRecorder: NSObject {
    private(set) var isRecording = false
    private(set) var isPaused = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var level: Float = 0
    private var recorder: AVAudioRecorder?
    private var timer: Task<Void, Never>?
    /// Kalıcı klasör: yazıya dökme başarısız olsa da kayıt kaybolmaz; her kayıt yeni dosya. Süren parçanın dosyası.
    private(set) var url = LectureRecorder.newURL()
    /// Biten parçalar (sırayla); kayıt parça sınırına gelince yeni dosyayla sürer.
    private(set) var segments: [URL] = []
    @ObservationIgnored private var stem = ""
    /// Biten parçaların toplam süresi (gösterilen süre = bu + süren parçanın konumu).
    @ObservationIgnored private var finishedSeconds: TimeInterval = 0
    @ObservationIgnored private var segmentSeconds = LectureRecorder.defaultSegmentSeconds
    /// Kullanıcı elle duraklattı: kesinti (arama, alarm) bitince kayıt kendiliğinden sürdürülmez.
    @ObservationIgnored private var userPaused = false
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

    static let bitrate = 32_000

    /// Yalnız Debug: `-lectureSegment=20` parça sınırını kısaltır (bölünmeyi yaklaşık 53 dakika beklemeden denemek için).
    static var defaultSegmentSeconds: Double {
        DebugArg.value("lectureSegment").flatMap { Double($0) }.map { max(5, $0) }
            ?? LectureLimit.segmentSeconds(maxBytes: LectureRecordSheet.maxRawBytes, bitrate: bitrate)
    }

    static func newURL(stem: String = LectureRecordings.stem(), part: Int = 1) -> URL {
        LectureRecordings.directory.appending(path: LectureRecordings.fileName(stem: stem, part: part))
    }

    /// 16 kHz mono AAC 32 kbps ≈ 14,4 MB/saat. Sunucu base64 olarak 18 MB kabul eder → ham ≈ 13,5 MB.
    private static func makeRecorder(_ url: URL) throws -> AVAudioRecorder {
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000,
                                       AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: bitrate]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        return recorder
    }

    func start() async -> String? {
        guard await AVAudioApplication.requestRecordPermission() else { return "Mikrofon izni verilmedi." }
        guard recorder == nil else { return nil }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            stem = LectureRecordings.stem()
            url = Self.newURL(stem: stem)
            let recorder = try Self.makeRecorder(url)
            recorder.record()
            self.recorder = recorder
        } catch {
            return "Kayıt başlatılamadı: \(error.localizedDescription)"
        }
        segments = []
        finishedSeconds = 0
        segmentSeconds = Self.defaultSegmentSeconds
        elapsed = 0
        userPaused = false
        isPaused = false
        isRecording = true
        observeInterruptions()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
        return nil
    }

    private func tick() {
        guard let recorder else { return }
        recorder.updateMeters()
        elapsed = finishedSeconds + recorder.currentTime
        level = max(0, min(1, (recorder.averagePower(forChannel: 0) + 50) / 50))
        if recorder.currentTime >= segmentSeconds { rollover() }
    }

    /// Parça sınırı: yeni dosya önceden hazırlanır, süren dosya kapatılır ve kayıt yenisiyle sürer (aradaki boşluk en aza iner).
    private func rollover() {
        guard let current = recorder else { return }
        let nextURL = Self.newURL(stem: stem, part: segments.count + 2)
        guard let next = try? Self.makeRecorder(nextURL), next.prepareToRecord() else {
            // Yeni dosya açılamadı: ses kaybolmasın diye kayıt eldeki dosyayla sürer; bu kayıtta bir daha denenmez.
            segmentSeconds = .infinity
            return
        }
        finishedSeconds += current.currentTime
        current.stop()
        segments.append(url)
        url = nextURL
        recorder = next
        if !isPaused { isPaused = !next.record() }
    }

    func togglePause() {
        guard let recorder else { return }
        if isPaused {
            // Kesintiden sonra ses oturumu kapalı kalmış olabilir.
            try? AVAudioSession.sharedInstance().setActive(true)
            userPaused = false
            isPaused = !recorder.record()
        } else {
            recorder.pause()
            userPaused = true
            isPaused = true
        }
    }

    /// Kaydı bitirir; kayıt sürüyorduysa parça dosyalarını sırayla döndürür (sürmüyorduysa boş).
    @discardableResult
    func stop() -> [URL] {
        timer?.cancel()
        timer = nil
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        guard let recorder else { return [] }
        recorder.stop()
        self.recorder = nil
        isRecording = false
        isPaused = false
        userPaused = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return segments + [url]
    }

    private func observeInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            MainActor.assumeIsolated { self?.interruption(type) }
        }
    }

    /// Arama ya da alarm kaydı sistemce duraklatır: ekran "Duraklatıldı" gösterir; kesinti bitince kullanıcı elle
    /// duraklatmadıysa kayıt sürdürülür (sürdürülemezse "Devam" ile elle başlatılabilir).
    private func interruption(_ type: AVAudioSession.InterruptionType?) {
        guard let recorder else { return }
        switch type {
        case .began:
            recorder.pause()
            isPaused = true
        case .ended:
            guard !userPaused else { return }
            try? AVAudioSession.sharedInstance().setActive(true)
            isPaused = !recorder.record()
        default:
            break
        }
    }
}

struct LectureRecordSheet: View {
    var onAdd: (ImportedSource) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = LectureRecorder()
    @State private var importing = false
    @State private var transcribing = false
    /// Çok parçalı kayıtta gönderilen parça ("2/3").
    @State private var partProgress: String?
    @State private var error: String?
    /// Yarıda kalan gönderim: kalan parçalar ve o ana dek gelen metinler ("tekrar gönder" kaldığı parçadan sürer).
    @State private var failed: Upload?
    @State private var confirmDiscard = false
    /// Diskte duran önceki kayıtlar (gönderilmemişler önce) ve yazıya dökülmüş olanların kök adları.
    @State private var saved: [LectureRecordings.Session] = []
    @State private var sentStems: Set<String> = []
    /// Gönderim durumu izlenmeden önce kaydedilmiş, durumu bilinmeyen kayıtlar (bkz. `LectureRecordings.legacy`).
    @State private var legacyStems: Set<String> = []
    @State private var sessionToDelete: LectureRecordings.Session?

    /// Sunucu base64 uzunluğunu 18 MiB ile sınırlar; ham veri sınırı bunun 3/4'ü.
    static let maxRawBytes = 18 * 1024 * 1024 * 3 / 4

    /// Yazıya dökülecek ses: uygulamanın kaydı (parçalarıyla; `stem` dolu) ya da seçilen ses dosyası.
    struct Upload {
        var name: String
        var parts: [URL]
        var texts: [String] = []
        var total: Int
        var stem: String?
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Sığıyorsa eskisi gibi ortalanır; hata ve bekleyen kayıt satırıyla taşarsa kaydırılır.
                ViewThatFits(in: .vertical) {
                    VStack(spacing: 22) {
                        Spacer(minLength: 0)
                        info
                        Spacer(minLength: 0)
                    }
                    ScrollView {
                        VStack(spacing: 22) { info }.padding(.vertical, 16)
                    }
                }
                // 320 nokta genişlikte iki düğme yan yana sığmaz: alt alta ve tam genişlikte.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { controls(stacked: false) }
                    VStack(spacing: 10) { controls(stacked: true) }.controlSize(.large)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("Ders kaydı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") {
                        if LectureLimit.needsDiscardConfirmation(isRecording: recorder.isRecording, elapsed: recorder.elapsed) {
                            confirmDiscard = true
                        } else {
                            discardAndClose()
                        }
                    }
                }
            }
            .interactiveDismissDisabled(recorder.isRecording || transcribing)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
                guard case let .success(url) = result else { return }
                Task { await transcribe(Upload(name: url.deletingPathExtension().lastPathComponent, parts: [url], total: 1)) }
            }
            .confirmationDialog("Kayıt silinsin mi?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Kaydı sil ve çık", role: .destructive) { discardAndClose() }
                Button("Kayda devam et", role: .cancel) {}
            } message: {
                Text("\(recorder.elapsed.clockText) süren kayıt yazıya dökülmeden silinir.")
            }
            .confirmationDialog("Kayıt silinsin mi?",
                                isPresented: Binding(get: { sessionToDelete != nil }, set: { if !$0 { sessionToDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Sil", role: .destructive) {
                    guard let session = sessionToDelete else { return }
                    LectureRecordings.delete(session.parts)
                    LectureRecordings.forget(session.stem)
                    reloadSaved()
                }
            } message: {
                Text("Ses dosyası bu cihazdan kalıcı olarak silinir.")
            }
            .task { reloadSaved() }
        }
    }

    @ViewBuilder
    private var info: some View {
        Text(recorder.elapsed.clockText).font(.system(size: 54, weight: .semibold, design: .rounded).monospacedDigit())
        Capsule().fill(Theme.warmGradient)
            .frame(width: 40 + CGFloat(recorder.level) * 220, height: 8)
            .animation(.easeOut(duration: 0.2), value: recorder.level)
        Text(recorder.isRecording ? (recorder.isPaused ? "Duraklatıldı" : "Kaydediliyor") : "Hocanın anlatımını kaydet; kayıt yazıya dökülüp düzenli bir ders podcast'ine dönüşür.")
            .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 24)
        if recorder.isRecording, !recorder.segments.isEmpty {
            Text("Uzun kayıt \(recorder.segments.count + 1) parça olarak saklanıyor; yazıya dökülünce tek kaynak olur.")
                .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 24)
        }
        if transcribing {
            HStack { ProgressView(); Text(partProgress.map { "Kayıt yazıya dökülüyor… (parça \($0))" } ?? "Kayıt yazıya dökülüyor…") }
        }
        if let error {
            Text(error).foregroundStyle(.red).multilineTextAlignment(.center).padding(.horizontal, 24)
            if let failed, !transcribing {
                Button("Aynı kaydı tekrar gönder", systemImage: "arrow.clockwise") {
                    Task { await transcribe(failed) }
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
            }
        }
        if !recorder.isRecording, !transcribing {
            // Şu an hata olarak gösterilen kayıt ayrıca listelenmez.
            let shown = saved.filter { $0.stem != failed?.stem }
            if let session = shown.first { savedRow(session, others: shown.count - 1) }
        }
    }

    @ViewBuilder
    private func controls(stacked: Bool) -> some View {
        if recorder.isRecording {
            Button { recorder.togglePause() } label: { controlLabel(recorder.isPaused ? "Devam" : "Duraklat", stacked: stacked) }
                .buttonStyle(.bordered)
            Button { finish() } label: { controlLabel("Bitir ve ekle", stacked: stacked) }
                .buttonStyle(.borderedProminent)
        } else {
            Button {
                Task {
                    let problem = await recorder.start()
                    error = problem
                    // Yeni kayıt başladı: önceki başarısız gönderim diskte durur, sonraki açılışta listelenir.
                    if problem == nil { failed = nil }
                }
            } label: {
                controlLabel("Kayda başla", symbol: "record.circle", stacked: stacked)
            }
            .buttonStyle(.borderedProminent)
            .disabled(transcribing)
            Button { importing = true } label: { controlLabel("Ses dosyası seç", symbol: "waveform", stacked: stacked) }
                .buttonStyle(.bordered)
                .disabled(transcribing)
        }
    }

    private func controlLabel(_ title: String, symbol: String? = nil, stacked: Bool) -> some View {
        Group {
            if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
        }
        .lineLimit(1)
        .frame(maxWidth: stacked ? .infinity : nil)
    }

    private func savedRow(_ session: LectureRecordings.Session, others: Int) -> some View {
        let status = LectureRecordings.status(session.stem, sent: sentStems, legacy: legacyStems)
        let sent = status == .sent
        return VStack(alignment: .leading, spacing: 8) {
            Label(status.title, systemImage: status.symbol)
                .font(.subheadline.weight(.semibold))
            Text(Self.savedDetail(session, others: others)).font(.caption).foregroundStyle(.secondary)
            if let note = status.note { Text(note).font(.caption).foregroundStyle(.secondary) }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { savedButtons(session, sent: sent) }
                VStack(alignment: .leading, spacing: 8) { savedButtons(session, sent: sent) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func savedButtons(_ session: LectureRecordings.Session, sent: Bool) -> some View {
        Button(sent ? "Yeniden gönder" : "Gönder", systemImage: "arrow.up.circle") {
            Task { await transcribe(Upload(name: Self.recordingName(session.modified), parts: session.parts, total: session.parts.count, stem: session.stem)) }
        }
        .buttonStyle(.bordered)
        .frame(minHeight: 44)
        Button("Sil", systemImage: "trash", role: .destructive) { sessionToDelete = session }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
    }

    /// "6 Eki 2026 14:05 · 12,4 MB · 2 parça · 1 kayıt daha"
    static func savedDetail(_ session: LectureRecordings.Session, others: Int) -> String {
        var parts = [session.modified.formatted(date: .abbreviated, time: .shortened),
                     ByteCountFormatter.string(fromByteCount: Int64(session.bytes), countStyle: .file)]
        if session.parts.count > 1 { parts.append("\(session.parts.count) parça") }
        if others > 0 { parts.append("\(others) kayıt daha") }
        return parts.joined(separator: " · ")
    }

    static func recordingName(_ date: Date = .now) -> String { "Ders kaydı · \(date.formatted(date: .abbreviated, time: .shortened))" }

    private func reloadSaved() {
        sentStems = LectureRecordings.sent()
        let sessions = LectureRecordings.sessions(LectureRecordings.files(in: LectureRecordings.directory))
        legacyStems = LectureRecordings.legacy(existing: sessions.map(\.stem))
        saved = LectureRecordings.ordered(sessions, sent: sentStems)
    }

    private func finish() {
        let parts = recorder.stop()
        guard let first = parts.first else { return }
        Task { await transcribe(Upload(name: Self.recordingName(), parts: parts, total: parts.count, stem: LectureRecordings.parse(first).stem)) }
    }

    /// "Vazgeç": süren kayıt bırakılır ve dosyaları silinir (uzun kayıtta önce onay alınır); kayıt sürmüyorsa yalnız kapanır.
    private func discardAndClose() {
        LectureRecordings.delete(recorder.stop())
        dismiss()
    }

    /// Parçaları sırayla yazıya döker ve tek kaynak olarak ekler. Bir parça başarısız olursa kalan parçalar ve o ana dek
    /// gelen metinler `failed`'de tutulur: yeniden gönderim baştan değil, kaldığı parçadan sürer.
    private func transcribe(_ upload: Upload) async {
        transcribing = true
        error = nil
        failed = nil
        defer {
            transcribing = false
            partProgress = nil
        }
        var remaining = upload
        do {
            while let url = remaining.parts.first {
                if upload.total > 1 { partProgress = "\(upload.total - remaining.parts.count + 1)/\(upload.total)" }
                if let text = try await Self.extract(url, recorded: upload.stem != nil, skipNegligible: upload.total > 1) {
                    remaining.texts.append(text)
                }
                remaining.parts.removeFirst()
            }
            let text = remaining.texts.joined(separator: "\n\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw APIError(status: 0, code: "empty", message: "Kayıttan okunabilir metin çıkmadı.")
            }
            onAdd(ImportedSource(name: upload.name, kind: .text(text)))
            // Ses silinmez, yalnız "yazıya döküldü" diye işaretlenir (metin podcast'e dönüşmeden kaybolursa yeniden gönderilebilsin).
            if let stem = upload.stem { LectureRecordings.markSent(stem) }
            dismiss()
        } catch {
            self.error = error.localizedDescription
            // Hiç parça kalmadıysa (yalnız metin boş çıktı) kayıt baştan gönderilir.
            failed = remaining.parts.isEmpty ? upload : remaining
            reloadSaved()
        }
    }

    /// Tek ses dosyasını yazıya döker; çok parçalı kayıtta yok sayılacak kadar kısa parça için nil.
    private static func extract(_ url: URL, recorded: Bool, skipNegligible: Bool) async throws -> String? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        if skipNegligible, LectureLimit.isNegligible(bytes: data.count) { return nil }
        guard data.count <= maxRawBytes else {
            throw APIError(status: 0, code: "too_large", message: LectureLimit.tooLargeMessage(bytes: data.count, maxBytes: maxRawBytes, recorded: recorded))
        }
        let ext = url.pathExtension.lowercased()
        let mime = ext == "mp3" ? "audio/mpeg" : ext == "wav" ? "audio/wav" : ext == "aac" ? "audio/aac" : "audio/mp4"
        let result = try await APIClient.shared.extract(ExtractRequest(kind: "audio", data: data.base64EncodedString(), mimeType: mime))
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

// MARK: - Öneri 17: el yazısı / fotoğraf metnini doğrula

struct HandwritingReviewSheet: View {
    var images: [ImportedSource]
    /// Doğrulanmış metin, görsellerin yerine tek bir metin kaynağı olarak eklenir.
    var onConfirm: (ImportedSource) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var loading = false
    @State private var error: String?
    @State private var warnings: [String] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                if loading {
                    Spacer()
                    ProgressView("\(images.count) sayfa okunuyor…")
                    Spacer()
                } else if let error {
                    ContentUnavailableView("Okunamadı", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    Text("Okunan metni kontrol et; yanlış okunan yerleri düzelt. [okunamadı] işaretli yerleri tamamla ya da sil.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                    ForEach(warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                    TextEditor(text: $text)
                        .font(.body)
                        .padding(8)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                }
            }
            .navigationTitle("Metni doğrula")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Onayla") {
                        onConfirm(ImportedSource(name: "\(images.first?.name ?? "Notlar") (doğrulanmış metin)", kind: .text(text)))
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 || loading)
                }
            }
            .task { await read() }
        }
    }

    private func read() async {
        loading = true
        defer { loading = false }
        let payload = images.compactMap { source -> ExtractImage? in
            if case let .image(data) = source.kind { return ExtractImage(data: data.base64EncodedString(), mimeType: "image/jpeg") }
            return nil
        }
        do {
            let result = try await APIClient.shared.extract(ExtractRequest(kind: "images", images: payload, handwriting: true))
            text = result.text
            warnings = result.warnings
        } catch {
            self.error = error.localizedDescription
        }
    }
}
