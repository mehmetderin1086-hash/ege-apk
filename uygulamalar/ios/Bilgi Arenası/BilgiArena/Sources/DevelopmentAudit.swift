import Foundation
import UIKit
import AVFoundation

extension GameStore {
    func runDevelopmentAuditIfRequested() async {
        #if DEBUG
        guard let mode = ProcessInfo.processInfo.environment["BILGI_PHONE_AUDIT"] else { return }
        let idleTimer = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = idleTimer }
        struct Report: Codable {
            var inventory: PhoneInventory?
            var checks: [ModelCheck]
            var questionCount: Int
            var generationModel: String?
            var questionError: String?
            var questionDiagnostic: String?
            var teamModels: [String] = []
            var reviewedCount = 0
            var coachCharacters = 0
            var hosts: [String: Int] = [:]
            var finished: Bool
        }
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("phone-acceptance.json")
        var report = Report(inventory: inventory, checks: [], questionCount: 0, finished: false)
        func write() { if let data = try? JSONEncoder().encode(report) { try? data.write(to: output, options: [.atomic, .completeFileProtection]) } }
        write()
        guard mode != "inventory" else { report.finished = true; write(); return }
        if mode == "live-microphone" {
            struct MicrophoneProof: Codable {
                var finished = false; var permissionGranted = false; var inputAvailable = false
                var recordingStarted = false; var transcribingStarted = false; var completedRound = false
                var answers = 0; var correctAnswers = 0; var results = 0; var maxInputLevel = 0.0
                var phases: [String] = []; var diagnostics: [String:Double] = [:]; var error: String?
            }
            var proof = MicrophoneProof()
            let url = output.deletingLastPathComponent().appendingPathComponent("live-microphone-acceptance.json")
            func saveProof() { if let data = try? JSONEncoder().encode(proof) { try? data.write(to:url,options:[.atomic,.completeFileProtection]) } }
            saveProof()
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("microphone-audit-"+UUID().uuidString)
            let name = "MicrophoneAudit-"+UUID().uuidString, defaults = UserDefaults(suiteName:name)!
            defer { microphoneAuditGame = nil; defaults.removePersistentDomain(forName:name) }
            do {
                guard await AVAudioApplication.requestRecordPermission() else { throw QuizError("Mikrofon izni kapalı.") }
                proof.permissionGranted = true; proof.inputAvailable = AVAudioSession.sharedInstance().isInputAvailable
                guard UIApplication.shared.applicationState == .active else { throw QuizError("Doğrulama için Bilgi Arenası önde olmalı.") }
                let pool = DailyQuestionPool(defaults:defaults,database:try QuestionPoolDatabase(url:folder.appendingPathComponent("pool.sqlite")))
                let controller = LiveQuizController()
                controller.factory = { _,voice in ChainedQuizVoice(voice:voice) } // Real recorder and Whisper, no fixture/mock.
                let qa = GameStore(defaults:defaults,startTimer:false,pool:pool,liveQuiz:controller)
                defer { qa.leave(); qa.voiceAnswer.suspend() }
                let qs = ["Birinci mikrofon denemesi. Kızıl gezegen hangisidir?", "İkinci mikrofon denemesi. Kızıl gezegen hangisidir?"].map {
                    Question(text:$0,options:["Venüs","Mars","Dünya","Jüpiter"],answer:1,explanation:"Mars kızıl gezegendir.",category:.science,difficulty:.easy)
                }
                qa.start(qs,source:"Gerçek mikrofon doğrulaması",mode:.training,live:true); microphoneAuditGame = qa
                let end = Date().addingTimeInterval(180)
                while qa.round?.finished == false && controller.phase != .failed && Date() < end {
                    guard UIApplication.shared.applicationState == .active, qa.round?.paused == false else { qa.pause(); proof.error = "Doğrulama duraklatıldı veya uygulama arka plana geçti."; break }
                    let state = controller.phase.rawValue+"/"+String(describing:qa.voiceAnswer.phase)
                    if proof.phases.last != state { proof.phases.append(state); saveProof() }
                    proof.recordingStarted = proof.recordingStarted || qa.voiceAnswer.phase == .recording
                    proof.transcribingStarted = proof.transcribingStarted || qa.voiceAnswer.phase == .transcribing
                    proof.maxInputLevel = max(proof.maxInputLevel,qa.voiceAnswer.level)
                    try await Task.sleep(for:.milliseconds(100))
                }
                proof.answers = qa.round?.answers.count ?? 0; proof.correctAnswers = qa.round?.answers.filter(\.correct).count ?? 0
                proof.results = qa.results.count; proof.completedRound = qa.round?.finished == true
                proof.error = proof.error ?? controller.error ?? (proof.completedRound ? nil : "Doğrulama tamamlanamadı.")
                proof.diagnostics = await qa.voiceAnswer.whisper.diagnostics()
                qa.leave(); await qa.voiceAnswer.whisper.unload()
            } catch { proof.error = (error as? QuizError)?.message ?? "Mikrofon doğrulaması tamamlanamadı." }
            proof.finished = true; saveProof(); return
        }
        if mode == "proxy-live" {
            struct ProxyProof: Codable { var finished = false; var rows: [PhoneGateway.ProxyVoiceProof] = []; var hosts: [String:Int] = [:] }
            var proof = ProxyProof()
            let url = output.deletingLastPathComponent().appendingPathComponent("proxy-live-acceptance.json")
            func saveProof() { if let data = try? JSONEncoder().encode(proof) { try? data.write(to:url,options:[.atomic,.completeFileProtection]) } }
            saveProof()
            for kind in ["openai-live","gemini-live","claude","codex","antigravity","claude-api"] {
                proof.rows.append(await gateway.probeProxyVoice(kind)); saveProof()
            }
            proof.hosts = await PhoneTraffic.shared.snapshot(); proof.finished = true; saveProof(); return
        }
        if mode == "live-connections" {
            struct LiveProof: Codable { var finished = false; var audioBytes: [String:Int] = [:]; var errors: [String:String] = [:]; var codes: [String:String] = [:]; var hosts: [String:Int] = [:] }
            var proof = LiveProof()
            let url = output.deletingLastPathComponent().appendingPathComponent("live-connection-acceptance.json")
            func saveProof() { if let data = try? JSONEncoder().encode(proof) { try? data.write(to:url,options:[.atomic,.completeFileProtection]) } }
            for engine in [QuizLiveEngine.openAI,.gemini] {
                let voice = RemoteQuizVoice(engine:engine,gateway:gateway)
                do { proof.audioBytes[engine.rawValue] = try await voice.probe() }
                catch { proof.errors[engine.rawValue] = (error as? QuizError)?.message ?? "Canlı ses bağlantısı doğrulanamadı." }
                proof.codes[engine.rawValue] = voice.lastErrorCode ?? voice.transportStatus ?? voice.closeKind
                voice.stop(); saveProof()
            }
            proof.hosts = await PhoneTraffic.shared.snapshot(); proof.finished = true; saveProof(); return
        }
        if mode == "live-chained" {
            struct ChainedProof: Codable {
                var finished = false; var completedRound = false; var correct = false
                var answers = 0; var results = 0; var spokenParts = 0; var recognized = ""; var sources: [String] = []
                var error: String?
            }
            var proof = ChainedProof()
            let url = output.deletingLastPathComponent().appendingPathComponent("live-chained-acceptance.json")
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("live-audit-"+UUID().uuidString)
            let name = "LiveAudit-"+UUID().uuidString, defaults = UserDefaults(suiteName:name)!
            defer { defaults.removePersistentDomain(forName:name); try? FileManager.default.removeItem(at:folder) }
            do {
                let pool = DailyQuestionPool(defaults:defaults,database:try QuestionPoolDatabase(url:folder.appendingPathComponent("pool.sqlite")))
                let controller = LiveQuizController()
                let qa = GameStore(defaults:defaults,startTimer:false,pool:pool,liveQuiz:controller)
                let driver = FixtureQuizLiveVoice(voice:qa.voiceAnswer,file:output.deletingLastPathComponent().appendingPathComponent("voice-answer-fixture.wav"))
                controller.factory = { _,_ in driver }
                let q = Question(text:"Hangi gezegen kızıl gezegendir?",options:["Venüs","Mars","Dünya","Jüpiter"],answer:1,explanation:"Mars yüzeyindeki demir oksit nedeniyle kızıl görünür.",category:.science,difficulty:.easy)
                qa.start([q],source:"İzole canlı ses kabulü",mode:.training,live:true)
                let end = Date().addingTimeInterval(120)
                while qa.round?.finished == false && controller.phase != .failed && Date() < end { try await Task.sleep(for:.milliseconds(150)) }
                proof.completedRound = qa.round?.finished == true; proof.answers = qa.round?.answers.count ?? 0; proof.results = qa.results.count
                proof.correct = qa.round?.answers.first?.correct == true; proof.spokenParts = driver.spokenParts
                proof.recognized = driver.recognized; proof.sources = driver.sources; proof.error = controller.error
                qa.leave(); await qa.voiceAnswer.whisper.unload()
            } catch { proof.error = "Sıralı canlı ses kabulü tamamlanamadı." }
            proof.finished = true
            if let data = try? JSONEncoder().encode(proof) { try? data.write(to:url,options:[.atomic,.completeFileProtection]) }; return
        }
        if mode == "bulk-transfer" {
            struct TransferProof: Codable { var finished = false; var imported = 0; var duplicates = 0; var exported = 0; var roundTrip = 0; var undone = 0; var preserved = false; var error: String? }
            var proof = TransferProof()
            let url = output.deletingLastPathComponent().appendingPathComponent("bulk-acceptance.json")
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bulk-audit-"+UUID().uuidString)
            defer { try? FileManager.default.removeItem(at:folder) }
            do {
                let database = try QuestionPoolDatabase(url:folder.appendingPathComponent("pool.sqlite"))
                try await database.insert([Seed.questions[0]])
                let input = output.deletingLastPathComponent().appendingPathComponent("bulk-1000.json")
                let first = try await QuestionTransfer.importFile(input,database:database)
                let retry = try await QuestionTransfer.importFile(input,database:database)
                proof.imported = first.inserted; proof.duplicates = retry.duplicates
                let exported = folder.appendingPathComponent("all.json")
                proof.exported = try await database.exportFile(to:exported)
                proof.roundTrip = try QuestionTransfer.decode(Data(contentsOf:exported)).questions.count
                if let id = first.importBatchID { proof.undone = try await database.undoImport(id) }
                let snapshot = try await database.snapshot(day:"test"); proof.preserved = snapshot.total == 1
            } catch { proof.error = "Toplu aktarım doğrulanamadı: \(String(error.localizedDescription.prefix(250)))" }
            proof.finished = true
            if let data = try? JSONEncoder().encode(proof) { try? data.write(to:url,options:[.atomic,.completeFileProtection]) }
            return
        }
        if mode == "voice-playback" {
            struct PlaybackProof: Codable { var finished = false; var played: [String:Bool] = [:]; var errors: [String:String] = [:] }
            var proof = PlaybackProof()
            for (name,engine,voice,text,language) in [("azure-elif",QuestionVoiceEngine.azure,"Elif","Merhaba, bilgi yarışmasına hoş geldin.","tr-TR"),("azure-aydin",.azure,"Aydın","Merhaba, yeni soruya geçiyoruz.","tr-TR"),("chirp-tr",.chirp,"Kore","Merhaba, bilgi yarışmasına hoş geldin.","tr-TR"),("chirp-en",.chirp,"Kore","Good morning. Welcome to the quiz.","en-US")] {
                let speaker = QuestionSpeaker(); var completed = false
                speaker.speak(.init(kind:.listening,title:"Ses kabulü",transcript:text,language:language),choice:.init(engine:engine,voice:voice,model:"gpt-4o-mini-tts")) { completed = $0 }
                let end = Date().addingTimeInterval(15)
                while speaker.playing && Date() < end { try? await Task.sleep(for:.milliseconds(100)) }
                proof.played[name] = speaker.everStarted && completed
                if let error = speaker.error { proof.errors[name] = error }; speaker.cancel()
            }
            proof.finished = true
            let url = output.deletingLastPathComponent().appendingPathComponent("voice-playback-acceptance.json")
            if let data = try? JSONEncoder().encode(proof) { try? data.write(to:url,options:[.atomic,.completeFileProtection]) }; return
        }
        if mode == "voice-apis" {
            struct VoiceProof: Codable { var finished = false; var configured = false; var bytes: [String:Int] = [:]; var durations: [String:Double] = [:]; var cached = false; var errors: [String:String] = [:]; var hosts: [String:Int] = [:] }
            var proof = VoiceProof()
            let url = output.deletingLastPathComponent().appendingPathComponent("voice-api-acceptance.json")
            func saveProof() { if let data = try? JSONEncoder().encode(proof) { try? data.write(to:url,options:[.atomic,.completeFileProtection]) } }
            let provision = output.deletingLastPathComponent().appendingPathComponent("question-voice-config.json")
            if FileManager.default.fileExists(atPath:provision.path) {
                defer { try? FileManager.default.removeItem(at:provision) }
                do { let config = try JSONDecoder().decode(QuestionVoiceConfiguration.self,from:Data(contentsOf:provision)); try config.save(); proof.configured = true }
                catch { proof.errors["configuration"] = "Ses API bağlantısı güvenli aktarılamadı." }
            } else { let config = QuestionVoiceConfiguration.load(); proof.configured = !config.azureKey.isEmpty && !config.googleProject.isEmpty }
            saveProof()
            for (name,engine,voice,text,language) in [("azure-aydin",QuestionVoiceEngine.azure,"Aydın","Merhaba, yeni soruya geçiyoruz.","tr-TR"),("azure-tr",QuestionVoiceEngine.azure,"Elif","Merhaba, bilgi yarışmasına hoş geldin.","tr-TR"),("azure-en",.azure,"Elif","Good morning. Welcome to the quiz.","en-US"),("chirp-tr",.chirp,"Kore","Merhaba, bilgi yarışmasına hoş geldin.","tr-TR"),("chirp-en",.chirp,"Kore","Good morning. Welcome to the quiz.","en-US"),("proxy-en",.proxy,"marin","Good morning.","en-US")] {
                do {
                    let choice = QuestionVoiceChoice(engine:engine,voice:voice,model:"gpt-4o-mini-tts")
                    let file = try await QuestionVoiceAPI.shared.audio(text:text,language:language,choice:choice)
                    proof.bytes[name] = (try Data(contentsOf:file)).count; proof.durations[name] = try AVAudioPlayer(contentsOf:file).duration
                    let again = try await QuestionVoiceAPI.shared.audio(text:text,language:language,choice:choice); proof.cached = again == file
                } catch { proof.errors[name] = (error as? QuizError)?.message ?? "Ses isteği tamamlanamadı." }
                saveProof()
            }
                        for model in models.filter({ $0.id.localizedCaseInsensitiveContains("gemini") && $0.id.localizedCaseInsensitiveContains("tts") }).prefix(2) {
                do {
                    let file = try await QuestionVoiceAPI.shared.audio(text:"Good morning.",language:"en-US",choice:.init(engine:.proxy,voice:"Kore",model:model.id))
                    proof.bytes[model.id] = (try Data(contentsOf:file)).count; proof.durations[model.id] = try AVAudioPlayer(contentsOf:file).duration
                } catch { proof.errors[model.id] = (error as? QuizError)?.message ?? "Gemini sesi alınamadı." }
            }
            proof.hosts = await PhoneTraffic.shared.snapshot(); proof.finished = true; saveProof(); return
        }
        if mode == "whisper-answer" {
            struct WhisperProof: Codable { var finished = false; var modelPresent = false; var recognized = ""; var choiceResolved = false; var foreignRecognized = ""; var phraseMatched = false; var diagnostics: [String:Double] = [:]; var error: String?; var microphonePermission = AVAudioApplication.shared.recordPermission.rawValue; var inputAvailable = AVAudioSession.sharedInstance().isInputAvailable }
            var proof = WhisperProof(); proof.modelPresent = LocalAnswerWhisper.downloaded
            let url = output.deletingLastPathComponent().appendingPathComponent("whisper-acceptance.json")
            func saveProof() { if let data = try? JSONEncoder().encode(proof) { try? data.write(to:url,options:[.atomic,.completeFileProtection]) } }
            saveProof()
            do {
                let whisper = LocalAnswerWhisper()
                try await whisper.prepare()
                proof.recognized = try await whisper.transcribe(output.deletingLastPathComponent().appendingPathComponent("voice-answer-fixture.wav"),language:"tr")
                let q = Question(text:"Hangi gezegen kızıl gezegendir?",options:["Venüs","Mars","Dünya","Jüpiter"],answer:1,explanation:"Mars kızıl gezegen olarak bilinir.",category:.science,difficulty:.easy)
                proof.choiceResolved = VoiceAnswerResolver.resolve(proof.recognized,for:q) == .choice(1)
                proof.foreignRecognized = try await whisper.transcribe(output.deletingLastPathComponent().appendingPathComponent("pronunciation-fixture.wav"),language:"en")
                proof.diagnostics = await whisper.diagnostics()
                let activity = ActivityQuestionSeeds.questions.first { $0.activity?.kind == .pronunciation }!.activity!
                proof.phraseMatched = activity.isCorrect(.init(indices:[],spokenText:proof.foreignRecognized))
            } catch { proof.error = "Whisper kabulü tamamlanamadı: \(String(error.localizedDescription.prefix(300)))" }
            proof.finished = true; saveProof(); return
        }
        if mode == "activities" {
            struct ActivityProof: Codable {
                var finished = false
                var clockWaited = false
                var speakerStarted = false
                var listeningCompleted = false
                var clockResumed = false
                var interrupted = false
                var submissions: [String:Bool] = [:]
                var generated: [String:Int] = [:]
                var models: [String] = []
                var errors: [String] = []
            }
            let proofURL = output.deletingLastPathComponent().appendingPathComponent("activity-acceptance.json")
            var proof = ActivityProof()
            func saveProof() { if let data = try? JSONEncoder().encode(proof) { try? data.write(to:proofURL,options:[.atomic,.completeFileProtection]) } }
            saveProof()
            let suite = "activity-phone-"+UUID().uuidString
            let isolated = UserDefaults(suiteName:suite)!
            let game = GameStore(defaults:isolated,startTimer:false)
            defer { game.leave(); isolated.removePersistentDomain(forName:suite) }
            game.soundEnabled = false; game.voiceEnabled = false; game.roundSettings = .init(minutes:1)
            let q = ActivityQuestionSeeds.questions[0]
            game.start([q],source:"Dinleme kabulü")
            game.tick(now:Date().addingTimeInterval(20))
            proof.clockWaited = game.round?.remaining == 30 && game.round?.totalRemaining == 60
            game.startListening()
            let end = Date().addingTimeInterval(25)
            while game.listening && Date() < end { try? await Task.sleep(for:.milliseconds(200)) }
            proof.speakerStarted = game.speaker.everStarted
            proof.listeningCompleted = game.round?.awaitsListening == false
            game.tick(now:Date().addingTimeInterval(2))
            proof.clockResumed = (game.round?.remaining ?? 30) < 30
            game.startListening()
            let replayEnd = Date().addingTimeInterval(3)
            while !game.speaker.everStarted && game.listening && Date() < replayEnd { try? await Task.sleep(for:.milliseconds(100)) }
            game.pause()
            proof.interrupted = !game.listening && !game.speaker.playing
            for q in ActivityQuestionSeeds.questions.prefix(3).filter({ $0.activity!.isInteractive }) {
                game.start([q],source:"Etkileşim kabulü",mode:.training)
                game.submitActivity(.init(indices:q.activity!.solution!))
                proof.submissions[q.activity!.kind.rawValue] = game.round?.answers.first?.correct == true && game.round?.answers.first?.response?.indices == q.activity?.solution
            }
            game.leave(); saveProof()
            var generated: [Question] = []
            let jobs: [(QuestionFormat,Topic,String,String)] = [
                (.listening,.science,"Kısa Türkçe bilim anlatısı","gpt-6-luna"),
                (.ordering,.exam,"Temel matematik: dört farklı tam sayıyı küçükten büyüğe sırala.","claude-sonnet-5-5"),
                (.matching,.language,"İngilizce A1 sözcükler ve tek anlamlı Türkçe karşılıkları","gemini-3.8-flash"),
                (.pronunciation,.language,"İngilizce kısa selamlama ifadesi","gpt-6-luna")
            ]
            for (format,topic,detail,model) in jobs {
                do {
                    let excluded = (try? await pool.database?.texts(topic:topic)) ?? []
                    let qs = try await AIService(gateway:gateway).questions(topic:topic,detail:detail,difficulty:.easy,count:1,models:[model],excluding:excluded,format:format,study:topic == .exam ? .init(exam:"TYT",lesson:"Matematik") : nil,accept:{ batch in try await self.pool.database?.novelCandidates(batch) ?? batch },progress:{ _,_,_ in })
                    generated += qs; proof.generated[format.databaseFilter] = qs.count; proof.models.append(model)
                } catch { proof.errors.append(format.rawValue+": "+((error as? QuizError)?.message ?? "Üretim tamamlanamadı")) }
                saveProof()
            }
            if !generated.isEmpty {
                packs.insert(QuestionPack(id:UUID(),date:Date(),title:"Yeni soru türleri · canlı deneme",questions:generated,models:proof.models),at:0); persist()
                do { try await pool.database?.insert(generated); await pool.refresh() }
                catch { proof.errors.append("Kalıcı havuz kaydı tamamlanamadı") }
                if let data = try? JSONEncoder().encode(generated) { try? data.write(to:output.deletingLastPathComponent().appendingPathComponent("activity-generated-questions.json"),options:[.atomic,.completeFileProtection]) }
            }
            proof.finished = true; saveProof(); return
        }
        if mode == "session-audio" {
            struct SessionProof: Codable {
                var finished = false
                var effects: [String:Bool] = [:]
                var turkishVoice = false
                var speechStarted = false
                var quarantined = 0
            }
            var proof = SessionProof()
            // Only questions introduced by our own visual acceptance pack are inspected here.
            let introduced = packs.filter { $0.title == "Görsel sorular · canlı deneme" }.flatMap(\.questions)
            for q in introduced {
                let ambiguousControl = q.text.localizedCaseInsensitiveContains("kontrol grubudur") && q.visual?.rows?.contains(where:{ $0.joined().localizedCaseInsensitiveContains("karanlık") }) == true
                let unlabeledMeasurement = q.visual?.kind == .barChart && q.visual?.title.localizedCaseInsensitiveContains("örnek") == false
                if ambiguousControl || unlabeledMeasurement { self.report(q,reason:.ambiguous); proof.quarantined += 1 }
            }
            let audio = GameAudio()
            let names = ["start","correct","wrong","tick","timeout","stage","finish"]
            for (event,name) in zip(GameAudio.Event.allCases,names) {
                audio.play(event,effects:true,speech:nil)
                try? await Task.sleep(for:.milliseconds(450))
                proof.effects[name] = audio.lastEffectStarted
            }
            proof.turkishVoice = AVSpeechSynthesisVoice(language:"tr-TR") != nil
            audio.play(.stage,effects:false,speech:"Ses denemesi. Yeni etap başlıyor.")
            try? await Task.sleep(for:.milliseconds(700))
            proof.speechStarted = audio.isSpeaking
            audio.stop(); proof.finished = true
            let url = output.deletingLastPathComponent().appendingPathComponent("session-acceptance.json")
            if let data = try? JSONEncoder().encode(proof) { try? data.write(to:url,options:[.atomic,.completeFileProtection]) }
            return
        }
        if mode == "visual-questions" {
            struct VisualAcceptance: Codable {
                var finished = false; var count = 0; var kinds: [String:Int] = [:]
                var valid = false; var models: [String] = []; var error: String?
            }
            var proof = VisualAcceptance()
            let url = output.deletingLastPathComponent().appendingPathComponent("visual-acceptance.json")
            func saveProof() { if let data = try? JSONEncoder().encode(proof) { try? data.write(to:url,options:[.atomic,.completeFileProtection]) } }
            saveProof()
            do {
                let excluded = (try? await pool.database?.texts(topic:.science)) ?? []
                let qs = try await AIService(gateway:gateway).questions(topic:.science,detail:"",difficulty:.easy,count:5,models:["gpt-6-luna"],excluding:excluded,format:.visual,progress:{ _,_,_ in })
                proof.count = qs.count; proof.valid = qs.allSatisfy { $0.isWellFormed && $0.visual != nil }
                proof.kinds = Dictionary(grouping:qs,by:{ $0.visual!.kind.rawValue }).mapValues(\.count)
                proof.models = Array(Set(qs.compactMap(\.modelID))).sorted()
                packs.insert(QuestionPack(id:UUID(),date:Date(),title:"Görsel sorular · canlı deneme",questions:qs,models:proof.models),at:0); persist()
                try await pool.database?.insert(qs); await pool.refresh()
                if let data = try? JSONEncoder().encode(["questions":qs]) { try? data.write(to:output.deletingLastPathComponent().appendingPathComponent("visual-generated-questions.json"),options:[.atomic,.completeFileProtection]) }
            } catch { proof.error = (error as? QuizError)?.message ?? "Görsel üretim tamamlanamadı." }
            proof.finished = true; saveProof(); report.finished = true; report.questionCount = proof.count; write(); return
        }
        if mode == "daily-pool" {
            struct PoolAcceptance: Codable {
                let day: String; let before: Int; let after: Int; let total: Int
                let models: [String]; let categories: [String:Int]; let levels: [String:Int]
                let valid: Bool; let unique: Bool; let status: String; let hosts: [String:Int]
            }
            await pool.bootstrap(packs:packs,reports:reports,history:history)
            let day = DailyPoolPlan.day(Date()), before = pool.snapshot.today
            await pool.run(maxBatches:2)
            let qs = (try? await pool.database?.dayQuestions(day)) ?? []
            let result = PoolAcceptance(day:day,before:before,after:pool.snapshot.today,total:pool.snapshot.total,
                models:Array(Set(qs.compactMap(\.modelID))).sorted(),categories:Dictionary(grouping:qs,by:{ $0.category.rawValue }).mapValues(\.count),
                levels:Dictionary(grouping:qs,by:{ $0.difficulty.rawValue }).mapValues(\.count),valid:qs.allSatisfy(\.isWellFormed),
                unique:Set(qs.map { QuestionSimilarity.fingerprint($0.text) }).count == qs.count,status:pool.status,hosts:await PhoneTraffic.shared.snapshot())
            let url = output.deletingLastPathComponent().appendingPathComponent("daily-pool-acceptance.json")
            if let data = try? JSONEncoder().encode(result) { try? data.write(to:url,options:[.atomic,.completeFileProtection]) }
            report.finished = true; report.questionCount = qs.count; write(); return
        }
        if mode == "reproduce" || mode == "recovery-check" {
            let sample: GenerationDraft?
            if mode == "recovery-check" {
                let fixture = output.deletingLastPathComponent().appendingPathComponent("recovery-fixture.json")
                sample = (try? Data(contentsOf: fixture)).flatMap { try? JSONDecoder().decode(GenerationDraft.self, from: $0) }
            } else { sample = draft }
            guard let draft = sample else { return }
            struct GenerationDiagnostic: Codable { let model: String; let error: String?; let content: String?; let count: Int; let before: Int; let preserved: Bool }
            var errorText: String?, questionCount = 0, preserved = false
            do {
                let qs = try await AIService(gateway: gateway).questions(topic: draft.topic, detail: draft.detail, difficulty: draft.difficulty, count: draft.count, models: draft.models, excluding: history.map { $0.question.text }, initial: draft.questions, progress: { _,_,_ in })
                questionCount = qs.count; preserved = Array(qs.prefix(draft.questions.count)) == draft.questions
            } catch { errorText = (error as? QuizError)?.message ?? "Bağlantı tamamlanamadı" }
            let diagnostic = GenerationDiagnostic(model: draft.models[(draft.questions.count/5)%draft.models.count], error: errorText, content: await gateway.contentDiagnostic(), count: questionCount, before: draft.questions.count, preserved: preserved)
            let url = output.deletingLastPathComponent().appendingPathComponent("generation-diagnostic.json")
            if let data = try? JSONEncoder().encode(diagnostic) { try? data.write(to: url, options: [.atomic, .completeFileProtection]) }
            return
        }
        if mode == "features" {
            do {
                let team = ["gpt-6-luna", "gemini-3.8-flash"]
                var qs = try await AIService(gateway: gateway).questions(topic: .science, detail: "", difficulty: .easy, count: 10, models: team, excluding: [], progress: { _,_,_ in })
                report.teamModels = Array(Set(qs.compactMap(\.modelID))).sorted()
                qs = try await AIService(gateway: gateway).verify(qs, model: "claude-sonnet-5-5")
                report.reviewedCount = qs.filter { $0.reviewedBy != nil }.count
                let answer = try await AIService(gateway: gateway).tutor(question: qs[0], selected: (qs[0].answer + 1) % 4, message: "Daha basit anlat ve bir örnek ver", model: "gpt-6-luna")
                report.coachCharacters = answer.count; report.questionCount = qs.count
                packs.insert(QuestionPack(id: UUID(), date: Date(), title: "Model takımı · Bilim", questions: qs, models: team), at: 0); persist()
            } catch { report.questionError = (error as? QuizError)?.message ?? "Özellik doğrulaması tamamlanamadı" }
            report.questionDiagnostic = await gateway.diagnostic()
            report.hosts = await PhoneTraffic.shared.snapshot(); report.finished = true; write(); return
        }
        let priorities = ["gpt-6-luna", "claude-sonnet-5-5", "gemini-3.8-flash"]
        let all = availableText.sorted { a,b in
            let ai = priorities.firstIndex(of: a.id) ?? 999, bi = priorities.firstIndex(of: b.id) ?? 999
            return ai == bi ? a.id < b.id : ai < bi
        }
        let ids = mode == "all" ? all.map(\.id) : mode == "retry" ? all.filter { checks[$0.id]?.success == false }.map(\.id) : priorities.filter { id in all.contains { $0.id == id } }
        await withTaskGroup(of: ModelCheck.self) { group in
            var iterator = ids.makeIterator()
            for _ in 0..<3 { if let id = iterator.next() { group.addTask { await self.gateway.probe(id) } } }
            while let check = await group.next() {
                report.checks.append(check); checks[check.model] = check
                report.hosts = await PhoneTraffic.shared.snapshot(); persist(); write()
                if let id = iterator.next() { group.addTask { await self.gateway.probe(id) } }
            }
        }
        if let successful = report.checks.first(where: \.success)?.model {
            do {
                let qs = try await AIService(gateway: gateway).questions(topic: .science, detail: "", difficulty: .easy, count: 5, models: [successful], excluding: [], progress: { _,_,_ in })
                report.questionCount = qs.count; report.generationModel = successful
                let pack = QuestionPack(id: UUID(), date: Date(), title: "iPhone canlı doğrulama", questions: qs, models: [successful])
                packs.insert(pack, at: 0); persist()
            } catch { report.questionError = (error as? QuizError)?.message ?? "Soru üretimi tamamlanamadı" }
        }
        report.hosts = await PhoneTraffic.shared.snapshot()
        report.finished = true; write()
        #endif
    }
}

#if DEBUG
/// Real TTS and device Whisper, using a prerecorded answer instead of a person's microphone.
@MainActor private final class FixtureQuizLiveVoice: QuizLiveVoice {
    let chained: ChainedQuizVoice
    let file: URL
    var route: String { chained.route }
    var level: Double { 0 }
    var spokenParts = 0, recognized = ""
    var sources: [String] = []
    init(voice: VoiceAnswerStore, file: URL) { chained = ChainedQuizVoice(voice:voice); self.file = file }
    func prepare() async throws { try await chained.prepare() }
    func speak(_ segments: [QuizSpeechSegment]) async throws {
        try await chained.speak(segments); spokenParts += segments.count; sources.append(chained.speaker.source)
    }
    func hear(language: String) async throws -> String {
        recognized = try await chained.voice.whisper.transcribe(file,language:language); return recognized
    }
    func finishHearing() {}
    func stop() { chained.stop() }
}
#endif
