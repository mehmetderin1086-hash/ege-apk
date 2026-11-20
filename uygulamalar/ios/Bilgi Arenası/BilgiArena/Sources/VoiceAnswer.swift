import Foundation
import AVFoundation
import Combine
@preconcurrency import WhisperKit

actor LocalAnswerWhisper {
    static let model = "openai_whisper-small"
    static var root: URL { FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("WhisperModelleri") }
    static var modelFolder: URL { root.appendingPathComponent("models/argmaxinc/whisperkit-coreml/"+model) }
    static var downloaded: Bool { ["AudioEncoder.mlmodelc","TextDecoder.mlmodelc","MelSpectrogram.mlmodelc"].allSatisfy { FileManager.default.fileExists(atPath:modelFolder.appendingPathComponent($0).path) } }
    static var downloadedBytes: Int {
        guard let items = FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.fileSizeKey]) else { return 0 }
        return items.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys:[.fileSizeKey]).fileSize } }.reduce(0,+)
    }
    private var engine: WhisperKit?
    private var metrics: [String:Double] = [:]
    func diagnostics() -> [String:Double] { metrics }
    private var preparation: Task<Void,Error>?
    private var decoding: Task<String,Error>?
    private var releaseTask: Task<Void,Never>?
    func prepare(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        if let releaseTask { await releaseTask.value }
        if engine != nil { return }
        if let preparation { try await preparation.value; return }
        let task = Task {
            if !Self.downloaded {
                _ = try await WhisperKit.download(variant:Self.model,downloadBase:Self.root) { progress($0.fractionCompleted) }
            }
            try Task.checkCancellation()
            let config = WhisperKitConfig(model:Self.model,downloadBase:Self.root,modelFolder:Self.modelFolder.path,tokenizerFolder:Self.root,
                                          computeOptions:ModelComputeOptions(melCompute:.cpuOnly,audioEncoderCompute:.cpuAndGPU,textDecoderCompute:.cpuAndGPU),
                                          verbose:false,logLevel:.error,prewarm:true,load:true,download:false)
            let engine = try await WhisperKit(config)
            try Task.checkCancellation(); self.engine = engine
        }
        preparation = task
        defer { preparation = nil }
        try await task.value
    }
    func unload() async {
        if let releaseTask { await releaseTask.value; return }
        preparation?.cancel(); _ = try? await preparation?.value
        let active = decoding, loaded = engine; engine = nil
        let release = Task { active?.cancel(); _ = try? await active?.value; await loaded?.unloadModels() }
        releaseTask = release
        await release.value; releaseTask = nil
    }
    func transcribe(_ url: URL, language: String = "tr") async throws -> String {
        guard decoding == nil else { throw QuizError("Önceki ses çözümlemesi bitiyor. Birazdan yeniden dene.") }
        let task = Task { try await self.decode(url,language:language) }
        decoding = task
        defer { decoding = nil }
        return try await withTaskCancellationHandler(operation:{ try await task.value },onCancel:{ task.cancel() })
    }
    private func decode(_ url: URL, language: String) async throws -> String {
        guard let engine else { throw QuizError("Önce Whisper'ı hazırla.") }
        try Task.checkCancellation()
        let rawAudio = try AudioProcessor.loadAudioAsFloatArray(fromPath:url.path)
        let rms = sqrt(rawAudio.reduce(0.0) { $0+Double($1*$1) } / Double(max(1,rawAudio.count)))
        metrics = ["rms":rms,"seconds":Double(rawAudio.count)/16000]
        guard rawAudio.count >= 4000, rawAudio.count <= 16_000*30, rms > 0.003 else { return "" }
        let audio = Array(repeating:Float(0),count:8000)+rawAudio+Array(repeating:Float(0),count:8000)
        var options = DecodingOptions(task:.transcribe,language:language,temperature:0,temperatureFallbackCount:1,usePrefillPrompt:true,detectLanguage:false,skipSpecialTokens:true,withoutTimestamps:true,suppressBlank:true,noSpeechThreshold:0.6,concurrentWorkerCount:1)
        var results = try await engine.transcribe(audioArray:audio,decodeOptions:options)
        if results.map(\.text).joined().trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
            options.noSpeechThreshold = nil; options.firstTokenLogProbThreshold = nil; options.logProbThreshold = nil
            results = try await engine.transcribe(audioArray:audio,decodeOptions:options)
        }
        metrics["noSpeech"] = Double(results.flatMap(\.segments).map(\.noSpeechProb).max() ?? 0)
        try Task.checkCancellation()
        return results.map(\.text).joined(separator:" ").trimmingCharacters(in:.whitespacesAndNewlines)
    }
}

@MainActor final class VoiceAnswerStore: NSObject, ObservableObject, AVAudioRecorderDelegate {
    enum Phase: Equatable { case idle, preparing, requestingMicrophone, recording, transcribing }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var ready = false
    @Published private(set) var level = 0.0
    @Published private(set) var progress = 0.0
    @Published var transcript = ""
    @Published private(set) var error: String?
    let whisper = LocalAnswerWhisper()
    private var recorder: AVAudioRecorder?
    private var file: URL?
    private var operation: Task<Void,Never>?
    private var generation = UUID()
    private var language = "tr"
    private var metering: Task<Void,Never>?
    private var endpoint = VoiceEndpointDetector()
    private var automaticStop = false
    private var peakDB: Float = -100
    private func recordDiagnostic(_ event: String, code: Int? = nil) {
        #if DEBUG
        var value: [String:Any] = ["event":event,"time":Date().timeIntervalSince1970,"phase":String(describing:phase),"permission":AVAudioApplication.shared.recordPermission.rawValue,"modelPresent":LocalAnswerWhisper.downloaded,"ready":ready,"peakDB":Double(peakDB)]
        if let code { value["errorCode"] = code }
        let url = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("voice-answer-state.json")
        if let data = try? JSONSerialization.data(withJSONObject:value) { try? data.write(to:url,options:[.atomic,.completeFileProtection]) }
        #endif
    }
    func prepare() {
        guard phase == .idle, !ready, !deleting else { return }
        phase = .preparing; error = nil; progress = 0
        let id = generation
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                try await whisper.prepare { [weak self] progress in Task { @MainActor in if self?.generation == id { self?.progress = progress } } }
                guard !Task.isCancelled, generation == id else { return }
                ready = true; phase = .idle; recordDiagnostic("model-ready")
            } catch { if generation == id { phase = .idle; self.error = "Whisper hazırlanamadı. Modeli ve boş alanı kontrol edip yeniden dene." } }
        }
    }
    func record(language: String = "tr", automaticStop: Bool = false) {
        guard ready, phase == .idle else { return }
        let limits = ArenaPreferences.endpoint(); self.automaticStop = automaticStop; endpoint = .init(limits:limits); peakDB = -100; self.language = language; transcript = ""; error = nil; phase = .requestingMicrophone; recordDiagnostic("request-microphone")
        let id = generation
        operation = Task { [weak self] in
            guard let self else { return }
            let allowed = await AVAudioApplication.requestRecordPermission()
            guard !Task.isCancelled, generation == id else { return }
            guard allowed else { phase = .idle; self.error = "Mikrofon izni kapalı. iPhone Ayarları'ndan Bilgi Arenası için açabilirsin."; recordDiagnostic("permission-denied"); return }
            let activation: (Bool,Int) = await withCheckedContinuation { continuation in
                GameAudio.sessionQueue.async {
                    do {
                        try AVAudioSession.sharedInstance().setCategory(.playAndRecord,mode:.default,options:[.defaultToSpeaker,.allowBluetoothHFP])
                        try AVAudioSession.sharedInstance().setActive(true); continuation.resume(returning:(true,0))
                    } catch { continuation.resume(returning:(false,(error as NSError).code)) }
                }
            }
            guard !Task.isCancelled, generation == id else { return }
            guard activation.0 else { phase = .idle; self.error = "Mikrofon açılamadı. Diğer sesli görüşmeyi kapatıp Bilgi Arenası öndeyken yeniden dene."; recordDiagnostic("audio-session-failed",code:activation.1); return }
            do {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-answer-"+UUID().uuidString+".m4a")
                file = url
                recorder = try AVAudioRecorder(url:url,settings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:16000,AVNumberOfChannelsKey:1,AVEncoderAudioQualityKey:AVAudioQuality.high.rawValue])
                recorder?.delegate = self; recorder?.isMeteringEnabled = true
                guard recorder?.record(forDuration:limits.maximum) == true else { throw QuizError("Kayıt başlatılamadı.") }
                phase = .recording; recordDiagnostic("recording")
                metering = Task { [weak self] in
                    while !Task.isCancelled, let self, self.generation == id, self.phase == .recording {
                        try? await Task.sleep(for:.milliseconds(100))
                        guard !Task.isCancelled, self.generation == id, self.phase == .recording else { return }
                        self.recorder?.updateMeters()
                        let db = self.recorder?.averagePower(forChannel:0) ?? -100
                        self.peakDB = max(self.peakDB,db)
                        self.level = max(0,min(1,Double((db+55)/55)))
                        if automaticStop, self.endpoint.sample(db:Double(db),seconds:0.1) { self.finishRecording(); return }
                    }
                }
            } catch { cancel(); self.error = "Ses kaydı başlatılamadı. Tekrar dene."; recordDiagnostic("recording-failed",code:(error as NSError).code) }
        }
    }
    func finishRecording() {
        guard phase == .recording, let url = file else { return }
        metering?.cancel(); metering = nil; level = 0
        if automaticStop && !endpoint.heardSpeech {
            recorder?.stop(); recorder = nil; try? FileManager.default.removeItem(at:url); file = nil; phase = .idle; error = "Ses duyulmadı. Mikrofon açıkken yeniden söyle."; recordDiagnostic("no-speech"); releaseAudio(); return
        }
        phase = .transcribing; recorder?.stop(); recorder = nil; recordDiagnostic("transcribing")
        let id = generation
        operation = Task { [weak self] in
            guard let self else { return }
            defer { try? FileManager.default.removeItem(at:url); if generation == id { file = nil; phase = .idle }; releaseAudio() }
            do {
                let text = try await whisper.transcribe(url,language:language)
                guard !Task.isCancelled, generation == id else { return }
                transcript = String(text.prefix(600))
                if transcript.isEmpty { self.error = "Konuşma anlaşılamadı. Daha net bir kayıtla yeniden dene." }
                recordDiagnostic(transcript.isEmpty ? "empty-transcript" : "transcript-ready")
            } catch { if generation == id { self.error = "Ses yazıya çevrilemedi. Yeniden dene veya dokunarak cevapla."; recordDiagnostic("transcription-failed",code:(error as NSError).code) } }
        }
    }
    func cancel() {
        if phase != .idle { recordDiagnostic("cancelled-"+String(describing:phase)) }
        generation = UUID(); operation?.cancel(); operation = nil
        metering?.cancel(); metering = nil; level = 0
        recorder?.stop(); recorder = nil
        if let file { try? FileManager.default.removeItem(at:file) }; file = nil
        phase = .idle; releaseAudio()
    }
    func suspend() { cancel(); ready = false; Task { await whisper.unload() } }
    /// Modeli bellekten indirir ve indirilen dosyaları siler; sonraki kullanımda yeniden indirilir.
    func deleteModel() async {
        deleting = true; defer { deleting = false }
        cancel(); ready = false; error = nil
        await whisper.unload()
        try? FileManager.default.removeItem(at:LocalAnswerWhisper.root)
    }
    private var deleting = false
    private func releaseAudio() { GameAudio.sessionQueue.async { try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation) } }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in guard self?.recorder === recorder else { return }; self?.finishRecording() }
    }
}

enum SpokenAnswer: Equatable { case choice(Int), activity(ActivityResponse) }
enum VoiceAnswerResolver {
    static func clean(_ text: String) -> String { Question.normalized(text).replacingOccurrences(of:"ı",with:"i").unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }.joined().split(whereSeparator:\.isWhitespace).joined(separator:" ") }
    static func resolve(_ text: String, for question: Question) -> SpokenAnswer? {
        let key = clean(text)
        guard !key.isEmpty, key.count <= 600 else { return nil }
        if let activity = question.activity, activity.kind == .pronunciation { guard text.count <= 300 else { return nil }; return .activity(.init(indices:[],spokenText:text)) }
        if let activity = question.activity, activity.isInteractive {
            let words = key.split(separator:" ").map(String.init)
            let numbers = ["bir":0,"iki":1,"uc":2,"dort":3,"1":0,"2":1,"3":2,"4":3]
            let indices = words.compactMap { numbers[$0] }
            guard indices.count == 4, Set(indices) == Set(0..<4) else { return nil }
            return .activity(.init(indices:indices,spokenText:text))
        }
        let (value,pointer,filler) = core(key)
        let exact = question.options.indices.filter { clean(question.options[$0]) == value }
        // Rakam yalnız hiçbir seçenekte rakam yokken ya da "şık/seçenek" sözcüğüyle şık sırası sayılır; aksi hâlde metindir.
        let numericOptions = question.options.contains { $0.contains(where:\.isNumber) }
        var byPosition = letters[value] ?? ordinals[value]
        if byPosition == nil, let digit = Int(value), (1...4).contains(digit), pointer || !numericOptions { byPosition = digit-1 }
        // "Bence de" onay sözüdür; dolgudan sonra kalan tek "de" şık sayılmaz.
        if value == "de" && filler && !pointer { byPosition = nil }
        if let byPosition, pointer || exact.isEmpty || exact == [byPosition] { return .choice(byPosition) }
        if exact.count == 1 { return .choice(exact[0]) }
        let words = key.split(separator:" ").map(String.init)
        guard !words.contains(where:{ $0.hasPrefix("degil") || $0 == "veya" || $0 == "yahut" || $0 == "olamaz" || $0.hasPrefix("haric") }), !(" "+key+" ").contains(" ya da ") else { return nil }
        let mentions = question.options.indices.filter { (" "+key+" ").contains(" "+clean(question.options[$0])+" ") }
        if mentions.count == 1 { return .choice(mentions[0]) }
        guard mentions.isEmpty, !numericOptions, !value.contains(where:\.isNumber) else { return nil }
        return closest(value,in:question.options.map(clean)).map(SpokenAnswer.choice)
    }
    static let letters = ["a":0,"b":1,"be":1,"c":2,"ce":2,"d":3,"de":3]
    static let ordinals = ["birinci":0,"ilk":0,"ikinci":1,"ucuncu":2,"dorduncu":3,"sonuncu":3]
    private static let prefixes = ["benim cevabim ","benim yanitim ","dogru cevap ","cevabim ","yanitim ","cevap ","yanit ","bence ","sanirim ","galiba ","herhalde ","sanki "]
    private static let pointers = [" sikkini seciyorum"," sikkini sectim"," secenegini seciyorum"," secenegini sectim"," sikkidir"," sikki"," secenegi"," secenek"," sik"]
    private static let suffixes = pointers+[" seciyorum"," sectim"," diyorum"," derim"," olsun"," olmali"," dir"," dur"," tir"]
    /// Dolgu sözlerini baştan ve sondan soyar: "bence c şıkkı olsun" → "c". `pointer`: şık/seçenek sözcüğü geçti; `filler`: baştan dolgu soyuldu.
    static func core(_ key: String) -> (value: String, pointer: Bool, filler: Bool) {
        var value = key, changed = true, pointer = false, filler = false
        while changed {
            changed = false
            for prefix in prefixes where value.hasPrefix(prefix) && value.count > prefix.count { value.removeFirst(prefix.count); changed = true; filler = true; break }
            for suffix in suffixes where value.hasSuffix(suffix) && value.count > suffix.count { value.removeLast(suffix.count); changed = true; pointer = pointer || pointers.contains(suffix); break }
        }
        return (value,pointer,filler)
    }
    /// Whisper'ın küçük yazım hatası için tek ve açık ara en yakın seçenek ("marss" → "mars").
    static func closest(_ value: String, in options: [String]) -> Int? {
        guard value.count >= 4 else { return nil }
        // Kısa seçenekler de belirsizlik kıyasına girer; yalnız kazananın en az 4 harf olması gerekir.
        let scored = options.enumerated().map { ($0.offset,distance(value,$0.element)) }.sorted { $0.1 < $1.1 }
        guard let best = scored.first, options[best.0].count >= 4 else { return nil }
        let allowed = max(1,min(value.count,options[best.0].count)/5)
        guard best.1 <= allowed else { return nil }
        if scored.count > 1, scored[1].1 <= best.1+1 { return nil }
        return best.0
    }
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }; guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i]+Array(repeating:0,count:b.count)
            for j in 1...b.count { current[j] = min(previous[j]+1,current[j-1]+1,previous[j-1]+(a[i-1] == b[j-1] ? 0 : 1)) }
            previous = current
        }
        return previous[b.count]
    }
}


struct VoiceEndpointDetector {
    struct Limits: Equatable {
        var silence = 1.2
        var maximum = 12.0
        var noSpeech = 6.0
    }
    let limits: Limits
    init(limits: Limits = .init()) { self.limits = limits }
    private(set) var heardSpeech = false
    private var elapsed = 0.0
    private var speech = 0.0
    private var silence = 0.0
    mutating func sample(db: Double, seconds: Double) -> Bool {
        elapsed += seconds
        if db.isFinite && db > -48 { speech += seconds; silence = 0; if speech >= 0.2 { heardSpeech = true } }
        else { silence += seconds; if !heardSpeech { speech = 0 } }
        return elapsed >= limits.maximum || (heardSpeech && silence >= limits.silence) || (!heardSpeech && elapsed >= min(limits.noSpeech,limits.maximum))
    }
}
