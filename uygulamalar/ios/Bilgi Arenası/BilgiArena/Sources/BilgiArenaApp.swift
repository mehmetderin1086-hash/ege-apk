import SwiftUI

@main struct BilgiArenaApp: App {
    @UIApplicationDelegateAdaptor(ArenaAppDelegate.self) private var appDelegate
    @StateObject private var store = GameStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).environmentObject(store.pool)
                .preferredColorScheme(.dark)
                .onChange(of: phase) { _, phase in store.setActive(phase == .active); store.pool.setForeground(phase == .active) }
        }
    }
}

let ink = Color(red: 0.035, green: 0.055, blue: 0.14)
let panel = Color(red: 0.09, green: 0.13, blue: 0.25)
let aqua = Color(red: 0.20, green: 0.85, blue: 0.78)
let gold = Color(red: 1, green: 0.76, blue: 0.30)

struct RootView: View {
    @EnvironmentObject var game: GameStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var page = 0
    @State private var showSettings = false
    @AppStorage(ArenaPreferences.Key.haptics) private var haptics = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var screen: Int { game.round == nil ? 0 : game.round?.finished == true ? 3 : game.card ? 2 : 1 }
    var body: some View {
        ZStack {
            ArenaBackdrop()
            if game.round != nil {
                if game.round?.finished == true { ResultView() }
                else if game.card { BreakView() }
                else { GameView() }
            } else {
                TabView(selection: $page) {
                    HomeView(showSettings: $showSettings).tabItem { Label("Oyna", systemImage: "play.circle.fill") }.tag(0)
                    HistoryView().tabItem { Label("İlerleme", systemImage: "chart.bar.fill") }.tag(1)
                    AcademyView().tabItem { Label("Akademi", systemImage: "books.vertical.fill") }.tag(2)
                    ModelCenterView().tabItem { Label("Modeller", systemImage: "cpu.fill") }.tag(3)
                    SettingsView().tabItem { Label("Ayarlar", systemImage: "gearshape.fill") }.tag(4)
                }.tint(aqua)
            }
        }
        .overlay {
            #if DEBUG
            if let audit = game.microphoneAuditGame {
                ZStack { ArenaBackdrop(); if audit.round?.finished == true { ResultView() } else { GameView() } }.environmentObject(audit)
            }
            #endif
        }
        .animation(reduceMotion ? nil : .easeInOut(duration:0.25),value:screen)
        .task {
            await game.loadModels()
            game.pool.setBusy(game.round != nil || game.loading)
            await game.pool.bootstrap(packs:game.packs,reports:game.reports,history:game.history)
            game.pool.setForeground(scenePhase == .active)
            await game.runDevelopmentAuditIfRequested()
        }
        .onChange(of:game.loading) { _,_ in game.pool.setBusy(game.round != nil || game.loading || game.checkingModel != nil) }
        .onChange(of:game.checkingModel) { _,_ in game.pool.setBusy(game.round != nil || game.loading || game.checkingModel != nil) }
        .onChange(of:game.mode) { _,_ in game.persistSelection() }
        .onChange(of:game.study) { _,_ in game.persistSelection() }
        .onChange(of:game.questionFormat) { _,_ in game.persistSelection() }
        .onChange(of:game.roundSettings) { _,_ in game.persistSelection() }
        .onChange(of:game.soundEnabled) { _,enabled in if !enabled { game.audio.stop() }; game.persistSelection() }
        .onChange(of:game.voiceEnabled) { _,enabled in if !enabled { game.audio.stop() }; game.persistSelection() }
        .sheet(isPresented: $showSettings) { ModelCenterView() }
        .alert("Bilgi Arenası", isPresented: Binding(get: { game.error != nil }, set: { if !$0 { game.error = nil } })) { Button("Tamam", role: .cancel) { game.error = nil } } message: { Text(game.error ?? "") }
        .sensoryFeedback(trigger:game.topic) { _,_ in haptics ? .selection : nil }
        .sensoryFeedback(trigger:game.mode) { _,_ in haptics ? .selection : nil }
        .sensoryFeedback(trigger:game.hapticCorrect) { _,_ in haptics ? .success : nil }
        .sensoryFeedback(trigger:game.hapticWrong) { _,_ in haptics ? .error : nil }
        .sensoryFeedback(trigger:game.hapticTick) { _,_ in haptics ? .impact(flexibility:.rigid,intensity:0.85) : nil }
        .sensoryFeedback(trigger:game.hapticCard) { _,_ in haptics ? .levelChange : nil }
    }
}

struct HomeView: View {
    @EnvironmentObject var game: GameStore
    @EnvironmentObject var pool: DailyQuestionPool
    @Binding var showSettings: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showPool = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("BİLGİ ARENASI").font(.caption.bold()).tracking(2).foregroundStyle(aqua)
                            Text("Merakının peşinden.").font(.title2.bold())
                        }
                        Spacer()
                        LevelEmblem(level:game.level)
                    }
                    ArenaHero(level:game.level,xp:game.totalXP)
                    Button { showPool = true } label: {
                        HStack(spacing:12) {
                            Image(systemName:"square.stack.3d.up.fill").font(.title2).foregroundStyle(gold)
                            VStack(alignment:.leading,spacing:4) {
                                Text("Büyüyen soru havuzun").font(.subheadline.bold())
                                Text("\(pool.snapshot.total) soru · Bugün \(pool.snapshot.today)/450").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName:pool.running ? "sparkles" : "chevron.right").foregroundStyle(aqua)
                        }.padding(16).arenaPanel(tint:gold,radius:18)
                    }.buttonStyle(ArenaPressStyle()).accessibilityIdentifier("openQuestionPool")
                    Button { game.start(ActivityQuestionSeeds.questions,source:"Yeni soru türleri",mode:.training) } label: { Label("Yeni soru türlerini dene",systemImage:"headphones").font(.headline).frame(maxWidth:.infinity).padding(17).arenaPanel(tint:gold,radius:20) }.accessibilityIdentifier("startActivityTour")
                    Button { game.start(VisualQuestionSeeds.questions,source:"Görsel keşif turu",mode:.training) } label: {
                        HStack(spacing:12) { Image(systemName:"photo.on.rectangle.angled").font(.title2).foregroundStyle(aqua); VStack(alignment:.leading,spacing:4) { Text("Görsel keşif turu").font(.subheadline.bold()); Text("Şekil, resim, tablo ve grafik · Süresiz").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName:"play.circle.fill").font(.title2).foregroundStyle(aqua) }.padding(16).arenaPanel(tint:aqua,radius:18)
                    }.buttonStyle(ArenaPressStyle()).disabled(game.loading).accessibilityIdentifier("startVisualTour")
                    Button { showSettings = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "iphone.gen3.radiowaves.left.and.right").font(.title2).foregroundStyle(aqua)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(game.teamEnabled ? "Model takımın" : "Seçili model").font(.subheadline.bold())
                                Text(game.teamEnabled ? "\(game.teamModels.count) model · iPhone bağlantısı" : game.selectedModel.isEmpty ? "Modellerini keşfet" : game.selectedModel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text("\(game.availableText.count) model").font(.caption.bold()).foregroundStyle(aqua)
                            Image(systemName: "chevron.right").font(.caption)
                        }.padding(16).arenaPanel(tint:aqua,radius:18)
                    }.buttonStyle(ArenaPressStyle()).accessibilityIdentifier("phoneModels")
                    HStack(spacing: 10) {
                        Button { game.daily() } label: { quickCard("Günün turu", detail: "10 soruluk keşif", icon: "sun.max.fill", color: gold) }
                        Button { game.startReview() } label: { quickCard("Tekrar zamanı", detail: "\(game.dueCards.count) soru bekliyor", icon: "arrow.trianglehead.2.clockwise.rotate.90", color: aqua) }.disabled(game.dueCards.isEmpty)
                    }.buttonStyle(ArenaPressStyle()).disabled(game.loading)
                    Text("Nasıl oynamak istersin?").font(.title3.bold())
                    Grid(horizontalSpacing:8,verticalSpacing:8) {
                        GridRow { ForEach(Array(GameMode.allCases.prefix(3))) { modeCard($0) } }
                        GridRow { ForEach(Array(GameMode.allCases.suffix(2))) { modeCard($0) } }
                    }
                    Text(game.mode.subtitle).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        preset("Keşif",mode:.training,minutes:0,count:10)
                        preset("Kısa Tur",mode:.timed,minutes:2,count:10)
                        preset("Maraton",mode:.stages,minutes:10,count:30)
                    }
                    SessionSettingsView()
                    LiveQuizSetup()
                    Text("Görsel sorularda en az 25, hız turunda 15 saniye verilir. Dakika turunda yalnız toplam saat işler.").font(.caption2).foregroundStyle(.secondary)
                    Text("Bir kategori seç").font(.title3.bold())
                    TopicGrid(selection:$game.topic)
                    if game.topic == .exam { StudyLessonPicker(selection:$game.study) }
                    if [.custom, .language, .exam].contains(game.topic) {
                        TextField(game.topic == .language ? "Örn. İngilizce B1 kelimeler" : game.topic == .exam ? "Örn. TYT biyoloji hücre" : "Örn. Uzay keşifleri", text: $game.detail).padding().background(panel, in: RoundedRectangle(cornerRadius: 14))
                        if game.topic == .language { presetChips(["İngilizce", "Almanca", "Arapça", "İspanyolca", "Fransızca"]) }
                        if game.topic == .exam { presetChips(["TYT", "AYT", "KPSS", "LGS"]) }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tur ayarları").font(.headline)
                        Picker("Soru biçimi",selection:$game.questionFormat) { ForEach(QuestionFormat.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu).accessibilityIdentifier("questionFormat")
                        Picker("Zorluk", selection: $game.difficulty) { ForEach(Difficulty.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                        HStack { Text("Soru sayısı"); Spacer(); Picker("Soru sayısı", selection: $game.count) { Text("10").tag(10); Text("20").tag(20); Text("30").tag(30) }.pickerStyle(.segmented).frame(width: 180) }
                        if let draft = game.draft, !draft.questions.isEmpty { Label("\(draft.questions.count) soruluk hazırlık saklandı. Aynı ayarlarla kaldığın yerden sürer.", systemImage: "arrow.clockwise").font(.caption).foregroundStyle(gold) }
                    }
                    if game.loading {
                        VStack(alignment: .leading, spacing: 12) {
                            GenerationIndicator(progress:game.progress,status:game.generationStatus)
                            Button("Hazırlığı durdur") { game.cancelGeneration() }.font(.subheadline.bold()).foregroundStyle(gold)
                        }.padding(16).arenaPanel(tint:aqua,radius:18)
                    } else {
                        Button { Task { await game.startAI() } } label: { Label(game.teamEnabled ? "Model takımıyla üret" : "Yapay zekâ ile oyna", systemImage: "sparkles") }.buttonStyle(PrimaryButton()).accessibilityIdentifier("startAI")
                    }
                    Button { game.startLocal() } label: { Label("Havuzdan hemen oyna", systemImage: "bolt.fill").font(.headline).frame(maxWidth: .infinity).padding(17).background(panel, in: RoundedRectangle(cornerRadius: 16)) }.disabled(game.loading).accessibilityIdentifier("startLocal")
                    Text("Havuz seçtiğin zorlukta ve kategoride açılır; soru sayısı kısalabilir. Yeni ve uzun süredir görmediğin sorular önce gelir. Havuz soruları çevrimdışı oynanır; AI üretimi internet kullanır.").font(.footnote).foregroundStyle(.white.opacity(0.5))
                }.padding(20)
            }.background(ArenaBackdrop()).toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented:$showPool) { NavigationStack { ScrollView { QuestionPoolSection().padding(20) }.background(ArenaBackdrop()).navigationTitle("Soru havuzu").toolbar { ToolbarItem(placement:.topBarTrailing) { Button("Kapat") { showPool = false } } } } }
        }.tint(aqua)
    }
    func modeCard(_ mode: GameMode) -> some View {
        Button { withAnimation(reduceMotion ? nil : .spring(response:0.32,dampingFraction:0.8)) { game.mode = mode } } label: {
            VStack(spacing:7) { Image(systemName:mode.icon).font(.title3); Text(mode.rawValue).font(.caption.bold()) }.frame(maxWidth:.infinity).padding(.vertical,14).background(game.mode == mode ? aqua : panel,in:RoundedRectangle(cornerRadius:15)).foregroundStyle(game.mode == mode ? ink : .white)
        }.buttonStyle(ArenaPressStyle())
    }
    func preset(_ title: String, mode: GameMode, minutes: Int, count: Int) -> some View {
        Button(title) { game.mode = mode; game.roundSettings = .init(minutes:minutes); game.count = count }
            .font(.caption.bold()).frame(maxWidth:.infinity).padding(.vertical,12).background(panel,in:Capsule()).buttonStyle(ArenaPressStyle())
    }
    func quickCard(_ title: String, detail: String, icon: String, color: Color) -> some View {
        VStack(alignment:.leading,spacing:10) { Image(systemName:icon).font(.system(size:21,weight:.semibold)).foregroundStyle(color).frame(width:40,height:40).background(color.opacity(0.12),in:RoundedRectangle(cornerRadius:12)); Text(title).font(.subheadline.bold()); Text(detail).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading).padding(16).arenaPanel(tint:color,radius:20)
    }
    func presetChips(_ values: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(values, id: \.self) { value in Button(value) { game.detail = value }.font(.caption.bold()).padding(10).background(panel, in: Capsule()) } } }
    }
}

struct GameView: View {
    @EnvironmentObject var game: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmExit = false
    @State private var wasPausedBeforeVisual = false
    @State private var showVoiceAnswer = false
    var body: some View {
        if let r = game.round {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment:.leading,spacing:18) {
                        HStack {
                            Button { confirmExit = true } label: { Image(systemName:"xmark").font(.subheadline.bold()).foregroundStyle(.white.opacity(0.7)).frame(width:42,height:42).arenaPanel(radius:14) }.buttonStyle(ArenaPressStyle()).accessibilityLabel("Oyundan çık")
                            Spacer()
                            VStack(spacing:3) { Text(r.liveVoice == true ? "CANLI SESLİ" : r.effectiveMode.rawValue.uppercased()).font(.system(size:9,weight:.bold)).tracking(1.5).foregroundStyle(aqua); Text("Soru \(r.index + 1) / \(r.questions.count)").font(.subheadline.bold()) }
                            Spacer()
                            Label("\(r.score)",systemImage:"star.fill").font(.subheadline.bold().monospacedDigit()).foregroundStyle(gold).padding(11).background(gold.opacity(0.09),in:Capsule()).contentTransition(.numericText())
                        }.id("question-top")
                        if r.liveVoice == true { LiveQuizPanel(live:game.liveQuiz) }
                        HStack(spacing:4) {
                            ForEach(0..<r.questions.count,id:\.self) { index in Capsule().fill(index < r.answers.count ? (r.answers[index].correct ? aqua : Color(red:1,green:0.46,blue:0.55)) : index == r.index ? .white.opacity(0.75) : .white.opacity(0.1)).frame(height:4) }
                        }.accessibilityHidden(true)
                        HStack {
                            if r.effectiveMode == .stages { Label("Etap \(r.stageIndex+1)/3 · \(r.stageTitle)",systemImage:"flag.checkered").foregroundStyle(gold).accessibilityIdentifier("stageLabel") }
                            Spacer()
                            if let clock = r.clockText { Label(clock,systemImage:"timer").monospacedDigit().foregroundStyle((r.totalRemaining ?? 60) <= 10 ? Color.red : aqua).accessibilityLabel("Tur süresi \(clock)").accessibilityIdentifier("roundClock") }
                        }.font(.subheadline.bold())
                        VStack(alignment:.leading,spacing:15) {
                            HStack {
                                Label(r.current.category.rawValue,systemImage:r.current.category.icon).font(.caption.bold()).foregroundStyle(r.current.category.accent).padding(.horizontal,11).padding(.vertical,7).background(r.current.category.accent.opacity(0.1),in:Capsule())
                                Spacer()
                                Button { if r.paused { game.resume() } else { game.pause() } } label: { Image(systemName:r.paused ? "play.fill" : "pause.fill").font(.caption.bold()).foregroundStyle(.white.opacity(0.65)).frame(width:32,height:32) }.accessibilityLabel(r.paused ? "Devam et" : "Duraklat")
                                if r.hasQuestionClock { CountdownDial(remaining:r.remaining,total:r.questionSeconds,training:false) }
                                else if r.totalRemaining == nil { CountdownDial(remaining:0,total:0,training:true) }
                            }
                            if let study = r.current.study { Text(study.title).font(.caption.bold()).foregroundStyle(gold) }
                            Text(r.current.text).font(.system(.title2,design:.rounded,weight:.bold)).fixedSize(horizontal:false,vertical:true).lineSpacing(3).accessibilityIdentifier("question")
                            if r.liveVoice != true && (r.current.activity?.kind == .listening || r.current.activity?.kind == .pronunciation) { ListeningQuestionCard(question:r.current,speaker:game.speaker).id(r.current.id) }
                            if let visual = r.current.visual {
                                QuestionVisualCard(visual:visual) { opening in
                                    if opening { wasPausedBeforeVisual = game.round?.paused ?? false; game.pause() }
                                    else if !wasPausedBeforeVisual, game.round?.id == r.id, game.round?.index == r.index { game.resume() }
                                }
                            }
                        }.padding(19).arenaPanel(tint:r.current.category.accent,radius:24)
                            .id("question-card-\(r.index)").transition(reduceMotion ? .opacity : .opacity.combined(with:.offset(x:18)))
                        if r.liveVoice != true, !r.revealed, !r.paused, !r.awaitsListening, !game.listening {
                            Button { game.pause(); showVoiceAnswer = true } label: { Label("Sesli cevap ver",systemImage:"mic.fill").font(.headline).frame(maxWidth:.infinity).padding(14).arenaPanel(tint:gold,radius:16) }.accessibilityIdentifier("openVoiceAnswer")
                        }
                        if let activity = r.current.activity, activity.kind == .pronunciation {
                            Text(r.liveVoice == true ? "Örneği dinle; mikrofon açılınca ifadeyi söyle. Anlaşılan kelimeler hedefle karşılaştırılır; aksan puanı verilmez." : "Örneği dinle; sesli cevap penceresinden ifadeyi söyle. Anlaşılan kelimeleri kontrol edip denemeni kaydet.").font(.subheadline).foregroundStyle(.secondary)
                        } else if let activity = r.current.activity, activity.isInteractive {
                            ActivityAnswerBoard(activity:activity,disabled:r.revealed || r.paused,submit:game.submitActivity,draft:r.revealed ? r.answers.last?.response : r.activityDraft,saveDraft:game.saveActivityDraft).id(r.current.id)
                        } else {
                        VStack(spacing:11) {
                            ForEach(0..<4,id:\.self) { index in
                                AnswerOption(index:index,text:r.current.options[index],revealed:r.revealed,correct:index == r.current.answer,chosen:r.answers.last?.chosen == index && r.revealed,eliminated:r.eliminated.contains(index),wrongTrigger:game.hapticWrong) { game.answer(index) }
                                    .disabled(r.revealed || r.paused || r.awaitsListening || game.listening || r.eliminated.contains(index))
                            }
                        }.id("options-\(r.index)")
                        }
                        if r.liveVoice != true, !r.revealed { Button("Bu turu sesli sürdür") { game.enableLive() }.font(.caption.bold()).accessibilityIdentifier("enableLiveQuiz") }
                        if r.paused {
                            VStack(spacing:10) { Label("Kısa bir mola",systemImage:"pause.circle").font(.headline).foregroundStyle(gold); Button("Oyuna devam et") { game.resume() }.buttonStyle(PrimaryButton()) }.padding(.top,6)
                        } else if r.revealed, let answer = r.answers.last {
                            VStack(alignment:.leading,spacing:12) {
                                HStack(alignment:.top,spacing:10) {
                                    Image(systemName:answer.correct ? "checkmark.seal.fill" : "lightbulb.fill").font(.title2).foregroundStyle(answer.correct ? aqua : gold)
                                    VStack(alignment:.leading,spacing:4) { Text(answer.correct ? "Harika, doğru cevap!" : answer.chosen == nil ? "Bir sonraki soruda devam!" : "Yeni bir şey öğrendin").font(.headline); Text(answer.correct ? "+\(answer.points) puan" : "Doğru cevap: \(r.current.correctAnswerText)").font(.subheadline.bold()).foregroundStyle(answer.correct ? aqua : gold) }
                                    Spacer(minLength:0)
                                    Button { game.toggleSaved(r.current) } label: { Image(systemName:game.saved.contains(where:{ $0.id == r.current.id }) ? "bookmark.fill" : "bookmark").font(.title3).foregroundStyle(aqua) }.accessibilityLabel("Soruyu kaydet")
                                }
                                Text(r.current.explanation).font(.subheadline).foregroundStyle(.white.opacity(0.8)).lineSpacing(3)
                                HStack { SingleQuestionShareButton(question:r.current); Spacer(); QuestionReportMenu(question:r.current) }.font(.caption).foregroundStyle(aqua)
                                if let spoken = answer.response?.spokenText { Text("Sesli yanıtın: " + spoken).font(.subheadline).foregroundStyle(.secondary) }
                                else if let response = answer.response, let activity = r.current.activity { Text("Yanıtın: " + activity.describe(response)).font(.subheadline).foregroundStyle(.secondary) }
                                if r.current.activity?.needsResponse != true, let selected = answer.chosen, let reasons = r.current.optionExplanations { Text("Seçtiğin şık: \(reasons[selected])").font(.subheadline).foregroundStyle(.white.opacity(0.65)) }
                            }.padding(18).arenaPanel(tint:answer.correct ? aqua : gold,radius:22).transition(.opacity.combined(with:.offset(y:reduceMotion ? 0 : 10)))
                            Button(r.index + 1 == r.questions.count ? "Sonucu gör" : "Sonraki soru") { game.next() }.buttonStyle(PrimaryButton()).accessibilityIdentifier("nextQuestion")
                            if r.current.modelID != nil { Text("Üreten: \(r.current.modelID ?? "")" + (r.current.reviewedBy.map { " · Kontrol: " + $0 } ?? "")).font(.caption2).foregroundStyle(.secondary) }
                            CoachPanel()
                        } else if r.liveVoice != true {
                            HStack(spacing:8) {
                                if r.current.activity?.needsResponse != true { joker("50:50",icon:"divide",used:r.usedHalf) { game.half() } }
                                if r.effectiveMode != .training { joker("+15 sn",icon:"clock.badge.plus",used:r.usedTime) { game.extraTime() } }
                                joker("Geç",icon:"forward.end.fill",used:r.usedSkip) { game.skip() }
                            }
                            Text("Her joker turda bir kez kullanılabilir.").font(.caption2).foregroundStyle(.white.opacity(0.4)).frame(maxWidth:.infinity)
                        }
                    }.padding(20).animation(reduceMotion ? nil : .easeInOut(duration:0.25),value:r.revealed)
                }.onChange(of:r.index) { _,_ in withAnimation(reduceMotion ? nil : .easeInOut(duration:0.3)) { reader.scrollTo("question-top",anchor:.top) } }
            }.safeAreaInset(edge:.bottom) { if r.liveVoice == true, !r.finished { LiveQuizDock(live:game.liveQuiz) } }
            .sheet(isPresented:$showVoiceAnswer,onDismiss:{ game.voiceAnswer.cancel(); if game.round?.id == r.id, game.round?.index == r.index, game.round?.finished == false { game.resume() } }) {
                VoiceAnswerSheet(question:r.current,voice:game.voiceAnswer) { result,text in
                    guard game.round?.id == r.id, game.round?.index == r.index else { return }
                    game.resume()
                    switch result { case .choice(let index): game.answer(index,spokenText:text); case .activity(let response): game.submitActivity(response) }
                }
            }.confirmationDialog("Bu turdan çıkılsın mı?",isPresented:$confirmExit) { Button("Turdan çık",role:.destructive) { game.leave() }; Button("Vazgeç",role:.cancel) {} }
        }
    }
    func joker(_ title: String, icon: String, used: Bool, action: @escaping () -> Void) -> some View {
        Button(action:action) { Label(title,systemImage:icon).font(.caption.bold()).foregroundStyle(used ? Color.secondary : Color.white.opacity(0.8)).frame(maxWidth:.infinity).padding(.vertical,14).arenaPanel(radius:14) }.buttonStyle(ArenaPressStyle()).disabled(used).opacity(used ? 0.4 : 1)
    }
}

struct AnswerOption: View {
    let index: Int
    let text: String
    let revealed: Bool
    let correct: Bool
    let chosen: Bool
    let eliminated: Bool
    let wrongTrigger: Int
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false
    private var letter: String { String(UnicodeScalar(65+index)!) }
    private var tint: Color { revealed && correct ? aqua : revealed && chosen ? Color(red:1,green:0.42,blue:0.50) : .white }
    var body: some View {
        Button(action:action) {
            HStack(spacing:13) {
                Text(letter).font(.system(.subheadline,design:.rounded,weight:.bold)).foregroundStyle(revealed && (correct || chosen) ? ink : .white.opacity(0.65)).frame(width:35,height:35).background(revealed && (correct || chosen) ? tint : .white.opacity(0.07),in:RoundedRectangle(cornerRadius:11))
                Text(text).font(.body.weight(.semibold)).foregroundStyle(.white).multilineTextAlignment(.leading).frame(maxWidth:.infinity,alignment:.leading)
                if revealed && (correct || chosen) {
                    if reduceMotion { Image(systemName:correct ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(tint) }
                    else { Image(systemName:correct ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(tint).symbolEffect(.bounce,value:revealed) }
                }
            }.padding(14).frame(maxWidth:.infinity,minHeight:66)
                .background(LinearGradient(colors:[revealed && (correct || chosen) ? tint.opacity(0.17) : panel.opacity(0.8),ink.opacity(0.6)],startPoint:.leading,endPoint:.trailing),in:RoundedRectangle(cornerRadius:19))
                .overlay(RoundedRectangle(cornerRadius:19).stroke(tint.opacity(revealed && (correct || chosen) ? 0.75 : 0.08),lineWidth:revealed && (correct || chosen) ? 1.4 : 1))
                .shadow(color:revealed && correct ? aqua.opacity(0.10) : .clear,radius:12,y:4)
        }.buttonStyle(ArenaPressStyle()).opacity(eliminated ? 0.25 : entered ? 1 : 0)
            .offset(x:entered || reduceMotion ? 0 : 15)
            .modifier(AnswerShake(amount:revealed && chosen && !correct && !reduceMotion ? 8 : 0,animatableData:CGFloat(wrongTrigger)))
            .animation(reduceMotion ? nil : .easeOut(duration:0.45),value:wrongTrigger)
            .accessibilityLabel("\(letter). \(text)" + (revealed && correct ? ", doğru cevap" : revealed && chosen ? ", yanlış cevap" : ""))
            .accessibilityIdentifier("answer\(index)")
            .task {
                if !reduceMotion { try? await Task.sleep(for:.milliseconds(index*40)) }
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .spring(response:0.35,dampingFraction:0.85)) { entered = true }
            }
    }
}

struct PrimaryButton: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth:.infinity).padding(18)
            .background(LinearGradient(colors:[aqua,Color(red:0.22,green:0.72,blue:0.77)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:18))
            .overlay(RoundedRectangle(cornerRadius:18).stroke(.white.opacity(0.18),lineWidth:1))
            .foregroundStyle(ink).shadow(color:aqua.opacity(enabled ? 0.15 : 0),radius:16,y:7)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .animation(reduceMotion ? nil : .spring(response:0.25,dampingFraction:0.7),value:configuration.isPressed)
    }
}

struct BreakView: View {
    @EnvironmentObject var game: GameStore
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                VStack(spacing:3) {
                    VictoryMedallion(symbol:"book.closed.fill",tint:Color(red:0.72,green:0.64,blue:1)).frame(height:170)
                    Text(game.round?.effectiveMode == .stages ? "Sıradaki etap: " + (game.round?.stageTitle ?? "") : "Bilgi molası").font(.system(.largeTitle,design:.rounded,weight:.bold)).accessibilityIdentifier("stageBreak")
                    Text("Saat durdu. Bir nefes al, öğrendiklerin yerleşsin.").font(.subheadline).foregroundStyle(.white.opacity(0.6))
                }.frame(maxWidth:.infinity).padding(.bottom,12)
                Label("SON 10 SORUDAN AKLINDA KALSIN",systemImage:"sparkles").font(.system(size:10,weight:.bold)).tracking(1).foregroundStyle(aqua)
                if let round = game.round {
                    ForEach(Array(round.answers.suffix(10))) { record in
                        HStack(alignment:.top,spacing:12) {
                            Image(systemName:record.correct ? "checkmark.circle.fill" : "lightbulb.fill").foregroundStyle(record.correct ? aqua : gold).padding(.top,2)
                            VStack(alignment:.leading,spacing:7) { Text(record.question.text).font(.headline); if let visual = record.question.visual { QuestionVisualCard(visual:visual) }; if let activity = record.question.activity { ActivitySummaryCard(activity:activity) }; Text(record.question.explanation).font(.subheadline).foregroundStyle(.white.opacity(0.65)).lineSpacing(3) }
                        }.padding(17).frame(maxWidth:.infinity,alignment:.leading).arenaPanel(tint:record.question.category.accent,radius:20)
                    }
                }
                Button("Devam et") { game.card = false }.buttonStyle(PrimaryButton())
            }.padding(22)
        }
    }
}

struct ResultView: View {
    @EnvironmentObject var game: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false
    var body: some View {
        if let r = game.round {
            ScrollView {
                VStack(spacing:20) {
                    VStack(spacing:7) {
                        VictoryMedallion().frame(height:175)
                        Text("TUR TAMAMLANDI").font(.system(size:10,weight:.bold)).tracking(2.3).foregroundStyle(gold)
                        Text(r.answers.filter(\.correct).count * 100 / max(1,r.answers.count) >= 80 ? "Bilgin parlıyor!" : "Her tur yeni bir keşif.").font(.system(.title,design:.rounded,weight:.bold)).multilineTextAlignment(.center).accessibilityIdentifier("roundResult")
                        ScoreCounter(value:entered ? Double(r.score) : 0).font(.system(size:62,weight:.heavy,design:.rounded)).foregroundStyle(LinearGradient(colors:[.white,aqua],startPoint:.top,endPoint:.bottom)).padding(.top,5).accessibilityLabel("Toplam \(r.score) puan")
                        Text("PUAN").font(.system(size:10,weight:.bold)).tracking(2.5).foregroundStyle(.white.opacity(0.45))
                    }.frame(maxWidth:.infinity).padding(.bottom,6)
                    HStack(spacing:9) { stat("\(r.answers.filter(\.correct).count)","Doğru",icon:"checkmark",color:aqua); stat("\(r.answers.filter { !$0.correct }.count)","Yanlış / boş",icon:"arrow.clockwise",color:gold); stat("\(r.answers.count)","Soru",icon:"square.stack",color:Color(red:0.72,green:0.65,blue:1)) }
                    HStack(spacing:12) { LevelEmblem(level:game.level); VStack(alignment:.leading,spacing:5) { Text("Keşfe devam").font(.headline); Text("Bilgi yolculuğunda \(game.totalXP) XP'ye ulaştın.").font(.caption).foregroundStyle(.secondary) }; Spacer() }.padding(16).arenaPanel(tint:gold)
                    HStack { Text("Turdan aklında kalanlar").font(.title3.bold()); Spacer(); Image(systemName:"text.book.closed").foregroundStyle(aqua) }.padding(.top,8)
                    ForEach(r.answers) { record in
                        VStack(alignment:.leading,spacing:9) {
                            HStack(alignment:.top,spacing:10) { Image(systemName:record.correct ? "checkmark.circle.fill" : "lightbulb.fill").foregroundStyle(record.correct ? aqua : gold); Text(record.question.text).font(.headline) }
                            if let visual = record.question.visual { QuestionVisualCard(visual:visual) }; if let activity = record.question.activity { ActivitySummaryCard(activity:activity) }
                            Text(record.question.correctAnswerText).font(.subheadline.bold()).foregroundStyle(record.correct ? aqua : gold)
                            Text(record.question.explanation).font(.subheadline).foregroundStyle(.white.opacity(0.65)).lineSpacing(3)
                        }.frame(maxWidth:.infinity,alignment:.leading).padding(17).arenaPanel(tint:record.correct ? aqua : gold,radius:20)
                    }
                }.padding(20)
            }
            .overlay(alignment:.top) { ConfettiBurst().frame(height:350) }
            .safeAreaInset(edge:.bottom) { Button("Yeni oyun") { game.leave() }.buttonStyle(PrimaryButton()).padding(.horizontal,20).padding(.top,12).padding(.bottom,8).background(.ultraThinMaterial) }
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration:0.9)) { entered = true } }
        }
    }
    func stat(_ number: String, _ title: String, icon: String, color: Color) -> some View {
        VStack(spacing:8) { Image(systemName:icon).font(.caption.bold()).foregroundStyle(color); Text(number).font(.system(.title2,design:.rounded,weight:.bold)); Text(title).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth:.infinity).padding(.vertical,16).arenaPanel(tint:color,radius:19)
    }
}

struct HistoryView: View {
    @EnvironmentObject var game: GameStore
    var body: some View {
        NavigationStack {
            ScrollView { VStack(alignment: .leading, spacing: 16) {
                Text("İlerlemen").font(.largeTitle.bold())
                HStack { metric("\(game.results.count)", "Oyun"); metric("\(game.results.map(\.score).max() ?? 0)", "En iyi puan"); metric("\(game.results.reduce(0) { $0 + $1.correct })", "Doğru") }
                VStack(alignment: .leading, spacing: 9) {
                    HStack { Text("Seviye \(game.level)").font(.title2.bold()); Spacer(); Text("\(game.totalXP) XP").foregroundStyle(gold) }
                    ProgressView(value: Double(game.totalXP % 250), total: 250).tint(aqua)
                    Text("Doğruluk: %\(game.accuracy)").font(.caption).foregroundStyle(.secondary)
                }.padding(16).background(panel, in: RoundedRectangle(cornerRadius: 16))
                Text("Rozetlerin").font(.title3.bold())
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(game.achievements) { badge in
                        VStack(spacing:9) { Image(systemName:badge.icon).font(.title2).foregroundStyle(badge.earned ? gold : .secondary).frame(width:44,height:44).background(gold.opacity(badge.earned ? 0.12 : 0.025),in:Circle()); Text(badge.title).font(.caption2.bold()).multilineTextAlignment(.center) }.frame(maxWidth:.infinity,minHeight:106).arenaPanel(tint:badge.earned ? gold : .white,radius:18).opacity(badge.earned ? 1 : 0.45)
                    }
                }
                Text("Kategorilerde durumun").font(.title3.bold())
                ForEach(Topic.allCases.filter { topic in game.history.contains { $0.question.category == topic } }) { topic in
                    let answers = game.history.filter { $0.question.category == topic }
                    HStack { Label(topic.rawValue, systemImage: topic.icon); Spacer(); Text("\(answers.filter(\.correct).count)/\(answers.count)").foregroundStyle(aqua) }.font(.subheadline).padding(12).background(panel, in: RoundedRectangle(cornerRadius: 12))
                }
                Text("Son oyunlar").font(.title3.bold())
                if game.results.isEmpty { Text("Henüz bir tur tamamlamadın. İlk oyun seni bekliyor!").foregroundStyle(.secondary).padding(.vertical) }
                ForEach(game.results) { result in
                    HStack { VStack(alignment: .leading, spacing: 5) { Text(result.source).font(.headline); Text(result.date, style: .date).font(.caption).foregroundStyle(.secondary) }; Spacer(); VStack(alignment: .trailing) { Text("\(result.score) puan").bold().foregroundStyle(aqua); Text("\(result.correct)/\(result.total) doğru").font(.caption).foregroundStyle(.secondary) } }.padding(16).background(panel, in: RoundedRectangle(cornerRadius: 15))
                }
            }.padding(20) }.background(ArenaBackdrop()).toolbar(.hidden, for: .navigationBar)
        }
    }
    func metric(_ value: String, _ title: String) -> some View { VStack(spacing: 6) { Text(value).font(.title2.bold()).foregroundStyle(aqua); Text(title).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 18).background(panel, in: RoundedRectangle(cornerRadius: 15)) }
}
