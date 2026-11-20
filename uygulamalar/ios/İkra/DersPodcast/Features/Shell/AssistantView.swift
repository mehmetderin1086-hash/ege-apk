import Observation
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Ana Sayfa asistanı (17 Eki 2026): yazarak ya da konuşarak her şey sorulur, uygulamada iş yaptırılır.
/// Soru telefonda yazıya dökülür (cihaz içi konuşma tanıma), cevabı ve eylemi `/v1/assistant` üretir, cevap cihaz sesiyle okunur.
/// Eylemler kapalı listedir (modül açma, iş başlatma, ayar sayfası, yazı boyutu); silme ya da gönderme gibi geri alınamaz iş yoktur.
@Observable
final class AssistantSession {
    struct Message: Identifiable, Equatable {
        enum Role { case user, assistant, error }
        let id = UUID()
        let role: Role
        let text: String
    }

    private(set) var messages: [Message] = []
    private(set) var thinking = false
    private(set) var listening = false
    private(set) var level: Float = 0
    var draft = ""
    /// Gönderilecek ekler (fotoğraf, PDF, belge); modele yalnız ad ve tür gider, dosyayı eylemin modülü işler.
    var attachments: [AssistantAttachment] = []

    /// Konuşmanın sonunda kendiliğinden gönderme için beklenen sessizlik (sn).
    nonisolated static let silenceSeconds = 1.6
    /// Modele giden geçmiş: son 8 soru-cevap.
    nonisolated static let historyLimit = 8

    @ObservationIgnored private var recorder = SpeechRecorder(foregroundOnly: true)
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var askTask: Task<Void, Never>?

    /// Önceki soru-cevaplar (hata mesajları hariç), en yenisi sonda.
    var history: [LiveQA] {
        var pairs: [LiveQA] = []
        var question: String?
        for message in messages {
            switch message.role {
            case .user: question = message.text
            case .assistant: if let q = question { pairs.append(LiveQA(q: q, a: message.text)); question = nil }
            case .error: question = nil
            }
        }
        return Array(pairs.suffix(Self.historyLimit))
    }

    func clear() {
        cancelListening()
        askTask?.cancel()
        SpeechOut.shared.stop()
        messages = []
        draft = ""
        attachments = []
        thinking = false
    }

    /// Seçiciden gelen dosyaları ek olarak alır (telefona kopyalar).
    func attach(files urls: [URL]) {
        for url in urls { if let made = try? AssistantAttachment.store(url) { attachments.append(made) } }
    }
    func attach(imageData data: Data, name: String) {
        if let made = try? AssistantAttachment.store(imageData: data, name: name) { attachments.append(made) }
    }
    func remove(_ attachment: AssistantAttachment) { attachments.removeAll { $0.id == attachment.id } }

    /// Yazılan ya da yazıya dökülen soruyu gönderir. `speak`: cevap sesli okunsun mu.
    func send(_ text: String, context: String, speak: Bool, perform: @escaping @MainActor (AssistantResponse.Action, [AssistantAttachment]) -> Bool) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !thinking else { return }
        SpeechOut.shared.stop()
        let history = history
        let attached = attachments
        messages.append(Message(role: .user, text: attached.isEmpty ? question : question + " (" + attached.map(\.name).joined(separator: ", ") + ")"))
        draft = ""
        thinking = true
        askTask = Task { [weak self] in
            do {
                let reply = try await APIClient.shared.assistant(AssistantRequest(message: question, history: history, context: context, attachments: attached.map(\.request)))
                guard let self, !Task.isCancelled else { return }
                self.thinking = false
                let say = reply.say.trimmingCharacters(in: .whitespacesAndNewlines)
                if !say.isEmpty { self.messages.append(Message(role: .assistant, text: say)) }
                // Eylem ekleri aldıysa liste boşalır; almadıysa ekler bir sonraki soru için durur.
                if perform(reply.action, attached) { self.attachments.removeAll { item in attached.contains { $0.id == item.id } } }
                if speak, !say.isEmpty { await SpeechOut.shared.speak(say) }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.thinking = false
                self.messages.append(Message(role: .error, text: (error as? APIError)?.message ?? error.localizedDescription))
            }
        }
    }

    /// Mikrofonu açar; konuşma bitince (sessizlik) yazıya dökülen soruyu `submit` ile verir. Açıksa kapatır ve o ana kadarkini gönderir.
    func toggleListening(submit: @escaping @MainActor (String) -> Void) {
        if listening {
            listenTask?.cancel()
            Task { [weak self] in
                guard let self else { return }
                let text = await self.recorder.stop()
                self.listening = false
                self.level = 0
                let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !spoken.isEmpty { submit(spoken) }
            }
            return
        }
        SpeechOut.shared.stop()
        listenTask = Task { [weak self] in
            guard let self else { return }
            if let message = await SpeechRecorder.requestPermissions() {
                self.messages.append(Message(role: .error, text: message))
                return
            }
            self.recorder = SpeechRecorder(foregroundOnly: true)
            await self.recorder.start()
            guard self.recorder.isRecording, !Task.isCancelled else {
                if let error = self.recorder.error { self.messages.append(Message(role: .error, text: error)) }
                return
            }
            self.listening = true
            var last = "", lastChange = Date.now
            while !Task.isCancelled, self.listening {
                try? await Task.sleep(for: .milliseconds(100))
                if self.recorder.level != self.level { self.level = self.recorder.level }
                let text = self.recorder.transcript
                if text != last { last = text; lastChange = .now; self.draft = text }
                // Bir şey söylendi ve bir süredir yeni sözcük gelmiyor: soru bitti.
                if !text.isEmpty, Date.now.timeIntervalSince(lastChange) >= Self.silenceSeconds {
                    let final = await self.recorder.stop()
                    self.listening = false
                    self.level = 0
                    let spoken = (final.isEmpty ? text : final).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !spoken.isEmpty { submit(spoken) }
                    return
                }
            }
        }
    }

    func cancelListening() {
        listenTask?.cancel()
        if listening { recorder.cancel() }
        listening = false
        level = 0
    }
}

/// Ana Sayfa'daki asistan kartı: konuşma, büyük mikrofon düğmesi ve yazı alanı.
struct AssistantCard: View {
    @Environment(AppState.self) private var app
    @Environment(\.isModuleActive) private var moduleActive
    @Bindable var session: AssistantSession
    /// Telefonun kısa durum özeti (asistanın bağlamı).
    let context: () -> String
    /// Ana Sayfa'da tek başına, tam ekran (kullanıcı kararı, 17 Eki 2026): konuşma kaydırılır, giriş çubuğu altta sabit.
    var fullScreen = false
    @AppStorage("assistant.speak") private var speakAnswers = true
    @FocusState private var typing: Bool
    @State private var pickingFiles = false
    @State private var pickingPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []

    private let suggestions = ["Mitoz ile mayoz farkı ne?", "Bugünün tekrarını başlat", "Soru çek", "Fotosentez videosu yap", "Son bölümü çal"]

    var body: some View {
        if fullScreen {
            // Giriş çubuğu alt güvenli alana eklenir: alt menü ve klavye onu örtmez, konuşma onun üstünde kayar.
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        conversation
                        Color.clear.frame(height: 1).id("son")
                    }
                    .padding(16)
                }
                .onChange(of: session.messages.count) { withAnimation { proxy.scrollTo("son", anchor: .bottom) } }
                .onChange(of: session.thinking) { withAnimation { proxy.scrollTo("son", anchor: .bottom) } }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Alt menü (BottomMenu) gezinme yığınının içine güvenli alan olarak ulaşmıyor: kapalı menünün yüksekliği kadar pay bırakılır.
                inputBar
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12 + BottomMenu.closedHeight)
                    .background(Theme.canvas)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(AssistantLifecycle(session: session, moduleActive: moduleActive, ask: ask))
        } else {
            VStack(alignment: .leading, spacing: 14) {
                header
                conversation
                inputBar
            }
            .padding(16)
            .okuSurface()
            .modifier(AssistantLifecycle(session: session, moduleActive: moduleActive, ask: ask))
        }
    }

    private var header: some View {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.title2.weight(.bold)).foregroundStyle(Theme.amber).accessibilityHidden(true)
                Text("Asistan").font(.title2.weight(.heavy)).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { speakAnswers.toggle(); if !speakAnswers { SpeechOut.shared.stop() } } label: {
                    Image(systemName: speakAnswers ? "speaker.wave.2.fill" : "speaker.slash.fill").font(.title3.weight(.bold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(speakAnswers ? "Sesli cevap açık" : "Sesli cevap kapalı")
                .accessibilityHint("Cevapların sesli okunmasını açar ya da kapatır")
                if !session.messages.isEmpty {
                    Button { session.clear() } label: {
                        Image(systemName: "trash").font(.title3.weight(.bold)).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Konuşmayı temizle")
                }
            }
    }

    @ViewBuilder private var conversation: some View {
            if session.messages.isEmpty {
                Text("Her şeyi sor ya da yaptır: ders sorusu, genel bilgi, \"Soru Çöz'ü aç\", \"yazıları büyüt\"… Artı ile fotoğraf ya da PDF ekleyip \"soruları çöz\", \"podcast yap\", \"görsellere ekle\", \"video yap\" de.")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.primary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                FlowSuggestions(items: suggestions) { ask($0, spoken: false) }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(session.messages.suffix(6)) { bubble($0) }
                    if session.thinking {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Düşünüyor…").font(.headline)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !session.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(session.attachments) { item in
                            HStack(spacing: 6) {
                                Image(systemName: item.kind == .image ? "photo" : item.kind == .pdf ? "doc.richtext" : "doc.text").font(.caption.weight(.bold))
                                Text(item.name).font(.caption.weight(.semibold)).lineLimit(1)
                                Button { session.remove(item) } label: { Image(systemName: "xmark.circle.fill").font(.caption) }
                                    .buttonStyle(.plain).accessibilityLabel("\(item.name) ekini kaldır")
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Theme.yellow.opacity(0.3), in: Capsule())
                        }
                    }
                }
                .accessibilityLabel("Ekler: " + session.attachments.map(\.name).joined(separator: ", "))
            }
            HStack(alignment: .bottom, spacing: 10) {
                // Ek: fotoğraf ya da dosya (PDF, belge). Eylem (çöz, podcast yap, görsellere ekle, video yap) söylenerek verilir.
                Menu {
                    Button { pickingPhotos = true } label: { Label("Fotoğraf ekle", systemImage: "photo.on.rectangle") }
                    Button { pickingFiles = true } label: { Label("Dosya ekle (PDF, belge)", systemImage: "doc") }
                } label: {
                    Image(systemName: "plus").font(.title2.weight(.heavy)).foregroundStyle(Theme.blueInk)
                        .frame(width: 56, height: 56)
                        .background(Theme.blue.opacity(0.12), in: Circle())
                        .overlay { Circle().strokeBorder(Theme.blue.opacity(0.35), lineWidth: 1) }
                }
                .accessibilityLabel("Fotoğraf ya da dosya ekle")
                TextField(session.listening ? "Dinliyorum…" : session.attachments.isEmpty ? "Yaz ya da mikrofona dokun" : "Eklerle ne yapayım? (çöz, podcast yap, video yap…)", text: $session.draft, axis: .vertical)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1...4)
                    .focused($typing)
                    .submitLabel(.send)
                    .onSubmit { ask(session.draft, spoken: false) }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(minHeight: 56)
                    .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.blue.opacity(0.6), lineWidth: 2) }
                if !session.draft.trimmingCharacters(in: .whitespaces).isEmpty, !session.listening {
                    Button { ask(session.draft, spoken: false) } label: {
                        Image(systemName: "arrow.up").font(.title2.weight(.heavy)).foregroundStyle(.white)
                            .frame(width: 56, height: 56).background(Theme.gradient, in: Circle())
                    }
                    .disabled(session.thinking)
                    .accessibilityLabel("Gönder")
                }
                Button {
                    typing = false
                    session.toggleListening { ask($0, spoken: true) }
                } label: {
                    Image(systemName: session.listening ? "stop.fill" : "mic.fill").font(.title2.weight(.heavy))
                        .foregroundStyle(Theme.navy)
                        .frame(width: 56, height: 56)
                        .background(Theme.warmGradient, in: Circle())
                        .overlay { Circle().strokeBorder(Theme.navy.opacity(session.listening ? 0.9 : 0), lineWidth: 3).scaleEffect(1 + CGFloat(session.level) * 0.25) }
                }
                .accessibilityLabel(session.listening ? "Dinlemeyi bitir ve gönder" : "Konuşarak sor")
            }
        }
        .fileImporter(isPresented: $pickingFiles, allowedContentTypes: [.pdf, .image, .plainText, UTType("org.openxmlformats.wordprocessingml.document")!], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { session.attach(files: urls) }
        }
        .photosPicker(isPresented: $pickingPhotos, selection: $photoItems, maxSelectionCount: 20, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for (index, item) in items.enumerated() {
                    guard let raw = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: raw), let jpg = image.jpegData(compressionQuality: 0.92) else { continue }
                    session.attach(imageData: jpg, name: "Fotoğraf \(session.attachments.count + index + 1).jpg")
                }
                photoItems = []
            }
        }
    }

    private func ask(_ text: String, spoken: Bool) {
        typing = false
        session.send(text, context: context(), speak: speakAnswers) { action, attachments in AssistantActions.perform(action, attachments: attachments, app: app) }
    }

    @ViewBuilder private func bubble(_ message: AssistantSession.Message) -> some View {
        switch message.role {
        case .user:
            Text(message.text).font(.headline.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("Sen: " + message.text)
        case .assistant:
            Text(message.text).font(.headline.weight(.medium)).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.yellow.opacity(0.28), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.amber.opacity(0.6), lineWidth: 1.5) }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Asistan: " + message.text)
        case .error:
            Label(message.text, systemImage: "exclamationmark.triangle.fill").font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Kartın yaşam döngüsü: modülden ayrılınca mikrofon kapanır; DEBUG'da `-assistantAsk=<soru>` açılışta soruyu gönderir.
private struct AssistantLifecycle: ViewModifier {
    let session: AssistantSession
    let moduleActive: Bool
    let ask: (String, Bool) -> Void
    func body(content: Content) -> some View {
        content
            .onChange(of: moduleActive) { _, active in if !active { session.cancelListening() } }
            .task {
                #if DEBUG
                if let question = DebugArg.value("assistantAsk"), session.messages.isEmpty {
                    try? await Task.sleep(for: .seconds(2))
                    ask(question, false)
                }
                #endif
            }
    }
}

/// Öneri düğmeleri: satıra sığdığı kadar yan yana, sığmayan alt satıra.
private struct FlowSuggestions: View {
    let items: [String]
    let tap: (String) -> Void
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { tap(item) } label: {
                    Text(item).font(.subheadline.weight(.bold)).foregroundStyle(Theme.blueInk)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.blue.opacity(0.12), in: Capsule())
                        .overlay { Capsule().strokeBorder(Theme.blue.opacity(0.35), lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
