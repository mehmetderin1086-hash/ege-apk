import SwiftUI

/// Tam ekran sesli asistan: konuş → anlasın → cevabı sesli okusun (Azure / Chirp / cihaz sesi). Sürekli sohbet açıkken cevaptan sonra yeniden dinler.
struct VoiceAssistantView: View {
    let session: AssistantSession
    let onOpen: (Route) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("voice.continuous") private var continuous = true
    @AppStorage("voice.engine") private var engineRaw = VoiceEngine.auto.rawValue
    @AppStorage("voice.chirp") private var chirpVoice = "Kore"
    @State private var listener = VoiceListener()
    private let player = VoicePlayer.shared
    @State private var phase: Phase = .idle
    @State private var question = ""
    @State private var reply: AssistantReply?
    @State private var errorText: String?
    @State private var loop: Task<Void, Never>?
    enum Phase { case idle, listening, thinking, speaking }

    private var planned: String {
        let order = VoiceRouter.order(VoiceEngine(rawValue: engineRaw) ?? .auto, azureConfigured: VoiceConfig.azureConfigured, serverConfigured: VoiceConfig.serverConfigured)
        switch order.first {
        case .azure: return "Azure · \(VoiceConfig.azureVoice.replacingOccurrences(of: "tr-TR-", with: "").replacingOccurrences(of: "Neural", with: ""))"
        case .chirp: return "Chirp · \(chirpVoice)"
        default: return "Cihaz sesi"
        }
    }
    private var status: String {
        switch phase { case .idle: "Dokun ve konuş"; case .listening: listener.transcript.isEmpty ? "Dinliyorum…" : "Dinliyorum"; case .thinking: "Düşünüyorum…"; case .speaking: "Konuşuyorum" }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.05, blue: 0.16), Color(red: 0.12, green: 0.05, blue: 0.28)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 18) {
                topBar
                Spacer(minLength: 0)
                orb.onTapGesture { orbTapped() }.accessibilityLabel(status).accessibilityAddTraits(.isButton)
                Text(status).font(.title3.weight(.semibold)).foregroundStyle(.white.opacity(0.9)).contentTransition(.opacity).animation(.easeInOut, value: phase)
                transcriptArea
                Spacer(minLength: 0)
                if let errorText { Label(errorText, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center).padding(.horizontal) }
                chips
                bottomBar
            }.padding()
        }
        .preferredColorScheme(.dark)
        .onAppear { begin() }
        .onDisappear { shutDown() }
        .sensoryFeedback(.impact(weight: .light), trigger: phase)
    }

    // MARK: Parçalar
    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).padding(12).background(.white.opacity(0.12), in: .circle) }.accessibilityLabel("Kapat")
            Spacer()
            Menu {
                Picker("Motor", selection: $engineRaw) { ForEach(VoiceEngine.allCases) { Text($0.title).tag($0.rawValue) } }
                Picker("Chirp sesi", selection: $chirpVoice) { ForEach(VoiceConfig.chirpVoices, id: \.self) { Text($0).tag($0) } }
            } label: { Label(planned, systemImage: "waveform").font(.footnote.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8).background(.white.opacity(0.12), in: .capsule) }
        }.foregroundStyle(.white)
    }

    /// Duruma tepki veren küre: dinlerken ses seviyesiyle büyür, düşünürken döner, konuşurken halkalar yayılır.
    private var orb: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let level = CGFloat(listener.level)
            ZStack {
                switch phase {
                case .speaking:
                    ForEach(0..<3) { i in
                        let p = (t * 0.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        Circle().stroke(Color.green.opacity(0.5 * (1 - p)), lineWidth: 3).frame(width: 150 + p * 140, height: 150 + p * 140)
                    }
                case .listening:
                    Circle().fill(Color.cyan.opacity(0.18)).frame(width: 190 + level * 110, height: 190 + level * 110).blur(radius: 14)
                case .thinking:
                    Circle().trim(from: 0.1, to: 0.8).stroke(AngularGradient(colors: [.purple, .pink, .clear], center: .center), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 190, height: 190).rotationEffect(.radians(t * 3))
                case .idle: EmptyView()
                }
                Circle()
                    .fill(RadialGradient(colors: phase == .speaking ? [.green, Color(red: 0, green: 0.5, blue: 0.4)] : phase == .thinking ? [.purple, .indigo] : [.cyan, Color(red: 0.1, green: 0.3, blue: 0.9)], center: .topLeading, startRadius: 5, endRadius: 140))
                    .frame(width: 150, height: 150)
                    .scaleEffect(1 + (phase == .listening ? level * 0.25 : 0) + CGFloat(sin(t * 2.4)) * 0.025)
                    .shadow(color: (phase == .speaking ? Color.green : Color.cyan).opacity(0.55), radius: 26)
                Image(systemName: phase == .speaking ? "speaker.wave.3.fill" : phase == .thinking ? "sparkles" : "mic.fill").font(.system(size: 44)).foregroundStyle(.white)
                    .symbolEffect(.pulse, isActive: phase != .idle)
            }
            .frame(height: 320)
        }
    }

    private var transcriptArea: some View {
        VStack(spacing: 10) {
            let heard = phase == .listening ? listener.transcript : question
            if !heard.isEmpty { Text("“\(heard)”").font(.title3).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center).transition(.opacity) }
            if let reply, phase != .listening {
                ScrollView { Text(reply.text).font(.body).foregroundStyle(.white).multilineTextAlignment(.center).padding(14).frame(maxWidth: .infinity) }
                    .frame(maxHeight: 190).background(.white.opacity(0.08), in: .rect(cornerRadius: 18)).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }.animation(.spring(duration: 0.4), value: reply?.text)
    }

    @ViewBuilder private var chips: some View {
        let items: [AnyHashable] = (reply?.actions.map { AnyHashable($0) } ?? []) + (reply?.followUps.prefix(3).map { AnyHashable($0) } ?? [])
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(reply?.actions ?? [], id: \.self) { action in
                        switch action {
                        case .open(let route, let title, let icon):
                            Button { shutDown(); onOpen(route) } label: { Label(title, systemImage: icon).font(.footnote.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8).background(Color.cyan.opacity(0.25), in: .capsule) }
                        default: EmptyView()
                        }
                    }
                    ForEach(Array((reply?.followUps ?? []).prefix(3))) { item in
                        Button { ask(item.text) } label: { Text(item.text).font(.footnote).padding(.horizontal, 12).padding(.vertical, 8).background(.white.opacity(0.12), in: .capsule) }
                    }
                }
            }.foregroundStyle(.white)
        }
    }

    private var bottomBar: some View {
        HStack {
            Toggle(isOn: $continuous) { Label("Sürekli sohbet", systemImage: "infinity") }.toggleStyle(.button).tint(.cyan).font(.footnote.weight(.semibold))
            Spacer()
            if phase == .speaking { Button { player.stop() } label: { Label("Sustur", systemImage: "speaker.slash.fill").font(.footnote.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8).background(.white.opacity(0.12), in: .capsule) } }
        }.foregroundStyle(.white)
    }

    // MARK: Akış
    private func begin() {
        listener.onFinal = { text in ask(text) }
        Task { if await listener.requestPermissions() { startListening() } else { errorText = "Mikrofon ve konuşma tanıma izni gerekli (Ayarlar › Otobüs Asistanı)." } }
    }
    private func shutDown() { loop?.cancel(); listener.stop(); player.stop(); phase = .idle }

    private func startListening() {
        player.stop(); errorText = nil
        do { try listener.start(); phase = .listening; question = "" }
        catch { errorText = error.localizedDescription; phase = .idle }
    }
    private func orbTapped() {
        switch phase {
        case .speaking: player.stop(); startListening()
        case .listening: let text = listener.transcript; listener.stop(); if text.isEmpty { phase = .idle } else { ask(text) }
        case .idle: startListening()
        case .thinking: break
        }
    }
    private func ask(_ text: String) {
        loop?.cancel(); listener.stop(); player.stop()
        question = text; phase = .thinking; errorText = nil
        loop = Task {
            let answer = await session.reply(to: text)
            if Task.isCancelled { return }
            reply = answer; phase = .speaking
            await player.speak(answer.text, recording: true)
            if let error = player.lastError, player.lastEngine.hasPrefix("Cihaz") { errorText = "Bulut sesi kullanılamadı: \(error)" }
            if Task.isCancelled { return }
            phase = .idle
            if continuous { startListening() }
        }
    }
}
