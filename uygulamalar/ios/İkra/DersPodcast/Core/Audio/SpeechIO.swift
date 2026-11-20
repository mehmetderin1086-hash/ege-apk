import AVFoundation
import Foundation
import Observation
import Speech
import UIKit

/// Cihaz içi konuşma tanıma (Türkçe/İngilizce) + isteğe bağlı ses kaydı.
/// Sokratik cevap, Feynman anlatımı, sesli kart tekrarı ve sesli not bunu kullanır.
@Observable
final class SpeechRecorder {
    private(set) var transcript = ""
    private(set) var level: Float = 0
    private(set) var isRecording = false
    /// Durdurma sürüyor (tanıyıcı son sözcükleri topluyor): bu sırada yeni kayıt başlamaz, düğme pasif kalmalı.
    private(set) var isStopping = false
    private(set) var error: String?
    /// true: uygulama arka plandayken (ekran kilitliyken) kayıt açılmaz (#29 Anlatarak hatırla).
    /// Varsayılan false: sesli kart tekrarı gibi ekrana bakmadan çalışan akışlar kilitliyken de dinler.
    let foregroundOnly: Bool

    private var io: SpeechCaptureIO?
    private var levelTask: Task<Void, Never>?
    private var finishing: Task<String, Never>?
    /// Kayıt oturumu sayacı: önceki kaydın geç gelen sonucu ya da hatası yeni kaydın transkriptine yazılmasın.
    private var session = 0

    static let recognitionStoppedMessage = "Konuşma tanıma durdu. Kaydı bitirip yeniden dene."

    init(foregroundOnly: Bool = false) {
        self.foregroundOnly = foregroundOnly
    }

    /// "Tanıma durdu" iletisi süren kayda aittir, kayıt kapanınca kalkar (yoksa bir sonraki `start`a kadar, kayıt
    /// yokken de ekranda dururdu). Başlangıç hataları (izin yok gibi kalıcı durumlar) yerinde kalır.
    private func clearRecognitionStopped() {
        if error == Self.recognitionStoppedMessage { error = nil }
    }

    #if DEBUG
    /// Testler: mikrofon olmadan hata durumunu taklit eder.
    func setErrorForTesting(_ message: String?) { error = message }
    #endif

    /// Mikrofon + konuşma tanıma izinlerini ister.
    /// Sistem geri çağrısı arka plan kuyruğunda gelir: kapanış MainActor'a bağlı olmamalı (Swift 6 çalışma zamanı denetimi çöker).
    nonisolated static func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in c.resume(returning: status) }
        }
    }

    static func requestPermissions() async -> String? {
        guard await AVAudioApplication.requestRecordPermission() else {
            return "Mikrofon izni verilmedi. Ayarlar → \(Config.appName) → Mikrofon'dan açabilirsin."
        }
        let status = await speechAuthorization()
        guard status == .authorized else {
            return "Konuşma tanıma izni verilmedi. Ayarlar → \(Config.appName) → Konuşma Tanıma'dan açabilirsin."
        }
        return nil
    }

    /// Kayda başlar. `recordTo` verilirse ses ayrıca m4a dosyasına yazılır.
    func start(language: String = "tr-TR", recordTo file: URL? = nil) async {
        // Önceki kaydın kapanışı sürerken yenisi başlamaz (eski kapanış yeni oturumu kapatmasın; çift dokunma).
        guard !isRecording, !isStopping else { return }
        session += 1
        let current = session
        transcript = ""
        error = nil
        // Yalnız isteyen akışta: kilitliyken / arka planda mikrofon açılmaz (#29).
        if foregroundOnly, UIApplication.shared.applicationState == .background {
            error = "Kayıt yalnız uygulama açıkken yapılabilir."
            return
        }
        // Kayıttan önce: okuma bitsin, podcast ve önizleme dursun (aksi halde mikrofon hoparlörü de yazıya döker).
        SpeechOut.shared.stop()
        AppState.current?.player.suspendForLiveSession()
        if let message = await Self.requestPermissions() {
            error = message
            return
        }
        let io = SpeechCaptureIO(locale: Locale(identifier: language))
        do {
            try io.start(recordTo: file, onText: { [weak self] text in
                Task { @MainActor in
                    guard let self, self.session == current else { return }
                    self.transcript = text
                }
            }, onFailure: { [weak self] _ in
                // Yalnız yazıya dökme durdu: ses dosyası kaydı sürer, o ana kadarki metin durur.
                Task { @MainActor in
                    guard let self, self.session == current, self.isRecording else { return }
                    self.error = SpeechRecorder.recognitionStoppedMessage
                }
            })
        } catch {
            io.cancel()   // yarım kalan dinleyici/oturum açık kalmasın
            self.error = "Kayıt başlatılamadı: \(error.localizedDescription)"
            return
        }
        self.io = io
        isRecording = true
        levelTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, let io = self.io else { return }
                self.level = io.level
            }
        }
    }

    /// Kaydı durdurur ve son transkripti döndürür (tanıyıcının son sözcükleri toparlaması için kısa bekler).
    /// Son kayıtta dosyaya yazma hatası oldu mu (sesli not kaydedilmemeli).
    private(set) var lastRecordingFailed = false

    /// Yeniden girişe dayanıklı: kapanış sürerken gelen ikinci çağrı (çift dokunma, 45 sn sayacı) aynı sonucu bekler;
    /// kayıt durumu beklemeden önce kapanır, böylece `isRecording` bakan ikinci yol bir daha durdurmaz.
    @discardableResult
    func stop() async -> String {
        clearRecognitionStopped()
        if let finishing {
            let final = await finishing.value
            return final.isEmpty ? transcript : final
        }
        guard let io else { return transcript }
        self.io = nil
        isRecording = false
        isStopping = true
        levelTask?.cancel()
        level = 0
        let task = Task { await io.finish() }
        finishing = task
        let final = await task.value
        finishing = nil
        isStopping = false
        lastRecordingFailed = io.hadWriteError
        if !final.isEmpty { transcript = final }
        return transcript
    }

    func cancel() {
        session += 1
        levelTask?.cancel()
        io?.cancel()
        io = nil
        isRecording = false
        level = 0
        clearRecognitionStopped()
    }
}

/// Ses iş parçacığında çalışan kısım (ana aktöre bağlı değil).
nonisolated final class SpeechCaptureIO: @unchecked Sendable {
    /// Bir kayıtta tanıma görevi en çok bu kadar kez yeniden kurulur.
    static let maxRestarts = 10
    /// İki görev kurulumu arasındaki en kısa süre (sn): hemen kapanan görev sıkı döngüye girmesin.
    static let minRestartInterval: TimeInterval = 1

    nonisolated private enum Ending { case ignore, resolve, restart(after: TimeInterval), fail }

    private let engine = AVAudioEngine()
    private let recognizer: SFSpeechRecognizer?
    private var file: AVAudioFile?
    private let lock = NSLock()
    // İstek ve görev kayıt boyunca değişebilir; ses iş parçacığı, tanıyıcı kuyruğu ve yeniden başlatma zamanlayıcısı
    // ortak kullandığı için kilitle korunur.
    /// Süren görevin isteği. Görev kapanıp yenisi kurulana kadar nil: o aradaki tamponlar tanımaya gitmez.
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    /// Kapanan görevlerden kalan metin; süren görevin metni bunun ardına eklenir.
    private var committed = ""
    /// Görev kuşağı: kapanmış görevin geç gelen geri çağrıları yok sayılır (metin iki kez eklenmesin, iki kez kurulmasın).
    private var generation = 0
    private var restarts = 0
    private var taskStarted: TimeInterval = 0
    private var currentLevel: Float = 0
    /// Son transkript bir kez çözülür; birden çok bekleyen olabilir (hiçbiri asılı kalmaz).
    private let finalText = OnceValue<String>()
    private var finishing = false
    private var writeFailed = false
    /// Kayıt dosyasına yazma hatası oldu mu (sesli not bozuk olabilir).
    var hadWriteError: Bool { lock.withLock { writeFailed } }

    var level: Float { lock.withLock { currentLevel } }

    init(locale: Locale) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    /// Önceki görevlerden kalan metinle süren görevin metnini birleştirir (saf).
    static func join(_ committed: String, _ current: String) -> String {
        if committed.isEmpty || current.hasPrefix(committed) { return current }
        if current.isEmpty { return committed }
        return committed.last?.isWhitespace == true ? committed + current : committed + " " + current
    }

    /// Kayıt sürerken kapanan görevin ardından tanıma yeni görevle sürdürülür mü (saf). Hiç metin gelmeden hata
    /// (ör. cihazda Dikte kapalı) yeniden denenmez; sınır aşılınca da bırakılır.
    static func shouldRestart(hadError: Bool, text: String, restarts: Int) -> Bool {
        restarts < maxRestarts && !(hadError && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// Önceki görev `elapsed` sn önce kurulduysa yenisinden önce beklenecek süre (saf).
    static func restartDelay(elapsed: TimeInterval) -> TimeInterval {
        min(max(0, minRestartInterval - elapsed), minRestartInterval)
    }

    /// `onFailure`: tanıma kayıt sürerken sürdürülemez biçimde durdu (en çok bir kez; kapanış başladıktan sonra çağrılmaz).
    /// Ses ve dosya kaydı etkilenmez. Verilen metin ayrıntıdır (sistemin hata açıklaması), kullanıcıya gösterilecek ileti değil.
    func start(recordTo url: URL?, onText: @escaping @Sendable (String) -> Void,
               onFailure: @escaping @Sendable (String) -> Void = { _ in }) throws {
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "Speech", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bu dilde konuşma tanıma şu an kullanılamıyor."])
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw NSError(domain: "Speech", code: 2, userInfo: [NSLocalizedDescriptionKey: "Mikrofon bulunamadı."])
        }
        if let url {
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate,
                                           AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 48_000]
            file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            lock.withLock { request }?.append(buffer)
            lock.withLock {
                guard let file else { return }
                do { try file.write(from: buffer) } catch { writeFailed = true }
            }
            if let channel = buffer.floatChannelData?[0] {
                let n = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<n { sum += channel[i] * channel[i] }
                let rms = n > 0 ? (sum / Float(n)).squareRoot() : 0
                lock.withLock { currentLevel = min(1, rms * 12) }
            }
        }
        startTask(onText: onText, onFailure: onFailure)
        engine.prepare()
        try engine.start()
    }

    /// Yeni istek ve görev kurar. Tanıyıcı görevi kayıt sürerken kendiliğinden kapatabilir (sunucu tanımasında yaklaşık
    /// 1 dakikalık sınır, uzun duraksamada kesinleşme, hata); o zaman `taskEnded` tanımayı yeni görevle sürdürür.
    private func startTask(onText: @escaping @Sendable (String) -> Void, onFailure: @escaping @Sendable (String) -> Void) {
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        // Bekleyen yeniden başlatma kapanışla yarışabilir: kapanış başladıysa yeni görev kurulmaz.
        let id = lock.withLock { () -> Int? in
            guard !finishing else { return nil }
            self.request = request
            taskStarted = ProcessInfo.processInfo.systemUptime
            return generation
        }
        guard let id else { return }
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            var ended = error != nil
            if let result {
                let text = lock.withLock { () -> String? in
                    guard id == generation else { return nil }
                    latest = Self.join(committed, result.bestTranscription.formattedString)
                    return latest
                }
                if let text { onText(text) }
                if result.isFinal { ended = true }
            }
            if ended { taskEnded(id, error: error, onText: onText, onFailure: onFailure) }
        }
        lock.withLock { if id == generation { self.task = task } }
    }

    /// Görev son sonucunu ya da hatasını verdi. Kapanış sürüyorsa bekleyen `finish` çözülür. Kayıt sürüyorsa o ana kadarki
    /// metin `committed` olur ve tanıma yeni görevle sürer; sürdürülemiyorsa `onFailure` çağrılır.
    private func taskEnded(_ id: Int, error: (any Error)?, onText: @escaping @Sendable (String) -> Void,
                           onFailure: @escaping @Sendable (String) -> Void) {
        let ending = lock.withLock { () -> Ending in
            guard id == generation else { return .ignore }
            if finishing { return .resolve }
            generation += 1
            request = nil
            task = nil
            guard Self.shouldRestart(hadError: error != nil, text: latest, restarts: restarts) else { return .fail }
            restarts += 1
            committed = latest
            return .restart(after: Self.restartDelay(elapsed: ProcessInfo.processInfo.systemUptime - taskStarted))
        }
        switch ending {
        case .ignore: break
        case .resolve: resolve()
        case .fail: onFailure(error?.localizedDescription ?? "Tanıma görevi çok kez kapandı.")
        case let .restart(delay):
            // Olağan durumda (görev 1 sn'den uzun sürdü) hemen kurulur: arada ses kaçmasın.
            if delay <= 0 {
                startTask(onText: onText, onFailure: onFailure)
            } else {
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.startTask(onText: onText, onFailure: onFailure)
                }
            }
        }
    }

    /// Kaydı bitirir; tanıyıcı son sonucu verene kadar en fazla 1,5 sn bekler.
    /// İkinci çağrı sesi yeniden kapatmaz, aynı sonucu bekler (önceki bekleyenin üzerine yazılmaz).
    func finish() async -> String {
        let (first, live) = lock.withLock { () -> (Bool, SFSpeechAudioBufferRecognitionRequest?) in
            defer { finishing = true }
            return (!finishing, request)
        }
        if first {
            stopAudio()
            if let live {
                live.endAudio()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.resolve() }
            } else {
                resolve()   // süren görev yok (tanıma durdu ya da yeniden kurulmayı bekliyordu): beklenecek son sonuç da yok
            }
        }
        return await finalText.wait()
    }

    func cancel() {
        stopAudio()
        let (live, task) = lock.withLock { () -> (SFSpeechAudioBufferRecognitionRequest?, SFSpeechRecognitionTask?) in
            finishing = true
            return (request, self.task)
        }
        // O anda kurulmakta olan görev `task`a henüz yazılmamış olabilir: isteği kapatmak onu da sonlandırır.
        live?.endAudio()
        task?.cancel()
        resolve()
    }

    private func stopAudio() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.withLock { file = nil }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Yalnız kapanış başladıktan sonra çözer (ilk gelen kazanır); kayıt sürerken biten görevi `taskEnded` ele alır.
    private func resolve() {
        let (ready, text) = lock.withLock { (finishing, latest) }
        if ready { finalText.resolve(text) }
    }
}

/// Bir kez çözülen değer; çözülmeden önce de sonra da bekleyen herkes aynı sonucu alır.
nonisolated final class OnceValue<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?
    private var waiters: [CheckedContinuation<Value, Never>] = []

    var isResolved: Bool { lock.withLock { value != nil } }

    func wait() async -> Value {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock { () -> Value? in
                if let value { return value }
                waiters.append(continuation)
                return nil
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }

    /// İlk çağrı kazanır; sonrakiler yok sayılır.
    func resolve(_ newValue: Value) {
        let pending = lock.withLock { () -> [CheckedContinuation<Value, Never>] in
            guard value == nil else { return [] }
            value = newValue
            let pending = waiters
            waiters = []
            return pending
        }
        for waiter in pending { waiter.resume(returning: newValue) }
    }
}

/// Cihaz sesiyle metin okuma (asistan cevabı, Sokratik sorular, sesli kartlar). `speak` okuma bitince döner.
/// Ayarlar › Ses'teki ses, modeli inmiş bir iPhone motoruysa (EMA-TTS, Supertonic, Piper) Türkçe metin o motorla üretilip
/// çalınır (kullanıcı kararı, 17 Eki 2026: asistan EMA-TTS ile konuşsun); değilse Apple'ın sesi okur.
@MainActor
@Observable
final class SpeechOut: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechOut()
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?
    /// Bekleyen okumanın utterance'ı; eski okumanın geç gelen geri çağrısı yenisini erken bitirmesin.
    private var current: ObjectIdentifier?
    /// Cihaz içi sinir ağı motoruyla süren okuma (üretim + çalma); yeni okuma ya da `stop` eskisini geçersiz kılar.
    private var neural: UUID?
    /// Cihaz içi okumanın çaları: tek motor + tek çalar düğümü; parçalar kesintisiz art arda sıralanır (parça başına yeni çalar
    /// açılmaz: parça eklerinde tıkırtı ve ses oturumu çalkantısı olmaz).
    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    private var scheduled = 0
    private var allScheduled = false
    private var playbackDone: CheckedContinuation<Void, Never>?
    private(set) var isSpeaking = false
    /// Okunan metin ve şu an seslendirilen aralığı (okurken takip için).
    private(set) var spokenText: String?
    private(set) var spokenRange: NSRange?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Aynı metin okunurken yeniden istenirse okuma durur ("Sesli oku" düğmeleri aç/kapa gibi davranır). Çağıran görev
    /// iptal edilirse (görünüm kapandı) okuma susar. Boş metin okunmaz.
    func speak(_ text: String, language: String = "tr-TR", rate: Float = 0.5) async {
        if isSpeaking, spokenText == text {
            stop()
            return
        }
        stop()
        // Boş metinde bitiş geri çağrısı gelmeyebilir: devam asılı, `isSpeaking` true kalırdı.
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !Task.isCancelled else { return }
        AppState.current?.player.suspendForLiveSession()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        if language.hasPrefix("tr"), let settings = Self.neuralSettings(), await speakNeural(text, settings: settings, rate: rate) { return }
        let utterance = AVSpeechUtterance(string: text)
        let id = ObjectIdentifier(utterance)
        spokenText = text
        spokenRange = nil
        utterance.voice = Self.bestVoice(for: language)
        utterance.rate = rate
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                current = id
                isSpeaking = true
                synthesizer.speak(utterance)
            }
        } onCancel: {
            // Araya giren yeni okumaya dokunmaz: yalnız bu çağrının okuması sürüyorsa durdurur.
            Task { @MainActor in if self.current == id { self.stop() } }
        }
    }

    func stop() {
        current = nil
        neural = nil
        isSpeaking = false
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        node?.stop(); engine?.stop()
        node = nil; engine = nil
        scheduled = 0; allScheduled = false
        playbackDone?.resume(); playbackDone = nil
        continuation?.resume()
        continuation = nil
    }

    /// Ayarlar › Ses'teki birincil ses, modeli telefona inmiş bir cihaz içi sinir ağı motoruysa onun podcast ayarı (tek anlatıcı);
    /// Apple, Chirp ya da sunucu sesiyse `nil` (Apple'ın sesi okur: asistan cevabı sunucu sırası beklemesin).
    static func neuralSettings(_ defaults: UserDefaults = .standard) -> PodcastSettings? {
        var key = AppVoice.primary(defaults)
        if !(key.engine.speech?.isNeuralOnDevice ?? false), OfflineModelCatalog.ready(.ema) {
            // Kullanıcı kararı (17 Eki 2026, "hâlâ eski ses"): EMA-TTS indirildiyse ses ayarı başka olsa da asistan ve okumalar EMA ile konuşur.
            key = QSVoiceKey(local: .ema, voice: "tr")
        }
        guard let speech = key.engine.speech, speech.isNeuralOnDevice, OfflineModelCatalog.ready(speech) else { return nil }
        var settings = PodcastSettings()
        settings.apply(voiceA: key)
        settings.format = .tekAnlatici
        settings.language = .tr
        // AVSpeech hızı 0,5 = olağan; 0,4 → %80, 0,6 → %120 (podcast tempo adımlarıyla aynı aralık).
        return settings
    }

    /// Metni cihaz içi motorla cümle cümle üretip çalar: ilk parça (kısa tutulur) hazır olunca çalma başlar, sonrakiler çalma
    /// sırasında üretilip aynı çalar düğümüne kesintisiz eklenir (gecikme bütün cevabın değil ilk cümlenin üretim süresi kadar).
    /// Her parça sahne düzeyine (yaklaşık −16 dBFS) eşitlenir. Okuma bitince (ya da `stop`/iptalle) döner. İlk parça
    /// üretilemezse `false`: çağıran Apple'ın sesine düşer.
    private func speakNeural(_ text: String, settings: PodcastSettings, rate: Float) async -> Bool {
        let id = UUID()
        neural = id
        spokenText = text
        spokenRange = nil
        isSpeaking = true
        var settings = settings
        settings.pace = rate < 0.45 ? .yavas : rate > 0.55 ? .hizli : .normal
        let pieces = Self.pieces(text)
        guard !pieces.isEmpty else { neural = nil; isSpeaking = false; return false }
        let fixed = settings
        let dictionary = Pronunciations.all
        func render(_ piece: String) -> Task<PCMClip, Error> {
            Task.detached(priority: .userInitiated) { [fixed, dictionary, piece] in
                let turns = SpeakableText.prepare([ScriptTurn(speaker: .a, text: piece, style: "", sourcePage: nil)], language: .tr, dictionary: dictionary).turns
                let clip = try await NeuralSpeechRenderer.shared.scene(turns: turns, settings: fixed)
                return QSAudioPolish.polished(clip, gap: 0.12)
            }
        }
        scheduled = 0; allScheduled = false
        var pending: Task<PCMClip, Error>? = render(pieces[0])
        #if DEBUG
        var dump: [Int16] = []
        #endif
        for index in pieces.indices {
            guard let task = pending else { break }
            let clip: PCMClip
            do { clip = try await task.value }
            catch {
                guard neural == id else { return true }
                pending = nil
                if index == 0 { neural = nil; isSpeaking = false; return false }
                break
            }
            guard neural == id, !Task.isCancelled else { pending?.cancel(); return true }
            // Sonraki parça, bu parça çalarken üretilir.
            pending = index + 1 < pieces.count ? render(pieces[index + 1]) : nil
            #if DEBUG
            dump += clip.samples
            #endif
            do { try enqueue(clip, id: id) }
            catch {
                pending?.cancel()
                if index == 0 { neural = nil; isSpeaking = false; return false }
                break
            }
        }
        allScheduled = true
        if scheduled > 0, neural == id {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in self.playbackDone = continuation }
            } onCancel: {
                Task { @MainActor in if self.neural == id { self.stop() } }
            }
        }
        #if DEBUG
        // Cihazda dinleme kalitesini incelemek için son okuma Documents/son-okuma.wav'a yazılır.
        if !dump.isEmpty { try? WAV.encode(PCMClip(samples: dump, sampleRate: 48_000)).write(to: URL.documentsDirectory.appending(path: "son-okuma.wav")) }
        #endif
        guard neural == id else { return true }
        neural = nil
        isSpeaking = false
        node?.stop(); engine?.stop(); node = nil; engine = nil
        return true
    }

    /// Okunacak parçalar: ilk parça kısa (ilk ses erken gelsin), sonrakiler cümle sınırında en çok 220 karakter.
    nonisolated static func pieces(_ text: String) -> [String] {
        let all = LocalSpeech.chunks(text, limit: 220)
        guard let first = all.first else { return [] }
        return LocalSpeech.chunks(first, limit: 110) + all.dropFirst()
    }

    /// Parçayı çalar düğümüne ekler; düğüm çalmıyorsa başlatır. Tamamlanma geri çağrısı sayacı düşürür; hepsi çalınınca okuma biter.
    private func enqueue(_ clip: PCMClip, id: UUID) throws {
        let node = try playerNode()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(clip.sampleRate), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(clip.samples.count)) else {
            throw OfflineSpeechError.noAudio
        }
        buffer.frameLength = AVAudioFrameCount(clip.samples.count)
        let channel = buffer.floatChannelData![0]
        for (index, sample) in clip.samples.enumerated() { channel[index] = Float(sample) / 32_768 }
        scheduled += 1
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.bufferPlayed(id) }
        }
        if !node.isPlaying { node.play() }
    }

    private func bufferPlayed(_ id: UUID) {
        guard neural == id else { return }
        scheduled = max(0, scheduled - 1)
        if scheduled == 0, allScheduled { playbackDone?.resume(); playbackDone = nil }
    }

    /// Tek motor + tek çalar düğümü (48 kHz tek kanal; karıştırıcı donanım hızına çevirir).
    private func playerNode() throws -> AVAudioPlayerNode {
        if let node, let engine, engine.isRunning { return node }
        let engine = AVAudioEngine(), node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        engine.prepare()
        try engine.start()
        self.engine = engine; self.node = node
        return node
    }

    /// En kaliteli yerel ses (premium > enhanced > varsayılan).
    static func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        SpeechVoiceCatalog.voices(language: language).max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: language)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in if id == self.current { self.spokenRange = characterRange } }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id) }
    }

    private func finished(_ id: ObjectIdentifier) {
        guard id == current else { return }
        current = nil
        isSpeaking = false
        continuation?.resume()
        continuation = nil
    }
}
