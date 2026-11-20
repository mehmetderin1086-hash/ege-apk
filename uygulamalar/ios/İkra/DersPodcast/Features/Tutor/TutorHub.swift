import PDFKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Ders bağımsız öğretmen, kaynakla çalışma ve mevcut öğrenme araçlarının ortak girişi.
struct TutorHub: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = JSONStore<TutorSession>("tutor-sessions")
    @State private var subject = "Matematik"
    @State private var level = "TYT"
    @State private var mode: TutorMode = .socratic
    @State private var selected: TutorSession?
    @State private var tool: Tool?
    static let subjects = ["Matematik", "Geometri", "Fizik", "Kimya", "Biyoloji", "Türkçe", "Türk Dili ve Edebiyatı",
                           "Tarih", "Coğrafya", "Felsefe", "Din Kültürü", "İngilizce", "Almanca", "Bilişim"]
    private enum Tool: String, Identifiable {
        case cards, newCards, exam, written, lab, dailyPlan, plan, stats, brain, sources, mistakes, badges, games
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Öğren, dene, eksiklerini tamamla")
                        .font(.title2.bold())
                    Text("Bir ders ve çalışma biçimi seç. Sorunu yaz, sesle anlat, fotoğraf veya PDF ekle.")
                        .foregroundStyle(.secondary)
                    Picker("Ders", selection: $subject) {
                        ForEach(Self.subjects, id: \.self) { Text($0) }
                    }
                    Picker("Düzey", selection: $level) {
                        ForEach(["İlkokul", "Ortaokul", "LGS", "9. sınıf", "10. sınıf", "11. sınıf", "12. sınıf", "TYT", "AYT", "Üniversite"], id: \.self) { Text($0) }
                    }
                    Picker("Çalışma biçimi", selection: $mode) {
                        ForEach(TutorMode.allCases.filter { $0 != .writtenExam && $0 != .cardDeck }) { Text($0.title).tag($0) }
                    }
                    Button("Öğretmenle çalışmaya başla", systemImage: "sparkles") {
                        let session = TutorSession(title: "\(subject) · \(mode.title)", subject: subject, level: level,
                                                   mode: mode, messages: [], createdAt: .now)
                        selected = session
                    }
                    .font(.headline)
                    .accessibilityIdentifier("tutor.start")
                }
                Section("Çalışmanı sürdür") {
                    shortcut("Konudan bilgi kartları oluştur", "rectangle.stack.badge.plus", .newCards)
                    shortcut("Tekrar kartları", "rectangle.on.rectangle", .cards)
                    shortcut("Süreli deneme sınavı", "stopwatch", .exam)
                    shortcut("Süreli yazılı sınav ve değerlendirme", "pencil.and.list.clipboard", .written)
                    shortcut("Etkileşimli laboratuvar", "slider.horizontal.3", .lab)
                    shortcut("Gün gün kişisel çalışma planı", "checklist", .dailyPlan)
                    shortcut("Takvim ve hatırlatmalar", "calendar", .plan)
                    shortcut("İlerleme ve çalışma serisi", "chart.bar", .stats)
                    shortcut("Zihin antrenmanı", "brain", .brain)
                    shortcut("Zihin oyunları", "puzzlepiece", .games)
                    shortcut("Başarı rozetleri", "medal", .badges)
                    shortcut("MEB kitapları ve öğretim programları", "books.vertical", .sources)
                    shortcut("Yanlış defteri", "arrow.uturn.backward", .mistakes)
                }
                if !store.items.isEmpty {
                    Section("Öğretmenle çalışmaların") {
                        LabeledContent("Kayıtlı çalışma", value: "\(store.items.count)")
                        LabeledContent("Öğretmen yanıtı", value: "\(store.items.flatMap(\.messages).filter { $0.role == "assistant" }.count)")
                    }
                    Section("Geçmiş çalışmalar") {
                        ForEach(store.items.sorted { $0.createdAt > $1.createdAt }) { session in
                            Button { selected = session } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.title).foregroundStyle(.primary)
                                    Text("\(session.level) · \(session.messages.count / 2) yanıt · \(session.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { indexes in
                            let sorted = store.items.sorted { $0.createdAt > $1.createdAt }
                            let ids = indexes.map { sorted[$0].id }
                            store.items.removeAll { ids.contains($0.id) }
                            for id in ids { try? FileManager.default.removeItem(at: TutorAttachment.url(id)) }
                        }
                    }
                }
            }
            .navigationTitle("Öğrenme Merkezi")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
            .sheet(item: $selected) { session in
                TutorConversationView(session: session) { updated in
                    if let index = store.items.firstIndex(where: { $0.id == updated.id }) {
                        store.items[index] = updated
                    } else { store.items.append(updated) }
                }
            }
            .sheet(item: $tool) { item in
                switch item {
                case .cards: ReviewView()
                case .newCards: TutorCardsView()
                case .exam: ExamSimulatorView()
                case .written: TutorWrittenExamView()
                case .lab: TutorLabView()
                case .dailyPlan: TutorPlanView()
                case .plan: StudyPlanView()
                case .stats: ProgressChartsView()
                case .brain: DailyWorkoutView()
                case .sources: NavigationStack { MEBLibraryView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { tool = nil } } } }
                case .mistakes: MistakeBookView()
                case .badges: BadgesView()
                case .games:
                    NavigationStack {
                        List {
                            NavigationLink("Zihinden matematik") { MentalMathView() }
                            NavigationLink("Eşleştirme oyunu") { MatchGameView() }
                            NavigationLink("Schulte dikkat tablosu") { SchulteView() }
                            NavigationLink("Sayı hafızası") { DigitSpanView() }
                        }.navigationTitle("Zihin oyunları")
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { tool = nil } } }
                    }
                }
            }
        }
    }

    private func shortcut(_ title: String, _ symbol: String, _ destination: Tool) -> some View {
        Button { tool = destination } label: { Label(title, systemImage: symbol) }
    }
}

private enum TutorAttachment {
    static func url(_ id: UUID) -> URL {
        URL.applicationSupportDirectory.appending(path: "TutorAttachments/\(id.uuidString).jpg")
    }
    static func save(_ data: Data, id: UUID) throws {
        let path = url(id)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: path, options: .atomic)
    }
}

struct TutorConversationView: View {
    @Environment(\.dismiss) private var dismiss
    @State var session: TutorSession
    let save: (TutorSession) -> Void
    @State private var draft = ""
    @State private var image: Data?
    @State private var photo: PhotosPickerItem?
    @State private var camera = false
    @State private var importFile = false
    @State private var busy = false
    @State private var importing = false
    @State private var error: String?
    @State private var request: Task<Void, Never>?
    @State private var photoRequest: Task<Void, Never>?
    @State private var recorder = SpeechRecorder()
    @State private var readAloud = false
    @State private var examDate = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
    @State private var minutes = 30
    @State private var targetGrade = 80
    @State private var sourceName: String?
    @State private var sourceProgress: String?
    @State private var sourceRequest: Task<Void, Never>?
    @State private var documentLink = QSTutorDocumentLinks.State()
    @State private var sourceLibrary = false
    @State private var sourceLocation: QSDocumentPageLocation?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if session.messages.isEmpty { introduction }
                            ForEach(session.messages) { message in
                                messageRow(message)
                            }
                            if busy { ProgressView("Öğretmenin hazırlanıyor…").padding() }
                            Color.clear.frame(height: 1).id("bottom")
                        }.padding()
                    }
                    .onChange(of: session.messages.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                }
                if let error {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(error).font(.callout).foregroundStyle(.red)
                        if session.messages.last?.role == "user" {
                            Button("Yanıtı yeniden iste", systemImage: "arrow.clockwise") { respond() }.disabled(busy)
                        }
                    }.padding(.horizontal).padding(.vertical, 8)
                }
                composer
            }
            .navigationTitle(session.mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Toggle("Yanıtları sesli oku", isOn: $readAloud)
                        ShareLink(item: session.messages.map { "\($0.role == "user" ? "Ben" : "İkra"): \($0.text)" }.joined(separator: "\n\n")) {
                            Label("Çalışmayı paylaş", systemImage: "square.and.arrow.up")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .onAppear {
                image = try? Data(contentsOf: TutorAttachment.url(session.id))
                documentLink = QSTutorDocumentLinks.load(session.id)
                if let id = documentLink.sourceID { Task { sourceName = try? await QSDocumentService.shared.load(id).source.name } }
                if session.messages.last?.role == "user", !busy {
                    error = "Son sorunun yanıtı tamamlanmamış. Yanıtı yeniden isteyebilirsin."
                }
            }
            .onDisappear {
                request?.cancel()
                photoRequest?.cancel()
                sourceRequest?.cancel()
                SpeechOut.shared.stop()
                if recorder.isRecording { Task { _ = await recorder.stop() } }
            }
            .onChange(of: photo) { _, value in
                guard let value else { return }
                importing = true
                photoRequest?.cancel()
                photoRequest = Task {
                    defer { importing = false }
                    do {
                        guard let data = try await value.loadTransferable(type: Data.self), let uiImage = UIImage(data: data) else {
                            throw CocoaError(.fileReadCorruptFile)
                        }
                        try Task.checkCancellation()
                        try attach(uiImage)
                    } catch is CancellationError {
                    } catch { self.error = "Fotoğraf açılamadı: \(error.localizedDescription)" }
                }
            }
            .sheet(isPresented: $camera) {
                QSCamera(onImage: { value in
                    camera = false
                    do { try attach(value) } catch { self.error = error.localizedDescription }
                }, onCancel: { camera = false }).ignoresSafeArea()
            }
            .fileImporter(isPresented: $importFile, allowedContentTypes: [.pdf, .plainText]) { result in
                do {
                    let url = try result.get()
                    sourceRequest?.cancel()
                    importing = true
                    sourceRequest = Task {
                        defer { importing = false; sourceProgress = nil; sourceRequest = nil }
                        do { try await importSource(url) }
                        catch is CancellationError { self.error = "Belge okuma duraklatıldı. PDF kaynaklarından kaldığın yerden sürdürebilirsin." }
                        catch { self.error = "Belge açılamadı: " + error.localizedDescription }
                    }
                } catch { self.error = error.localizedDescription }
            }
            .sheet(isPresented: $sourceLibrary) {
                NavigationStack {
                    QSDocumentSourceLibraryView { source, page in
                        var updated = documentLink; updated.sourceID = source.id; updated.page = page
                        do {
                            try QSTutorDocumentLinks.save(updated, session: session.id)
                            documentLink = updated; sourceName = source.name; sourceLibrary = false
                        } catch { self.error = error.localizedDescription }
                    }.toolbar { Button("Kapat") { sourceLibrary = false } }
                }
            }
            .sheet(item: $sourceLocation) { location in
                NavigationStack {
                    QSDocumentSourceDetailView(sourceID: location.sourceID, initialPage: location.page)
                        .toolbar { Button("Kapat") { sourceLocation = nil } }
                }
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("\(session.subject) · \(session.level)", systemImage: "graduationcap")
                .font(.headline)
            Text(session.mode == .socratic ? "Sorunu birlikte keşfedelim. Önce ne düşündüğünü anlat; her adımda bir ipucuyla ilerleyeceğiz." : "Konu veya sorunu yaz. Eklediğin kaynak üzerinden de çalışabiliriz.")
            if session.mode == .plan {
                DatePicker("Sınav tarihi", selection: $examDate, in: Date.now..., displayedComponents: .date)
                Stepper("Günlük \(minutes) dakika", value: $minutes, in: 10...240, step: 10)
                Stepper("Hedef not: \(targetGrade)/100", value: $targetGrade, in: 10...100, step: 5)
                Text("Konuları ve zorlandığın alanları yaz; istersen sınav kâğıdının fotoğrafını ekle. Planını Takvim ve hatırlatmalar bölümünden takip edebilirsin.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Yapay zekâ yanıtları hata içerebilir. Resmî kazanımlar için Öğrenme Merkezi’ndeki MEB kaynaklarını kullan.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding().background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private func messageRow(_ message: TutorMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message.role == "user" ? "Sen" : "İkra").font(.caption.bold()).foregroundStyle(.secondary)
            Text(.init(message.text)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let evidence = documentLink.turns[message.id.uuidString] {
                Text("Bu yanıtta kullanılan kaynak: " + evidence.sourceName).font(.caption).foregroundStyle(.secondary)
                ForEach(Array(Set(evidence.excerpts.map(\.page))).sorted(), id: \.self) { page in
                    Button("PDF s. \(page)", systemImage: "doc.text.magnifyingglass") { sourceLocation = .init(sourceID: evidence.sourceID, page: page) }.font(.caption)
                }
            }
            if message.role == "assistant" {
                Button("Sesli oku", systemImage: "speaker.wave.2") {
                    Task { await SpeechOut.shared.speak(message.text, language: "tr-TR") }
                }.font(.caption)
            }
        }
        .padding(14)
        .background(message.role == "user" ? Color.blue.opacity(0.10) : Color.secondary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if let image, let preview = UIImage(data: image) {
                HStack {
                    Image(uiImage: preview).resizable().scaledToFit().frame(width: 52, height: 52)
                    Text("Kaynak fotoğrafı").font(.caption)
                    Spacer()
                    Button("Kaldır", systemImage: "xmark") {
                        self.image = nil
                        photo = nil
                        try? FileManager.default.removeItem(at: TutorAttachment.url(session.id))
                    }.disabled(busy)
                }
            }
            if let sourceName {
                HStack {
                    Button { sourceLibrary = true } label: {
                        Label(sourceName + (documentLink.page.map { " · PDF s. \($0)" } ?? " · kaynakta ara"), systemImage: "doc.text.magnifyingglass").lineLimit(2)
                    }
                    Spacer()
                    Button("Kaldır") {
                        var updated = documentLink; updated.sourceID = nil; updated.page = nil
                        do { try QSTutorDocumentLinks.save(updated, session: session.id); documentLink = updated; self.sourceName = nil }
                        catch { self.error = error.localizedDescription }
                    }.disabled(busy || importing)
                }.font(.caption)
            }
            TextField("Sorunu veya cevabını yaz…", text: $draft, axis: .vertical)
                .lineLimit(2...6).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("tutor.input")
            HStack {
                PhotosPicker(selection: $photo, matching: .images) { Image(systemName: "photo") }
                    .accessibilityLabel("Fotoğraf seç").disabled(busy || importing)
                if QSCamera.available {
                    Button { camera = true } label: { Image(systemName: "camera") }
                        .accessibilityLabel("Fotoğraf çek").disabled(busy || importing)
                }
                Menu {
                    Button("PDF veya metin ekle", systemImage: "doc.badge.plus") { importFile = true }
                    Button("Kayıtlı PDF kaynaklarını aç", systemImage: "books.vertical") { sourceLibrary = true }
                } label: { Image(systemName: "doc.badge.plus") }
                    .accessibilityLabel("Belge ekle veya kayıtlı PDF seç").disabled(busy || importing)
                Button {
                    SpeechOut.shared.stop()
                    Task {
                        if recorder.isRecording {
                            let text = await recorder.stop()
                            if !text.isEmpty { draft += (draft.isEmpty ? "" : "\n") + text }
                        } else { await recorder.start() }
                    }
                } label: { Image(systemName: recorder.isRecording ? "stop.circle.fill" : "mic") }
                    .accessibilityLabel(recorder.isRecording ? "Sesli cevabı bitir" : "Sesli cevap ver")
                    .disabled(busy || recorder.isStopping)
                Spacer()
                if busy {
                    Button("Durdur") { request?.cancel() }
                } else {
                    Button("Gönder", systemImage: "arrow.up.circle.fill") { send() }
                        .buttonStyle(.borderedProminent)
                        .disabled(importing || recorder.isRecording || (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && image == nil))
                        .accessibilityIdentifier("tutor.send")
                }
            }.font(.title3)
            if importing {
                ProgressView(sourceProgress ?? "Kaynak alınıyor…")
                if sourceRequest != nil { Button("Belge okumayı duraklat") { sourceRequest?.cancel() }.font(.caption) }
            }
            if recorder.isRecording { Text(recorder.transcript.isEmpty ? "Dinleniyor…" : recorder.transcript).font(.caption) }
            if let error = recorder.error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding().background(.bar)
    }

    private func attach(_ value: UIImage) throws {
        guard let data = QSImage.uploadData(value) else { throw CocoaError(.fileReadCorruptFile) }
        try TutorAttachment.save(data, id: session.id)
        image = data
        error = nil
        save(session)
    }

    private func importSource(_ url: URL) async throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= QSDocumentService.byteLimit else { throw TutorImportError.tooLarge }
        if url.pathExtension.lowercased() == "pdf" {
            let data = try Data(contentsOf: url)
            let indexed = try await QSDocumentService.shared.indexPDF(data, name: url.lastPathComponent) { done, total in
                sourceProgress = "PDF sayfaları hazırlanıyor: \(done)/\(total)"
            }
            var updated = documentLink; updated.sourceID = indexed.source.id; updated.page = nil
            try QSTutorDocumentLinks.save(updated, session: session.id)
            documentLink = updated; sourceName = indexed.source.name
            error = indexed.source.failed.isEmpty ? nil : "\(indexed.source.failed.count) sayfa okunamadı. PDF kaynaklarından inceleyip yeniden okutabilirsin."
            save(session)
        } else {
            let text = try String(contentsOf: url, encoding: .utf8)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TutorImportError.unreadable }
            guard draft.count + text.count < 24_000 else { throw TutorEngine.Failure(message: "Metin tek mesaj için çok uzun. Bir bölüm seç veya PDF olarak ekleyip kaynak aramasını kullan; metin kesilmedi.") }
            var updated = documentLink; updated.sourceID = nil; updated.page = nil
            try QSTutorDocumentLinks.save(updated, session: session.id)
            documentLink = updated; sourceName = nil
            draft += "\n\nKaynak (\(url.lastPathComponent)):\n" + text
        }
    }

    private func send() {
        var text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= 25_000 else {
            error = "Mesajın çok uzun. Konu ve kaynak metnini toplam 25.000 karakterin altında tut."
            return
        }
        if text.isEmpty { text = "Bu görsel üzerinden \(session.mode.title.lowercased()) çalışması yapalım." }
        if session.mode == .plan, session.messages.isEmpty {
            text += "\nBugün: \(Date.now.formatted(date: .numeric, time: .omitted)); sınav: \(examDate.formatted(date: .numeric, time: .omitted)); günlük \(minutes) dakika; hedef not \(targetGrade)/100. Gün gün uygulanabilir bir plan hazırla."
        }
        session.messages.append(TutorMessage(role: "user", text: text))
        draft = ""
        save(session)
        respond()
    }

    private func respond() {
        guard !busy else { return }
        busy = true
        error = nil
        request = Task {
            defer { busy = false }
            do {
                var messages = session.messages
                if let last = messages.last, last.role == "user" {
                    var evidence = documentLink.turns[last.id.uuidString]
                    if evidence == nil, let sourceID = documentLink.sourceID {
                        let snapshot = try await QSDocumentService.shared.load(sourceID)
                        let available = min(14_000, max(0, 24_000 - last.text.count - 1500))
                        let pageSelection = QSDocumentRetrieval.pageSelection(snapshot, query: last.text, selectedPage: documentLink.page)
                        if let issue = pageSelection.issue { throw TutorEngine.Failure(message: issue) }
                        let excerpts = QSDocumentRetrieval.excerpts(snapshot, query: last.text, selectedPage: documentLink.page, budget: available)
                        guard !excerpts.isEmpty else {
                            throw TutorEngine.Failure(message: "Bu istek için kaynak alıntısı bulunamadı. Belgeye dokunup bir PDF sayfası seç veya aradığın kavramı yaz. Kaynak okunmuş gibi yanıt verilmedi.")
                        }
                        evidence = .init(sourceID: sourceID, sourceName: snapshot.source.name, totalPages: snapshot.source.pageCount, excerpts: excerpts)
                        var updated = documentLink; updated.turns[last.id.uuidString] = evidence
                        try QSTutorDocumentLinks.save(updated, session: session.id)
                        documentLink = updated
                    }
                    if let evidence { messages[messages.count - 1].text += "\n\n" + evidence.context }
                }
                let answer = try await TutorEngine.reply(mode: session.mode, subject: session.subject, level: session.level,
                                                        messages: messages, image: image)
                try Task.checkCancellation()
                let reply = TutorMessage(role: "assistant", text: answer)
                session.messages.append(reply)
                save(session)
                LearningContinuity.record(source: .tutor, sourceID: reply.id.uuidString, subject: session.subject, topic: String((messages.last?.text ?? session.title).prefix(300)), correct: nil, assisted: true, detail: session.mode.title + " · Öğretmen yanıtı alındı; öğrenci doğruluğu ölçülmedi.", resourceID: session.id.uuidString)
                if readAloud || session.mode == .oralExam { await SpeechOut.shared.speak(answer, language: "tr-TR") }
            } catch is CancellationError {
                error = "Yanıt durduruldu. Aynı soruyu yeniden gönderebilirsin."
            } catch { self.error = error.localizedDescription }
        }
    }
}

private enum TutorImportError: LocalizedError {
    case tooLarge, unreadable
    var errorDescription: String? {
        switch self {
        case .tooLarge: "Belge boş veya 240 MB sınırından büyük."
        case .unreadable: "Belgede okunabilir metin bulunamadı."
        }
    }
}
