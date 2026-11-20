import Foundation
import Combine

@MainActor final class LiveQuizController: ObservableObject {
    enum Phase: String { case idle, preparing, speaking, openingMicrophone, listening, transcribing, reviewing, feedback, paused, failed, finished }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var route = ""
    @Published private(set) var notice = ""
    @Published private(set) var error: String?
    @Published private(set) var transcript = ""
    @Published private(set) var preview = ""
    @Published private(set) var countdown = 0
    @Published private(set) var level = 0.0
    var factory: ((QuizLiveEngine,VoiceAnswerStore) -> any QuizLiveVoice)?
    /// Testler sabit bekleme verir; nil ise Ayarlar'daki gönderim öncesi bekleme kullanılır.
    var reviewDelay: Duration?
    private weak var game: GameStore?
    private var operation: Task<Void,Never>?
    private var metering: Task<Void,Never>?
    private var voice: (any QuizLiveVoice)?
    private var generation = UUID()
    private var useChain = false
    private var localOnly = false
    var engine: QuizLiveEngine { QuizLiveEngine(rawValue:UserDefaults.standard.string(forKey:"quizLiveEngine") ?? "") ?? .chained }
    var title: String {
        switch phase {
        case .idle:return "Canlı sesli tur"
        case .preparing:return "Ses bağlantısı hazırlanıyor"
        case .speaking:return "Sunucu soruyu okuyor"
        case .openingMicrophone:return "Mikrofon hazırlanıyor"
        case .listening:return "Seni dinliyorum"
        case .transcribing:return "Whisper yanıtını çözümlüyor"
        case .reviewing:return "Yanıtın \(countdown) saniye sonra gönderilecek"
        case .feedback:return "Sonuç ve açıklama"
        case .paused:return "Canlı tur duraklatıldı"
        case .failed:return "Bir kez daha deneyelim"
        case .finished:return "Canlı tur tamamlandı"
        }
    }
    private func makeVoice(_ game: GameStore) -> any QuizLiveVoice {
        if let factory { return factory(engine,game.voiceAnswer) }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-live") { return PreviewQuizLiveVoice() }
        #endif
        if engine == .chained || useChain {
            let value = ChainedQuizVoice(voice:game.voiceAnswer); value.localOnly = localOnly; return value
        }
        return RemoteQuizVoice(engine:engine,gateway:game.gateway)
    }
    func start(_ game: GameStore, skipReading: Bool = false) {
        stop(); self.game = game
        guard let round = game.round, round.liveVoice == true, !round.finished else { phase = .finished; return }
        guard !round.paused else { phase = .paused; return }
        let id = generation, roundID = round.id, index = round.index
        phase = .preparing; error = nil; transcript = ""; preview = ""
        operation = Task { [weak self, weak game] in
            guard let self, let game else { return }
            do {
                var driver = makeVoice(game); voice = driver
                do { try await driver.prepare() }
                catch {
                    try Task.checkCancellation()
                    guard generation == id, engine != .chained, !useChain else { throw error }
                    driver.stop(); useChain = true
                    notice = "Canlı API açılamadı. Asistan'ın sıralı sesli yolu kullanılıyor; cevaplar cihazda Whisper ile çözülür."
                    driver = makeVoice(game); voice = driver; try await driver.prepare()
                }
                try validate(game,id:id,roundID:roundID,index:index)
                route = driver.route
                if !game.round!.revealed {
                    phase = .speaking
                    if !skipReading { try await speak(QuizNarration.question(round.current,number:index+1),game:game,id:id,driver:&driver) }
                    try validate(game,id:id,roundID:roundID,index:index)
                    game.round?.audioReadyQuestionID = round.current.id; game.persist()
                    phase = .openingMicrophone
                    metering = Task { [weak self] in
                        while !Task.isCancelled {
                            guard let self, generation == id else { return }
                            level = driver.level
                            switch driver.hearingPhase {
                            case .opening:phase = .openingMicrophone
                            case .recording:phase = .listening
                            case .transcribing:phase = .transcribing
                            }
                            try? await Task.sleep(for:.milliseconds(100))
                        }
                    }
                    let language = round.current.activity?.kind == .pronunciation ? String((round.current.activity?.language ?? "en-US").prefix(2)) : "tr"
                    let text = try await driver.hear(language:language)
                    metering?.cancel(); level = 0
                    try validate(game,id:id,roundID:roundID,index:index)
                    transcript = text
                    switch Self.command(text) {
                    case .pause:game.pause(); return
                    case .repeatQuestion:start(game); return
                    case .skip:
                        game.answer(nil); return
                    case nil:break
                    }
                    guard let answer = VoiceAnswerResolver.resolve(text,for:round.current) else { throw QuizError("Tek bir yanıt anlaşılamadı. Şık harfini ya da seçeneğin tamamını yeniden söyle.") }
                    preview = Self.preview(answer,question:round.current); phase = .reviewing
                    let steps = reviewDelay == nil ? ArenaPreferences.liveReviewSeconds() : 3
                    let wait = reviewDelay ?? .seconds(steps)
                    for value in stride(from:steps,through:1,by:-1) {
                        countdown = value; try await Task.sleep(for:wait/steps)
                        try validate(game,id:id,roundID:roundID,index:index)
                    }
                    switch answer { case .choice(let value):game.answer(value,spokenText:text); case .activity(let response):game.submitActivity(response) }
                    guard game.round?.revealed == true else { throw QuizError("Bu yanıt kaydedilemedi. Yeniden söyle veya seçeneğe dokun.") }
                    return // GameStore starts feedback using the committed answer.
                }
                phase = .feedback
                if let answer = game.round?.answers.last {
                    try await speak(QuizNarration.feedback(round.current,correct:answer.correct,last:index+1 == round.questions.count,explain:ArenaPreferences.liveExplanation()),game:game,id:id,driver:&driver)
                }
                try validate(game,id:id,roundID:roundID,index:index)
                game.next()
            } catch is CancellationError { }
            catch {
                guard generation == id else { return }
                voice?.stop(); metering?.cancel(); level = 0
                self.error = (error as? QuizError)?.message ?? "Canlı ses tamamlanamadı. Yeniden dene."; phase = .failed
            }
        }
    }
    private func speak(_ segments: [QuizSpeechSegment], game: GameStore, id: UUID, driver: inout any QuizLiveVoice) async throws {
        do { try await driver.speak(segments) }
        catch {
            try Task.checkCancellation()
            guard generation == id, engine != .chained, !useChain else { throw error }
            driver.stop(); useChain = true
            notice = "Canlı API ses üretemedi. Asistan'ın sıralı sesli yolu kullanılıyor; cevaplar cihazda Whisper ile çözülür."
            driver = makeVoice(game); voice = driver; try await driver.prepare(); route = driver.route
            try await driver.speak(segments)
        }
    }
    private func validate(_ game: GameStore, id: UUID, roundID: UUID, index: Int) throws {
        try Task.checkCancellation()
        guard generation == id, game.round?.id == roundID, game.round?.index == index, game.round?.paused == false, game.round?.finished == false else { throw CancellationError() }
    }
    enum Command { case pause, repeatQuestion, skip }
    nonisolated static func command(_ text: String) -> Command? {
        switch VoiceAnswerResolver.clean(text) {
        case "dur","duraklat","durdur","mola","bekle","mola ver":return .pause
        case "tekrar","tekrar oku","soruyu tekrar oku","tekrar et","yeniden oku","bir daha oku","bir daha","soruyu tekrarla","tekrarla":return .repeatQuestion
        case "gec","soruyu gec","pas","pas gec","atla","soruyu atla","sonraki","sonraki soru":return .skip
        default:return nil
        }
    }
    nonisolated static func preview(_ answer: SpokenAnswer, question: Question) -> String {
        switch answer { case .choice(let value):return "\(String(UnicodeScalar(65+value)!)) · \(question.options[value])"; case .activity(let response):return question.activity?.describe(response) ?? "" }
    }
    func finishHearing() { voice?.finishHearing() }
    func retry(local: Bool = false) { if local { useChain = true; localOnly = true }; if let game { game.resumeLive() } }
    func pause() { stop(); phase = .paused }
    func endSession() { stop(); useChain = false; localOnly = false; notice = ""; phase = .idle }
    func stop() {
        generation = UUID(); operation?.cancel(); metering?.cancel(); operation = nil; metering = nil
        voice?.stop(); voice = nil; countdown = 0; level = 0
    }
}
#if DEBUG
@MainActor private final class PreviewQuizLiveVoice: QuizLiveVoice {
    var route: String { "Arayüz test sesi" }
    var level: Double { 0.45 }
    func prepare() async throws { }
    func speak(_ segments: [QuizSpeechSegment]) async throws { try await Task.sleep(for:.seconds(3)) }
    func hear(language: String) async throws -> String { try await Task.sleep(for:.seconds(3)); return "A" }
    func finishHearing() {}
    func stop() {}
}
#endif
