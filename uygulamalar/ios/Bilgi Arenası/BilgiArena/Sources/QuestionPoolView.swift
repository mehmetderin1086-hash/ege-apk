import SwiftUI

struct QuestionPoolSection: View {
    @EnvironmentObject var game: GameStore
    @EnvironmentObject var pool: DailyQuestionPool
    @State private var search = ""
    @State private var topic: Topic = .mixed
    @State private var level = ""
    @State private var study: StudyLesson?
    @State private var format: QuestionFormat = .mixed
    @State private var questions: [Question] = []
    @State private var error: String?
    @FocusState private var searchFocused: Bool
    private var queryKey: String { search + "|" + topic.rawValue + "|" + level + "|" + format.rawValue + "|" + (study?.title ?? "") + "|\(pool.snapshot.total)" }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            VStack(alignment:.leading,spacing:14) {
                HStack { Image(systemName:"sparkles").foregroundStyle(gold); Text("Her gün yeni keşifler").font(.title3.bold()); Spacer() }
                Toggle("Otomatik soru üretimi",isOn:$pool.enabled).tint(aqua).accessibilityIdentifier("automaticPool")
                Text("9 kategori × 50 soru = günlük 450 soru hedefi. Kolay, orta ve zor seviyeler her kategoride 16–17 soru olacak şekilde dengelenir.").font(.subheadline).foregroundStyle(.secondary)
                HStack { Text("Bugün \(pool.snapshot.today) / 450").bold(); Spacer(); Text("Toplam \(pool.snapshot.total)").foregroundStyle(aqua) }.font(.subheadline)
                ProgressView(value:Double(min(450,pool.snapshot.today)),total:450).tint(aqua)
                Label(pool.status,systemImage:pool.running ? "sparkles" : "clock").font(.caption).foregroundStyle(.secondary).lineLimit(3).accessibilityIdentifier("poolStatus")
                Text("Modeller küçük paketlerde sırayla çalışır. Hata veren model bekletilir. iOS arka plan süresini belirler; günlük hedef garanti değildir. Uygulama açıkken de devam eder, oyun sırasında bekler.").font(.caption).foregroundStyle(.secondary)
                if !pool.scheduleStatus.isEmpty { Text(pool.scheduleStatus).font(.caption2).foregroundStyle(.secondary) }
                if pool.enabled { Button("Üretimi sürdür") { pool.retry() }.font(.subheadline.bold()).accessibilityIdentifier("resumePool") }
            }.padding(18).arenaPanel(tint:gold)
            DisclosureGroup("Kategorilerde bugünkü üretim") {
                ForEach(DailyPoolPlan.categories) { category in
                    VStack(alignment:.leading,spacing:6) {
                        HStack { Label(category.rawValue,systemImage:category.icon).foregroundStyle(category.accent); Spacer(); Text("\(Difficulty.allCases.reduce(0) { $0 + pool.snapshot.counts[PoolCell(topic:category,difficulty:$1),default:0] }) / 50").monospacedDigit() }.font(.subheadline)
                        Text(Difficulty.allCases.map { d in "\(d.rawValue) \(pool.snapshot.counts[PoolCell(topic:category,difficulty:d),default:0])/\(DailyPoolPlan.quota(PoolCell(topic:category,difficulty:d),day:DailyPoolPlan.day(Date())))" }.joined(separator:" · ")).font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical,6)
                }
            }.padding(16).arenaPanel()
            Text("Havuzda keşfet").font(.title2.bold())
            ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:12) { ForEach(QuestionVisualKind.allCases,id:\.self) { kind in Label("\(pool.snapshot.visualCounts[kind,default:0]) \(kind.title)",systemImage:kind.icon).font(.caption.bold()).foregroundStyle(aqua).padding(10).arenaPanel(radius:12) } } }
            Text("Karma tüm kategorileri birleştirir. Dil soruları beş dil arasında, sınav soruları farklı dersler arasında dönüşür. AI içeriği kaynak doğrulaması sayılmaz; sorunlu soruyu işaretleyebilirsin.").font(.caption).foregroundStyle(.secondary)
            TextField("Soru veya açıklamada ara",text:$search).textInputAutocapitalization(.never).focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }.padding(14).arenaPanel(radius:14).accessibilityIdentifier("poolSearch")
            ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:12) { ForEach(ActivityKind.allCases,id:\.self) { kind in Label("\(pool.snapshot.activityCounts[kind,default:0]) \(kind.title)",systemImage:kind.icon).font(.caption.bold()).foregroundStyle(gold).padding(10).arenaPanel(radius:12) } } }
            QuestionTransferControls(search:search,topic:topic,difficulty:Difficulty(rawValue:level),format:format,study:topic == .exam ? study : nil)
            Picker("Soru biçimi",selection:$format) { ForEach(QuestionFormat.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu).accessibilityIdentifier("poolFormat")
            HStack {
                Picker("Kategori",selection:$topic) { Text("Tüm kategoriler").tag(Topic.mixed); ForEach(DailyPoolPlan.categories) { Text($0.rawValue).tag($0) } }
                Spacer()
                Picker("Seviye",selection:$level) { Text("Tüm seviyeler").tag(""); ForEach(Difficulty.allCases,id:\.self) { Text($0.rawValue).tag($0.rawValue) } }
            }.tint(aqua)
            if topic == .exam { StudyLessonPicker(selection:$study); Text("Ders filtresi yeni etiketlenen sorularda uygulanır.").font(.caption).foregroundStyle(.secondary) }
            if let error { Text(error).font(.subheadline).foregroundStyle(gold) }
            if questions.isEmpty { Text("Bu filtrelerde henüz soru yok.").foregroundStyle(.secondary).padding(.vertical) }
            LazyVStack(spacing:12) {
                ForEach(questions) { question in
                    DisclosureGroup {
                        VStack(alignment:.leading,spacing:10) {
                            if let visual = question.visual { QuestionVisualCard(visual:visual) }
                            if let activity = question.activity { ActivitySummaryCard(activity:activity) }
                            Text("Doğru cevap: \(question.correctAnswerText)").font(.subheadline.bold()).foregroundStyle(aqua)
                            Text(question.explanation).font(.subheadline).foregroundStyle(.secondary)
                            Text(question.modelID.map { "Üreten: \($0)" } ?? "Hazır alıştırma").font(.caption2).foregroundStyle(.secondary)
                            HStack {
                                Button { game.toggleSaved(question) } label: { Label(game.saved.contains { $0.id == question.id } ? "Kaydedildi" : "Kaydet",systemImage:"bookmark") }
                                Spacer(); SingleQuestionShareButton(question:question); QuestionReportMenu(question:question)
                            }.font(.caption)
                        }.padding(.top,10)
                    } label: {
                        VStack(alignment:.leading,spacing:8) {
                            Text("\(question.category.rawValue) · \(question.difficulty.rawValue)" + (question.visual.map { " · \($0.kind.title)" } ?? question.activity.map { " · \($0.kind.title)" } ?? "")).font(.caption.bold()).foregroundStyle(question.category.accent)
                            Text(question.text).font(.subheadline.bold()).foregroundStyle(.white)
                        }
                    }.padding(16).arenaPanel(tint:question.category.accent,radius:18)
                }
            }
            if questions.count == 100 { Text("İlk 100 eşleşme gösteriliyor; aramayla daraltabilirsin.").font(.caption).foregroundStyle(.secondary) }
            if !game.reports.isEmpty {
                DisclosureGroup("İşaretleyip gizlediğin sorular (\(game.reports.count))") {
                    ForEach(game.reports) { report in
                        VStack(alignment:.leading,spacing:8) {
                            Text(report.question.text).font(.subheadline)
                            HStack { Text(report.reason.rawValue).font(.caption).foregroundStyle(.secondary); Spacer(); Button("Geri al") { game.restore(report) }.font(.caption.bold()) }
                        }.padding(.vertical,10)
                    }
                }.padding(16).arenaPanel(tint:gold)
            }
        }.task(id:queryKey) {
            try? await Task.sleep(for:.milliseconds(250))
            guard !Task.isCancelled, let database = pool.database else { return }
            do {
                let result = try await database.search(text:search,topic:topic,difficulty:Difficulty(rawValue:level),format:format,study:topic == .exam ? study : nil)
                guard !Task.isCancelled else { return }; questions = result; error = nil
            } catch { self.error = "Havuz okunamadı; yeniden dene." }
        }
    }
}

struct QuestionReportMenu: View {
    @EnvironmentObject var game: GameStore
    let question: Question
    var body: some View {
        Menu {
            Text("İşaretlenen soru sonraki oyunlardan gizlenir. Bildirim yalnız bu cihazda tutulur.")
            ForEach(ReportReason.allCases) { reason in Button(reason.rawValue) { game.report(question,reason:reason) } }
        } label: { Label(game.isReported(question) ? "İşaretlendi" : "Sorunu işaretle",systemImage:game.isReported(question) ? "flag.fill" : "flag") }
            .disabled(game.isReported(question)).accessibilityIdentifier("reportQuestion")
    }
}
