import AVFoundation
import Speech

/// #13/#20: cihaz içi Türkçe konuşma tanıma (ses Apple sunucularına gönderilmez).
/// Sıra: iOS 26 `DictationTranscriber` (tr_TR, `.audioTimeRange`) → `SFSpeechRecognizer` (yalnız cihazda) → yok.
nonisolated enum SpeechAlignment {
    static let locale = Locale(identifier: "tr-TR")

    enum Engine: Sendable, Equatable { case dictation, legacy }
    enum ModelState: Sendable, Equatable { case ready(Engine), needsDownload, unsupported }

    enum Failure: LocalizedError {
        case unavailable, timeout
        var errorDescription: String? {
            switch self {
            case .unavailable: "Cihazda Türkçe konuşma tanıma kullanılamıyor."
            case .timeout: "Konuşma tanıma yanıt vermedi."
            }
        }
    }

    static var isAuthorized: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }
    static var isDenied: Bool { [.denied, .restricted].contains(SFSpeechRecognizer.authorizationStatus()) }

    /// İzin ister (yalnız arayüzden, bir kez).
    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status == .authorized) }
        }
    }

    static var legacyAvailable: Bool {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else { return false }
        return recognizer.supportsOnDeviceRecognition
    }

    static func modelState() async -> ModelState {
        if #available(iOS 26, *), let status = await dictationStatus() {
            if status == .installed { return .ready(.dictation) }
            if legacyAvailable { return .ready(.legacy) }
            if status == .supported || status == .downloading { return .needsDownload }
        }
        return legacyAvailable ? .ready(.legacy) : .unsupported
    }

    /// Dikte modelini indirir (kullanıcı onayından sonra çağrılır).
    static func downloadModel() async throws {
        guard #available(iOS 26, *), let transcriber = await makeTranscriber() else { throw Failure.unavailable }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    /// Ses dosyasındaki kelimeler (dosya başına göre sn). İki yolda da süre sınırı var: model takılırsa üretimdeki
    /// kalite kapısı ve kelime senkronu süresiz beklemez.
    static func recognize(_ url: URL, engine: Engine) async throws -> [RecognizedWord] {
        let limit = timeout(forAudioSeconds: audioSeconds(url))
        switch engine {
        case .dictation:
            guard #available(iOS 26, *) else { throw Failure.unavailable }
            return try await withDeadline(seconds: limit) { try await dictation(url) }
        case .legacy:
            return try await legacy(url, timeout: limit)
        }
    }

    /// Tanıma süre sınırı: en az 120 sn, uzun seste sesin iki katı + 30 sn.
    static func timeout(forAudioSeconds seconds: Double) -> Double { max(120, 2 * max(0, seconds) + 30) }

    private static func audioSeconds(_ url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    /// İşi süre sınırıyla çalıştırır: süre dolunca iş iptal edilir ve `Failure.timeout` atılır. İş iptale yanıt
    /// vermese bile çağıran beklemez (iş arka planda biter, sonucu atılır).
    static func withDeadline(seconds: Double, _ work: @escaping @Sendable () async throws -> [RecognizedWord]) async throws -> [RecognizedWord] {
        let once = OnceContinuation()
        let task = Task {
            do { once.resume(.success(try await work())) } catch { once.resume(.failure(error)) }
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[RecognizedWord], Error>) in
                once.set(continuation)
                DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                    task.cancel()
                    once.resume(.failure(Failure.timeout))
                }
            }
        } onCancel: {
            task.cancel()
            once.resume(.failure(CancellationError()))
        }
    }

    // MARK: iOS 26 dikte

    @available(iOS 26, *)
    private static func makeTranscriber() async -> DictationTranscriber? {
        guard let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) else { return nil }
        return DictationTranscriber(locale: supported, contentHints: [], transcriptionOptions: [],
                                    reportingOptions: [], attributeOptions: [.audioTimeRange])
    }

    @available(iOS 26, *)
    private static func dictationStatus() async -> AssetInventory.Status? {
        guard let transcriber = await makeTranscriber() else { return nil }
        return await AssetInventory.status(forModules: [transcriber])
    }

    @available(iOS 26, *)
    private static func dictation(_ url: URL) async throws -> [RecognizedWord] {
        guard let transcriber = await makeTranscriber() else { throw Failure.unavailable }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collector = Task { () throws -> [RecognizedWord] in
            var words: [RecognizedWord] = []
            for try await result in transcriber.results {
                for run in result.text.runs {
                    guard let range = run.audioTimeRange else { continue }
                    let text = String(result.text[run.range].characters)
                    words += split(text, start: range.start.seconds, end: range.end.seconds)
                }
            }
            return words
        }
        do {
            let file = try AVAudioFile(forReading: url)
            if let last = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
        return try await collector.value
    }

    /// Yeni sonuç parçası eski listeyle birleştirilir: parçanın başladığı andan (küçük payla) sonraki eski sözcükler düşer, yenileri eklenir.
    /// Böylece aynı parçanın yenilenen sonucu önceki hâlini değiştirir, yeni parça ise önceki parçaların ardına eklenir.
    static func merged(_ words: [RecognizedWord], with incoming: [RecognizedWord]) -> [RecognizedWord] {
        guard let first = incoming.first else { return words }
        let cut = first.start - 0.05
        return words.filter { $0.start < cut && $0.end <= first.start + 0.05 } + incoming
    }

    /// Bir zaman aralığındaki metni kelimelere böler; aralık karakter oranıyla paylaştırılır.
    static func split(_ text: String, start: Double, end: Double) -> [RecognizedWord] {
        let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !parts.isEmpty, start.isFinite, end.isFinite else { return [] }
        let total = Double(parts.reduce(0) { $0 + $1.count })
        var cursor = start
        return parts.map { part in
            let length = total > 0 ? (end - start) * Double(part.count) / total : 0
            defer { cursor += length }
            return RecognizedWord(text: part, start: cursor, end: cursor + length)
        }
    }

    // MARK: SFSpeechRecognizer (yalnız cihazda)

    private static func legacy(_ url: URL, timeout: Double) async throws -> [RecognizedWord] {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else { throw Failure.unavailable }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        // Uzun dosyada tanıyıcı sesi parçalara böler; her geri çağrı yalnız o parçanın (ya da son parçanın) sözcüklerini taşır.
        // Yalnız `isFinal` sonucu almak son parçayı bırakıyordu (telefonda 40 sn'lik sahnede sadece son 10 sn). Bütün sonuçlar
        // zaman damgasıyla birleştirilir: yeni sonuç, başladığı andan sonraki eski sözcükleri değiştirir.
        request.shouldReportPartialResults = true
        request.addsPunctuation = false
        let once = OnceContinuation()
        let holder = TaskHolder()
        let gathered = WordGatherer()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[RecognizedWord], Error>) in
                once.set(continuation)
                holder.task = recognizer.recognitionTask(with: request) { result, error in
                    if let result {
                        let words = result.bestTranscription.segments.map { RecognizedWord(text: $0.substring, start: $0.timestamp, end: $0.timestamp + $0.duration) }
                        let merged = gathered.merge(words)
                        if result.isFinal { once.resume(.success(merged)) }
                    } else if let error {
                        // Parçalı tanımada son parça bazen hatayla biter; o zamana kadar toplananlar yine kullanılır.
                        let kept = gathered.merge([])
                        once.resume(kept.isEmpty ? .failure(error) : .success(kept))
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    holder.task?.cancel()
                    once.resume(.failure(Failure.timeout))
                }
            }
        } onCancel: {
            holder.task?.cancel()
            once.resume(.failure(CancellationError()))
        }
    }
}

/// Parçalı tanıma sonuçlarını zaman damgasıyla birleştirir (kilitli; tanıyıcı geri çağrıları kendi kuyruğundan gelir).
nonisolated final class WordGatherer: @unchecked Sendable {
    private let lock = NSLock()
    private var words: [RecognizedWord] = []
    func merge(_ incoming: [RecognizedWord]) -> [RecognizedWord] {
        lock.lock(); defer { lock.unlock() }
        words = SpeechAlignment.merged(words, with: incoming)
        return words
    }
}

/// Devamın yalnız bir kez sürdürülmesini sağlar (tanıyıcı geri çağrıları birden çok gelebilir).
nonisolated private final class OnceContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[RecognizedWord], Error>?
    private var pending: Result<[RecognizedWord], Error>?

    func set(_ c: CheckedContinuation<[RecognizedWord], Error>) {
        lock.lock()
        if let pending {
            lock.unlock()
            c.resume(with: pending)
            return
        }
        continuation = c
        lock.unlock()
    }

    func resume(_ result: Result<[RecognizedWord], Error>) {
        lock.lock()
        guard let c = continuation else {
            if pending == nil { pending = result }
            lock.unlock()
            return
        }
        continuation = nil
        pending = result
        lock.unlock()
        c.resume(with: result)
    }
}

nonisolated private final class TaskHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var _task: SFSpeechRecognitionTask?
    var task: SFSpeechRecognitionTask? {
        get { lock.withLock { _task } }
        set { lock.withLock { _task = newValue } }
    }
}
