import AVFoundation
import Foundation

nonisolated enum WordSyncOutcome: Sendable, Equatable { case ready, unsupported(String), denied, failed(String) }

/// Aynı anahtarla süren işi paylaştırır: ikinci çağıran yeni iş başlatmaz, süren işin sonucunu bekler.
/// İş `.utility` öncelikli ayrı görevde çalışır ve ancak bütün bekleyenleri iptal edilince iptal edilir
/// (bir bekleyenin iptali diğerinin işini kesmez). İptal edilen bekleyen, `ifCancelled` verilmediyse iş bitene
/// kadar bekler; verildiyse beklemeden o değeri alır.
nonisolated final class InFlight<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {
    private struct Entry { var task: Task<Value, Never>; var waiters: Int; var token: Int }
    private let lock = NSLock()
    private var running: [Key: Entry] = [:]
    private var lastToken = 0

    /// `ifCancelled`: iptal edilen çağıran işin bitmesini beklemeden bunu alır. Yoksa iş başka bekleyenler için
    /// sürdükçe (dakikalarca) askıda kalır ve çağıranın "sürüyor" kaydı da onunla birlikte kalır.
    func run(_ key: Key, ifCancelled fallback: Value? = nil, _ work: @escaping @Sendable () async -> Value) async -> Value {
        let (task, token) = lock.withLock { () -> (Task<Value, Never>, Int) in
            if let entry = running[key] {
                running[key]?.waiters += 1
                return (entry.task, entry.token)
            }
            lastToken += 1
            let token = lastToken
            let task = Task.detached(priority: .utility) {
                let value = await work()
                self.finish(key, token)
                return value
            }
            running[key] = Entry(task: task, waiters: 1, token: token)
            return (task, token)
        }
        guard let fallback else {
            return await withTaskCancellationHandler { await task.value } onCancel: { self.leave(key, token) }
        }
        // `task.value` bekleyenin iptaliyle dönmez: sonuç ile iptalden hangisi önce gelirse o alınır.
        let result = OnceValue<Value>()
        Task.detached(priority: .utility) { result.resolve(await task.value) }
        return await withTaskCancellationHandler { await result.wait() } onCancel: {
            self.leave(key, token)
            result.resolve(fallback)
        }
    }

    /// Anahtarla süren işi bekleyen çağrı sayısı (süren iş yoksa 0); testler ve tanılama.
    func waiters(for key: Key) -> Int { lock.withLock { running[key]?.waiters ?? 0 } }

    /// İş bitti: kayıt silinir, aynı anahtarla gelen sonraki çağrı yeniden çalıştırır.
    private func finish(_ key: Key, _ token: Int) {
        lock.withLock { if running[key]?.token == token { running[key] = nil } }
    }

    /// Bir bekleyen iptal edildi. Kimse kalmadıysa iş iptal edilir ve kayıt hemen silinir: iptal edilen iş kapanırken
    /// gelen yeni çağrı ona katılmaz (yoksa "durduruldu" sonucunu alırdı), kendi işini başlatır.
    private func leave(_ key: Key, _ token: Int) {
        let abandoned = lock.withLock { () -> Task<Value, Never>? in
            guard var entry = running[key], entry.token == token else { return nil }
            entry.waiters -= 1
            running[key] = entry.waiters > 0 ? entry : nil
            return entry.waiters > 0 ? nil : entry.task
        }
        abandoned?.cancel()
    }
}

/// #20: gerçek kelime senkronu. Bölüm sesi tur gruplarıyla (≤60 sn) cihazda tanınır, bilinen metinle hizalanır.
/// Çıktı `episode.directory/word_times.json`: {"audio": hangi ses dosyası için (ad, boyut, değişim zamanı),
/// "times": [küresel TimedTurn.id: [ORİJİNAL kelime başlangıcı (mutlak sn)]]}. Zamanlar yalnız damga bugünkü
/// sesle aynıysa geçerlidir; böylece ses değiştikten sonra yazılan ya da kalan dosya kullanılmaz.
/// Yalnız ön planda çağrılır; ses değişen her yolda `invalidate` edilir.
nonisolated enum WordSync {
    static let fileName = "word_times.json"
    static let autoKey = "wordSync.auto"
    /// Otomatik hazırlık en çok bu uzunluktaki bölümlerde (daha uzunlarda düğmeyle).
    static let autoMaxDuration: Double = 30 * 60
    static let maxChunkSeconds = 60.0

    /// Ses dosyasının kimliği (ad + boyut + değişim zamanı). `replaceItemAt`/taşıma/yeniden yazma bunu değiştirir.
    struct AudioStamp: Codable, Sendable, Equatable {
        var name: String
        var size: Int64
        var modified: Double

        init?(of url: URL) {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = (attributes[.size] as? NSNumber)?.int64Value,
                  let date = attributes[.modificationDate] as? Date else { return nil }
            name = url.lastPathComponent
            self.size = size
            modified = date.timeIntervalSinceReferenceDate
        }

        static func == (a: AudioStamp, b: AudioStamp) -> Bool {
            a.name == b.name && a.size == b.size && abs(a.modified - b.modified) < 0.000_5
        }
    }

    private struct Stored: Codable {
        var audio: AudioStamp?
        var times: [String: [Double]]
    }

    static var autoEnabled: Bool { UserDefaults.standard.object(forKey: autoKey) as? Bool ?? true }
    static func shouldAutoPrepare(duration: Double) -> Bool { autoEnabled && duration <= autoMaxDuration }

    static var isSupported: Bool {
        get async { await SpeechAlignment.modelState() != .unsupported }
    }

    /// Dikte modeli indirilmeden çalışamıyor mu (kullanıcıya sorulur, sonra `downloadModel`).
    static var needsModelDownload: Bool {
        get async { await SpeechAlignment.modelState() == .needsDownload }
    }

    static func downloadModel() async throws { try await SpeechAlignment.downloadModel() }

    /// Klasör OLUŞTURMAZ (silinmiş bölümün klasörü yeniden doğmasın).
    static func fileURL(_ episodeID: UUID, root: URL = EpisodeFiles.root) -> URL {
        root.appending(path: episodeID.uuidString, directoryHint: .isDirectory).appending(path: fileName)
    }

    /// word_times.json: [küresel TimedTurn.id: [kelime başlangıcı (mutlak sn)]]. Yalnız bölümün bugünkü sesi için
    /// yazılmışsa döner (damga uyuşmazsa ya da damgasızsa nil → yeniden hazırlanır).
    static func load(episodeID: UUID, root: URL = EpisodeFiles.root) -> [Int: [Double]]? {
        let url = fileURL(episodeID, root: root)
        guard let stored = read(url), let stamp = stored.audio,
              AudioStamp(of: url.deletingLastPathComponent().appending(path: stamp.name)) == stamp else { return nil }
        return decode(stored.times)
    }

    /// Damgaya bakmadan okur (testler ve tanılama).
    static func load(from url: URL) -> [Int: [Double]]? { read(url).flatMap { decode($0.times) } }

    /// Dosyanın hangi ses için yazıldığı.
    static func stamp(at url: URL) -> AudioStamp? { read(url)?.audio }

    private static func read(_ url: URL) -> Stored? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let stored = try? JSONDecoder().decode(Stored.self, from: data) { return stored }
        // Eski biçim (damgasız sözlük).
        return (try? JSONDecoder().decode([String: [Double]].self, from: data)).map { Stored(audio: nil, times: $0) }
    }

    private static func decode(_ raw: [String: [Double]]) -> [Int: [Double]]? {
        var result: [Int: [Double]] = [:]
        for (key, value) in raw { if let id = Int(key) { result[id] = value } }
        return result.isEmpty ? nil : result
    }

    /// Ses değişti: zamanlar silinir. İstisna: dosya, bugünkü sesin kendisi için yazılmışsa korunur (üretimde kalite
    /// kapısının zamanları `stitch` içinde yazılır; ardından gelen "ses değişti" bildirimi onları silmesin).
    static func invalidate(_ episodeID: UUID, root: URL = EpisodeFiles.root) {
        let url = fileURL(episodeID, root: root)
        // Ses değişen her yol (yeniden üretim, konu çıkarma, önceki sese dönüş, sahne düzenleme) buradan geçer:
        // eski sahne düzenlemesinin geri alma kopyası (tam bölüm boyunda m4a) artık geçersiz, yer tutmasın.
        // Sahne düzenlemesi kendi kaydını bu çağrıdan SONRA yazar.
        SceneEditor.clearUndo(directory: url.deletingLastPathComponent())
        if let stamp = read(url)?.audio,
           AudioStamp(of: url.deletingLastPathComponent().appending(path: stamp.name)) == stamp { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// `audio` için hesaplanan zamanları yazar; boşsa dosyayı siler. Klasör yoksa (bölüm silinmiş) yazmaz.
    @discardableResult
    static func save(_ times: [Int: [Double]], to url: URL, audio: AudioStamp?) -> Bool {
        let fm = FileManager.default
        guard !times.isEmpty, let audio else {
            try? fm.removeItem(at: url)
            return false
        }
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
        let stored = Stored(audio: audio, times: Dictionary(uniqueKeysWithValues: times.map { (String($0.key), $0.value) }))
        guard let data = try? JSONEncoder().encode(stored) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Tanıma parçaları: ardışık turlar, konu değişiminde ya da süre `maxSeconds`'ı aşınca bölünür.
    static func chunks(_ timeline: Timeline, maxSeconds: Double = maxChunkSeconds) -> [[Int]] {
        var result: [[Int]] = []
        var current: [Int] = []
        for (i, turn) in timeline.turns.enumerated() {
            if let first = current.first {
                let head = timeline.turns[first]
                if head.chapterIndex != turn.chapterIndex || turn.end - head.start > maxSeconds {
                    result.append(current)
                    current = []
                }
            }
            current.append(i)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Sonuç, başlangıçta okunan ses dosyası hâlâ yerindeyse yazılır; arada ses değiştiyse (sahne düzenleme, konu
    /// çıkarma, yeniden üretim) ya da bölüm silindiyse hiçbir şey yazılmaz ve `.failed` döner.
    /// Plan #20: düşük öncelik. Çağıranın önceliği ne olursa olsun (ör. `.userInitiated` görev) tanıma ve hizalama
    /// `.utility` öncelikli ayrı görevde çalışır.
    /// `language`: bölümün dili (ayarlardan); nil ise metinden tahmin edilir (`looksTurkish`).
    /// Aynı bölüm ve aynı ses için süren hazırlık varken gelen ikinci çağrı (üretim bitişi + bölümün açılması) yeni
    /// tanıma başlatmaz, süreninkini bekler: bölüm cihazda iki kez tanınmaz, iki iş aynı dosyayı yazmaz. Çağıranın
    /// iptali, işi bekleyen başka çağıran kalmadıysa göreve geçer; iptal edilen çağıran her durumda beklemeden
    /// `.failed(stoppedMessage)` alır (kapanan görünüm, üretim bitişinin başlattığı iş sürerken askıda kalmasın).
    static func prepare(episodeID: UUID, audioURL: URL, timeline: Timeline, script: PodcastScript,
                        language: PodcastLanguage? = nil) async -> WordSyncOutcome {
        await inFlight.run(flightKey(episodeID: episodeID, audioURL: audioURL), ifCancelled: .failed(stoppedMessage)) {
            await run(episodeID: episodeID, audioURL: audioURL, timeline: timeline, script: script, language: language)
        }
    }

    private static let inFlight = InFlight<String, WordSyncOutcome>()

    /// Bölüm + ses damgası: ses değiştiyse eski sese ait (boşa çıkacak) işe katılınmaz. Damga okunamazsa yalnız bölüm.
    static func flightKey(episodeID: UUID, audioURL: URL) -> String {
        guard let stamp = AudioStamp(of: audioURL) else { return episodeID.uuidString }
        return "\(episodeID.uuidString)|\(stamp.name)|\(stamp.size)|\(stamp.modified)"
    }

    @concurrent
    private static func run(episodeID: UUID, audioURL: URL, timeline: Timeline, script: PodcastScript,
                            language: PodcastLanguage?) async -> WordSyncOutcome {
        guard !SpeechAlignment.isDenied else { return .denied }
        guard SpeechAlignment.isAuthorized else { return .denied }
        let engine: SpeechAlignment.Engine
        switch await SpeechAlignment.modelState() {
        case .ready(let e): engine = e
        case .needsDownload: return .unsupported("Kelime senkronu için Türkçe konuşma modelinin indirilmesi gerekiyor.")
        case .unsupported: return .unsupported("Bu cihazda Türkçe konuşma tanıma yok; tahmini senkron kullanılıyor.")
        }
        let language = language ?? (looksTurkish(script) ? PodcastLanguage.tr : .en)
        guard language == .tr else { return .unsupported("Kelime senkronu yalnız Türkçe bölümlerde çalışır.") }
        guard let stamp = AudioStamp(of: audioURL) else { return .failed(changedMessage) }
        let dictionary = Pronunciations.all
        let temp = FileManager.default.temporaryDirectory.appending(path: "wordsync-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        do {
            let source = try AVAudioFile(forReading: audioURL)
            var result: [Int: [Double]] = [:]
            var matched = 0.0, total = 0.0
            for (n, group) in chunks(timeline).enumerated() {
                try Task.checkCancellation()
                guard AudioStamp(of: audioURL) == stamp else { return .failed(changedMessage) }
                let turns = group.map { timeline.turns[$0] }
                guard let first = turns.first, let last = turns.last else { continue }
                let start = max(0, first.start - 0.05)
                let end = min(timeline.duration, last.end + 0.05)
                let slice = temp.appending(path: "chunk-\(n).wav")
                try writeSlice(source, from: start, to: end, at: slice)
                let words = try await SpeechAlignment.recognize(slice, engine: engine).map {
                    RecognizedWord(text: $0.text, start: $0.start + start, end: $0.end + start)
                }
                try? FileManager.default.removeItem(at: slice)
                let scriptTurns = turns.map { ScriptTurn(speaker: $0.speaker, text: $0.text, style: "", sourcePage: nil) }
                let aligned = WordAligner.turnWordTimes(scriptTurns, language: language, dictionary: dictionary, recognized: words,
                                                        span: start...end, spans: turns.map { $0.start...max($0.start, $0.end) })
                let count = Double(scriptTurns.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count })
                matched += aligned.coverage * count
                total += count
                for (k, id) in group.enumerated() where !aligned.times[k].isEmpty { result[id] = aligned.times[k] }
            }
            guard total > 0, matched / total >= 0.5 else {
                return .failed("Ses metinle yeterince eşleşmedi; tahmini senkron kullanılıyor.")
            }
            return commit(result, episodeID: episodeID, audioURL: audioURL, stamp: stamp) ? .ready : .failed(changedMessage)
        } catch is CancellationError {
            return .failed(stoppedMessage)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static let changedMessage = "Bölüm sesi bu sırada değişti; kelime senkronu yeniden hazırlanacak."
    static let stoppedMessage = "Kelime senkronu durduruldu."

    /// Yalnız ses hâlâ `stamp` ise ve bölüm klasörü duruyorsa yazar. Yazdıktan sonra ses değişmişse dosya geri silinir
    /// (yazma ile `invalidate` arasındaki yarışta eski zaman kalmasın; `load` da damgayı ayrıca denetler).
    static func commit(_ times: [Int: [Double]], episodeID: UUID, audioURL: URL, stamp: AudioStamp,
                       root: URL = EpisodeFiles.root) -> Bool {
        let url = fileURL(episodeID, root: root)
        guard AudioStamp(of: audioURL) == stamp, save(times, to: url, audio: stamp) else { return false }
        guard AudioStamp(of: audioURL) == stamp else {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        return true
    }

    /// Bölüm sesinden [start, end] aralığını 16 bit WAV olarak yazar (parça parça okunur).
    static func writeSlice(_ source: AVAudioFile, from start: Double, to end: Double, at url: URL) throws {
        let format = source.processingFormat
        let rate = format.sampleRate
        let from = min(source.length, AVAudioFramePosition(max(0, start) * rate))
        let to = min(source.length, AVAudioFramePosition(max(0, end) * rate))
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate,
                                       AVNumberOfChannelsKey: Int(format.channelCount), AVLinearPCMBitDepthKey: 16,
                                       AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let writer = try AVAudioFile(forWriting: url, settings: settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        source.framePosition = from
        var remaining = max(0, to - from)
        while remaining > 0 {
            let chunk = AVAudioFrameCount(min(remaining, 48_000))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { break }
            try source.read(into: buffer, frameCount: chunk)
            if buffer.frameLength == 0 { break }
            try writer.write(from: buffer)
            remaining -= AVAudioFramePosition(buffer.frameLength)
        }
    }

    /// Türkçe mi? (Türkçe harf ya da sık kelime). Konuşma tanıyıcı yalnız tr-TR.
    static func looksTurkish(_ script: PodcastScript) -> Bool {
        let sample = script.flatScenes.prefix(6).flatMap { $0.scene.turns.map(\.text) }.joined(separator: " ")
        return looksTurkish(sample)
    }

    /// Yalnız dil bilinmediğinde tahmin. Tek bir "ö/ü/ç" (Schrödinger, Gödel) Türkçe saydırmaz: yalnız Türkçeye özgü
    /// harfler (ğ ı ş İ) ve sık kelimeler sayılır; kanıt yoksa ya da eşitse Türkçe DEĞİL (İngilizce bölümde gereksiz
    /// tr-TR tanıma, düşük kapsama ve kota harcayan yeniden üretim olmasın).
    static func looksTurkish(_ text: String) -> Bool {
        let words = text.split(whereSeparator: { !$0.isLetter })
        let tr: Set<String> = ["ve", "bir", "bu", "için", "ile", "da", "de", "ne", "çok", "gibi", "ama", "daha", "değil",
                               "olarak", "mi", "mu", "mü", "evet", "hayir", "şey", "yani", "peki", "şimdi"]   // katlanmış biçim (ı → i)
        let en: Set<String> = ["the", "and", "is", "of", "to", "in", "that", "it", "with", "a", "are", "you",
                               "this", "what", "we", "so", "yes", "for", "not", "but"]
        var t = 0, e = 0
        for word in words {
            let folded = TurkishFold.fold(String(word))
            if word.contains(where: { "ğışĞİŞ".contains($0) }) || tr.contains(folded) { t += 1 }
            else if en.contains(String(word).lowercased()) { e += 1 }
        }
        return t > e
    }
}
