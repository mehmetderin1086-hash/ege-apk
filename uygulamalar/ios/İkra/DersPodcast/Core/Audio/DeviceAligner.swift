import AVFoundation
import Foundation
import Observation
import os
@preconcurrency import PiperRuntime
import UIKit

// Madde 50 — cihazda CTC hizalama yedeği. Kelime zamanı zinciri: sunucu hizalaması (madde 12) → cihazda CTC (bu dosya) →
// cihazdaki konuşma tanıma (`SpeechAlignment`: DictationTranscriber, eski tanıyıcı) → sessizlik ölçümü.
// Akustik model (parseh/aligner-tr, int8 ONNX, 356 MB, CC-BY-4.0) uygulama paketinde ve depoda DEĞİLDİR: kullanıcı indirirse
// (çevrimdışı model katmanı, `OfflineSpeechManifest.json` "aligner") devreye girer; indirilmemişse bu basamak sessizce atlanır.
// Ölçüm (13 Eki 2026, benzeticide bu kodla, Apple Yelda sesi ve motor işaretçileri): kelime başlangıcında ortalama hata 84
// kelimelik seste 18 ms (en büyük 68 ms), rakamlı 48 kelimelik seste 16 ms (rakamlı kelimelerde 25 ms). Mac'te (yük altında)
// 41,8 sn ses 9 sn'de hizalandı; iPhone'da süre ve bellek ölçülmedi.

nonisolated enum DeviceAlign {
    /// Model bildirimindeki anahtar ve çevrimdışı model klasörünün adı.
    static let key = "aligner"
    static let modelFile = "model.int8.onnx", vocabFile = "vocab.json"
    /// Ayar: kullanıcı kapatmadıysa açık (model indirilmişse çalışır).
    static let enabledKey = "qs.align.device", reportKey = "qs.align.device.last"
    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    static var manifest: OfflineModelManifest? { OfflineModelCatalog.manifests[key].flatMap { $0.files.isEmpty ? nil : $0 } }
    static var modelRoot: URL { OfflineModelCatalog.root.appending(path: key, directoryHint: .isDirectory) }
    static var directory: URL { modelRoot.appending(path: "aligner-tr", directoryHint: .isDirectory) }
    static var ready: Bool { manifest.map { OfflineModelCatalog.ready($0, directory: directory) } ?? false }
    static var sizeLabel: String { manifest.map { ByteCountFormatter.string(fromByteCount: $0.size, countStyle: .file) } ?? "" }

    // MARK: Koşullar

    /// Bu basamağın atlanma nedeni (yoksa çalışabilir).
    enum Blocker: String, Sendable, Equatable { case disabled, noModel, exporting, memory, background }

    /// Hizalama için süreç sınırına kalması gereken bellek. Ölçüm (benzetici, uygulamanın onnxruntime derlemesi): model yüklenince
    /// 360 MB, 10 sn'lik eşit boylu pencerelerde tepe 0,61 GB ve ses uzunluğundan bağımsız (Mac'te Python onnxruntime ile 0,78 GB).
    /// Eşik bunun yaklaşık iki katıdır: bellek yetmezse süreç öldürülür (geri dönüşü yok), hizalamanın atlanması ise zararsızdır.
    /// Telefonda ölçülmedi.
    static let requiredMemory: UInt64 = 1_200_000_000
    /// `available`: `os_proc_available_memory()` (süreç bellek sınırına kalan bayt). Benzeticide 0 döner (sınır yok): engel sayılmaz.
    static func blocker(enabled: Bool, ready: Bool, exporting: Bool, available: UInt64, foreground: Bool = true) -> Blocker? {
        if !enabled { return .disabled }
        if !ready { return .noModel }
        if exporting { return .exporting }
        if !foreground { return .background }
        if available != 0, available < requiredMemory { return .memory }
        return nil
    }
    static var blocker: Blocker? {
        blocker(enabled: enabled, ready: ready, exporting: exporting, available: UInt64(max(0, os_proc_available_memory())), foreground: foreground.active)
    }

    /// Notification callbacks can stop inference while its actor is inside a synchronous native call.
    /// Unknown/inactive state is conservative: expensive alignment only runs while the app is active.
    final class ForegroundGate: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var active: Bool { lock.withLock { value } }
        func update(_ active: Bool) { lock.withLock { value = active } }
    }
    static let foreground = ForegroundGate()
    @MainActor private static var lifecycleObservers: [NSObjectProtocol] = []
    @MainActor static var isForeground: Bool { UIApplication.shared.applicationState == .active }
    @MainActor static func prepareLifecycle() {
        if lifecycleObservers.isEmpty {
            for (name, active) in [(UIApplication.didBecomeActiveNotification, true),
                                   (UIApplication.willResignActiveNotification, false),
                                   (UIApplication.didEnterBackgroundNotification, false)] {
                lifecycleObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                    foreground.update(active)
                    if !active { Task { await DeviceAligner.shared.unload() } }
                })
            }
        }
        foreground.update(isForeground)
    }

    final class CancellationSignal: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isCancelled: Bool { lock.withLock { value } }
        func cancel() { lock.withLock { value = true } }
    }

    /// Async pacing makes actors reentrant. A separate lease keeps a second caller from starting CTC
    /// during the first caller's rest; rejecting that optional step leaves the normal fallback available.
    final class InferenceGate: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var active: Bool { lock.withLock { value } }
        func begin() -> Bool { lock.withLock { if value { return false }; value = true; return true } }
        func end() { lock.withLock { value = false } }
    }

    enum InferenceBudget {
        static let coreSeconds = 2.0, maximumWindowSeconds = 4.0, maximumWorkSeconds = 20.0
        /// At most half of sustained elapsed time is native inference; ORT spinning is disabled too.
        static func restSeconds(after work: Double) -> Double { work.isFinite ? max(0.05, work) : maximumWindowSeconds }
        static func allows(workSeconds: Double) -> Bool { workSeconds.isFinite && workSeconds >= 0 && workSeconds < maximumWorkSeconds }
    }

    // MARK: Dışa aktarma kilidi

    /// Süren dışa aktarmaların sayacı (iç içe ve eşzamanlı yazımlar için; kilitli).
    final class ExportGate: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var active: Bool { lock.withLock { count > 0 } }
        func begin() { lock.withLock { count += 1 } }
        func end() { lock.withLock { count = max(0, count - 1) } }
    }
    static let exports = ExportGate()
    /// MP4 dışa aktarma sürüyor mu. Sürerken hizalama başlamaz; başlamış olan sıradaki pencerede bırakır (bellek ve işlemci yazıcıya kalır).
    static var exporting: Bool { exports.active }
    /// Dışa aktarma başlarken çağrılır: model bellekten bırakılır.
    static func exportBegan() {
        exports.begin()
        Task { await DeviceAligner.shared.unload() }
    }
    static func exportEnded() { exports.end() }

    // MARK: Hat

    struct Result: Sendable, Equatable {
        /// Anlatımın her kelimesi için zaman (sunucudaki `Alignment.words` ile aynı biçim).
        var words: [WordTime]
        var coverage: Double
        var minScore: Double?
        var meanScore: Double?
        var medianScore: Double?
        var audioSeconds: Double
    }

    /// Kalite kapısı: metin sese uymuyorsa (ortanca skor) ya da kelimelerin yarısından azı güvenle hizalandıysa sonuç kullanılmaz.
    /// Ölçüm: doğru metinde ortanca −0,03; cümle sırası ters ya da bambaşka metinde −2,1…−2,3; kelimelerin %20'si yanlışken −0,04.
    static let minimumMedian = -1.0, minimumCoverage = 0.5
    static func accepted(_ alignment: CTCAlign.Alignment) -> Bool {
        (alignment.medianScore ?? -.infinity) >= minimumMedian && alignment.coverage >= minimumCoverage
    }

    /// Anlatımın söylenen biçimi (sayılar ve birimler yazıya açılmış; seslendirmedeki okunuş katmanının aynısı) ve her söylenen
    /// kelimenin anlatımdaki kelime sırası.
    static func spoken(_ narration: String) -> (words: [String], map: [Int]) {
        SpeakableText.spokenWords(narration, language: .tr, dictionary: [])
    }

    /// Söylenen kelimelerin zamanlarını anlatım kelimelerine toplar: kelimenin başlangıcı ilk söylenen parçasının başlangıcıdır.
    /// İlk parçası ölçülemeyen (ya da söylenen karşılığı olmayan) kelime komşularından doldurulur.
    static func collapse(_ aligned: [CTCAlign.Word], map: [Int], narration: [String], duration: Double) -> [CTCAlign.Word]? {
        guard aligned.count == map.count, !narration.isEmpty, map.allSatisfy({ narration.indices.contains($0) }) else { return nil }
        var result = narration.map { CTCAlign.Word(word: $0, start: 0, end: 0, score: nil, interpolated: true) }
        var seen = [Bool](repeating: false, count: narration.count), sums = [Double](repeating: 0, count: narration.count), counts = [Int](repeating: 0, count: narration.count)
        for (part, index) in zip(aligned, map) {
            if !seen[index] { seen[index] = true; result[index].start = part.start; result[index].interpolated = part.interpolated }
            result[index].end = part.end
            if let score = part.score { sums[index] += score; counts[index] += 1 }
        }
        for index in result.indices where !result[index].interpolated && counts[index] > 0 { result[index].score = sums[index] / Double(counts[index]) }
        for index in result.indices where result[index].score == nil { result[index].interpolated = true }
        CTCAlign.fill(&result, duration: duration)
        return result
    }

    /// Örneklerden kelime zamanlarına bütün hat. Akustik model dışarıdan verilir (uygulamada onnxruntime, testte sahte).
    /// `stop` pencereler arasında sorulur (iptal, dışa aktarma). Yol bulunamazsa ya da kalite kapısı geçilmezse `nil`.
    static func run(samples: [Float], narration: String, vocabulary: CTCAlign.Vocabulary, stop: () -> Bool = { false },
                    logits: (_ input: [Float], _ window: CTCAlign.Window) throws -> (values: [Float], frames: Int, vocab: Int)) -> Result? {
        let original = narration.split(whereSeparator: \.isWhitespace).map(String.init), duration = Double(samples.count) / Double(CTCAlign.sampleRate)
        let text = spoken(narration)
        guard !original.isEmpty, !text.words.isEmpty else { return nil }
        var emissions = CTCAlign.Emissions(vocab: vocabulary.count)
        for window in CTCAlign.windows(samples: samples.count) {
            if stop() { return nil }
            guard let output = try? logits(CTCAlign.normalized(samples[window.input], padding: window.padding), window), !stop(),
                  output.vocab == vocabulary.count, output.frames >= window.skip + window.frames,
                  emissions.append(logits: output.values, frames: output.frames, keep: window.skip..<(window.skip + window.frames)) else { return nil }
        }
        guard !stop() else { return nil }
        let result = finish(emissions, original: original, text: text, vocabulary: vocabulary, duration: duration)
        return stop() ? nil : result
    }

    /// Production path: short windows, cancellable async rest, and an aggregate inference budget.
    /// Injected clock/rest keep the stop, pacing and timestamp behavior deterministic in regression tests.
    static func runCooperatively(samples: [Float], narration: String, vocabulary: CTCAlign.Vocabulary,
                                 isolation: isolated (any Actor)? = #isolation,
                                 stop: () -> Bool = { false }, now: () -> Double = { ProcessInfo.processInfo.systemUptime },
                                 rest: (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
                                 logits: (_ input: [Float], _ window: CTCAlign.Window) throws -> (values: [Float], frames: Int, vocab: Int)) async -> Result? {
        let original = narration.split(whereSeparator: \.isWhitespace).map(String.init), duration = Double(samples.count) / Double(CTCAlign.sampleRate)
        let text = spoken(narration)
        guard !original.isEmpty, !text.words.isEmpty else { return nil }
        var emissions = CTCAlign.Emissions(vocab: vocabulary.count), workSeconds = 0.0
        for window in CTCAlign.windows(samples: samples.count, core: InferenceBudget.coreSeconds) {
            guard !Task.isCancelled, !stop(), InferenceBudget.allows(workSeconds: workSeconds) else { return nil }
            let started = now()
            let output = try? logits(CTCAlign.normalized(samples[window.input], padding: window.padding), window)
            guard !Task.isCancelled, !stop() else { return nil }
            let elapsed = max(0, now() - started)
            workSeconds += elapsed
            // Failed/timed-out windows also rest; otherwise repeated scene failures could bypass pacing.
            do { try await rest(InferenceBudget.restSeconds(after: elapsed)) } catch { return nil }
            guard !Task.isCancelled, !stop() else { return nil }
            guard let output, elapsed <= InferenceBudget.maximumWindowSeconds, InferenceBudget.allows(workSeconds: workSeconds),
                  output.vocab == vocabulary.count, output.frames >= window.skip + window.frames,
                  emissions.append(logits: output.values, frames: output.frames, keep: window.skip..<(window.skip + window.frames)) else { return nil }
        }
        guard !Task.isCancelled, !stop() else { return nil }
        let result = finish(emissions, original: original, text: text, vocabulary: vocabulary, duration: duration)
        return Task.isCancelled || stop() ? nil : result
    }

    private static func finish(_ emissions: CTCAlign.Emissions, original: [String], text: (words: [String], map: [Int]),
                               vocabulary: CTCAlign.Vocabulary, duration: Double) -> Result? {
        guard emissions.frames > 0, let alignment = CTCAlign.align(emissions, words: text.words, vocabulary: vocabulary, duration: duration),
              accepted(alignment), let words = collapse(alignment.words, map: text.map, narration: original, duration: duration) else { return nil }
        let measured = words.filter { !$0.interpolated }.count
        return Result(words: words.map { WordTime(word: $0.word, start: $0.start, end: $0.end, score: $0.score, interpolated: $0.interpolated) },
                      coverage: Double(measured) / Double(words.count), minScore: alignment.minScore, meanScore: alignment.meanScore,
                      medianScore: alignment.medianScore, audioSeconds: duration)
    }

    /// Bundan uzun ses hizalanmaz (dosyanın tamamı belleğe okunur; sahneler bunun çok altındadır).
    static let maximumAudioSeconds = 600.0
    /// Ses dosyasının 16 kHz tek kanal örnekleri (akustik modelin girdisi).
    static func samples(of url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let source = file.processingFormat
        guard file.length > 0, source.sampleRate > 0, Double(file.length) / source.sampleRate <= maximumAudioSeconds, let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(file.length)),
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(CTCAlign.sampleRate), channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: target) else { throw OfflineSpeechError.noAudio }
        try file.read(into: input)
        converter.primeMethod = .none
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * target.sampleRate / source.sampleRate) + 256)
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { throw OfflineSpeechError.noAudio }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if consumed { state.pointee = .endOfStream; return nil }
            consumed = true; state.pointee = .haveData; return input
        }
        guard status != .error, error == nil, output.frameLength > 0, let channel = output.floatChannelData else { throw OfflineSpeechError.noAudio }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(output.frameLength)))
    }

    /// Zincirin cihaz basamağı: sahne sesini anlatıma hizalar. Model yoksa, kapalıysa, dışa aktarma sürüyorsa, bellek yetmiyorsa ya
    /// da sonuç kalite kapısından geçmiyorsa `nil` döner; çağıran konuşma tanımaya düşer.
    static func align(audio url: URL, narration: String) async -> Result? {
        await prepareLifecycle()
        guard !Task.isCancelled else { return nil }
        if let reason = blocker {
            // Bellek engeli kullanıcının seçimi değildir ve telefonda ölçülemedi: Ayarlar'daki "Son çalışma" satırında görünür.
            if reason == .memory { report("Boş bellek yetmedi (\(max(0, os_proc_available_memory()) >> 20) MB); konuşma tanımaya dönüldü") }
            return nil
        }
        return await DeviceAligner.shared.align(audio: url, narration: narration)
    }

    /// Son çalışmanın özeti (Ayarlar'da görünür; telefondaki gerçek süre buradan okunur).
    static var lastReport: String? { UserDefaults.standard.string(forKey: reportKey) }
    static func report(_ text: String) {
        UserDefaults.standard.set(Date().formatted(date: .abbreviated, time: .shortened) + " · " + text, forKey: reportKey)
    }
}

/// Akustik modelin tek sıralı çalışma hattı: aynı anda tek hizalama (bellek üst sınırı pencere boyuyla belirlenir). Model, son
/// hizalamadan `idleSeconds` sonra, bellek uyarısında ya da dışa aktarma başlarken bırakılır (bellekte ≈ 0,5 GB tutar).
actor DeviceAligner {
    static let shared = DeviceAligner()
    private var model: CTCAcousticModel?
    private var vocabulary: CTCAlign.Vocabulary?
    private var idleTask: Task<Void, Never>?
    private var observing = false
    private let inferenceGate = DeviceAlign.InferenceGate()
    private var currentCancellation: DeviceAlign.CancellationSignal?
    let idleSeconds: Double

    init(idleSeconds: Double = 45) { self.idleSeconds = idleSeconds }

    var isResident: Bool { model != nil }
    var isAligning: Bool { inferenceGate.active }

    func unload() {
        currentCancellation?.cancel()
        idleTask?.cancel(); idleTask = nil
        model = nil; vocabulary = nil
    }

    private func scheduleIdleUnload() {
        idleTask?.cancel()
        let delay = idleSeconds
        idleTask = Task { [weak self] in
            guard (try? await Task.sleep(for: .seconds(delay))) != nil else { return }
            await self?.unload()
        }
    }

    private func observeMemoryWarnings() {
        guard !observing else { return }
        observing = true
        Task { @MainActor in
            _ = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
                Task { await DeviceAligner.shared.unload() }
            }
        }
    }

    private func load(from directory: URL) throws -> (CTCAcousticModel, CTCAlign.Vocabulary) {
        if let model, let vocabulary { return (model, vocabulary) }
        guard let table = CTCAlign.Vocabulary(json: try Data(contentsOf: directory.appending(path: DeviceAlign.vocabFile))) else { throw OfflineSpeechError.corruptDownload }
        let loaded = try CTCAcousticModel(modelPath: directory.appending(path: DeviceAlign.modelFile).path, threads: 1)
        model = loaded; vocabulary = table
        return (loaded, table)
    }

    /// Pencereler arasında askıya alınır; inferenceGate ikinci çağrının aynı anda model çalıştırmasını engeller.
    /// `directory`: model klasörü (varsayılan: indirilen model).
    func align(audio url: URL, narration: String, directory: URL = DeviceAlign.directory,
               exporting: @escaping @Sendable () -> Bool = { DeviceAlign.exporting },
               foreground: @escaping @Sendable () -> Bool = { DeviceAlign.foreground.active }) async -> DeviceAlign.Result? {
        await DeviceAlign.prepareLifecycle()
        guard !Task.isCancelled, foreground(), !exporting(), inferenceGate.begin() else { return nil }
        let cancellation = DeviceAlign.CancellationSignal()
        currentCancellation = cancellation
        idleTask?.cancel(); idleTask = nil
        observeMemoryWarnings()
        // Dışa aktarma araya girdiyse model hemen bırakılır; değilse art arda gelen sahneler için kısa süre bellekte kalır.
        defer {
            currentCancellation = nil; inferenceGate.end()
            if model != nil { if exporting() || !foreground() || cancellation.isCancelled { unload() } else { scheduleIdleUnload() } }
        }
        // Engel (`DeviceAlign.blocker`) aktöre girmeden önce sorulur; hizalama sırada beklerken dışa aktarma başlamış olabilir.
        guard !Task.isCancelled, foreground(), !exporting() else { return nil }
        let started = Date()
        let samples: [Float]
        do { samples = try DeviceAlign.samples(of: url) } catch {
            DeviceAlign.report("Ses okunamadı (\(url.lastPathComponent)): \(error.localizedDescription); konuşma tanımaya dönüldü")
            return nil
        }
        guard !Task.isCancelled, foreground(), !exporting(), samples.count >= CTCAlign.sampleRate / 5 else { return nil }
        let seconds = Double(samples.count) / Double(CTCAlign.sampleRate)
        do {
            let (model, vocabulary) = try load(from: directory)
            // Model yüklenirken dışa aktarma başladıysa ilk pencere de çalıştırılmaz (model `defer` ile bırakılır).
            guard !Task.isCancelled, foreground(), !exporting() else { return nil }
            var windows = 0
            let shouldStop: @Sendable () -> Bool = { cancellation.isCancelled || !foreground() || exporting() }
            let result = await withTaskCancellationHandler {
                await DeviceAlign.runCooperatively(samples: samples, narration: narration, vocabulary: vocabulary,
                                                   stop: shouldStop) { input, _ in
                    windows += 1
                    return try model.logits(input, maximumSeconds: DeviceAlign.InferenceBudget.maximumWindowSeconds, shouldStop: shouldStop)
                }
            } onCancel: {
                cancellation.cancel()
            }
            let elapsed = Date().timeIntervalSince(started)
            if let result {
                DeviceAlign.report(String(format: "%.1f sn ses %.1f sn'de hizalandı · kapsama %%%d · ortanca skor %.2f", seconds, elapsed, Int((result.coverage * 100).rounded()), result.medianScore ?? 0))
            } else if !Task.isCancelled, !exporting(), foreground(), !cancellation.isCancelled {
                DeviceAlign.report(String(format: "%.1f sn ses hizalanamadı (%d pencere, %.1f sn); konuşma tanımaya dönüldü", seconds, windows, elapsed))
            }
            return result
        } catch {
            unload()
            DeviceAlign.report("Model çalıştırılamadı: \(error.localizedDescription)")
            return nil
        }
    }
}

/// Hizalayıcı modelinin indirme durumu (Ayarlar ekranı). Aktarım, ses modelleriyle aynı katmandan geçer: dosya başına boyut ve
/// özet doğrulaması, kaldığı dosyadan devam, en sonda `.ready` işareti.
@Observable
final class DeviceAlignerModel {
    static let shared = DeviceAlignerModel()
    struct State { var ready = false; var downloading = false; var removing = false; var progress: Double = 0; var message: String? }
    private(set) var state = State()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var received: [String: Int64] = [:]
    @ObservationIgnored private var generation: UUID?

    init() { DeviceAlign.prepareLifecycle(); refresh() }
    func refresh() { if task == nil { state.ready = DeviceAlign.ready } }

    func download() {
        guard task == nil, !state.removing else { return }
        let token = UUID()
        generation = token; state = State(downloading: true); received = [:]
        task = Task { [weak self] in
            guard let self else { return }
            do {
                guard let manifest = DeviceAlign.manifest else { throw OfflineSpeechError.message("Model listesi okunamadı. Uygulamayı güncelleyin.") }
                try FileManager.default.createDirectory(at: OfflineModelCatalog.root, withIntermediateDirectories: true)
                let available = try OfflineModelCatalog.root.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? Int64.max
                guard available > manifest.size + 150_000_000 else {
                    throw OfflineSpeechError.message("Model için telefonda yaklaşık \(DeviceAlign.sizeLabel) ve ek çalışma alanı gerekiyor.")
                }
                try await SpeechModelTransfer.download(manifest, to: DeviceAlign.directory) { [weak self] path, bytes in
                    Task { @MainActor in
                        guard let self, self.generation == token, self.task != nil else { return }
                        self.received[path] = bytes
                        self.state.progress = min(1, Double(self.received.values.reduce(0, +)) / Double(max(manifest.size, 1)))
                    }
                }
                try Task.checkCancellation()
                state = State(ready: true, progress: 1)
            } catch {
                state = State(message: error is CancellationError || Task.isCancelled ? "İndirme durduruldu. İndirilen dosyalardan devam edebilirsin." : error.localizedDescription)
            }
            task = nil
        }
    }
    func cancel() { task?.cancel() }

    func remove() async {
        guard !state.removing else { return }
        task?.cancel()
        await task?.value
        state = State(removing: true)
        try? FileManager.default.removeItem(at: DeviceAlign.directory.appending(path: ".ready"))
        await DeviceAligner.shared.unload()
        do {
            if FileManager.default.fileExists(atPath: DeviceAlign.modelRoot.path) { try FileManager.default.removeItem(at: DeviceAlign.modelRoot) }
            state = State()
        } catch { state = State(message: error.localizedDescription) }
    }
}
