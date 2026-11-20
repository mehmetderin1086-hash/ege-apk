import SwiftUI
import AVFoundation

@MainActor final class GameStore: ObservableObject {
    @Published var inventory: PhoneInventory?
    @Published var models: [PhoneModel] = []
    @Published var selectedModel = ""
    @Published var teamModels: Set<String> = []
    @Published var teamEnabled = false
    @Published var reviewer = ""
    @Published var reviewEnabled = false
    @Published var checks: [String: ModelCheck] = [:]
    @Published var checkingModel: String?
    @Published var auditProgress = ""
    @Published var topic: Topic = .mixed
    @Published var difficulty: Difficulty = .medium
    @Published var mode: GameMode = .classic
    @Published var roundSettings = RoundSettings()
    @Published var soundEnabled = true
    @Published var voiceEnabled = false
    let audio = GameAudio()
    let speaker = QuestionSpeaker()
    let voiceAnswer = VoiceAnswerStore()
    let liveQuiz: LiveQuizController
    @Published private(set) var listening = false
    @Published var study: StudyLesson?
    @Published var detail = ""
    @Published var count = 10
    @Published var questionFormat: QuestionFormat = .mixed
    @Published var round: Round?
    @Published var results: [RoundResult] = []
    @Published var saved: [Question] = []
    @Published var reviews: [ReviewCard] = []
    @Published var packs: [QuestionPack] = []
    @Published var draft: GenerationDraft?
    @Published var loading = false
    @Published private(set) var requestingLivePermission = false
    #if DEBUG
    @Published var microphoneAuditGame: GameStore?
    #endif
    @Published var progress = 0.0
    @Published var generationStatus = ""
    @Published var error: String?
    @Published var card = false
    @Published var coachAnswer = ""
    @Published var coachLoading = false
    @Published var hapticCorrect = 0
    @Published var hapticWrong = 0
    @Published var hapticTick = 0
    @Published var hapticCard = 0
    @Published var history: [AnswerRecord] = []
    @Published var reports: [QuestionReport] = []
    let pool: DailyQuestionPool
    private var timer: Timer?
    private var active = true
    private let defaults: UserDefaults
    let gateway: PhoneGateway
    private var generation: Task<Void, Never>?
    private var audit: Task<Void, Never>?
    private var coachTask: Task<Void, Never>?
    private var generationID = UUID()
    private var coachID = UUID()
    private var lastTick = Date()

    init(defaults: UserDefaults = .standard, gateway: PhoneGateway = .shared, startTimer: Bool = true, pool: DailyQuestionPool? = nil, liveQuiz: LiveQuizController? = nil) {
        self.defaults = defaults; self.gateway = gateway; self.pool = pool ?? .shared; self.liveQuiz = liveQuiz ?? LiveQuizController()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-new-round") {
            defaults.removeObject(forKey:"round"); defaults.removeObject(forKey:"gameMode"); defaults.removeObject(forKey:"roundSettings"); defaults.set(QuestionFormat.text.rawValue,forKey:"questionFormat")
        }
        #endif
        selectedModel = defaults.string(forKey: "selectedPhoneModel") ?? ""
        teamModels = Set(defaults.stringArray(forKey: "teamModels") ?? [])
        reviewer = defaults.string(forKey: "reviewer") ?? ""
        teamEnabled = defaults.bool(forKey: "teamEnabled")
        reviewEnabled = defaults.bool(forKey: "reviewEnabled")
        mode = defaults.string(forKey:"gameMode").flatMap(GameMode.init(rawValue:)) ?? .classic
        questionFormat = defaults.string(forKey:"questionFormat").flatMap(QuestionFormat.init(rawValue:)) ?? .mixed
        study = read("studyLesson")
        roundSettings = (read("roundSettings") as RoundSettings? ?? .init()).normalized
        soundEnabled = defaults.object(forKey:"soundEnabled") as? Bool ?? true
        voiceEnabled = defaults.bool(forKey:"voiceEnabled")
        results = read("results") ?? []; saved = read("saved") ?? []
        reviews = read("reviews") ?? []; packs = read("packs") ?? []
        draft = read("draft"); history = read("answerHistory") ?? []
        reports = read("questionReports") ?? []
        checks = read("checks") ?? [:]
        if let value: Round = read("round"), !value.questions.isEmpty, value.questions.indices.contains(value.index), !value.finished { round = value; round?.paused = true }
        // Legacy VPS connection metadata is retired. No URL or credential is read.
        defaults.removeObject(forKey: "connection")
        if startTimer {
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in Task { @MainActor [weak self] in self?.tick() } }
        }
    }
    private func read<T: Decodable>(_ key: String) -> T? { defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) } }
    private func write<T: Encodable>(_ value: T, _ key: String) { defaults.set(try? JSONEncoder().encode(value), forKey: key) }
    func persistSelection() {
        defaults.set(selectedModel, forKey: "selectedPhoneModel"); defaults.set(Array(teamModels), forKey: "teamModels")
        defaults.set(teamEnabled, forKey: "teamEnabled"); defaults.set(reviewer, forKey: "reviewer"); defaults.set(reviewEnabled, forKey: "reviewEnabled")
        defaults.set(questionFormat.rawValue,forKey:"questionFormat")
        defaults.set(mode.rawValue,forKey:"gameMode")
        write(study,"studyLesson"); write(roundSettings,"roundSettings")
        defaults.set(soundEnabled,forKey:"soundEnabled"); defaults.set(voiceEnabled,forKey:"voiceEnabled")
    }
    func persist() {
        write(round, "round"); write(results, "results"); write(saved, "saved")
        write(reviews, "reviews"); write(packs, "packs"); write(draft, "draft"); write(history, "answerHistory"); write(checks, "checks")
        write(reports,"questionReports")
    }
    /// XP, tur geçmişi, cevap istatistiği ve tekrar defterini siler; kaydedilen bilgi kartları ve paketler kalır.
    func resetProgress() { results = []; history = []; reviews = []; persist() }
    func resetPreferences() {
        ArenaPreferences.reset(defaults); soundEnabled = true; voiceEnabled = false; persistSelection()
    }
    var availableText: [PhoneModel] { models.filter(\.textCapable) }
    var dueCards: [ReviewCard] { reviews.filter { $0.due <= Date() && !isReported($0.question) } }
    var totalXP: Int { results.reduce(0) { $0 + $1.correct * 20 + 30 } }
    var level: Int { totalXP / 250 + 1 }
    var accuracy: Int { let n = history.count; return n == 0 ? 0 : history.filter(\.correct).count * 100 / n }
    var achievements: [Achievement] {
        [Achievement(id:"first",title:"İlk Adım",icon:"flag.fill",earned:!results.isEmpty),
         Achievement(id:"ten",title:"Meraklı",icon:"sparkles",earned:results.count >= 10),
         Achievement(id:"perfect",title:"Kusursuz Tur",icon:"crown.fill",earned:results.contains { $0.correct == $0.total && $0.total >= 5 }),
         Achievement(id:"hundred",title:"Bilgi Ustası",icon:"brain.head.profile",earned:history.filter(\.correct).count >= 100),
         Achievement(id:"collector",title:"Koleksiyoncu",icon:"bookmark.fill",earned:saved.count >= 10),
         Achievement(id:"models",title:"Model Kaşifi",icon:"cpu.fill",earned:checks.values.filter(\.success).count >= 3)]
    }
    func loadModels() async {
        do {
            let value = try await gateway.inventory(); inventory = value; models = value.models
            // Keep explicit selections even when unavailable; initial selection only.
            if selectedModel.isEmpty { selectedModel = value.models.first(where: { $0.id == "gpt-6-luna" })?.id ?? availableText.first?.id ?? "" }
            if !defaults.bool(forKey: "phoneTeamV2Configured"), !availableText.isEmpty {
                let verified = Set(checks.values.filter(\.success).map(\.model))
                let preferred = Set(["gpt-6-luna", "claude-sonnet-5-5", "gemini-3.8-flash"])
                teamModels = Set(availableText.map(\.id)).intersection(verified.isEmpty ? preferred : verified)
                teamEnabled = !teamModels.isEmpty
                defaults.set(true, forKey: "phoneTeamV2Configured")
            }
            persistSelection()
        } catch { self.error = (error as? QuizError)?.message ?? "iPhone hesapları okunamadı." }
    }
    func startLocal(live: Bool = false) {
        guard !loading else { return }
        pool.setBusy(true)
        Task {
            await pool.bootstrap(packs:packs,reports:reports,history:history)
            defer { pool.setBusy(round != nil || loading) }
            do {
                guard let database = pool.database else { throw QuizError("Soru havuzu açılamadı.") }
                let excluded = Set(reports.map(\.id))
                var qs: [Question]
                if questionFormat == .mixed {
                    var selected: [Question] = []
                    var used = excluded
                    for format in [QuestionFormat.visual,.listening,.ordering,.matching,.pronunciation] {
                        let part = try await database.sample(topic:topic,difficulty:difficulty,limit:min(max(1,count/6),max(0,count-selected.count)),excluded:used,format:format,study:topic == .exam ? study : nil)
                        selected += part; used.formUnion(part.map(\.poolKey))
                    }
                    let rest = try await database.sample(topic:topic,difficulty:difficulty,limit:max(0,count-selected.count),excluded:used,study:topic == .exam ? study : nil)
                    qs = (selected+rest).shuffled()
                } else { qs = try await database.sample(topic:topic,difficulty:difficulty,limit:count,excluded:excluded,format:questionFormat,study:topic == .exam ? study : nil) }
                guard !qs.isEmpty else { throw QuizError("Bu kategori ve zorlukta henüz soru yok. Başka seviye seç veya yapay zekâyla üret.") }
                start(qs,source:live ? "Canlı sesli tur" : "Soru havuzu · \(difficulty.rawValue)",mode:live ? .training : nil,live:live)
            } catch { self.error = (error as? QuizError)?.message ?? "Havuz okunamadı." }
        }
    }
    func daily() { start(Seed.questions.daily(date: Date()), source: "Günün turu") }
    func startReview() { let qs = dueCards.map(\.question); guard !qs.isEmpty else { return }; start(Array(qs.prefix(20)), source: "Aralıklı tekrar", mode: .training) }
    func startPack(_ pack: QuestionPack) { start(pack.questions, source: "Çevrimdışı · \(pack.title)") }
    func start(_ questions: [Question], source: String, mode: GameMode? = nil, live: Bool = false) {
        let questions = questions.filter { !isReported($0) }
        guard !questions.isEmpty else { error = "Bu paketin soruları bildirimlerin nedeniyle gizlendi."; return }
        pool.setBusy(true)
        if loading { cancelGeneration() }
        liveQuiz.endSession(); stopListening(); coachTask?.cancel(); coachAnswer = ""; card = false
        round = Round(questions: questions, source: source, mode: mode ?? self.mode,settings:roundSettings); round?.liveVoice = live; lastTick = Date(); persist()
        notify(.start,round?.effectiveMode == .stages ? "Birinci etap. Isınma." : "Tur başladı.")
        if live { liveQuiz.start(self) }
    }
    func startAI() async {
        guard !loading else { return }
        pool.setBusy(true)
        defer { pool.setBusy(round != nil || loading) }
        loading = true
        if models.isEmpty { await loadModels() }
        let ordered = availableText.map(\.id).filter { teamModels.contains($0) && (!reviewEnabled || $0 != reviewer) }
        let cursor = ordered.isEmpty ? 0 : defaults.integer(forKey: "teamCursor") % ordered.count
        let used = teamEnabled ? Array(ordered.dropFirst(cursor)) + Array(ordered.prefix(cursor)) : [selectedModel]
        guard !used.isEmpty, used.allSatisfy({ m in availableText.contains { $0.id == m } }) else { loading = false; error = "Telefondaki modellerden birini veya bir model takımı seç."; return }
        if [.custom,.language,.exam].contains(topic), detail.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && !(topic == .exam && study != nil) { loading = false; error = "Önce bir konu, dil veya sınav yaz."; return }
        if reviewEnabled && (!availableText.contains { $0.id == reviewer } || used.contains(reviewer)) { loading = false; error = "İkinci kontrol için üretici modelden farklı bir denetçi seç."; return }
        let same = draft.map { $0.topic == topic && $0.detail == detail && $0.difficulty == difficulty && $0.count == count && $0.effectiveFormat == questionFormat && $0.study == (topic == .exam ? study : nil) } ?? false
        let prepared = same ? draft?.questions ?? [] : []
        if !same || draft?.models != used {
            draft = GenerationDraft(id: UUID(), topic: topic, detail: detail, difficulty: difficulty, count: count, models: used, questions: prepared,format:questionFormat,study:topic == .exam ? study : nil)
        }
        guard let snapshot = draft else { loading = false; return }
        persist()
        loading = true; generationID = UUID(); let requestID = generationID
        generationStatus = "iPhone modeli hazırlanıyor…"
        let exclusions = Array((packs.flatMap(\.questions).map(\.uniquenessText) + history.map { $0.question.uniquenessText } + reports.map { $0.question.uniquenessText }).suffix(500))
        let check = reviewEnabled ? reviewer : nil
        generation = Task { [weak self] in
            guard let self else { return }
            defer { if self.generationID == requestID { self.loading = false } }
            do {
                var qs = try await AIService(gateway: self.gateway).questions(topic: snapshot.topic, detail: snapshot.detail, difficulty: snapshot.difficulty, count: snapshot.count, models: snapshot.models, excluding: exclusions, initial: snapshot.questions,format:snapshot.effectiveFormat,study:snapshot.study,
                accept:{ [pool] batch in try await pool.database?.novelCandidates(batch) ?? batch },
                onBatch: { [weak self] qs in await self?.recordBatch(qs, requestID: requestID) },
                progress: { [weak self] done, total, model in await self?.recordProgress(done, total: total, model: model, requestID: requestID) })
                if let check { self.generationStatus = "İkinci model soruları inceliyor…"; qs = try await AIService(gateway: self.gateway).verify(qs, model: check) }
                try Task.checkCancellation(); guard self.generationID == requestID else { return }
                if let database = self.pool.database {
                    qs = try await database.insertUnique(qs)
                    await self.pool.refresh()
                    guard !qs.isEmpty else { self.draft = nil; throw QuizError("Bu paket yeni soru içermedi. Tekrar üreterek farklı bir paket iste.") }
                }
                self.packs.insert(QuestionPack(id:UUID(),date:Date(),title:snapshot.detail.isEmpty ? snapshot.topic.rawValue : snapshot.detail,questions:qs,models:snapshot.models),at:0)
                self.packs = Array(self.packs.prefix(30)); self.draft = nil
                if self.teamEnabled { self.defaults.set(self.defaults.integer(forKey: "teamCursor") + (snapshot.count + 4) / 5, forKey: "teamCursor") }
                self.start(qs, source: "iPhone CLI Proxy · \(snapshot.models.joined(separator: ", "))")
            } catch {
                guard self.generationID == requestID, !(error is CancellationError), !Task.isCancelled else { return }
                self.error = (error as? QuizError)?.message ?? "Sağlayıcı bağlantısı tamamlanamadı. Hazırlanan sorular saklandı; yeniden deneyebilirsin."
                self.persist()
            }
        }
        await generation?.value
    }
    private func recordBatch(_ qs: [Question], requestID: UUID) { guard generationID == requestID else { return }; draft?.questions = qs; persist() }
    private func recordProgress(_ done: Int, total: Int, model: String, requestID: UUID) { guard generationID == requestID else { return }; progress = Double(done)/Double(total); generationStatus = "\(done)/\(total) soru · \(model)" }
    func cancelGeneration() {
        generationID = UUID(); generation?.cancel(); generation = nil; loading = false
        generationStatus = "Hazırlanan sorular saklandı"; persist()
        pool.setBusy(round != nil)
    }
    func auditModels(ids: [String]? = nil) {
        guard checkingModel == nil else { return }
        let ids = ids ?? availableText.map(\.id)
        audit = Task { [weak self] in
            guard let self else { return }; defer { self.checkingModel = nil; self.auditProgress = "" }
            for (index, model) in ids.enumerated() {
                if Task.isCancelled { break }; self.checkingModel = model; self.auditProgress = "\(index + 1)/\(ids.count)"
                let check = await self.gateway.probe(model)
                guard !Task.isCancelled else { break }
                self.checks[model] = check; self.persist()
            }
        }
    }
    func cancelAudit() { audit?.cancel() }
    func askCoach(_ message: String) {
        guard let r = round, r.revealed, !coachLoading, !selectedModel.isEmpty else { return }
        coachID = UUID(); let id = coachID; coachLoading = true; coachAnswer = ""
        let question = r.current, choice = r.answers.last?.chosen
        coachTask = Task { [weak self] in
            guard let self else { return }; defer { if self.coachID == id { self.coachLoading = false } }
            do { let answer = try await AIService(gateway: self.gateway).tutor(question: question, selected: choice, message: message, model: self.selectedModel,response:r.answers.last?.response); try Task.checkCancellation(); if self.coachID == id { self.coachAnswer = answer } }
            catch { if !Task.isCancelled { self.error = (error as? QuizError)?.message ?? "Koç yanıtı alınamadı." } }
        }
    }
    func startListening() {
        guard let r = round, !r.finished, !r.revealed, !r.paused, let activity = r.current.activity, (activity.kind == .listening || activity.kind == .pronunciation) else { return }
        audio.stop(); listening = true; lastTick = Date()
        speaker.speak(activity) { [weak self] success in
            guard let self, self.round?.id == r.id, self.round?.index == r.index else { return }
            self.listening = false
            if success { self.round?.audioReadyQuestionID = r.current.id }
            self.lastTick = Date(); self.persist()
        }
    }
    func stopListening() { speaker.cancel(); listening = false; lastTick = Date() }
    func useListeningTranscript() {
        guard let r = round, r.current.activity?.kind == .listening, !r.paused else { return }
        stopListening(); round?.audioReadyQuestionID = r.current.id; persist()
    }
    func saveActivityDraft(_ response: ActivityResponse) {
        guard let r = round, !r.revealed, !r.finished, let activity = r.current.activity, activity.isValid, activity.isInteractive else { return }
        let used = response.indices.filter { $0 != -1 }
        guard response.indices.count <= 4, used.allSatisfy({ (0..<4).contains($0) }), Set(used).count == used.count,
              activity.kind == .matching ? response.indices.count == 4 : response.indices.allSatisfy({ $0 >= 0 }) else { return }
        round?.activityDraft = response; persist()
    }
    func submitActivity(_ response: ActivityResponse) {
        guard var r = round, !r.paused, !r.finished, !r.revealed,
              let activity = r.current.activity, activity.accepts(response) else { return }
        r.answer(activity.isCorrect(response) ? r.current.answer : (r.current.answer+1)%4,response:response)
        guard r.revealed else { return }
        round = r; recordAnswer(r.answers.last!); persist(); if r.liveVoice == true { liveQuiz.start(self) }
    }
    func answer(_ index: Int?, spokenText: String? = nil) {
        guard var r = round, !listening, !r.revealed, !r.finished, !r.paused else { return }
        r.answer(index,response:spokenText.map { ActivityResponse(indices:[],spokenText:String($0.prefix(600))) }); guard r.revealed else { return }
        round = r; recordAnswer(r.answers.last!); persist(); if r.liveVoice == true { liveQuiz.start(self) }
    }
    private func recordAnswer(_ answer: AnswerRecord) {
        if answer.correct { hapticCorrect += 1; notify(.correct,"Doğru cevap.") }
        else { hapticWrong += 1; notify(answer.chosen == nil ? .timeout : .wrong,answer.chosen == nil ? "Süre doldu." : "Yanlış cevap.") }
        history.append(answer); history = Array(history.suffix(1000))
        if let database = pool.database { Task { try? await database.markPlayed(answer.question) } }
        if let i = reviews.firstIndex(where: { $0.id == answer.question.id }) { reviews[i].record(answer.correct) }
        else if !answer.correct { reviews.append(ReviewCard(question: answer.question, due: Date(), interval: 0, attempts: 1, correct: 0)) }
    }
    func tick(now: Date = Date()) {
        guard active, !card, !listening, var r = round, !r.finished, !r.paused, !r.revealed, !r.awaitsListening, r.liveVoice != true, r.effectiveMode != .training else { lastTick = now; return }
        let elapsed = max(0, min(40, Int(now.timeIntervalSince(lastTick))))
        guard elapsed > 0 else { return }; lastTick = lastTick.addingTimeInterval(Double(elapsed))
        for _ in 0..<elapsed { r.tick() }
        let seconds = r.hasQuestionClock ? min(r.remaining,r.totalRemaining ?? Int.max) : r.totalRemaining ?? 0
        if !r.revealed && (1...5).contains(seconds) { hapticTick += 1; notify(.tick,seconds == 5 ? "Son beş saniye." : nil) }
        if r.revealed { recordAnswer(r.answers.last!) }
        round = r
        if r.finished { completeRound(r) }
        persist()
    }
    func next() {
        guard var r = round, r.revealed else { return }
        stopListening()
        let previousStage = r.stageIndex
        let shouldBreak = r.liveVoice != true && (r.index + 1).isMultiple(of: 10) && r.index + 1 < r.questions.count
        coachID = UUID(); coachTask?.cancel(); coachLoading = false; coachAnswer = ""
        r.next(); round = r; lastTick = Date()
        let newStage = r.effectiveMode == .stages && r.stageIndex != previousStage && !r.finished
        if shouldBreak || newStage {
            card = true; hapticCard += 1
            notify(.stage,newStage ? "Yeni etap. \(r.stageTitle)." : "Bilgi molası.")
        }
        if r.finished { completeRound(r); liveQuiz.stop() }
        persist()
        if r.liveVoice == true { liveQuiz.start(self) }
    }
    private func completeRound(_ r: Round) {
        guard !results.contains(where:{ $0.id == r.id }) else { return }
        results.insert(RoundResult(id:r.id,date:Date(),score:r.score,correct:r.answers.filter(\.correct).count,total:r.answers.count,source:r.source),at:0)
        results = Array(results.prefix(100))
        notify(.finish,"Tur tamamlandı. \(r.answers.count) soruda \(r.answers.filter(\.correct).count) doğru.")
    }
    func notify(_ event: GameAudio.Event, _ message: String?) { guard !listening, round?.liveVoice != true else { return }; audio.play(event,effects:soundEnabled,speech:voiceEnabled ? message : nil) }
    func pause() { liveQuiz.pause(); round?.paused = true; stopListening(); audio.stop(); persist() }
    func setActive(_ value: Bool) {
        active = value; lastTick = Date()
        #if DEBUG
        microphoneAuditGame?.setActive(value)
        #endif
        if !value { liveQuiz.pause(); voiceAnswer.suspend(); stopListening(); audio.stop(); if round?.finished == false { round?.paused = true }; cancelAudit(); persist() }
    }
    func toggleSaved(_ q: Question) { if saved.contains(where: { $0.id == q.id }) { saved.removeAll { $0.id == q.id } } else { saved.insert(q, at: 0) }; persist() }
    func half() { round?.half(); persist() }
    func extraTime() { round?.moreTime(); persist() }
    func skip() { stopListening(); guard var r = round, !r.usedSkip, !r.revealed, !r.paused else { return }; r.skip(); round = r; if let answer = r.answers.last { recordAnswer(answer) }; persist(); if r.liveVoice == true { liveQuiz.start(self) } }
    func resume() { guard active else { return }; round?.paused = false; lastTick = Date(); persist(); if round?.liveVoice == true { liveQuiz.start(self) } }
    func resumeLive() { resume() }
    func enableLive() {
        guard round?.finished == false else { return }
        let roundID = round?.id
        requestLiveAccess { [weak self] in
            guard let self, round?.id == roundID, round?.finished == false else { return }
            round?.liveVoice = true; round?.mode = .training; round?.totalRemaining = nil; round?.remaining = 0; resumeLive()
        }
    }
    func startLiveLocal() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-live") { start(Array(Seed.questions.prefix(2)),source:"Canlı sesli test",mode:.training,live:true); return }
        #endif
        requestLiveAccess { [weak self] in self?.startLocal(live:true) }
    }
    private func requestLiveAccess(_ action: @escaping @MainActor () -> Void) {
        guard !requestingLivePermission else { return }
        requestingLivePermission = true
        Task { [weak self] in
            guard let self else { return }; defer { requestingLivePermission = false }
            guard await AVAudioApplication.requestRecordPermission() else { error = "Canlı tur için mikrofon izni gerekiyor. iPhone Ayarları'ndan Bilgi Arenası mikrofonunu açabilirsin."; return }
            // The system permission alert can briefly make the scene inactive. Start only after it returns.
            for _ in 0..<20 {
                if active && UIApplication.shared.applicationState == .active { action(); return }
                guard UIApplication.shared.applicationState != .background else { break }
                try? await Task.sleep(for:.milliseconds(100))
            }
            error = "Canlı tur için Bilgi Arenası'nı öne getirip yeniden başlat."
        }
    }
    func leave() { liveQuiz.endSession(); voiceAnswer.cancel(); stopListening(); audio.stop(); coachID = UUID(); coachTask?.cancel(); coachLoading = false; round = nil; card = false; persist(); pool.setBusy(loading) }
    func isReported(_ q: Question) -> Bool { reports.contains { $0.id == q.poolKey } }
    func report(_ q: Question, reason: ReportReason) {
        guard !isReported(q) else { return }
        reports.insert(QuestionReport(question:q,reason:reason,date:Date()),at:0); persist()
        Task {
            do { try await pool.database?.hide(q.poolKey,hidden:true); await pool.refresh() }
            catch { self.error = "Bildirim saklandı; havuzdan gizleme sonraki açılışta yeniden denenecek." }
        }
    }
    func restore(_ report: QuestionReport) {
        Task {
            do {
                try await pool.database?.hide(report.id,hidden:false)
                reports.removeAll { $0.id == report.id }; persist(); await pool.refresh()
            } catch { self.error = "Soru geri alınamadı; tekrar dene." }
        }
    }
}
