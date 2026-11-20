import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let fromUser: Bool
    var actions: [AssistantAction] = []
}

struct AssistantView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var nav
    @AppStorage("speak") private var speak = false
    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var busy = false
    @State private var ai: AnyObject?
    @State private var session: AssistantSession?
    @State private var voiceMode = false
    @State private var cityTransit = false
    @State private var sharing: ShareMessage?
    @State private var followUps: [Suggestion] = []
    private let voice = VoicePlayer.shared
    @FocusState private var focused: Bool
    /// Favori durak, takip, sabit/son bakılan hat ve konuma göre kişiselleştirilmiş hazır sorular.
    private var suggestions: [Suggestion] {
        SuggestionBuilder.make(favorites: model.favorites, favoriteStops: model.favoriteStopList.map { ($0.code, $0.name) }, pinned: model.pinnedLines, recent: model.recentLines, hasLocation: model.location != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if messages.isEmpty { welcome }
                        ForEach(messages) { message in bubble(message).id(message.id) }
                        if busy { TypingDots().transition(.scale.combined(with: .opacity)).id("typing") }
                        else if !followUps.isEmpty, !messages.isEmpty { followRow }
                    }.padding(.horizontal).padding(.bottom, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } } }
                .onChange(of: busy) { if busy { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } } }
            }
            HStack(alignment: .bottom) {
                TextField("Hat, durak veya soru yaz…", text: $input, axis: .vertical).lineLimit(1...4).focused($focused)
                    .padding(.horizontal, 14).padding(.vertical, 10).background(.regularMaterial, in: .rect(cornerRadius: 20)).onSubmit { send(input) }
                if input.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button { voice.stop(); voiceMode = true } label: { Image(systemName: "mic.circle.fill").font(.system(size: 36)).symbolRenderingMode(.palette).foregroundStyle(.white, Theme.accent) }
                        .accessibilityLabel("Sesli asistan")
                } else {
                    Button { send(input) } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 36)).symbolRenderingMode(.palette).foregroundStyle(.white, Theme.accent) }
                        .disabled(busy)
                }
            }.padding()
        }
        .background { AuroraBackground() }
        .animation(.spring(duration: 0.45), value: messages.count)
        .animation(.spring(duration: 0.3), value: busy)
        .sensoryFeedback(.impact(weight: .light), trigger: messages.count)
        .shareSheet($sharing)
        .onAppear {
            if session == nil { session = AssistantSession(model: model) }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-voice") { Task { try? await Task.sleep(for: .milliseconds(900)); voiceMode = true } }
            #endif
        }
        .fullScreenCover(isPresented: $voiceMode) {
            VoiceAssistantView(session: session ?? AssistantSession(model: model)) { route in voiceMode = false; nav.push(route) }
        }
        .sheet(isPresented: $cityTransit) { CityTransitView() }
        .navigationTitle("Asistan")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Sohbeti temizle", systemImage: "trash") { voice.stop(); withAnimation { messages = []; session?.reset(); followUps = [] } }.disabled(messages.isEmpty)
            }
        }
    }

    private func order(_ group: String) -> Int { [SuggestionBuilder.groupStops: 0, SuggestionBuilder.groupLines: 1, SuggestionBuilder.groupGeneral: 2][group] ?? 3 }

    /// Son cevaptan sonra önerilen devam soruları.
    private var followRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(followUps) { item in
                    Button { send(item.text) } label: { Label(item.text, systemImage: item.icon).font(.footnote).padding(.horizontal, 12).padding(.vertical, 7).background(Theme.accent.opacity(0.14), in: .capsule) }.buttonStyle(.plain)
                }
            }
        }.transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var aiAvailable: Bool { if #available(iOS 26.0, *) { AIAssistant.isAvailable } else { false } }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(aiAvailable ? "Cihaz içi Apple Intelligence ile yanıtlıyorum" : "Apple Intelligence kapalı; kural tabanlı asistanla yanıtlıyorum", systemImage: aiAvailable ? "sparkles" : "text.bubble").font(.footnote).foregroundStyle(.secondary)
            Button { cityTransit = true } label: { Label("Metro, tramvay ve vapur rotası", systemImage: "tram.fill") }.buttonStyle(.bordered)
            let all = suggestions
            ForEach(Array(Dictionary(grouping: all, by: \.group).keys).sorted { order($0) < order($1) }, id: \.self) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group).font(.caption.weight(.bold)).foregroundStyle(.secondary).padding(.top, 6)
                    FlowRow(spacing: 8) {
                        ForEach(all.filter { $0.group == group }) { item in
                            Button { send(item.text) } label: { Label(item.text, systemImage: item.icon).font(.subheadline).padding(.horizontal, 12).padding(.vertical, 8).background(.regularMaterial, in: .capsule) }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }.padding(.top, 24)
    }

    @ViewBuilder private func bubble(_ message: ChatMessage) -> some View {
        VStack(alignment: message.fromUser ? .trailing : .leading, spacing: 8) {
            Text(message.text).padding(.horizontal, 14).padding(.vertical, 10).textSelection(.enabled)
                .background {
                    if message.fromUser { RoundedRectangle(cornerRadius: 20).fill(LinearGradient(colors: [Theme.accent, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)) }
                    else { RoundedRectangle(cornerRadius: 20).fill(.regularMaterial) }
                }
                .foregroundStyle(message.fromUser ? .white : .primary)
                .contextMenu {
                    Button("Kopyala", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.text }
                    Button("Paylaş…", systemImage: "square.and.arrow.up") { sharing = ShareBuilder.answer(message.text) }
                    if !message.fromUser { Button("Sesli oku", systemImage: "speaker.wave.2") { Task { await voice.speak(message.text) } } }
                }
            if !message.actions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(message.actions, id: \.self) { action in chip(action) } }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.fromUser ? .trailing : .leading)
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9, anchor: message.fromUser ? .bottomTrailing : .bottomLeading)), removal: .opacity))
    }

    @ViewBuilder private func chip(_ action: AssistantAction) -> some View {
        switch action {
        case .open(let route, let title, let icon):
            Button { focused = false; nav.push(route) } label: { Label(title, systemImage: icon).font(.footnote.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8).background(Theme.accent.opacity(0.15), in: .capsule) }
        case .starStop(let code):
            let starred = model.isFavoriteStop(code)
            Button { withAnimation(.spring) { model.toggleFavoriteStop(code) } } label: { Label(starred ? "Favoride" : "Favori durak yap", systemImage: starred ? "star.fill" : "star").font(.footnote.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8).background(Color.yellow.opacity(0.25), in: .capsule) }
                .sensoryFeedback(.success, trigger: starred)
        case .follow(let line, let stop, let title):
            let following = model.isFavorite(line: line, stop: stop)
            Button {
                if let durak = model.stop(code: stop) { withAnimation(.spring) { model.toggleFavorite(line: line, stop: durak) }; Task { await model.refreshFavorites() } }
            } label: { Label(following ? "Takipte" : title, systemImage: following ? "checkmark.circle.fill" : "plus.circle").font(.footnote.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8).background((following ? Color.green : Color.orange).opacity(0.18), in: .capsule) }
                .sensoryFeedback(.success, trigger: following)
        }
    }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !busy else { return }
        if session == nil { session = AssistantSession(model: model) }
        messages.append(.init(text: question, fromUser: true)); input = ""; busy = true; focused = false
        Task {
            guard let session else { busy = false; return }
            let reply = await session.reply(to: question)
            followUps = reply.followUps
            messages.append(.init(text: reply.text, fromUser: false, actions: reply.actions)); busy = false
            if speak { await voice.speak(reply.text) }
        }
    }
}
