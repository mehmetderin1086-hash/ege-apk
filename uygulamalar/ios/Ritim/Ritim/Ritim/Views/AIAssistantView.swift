import SwiftUI

struct AIAssistantView: View {
    @EnvironmentObject private var assistant: AIAssistantStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var downloads: DownloadStore
    @State private var showConnection = false
    @State private var showModels = false
    @State private var prompt = ""
    @State private var lastPrompt = ""
    @State private var lastSearch = ""
    @State private var lastProposal: AIPlaylistProposal?
    @State private var retryAction = RetryAction.models
    @State private var downloadNotice: String?
    @FocusState private var composerFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum RetryAction { case models, message, search, playlist }
    private var starters: [String] {
        var items: [String] = []
        if let current = playback.current {
            items.append("“\(current.title.prefix(40))” parçasına benzer 5 parçayı sıraya ekle")
        }
        switch AIDayPart(date: Date()) {
        case .morning: items.append("Güne başlamak için kitaplığımdan bir şeyler çal")
        case .noon, .afternoon: items.append("Çalışırken odaklanmamı sağlayacak bir liste hazırla")
        case .evening: items.append("Akşam için sakin bir liste hazırla")
        case .night: items.append("Uyumadan önce dinleyeceğim yumuşak parçaları çal")
        }
        if let artist = playback.current?.artist, !artist.isEmpty {
            items.append("YouTube’da \(artist.prefix(40)) benzeri şarkılar bul")
        }
        items += ["Favorilerime benzer yeni sanatçılar öner", "Dinleme alışkanlıklarımı yorumla"]
        return items
    }
    private var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        assistant.selectedModel != nil && !assistant.isLoading && !assistant.isLoadingModels
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 12)
            modelSelector.padding(.horizontal, 20).padding(.bottom, 12)
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if assistant.messages.isEmpty { welcome }
                        else if assistant.dj != nil || assistant.djLoading || assistant.djMessage != nil { DJStatusCard() }
                        ForEach(assistant.messages) { message in
                            messageCard(message).id(message.id)
                                .transition(reduceMotion ? .opacity : .asymmetric(
                                    insertion: .move(edge: message.role == "user" ? .trailing : .leading).combined(with: .opacity),
                                    removal: .opacity))
                        }
                        if assistant.isLoading { loadingCard }
                        if let message = assistant.actionMessage {
                            notice(message, icon: "checkmark.circle.fill", color: RitimTheme.mint)
                                .accessibilityIdentifier("ai.action.notice")
                        }
                        if assistant.isSearching || assistant.searchQuery != nil {
                            searchSection.id("ai.search.results")
                        }
                        if let error = assistant.errorMessage { errorCard(error) }
                        Color.clear.frame(height: 1).id("ai.bottom")
                    }.padding(.horizontal, 20).padding(.bottom, 12)
                    .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85), value: assistant.messages.count)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: assistant.isLoading)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: assistant.messages.count) { _, _ in
                    guard let last = assistant.messages.last else { return }
                    withAnimation(.easeOut(duration: 0.2)) { reader.scrollTo(last.id, anchor: .top) }
                }
                .onChange(of: assistant.isLoading) { _, loading in
                    if loading { withAnimation { reader.scrollTo("ai.bottom", anchor: .bottom) } }
                }
                .onChange(of: assistant.isSearching) { _, searching in
                    if searching { withAnimation { reader.scrollTo("ai.search.results", anchor: .top) } }
                }
            }
            composer
        }
        .sheet(isPresented: $showConnection) { AssistantConnectionView().environmentObject(assistant) }
        .sheet(isPresented: $showModels) { AssistantModelPicker().environmentObject(assistant) }
        .task { if assistant.models.isEmpty { await assistant.loadModels() } }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Ritim Asistan").font(.title2.bold())
                Text("iPhone’dan doğrudan · İnternet bağlantısıyla").font(.caption).foregroundStyle(RitimTheme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { showConnection = true } label: {
                Image(systemName: "gearshape").font(.title3)
                    .frame(width: 44, height: 44).background(RitimTheme.surface, in: Circle())
            }.buttonStyle(.plain).foregroundStyle(RitimTheme.mint)
                .accessibilityLabel("Asistan bağlantısı").accessibilityIdentifier("ai.connection")
            Button {
                assistant.clearConversation()
                prompt = ""; lastPrompt = ""; lastSearch = ""; lastProposal = nil; downloadNotice = nil
                composerFocused = false
            } label: {
                Image(systemName: "square.and.pencil").font(.title3)
                    .frame(width: 44, height: 44).background(RitimTheme.surface, in: Circle())
            }.buttonStyle(.plain).foregroundStyle(RitimTheme.mint)
                .accessibilityLabel("Yeni sohbet").accessibilityIdentifier("ai.clear")
                .disabled(assistant.messages.isEmpty && assistant.searchQuery == nil && !assistant.isLoading)
        }
    }

    private var modelSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(RitimTheme.lavender)
                if assistant.isLoadingModels {
                    ProgressView().tint(RitimTheme.mint)
                    Text("Modeller yükleniyor…").font(.subheadline).foregroundStyle(RitimTheme.muted)
                    Spacer(minLength: 0)
                } else if assistant.models.isEmpty {
                    Text("Yapay zekâ bağlantısı").font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Yenile") { retryAction = .models; Task { await assistant.loadModels() } }
                        .font(.subheadline.bold()).accessibilityIdentifier("ai.models.reload")
                } else {
                    Button {
                        composerFocused = false
                        showModels = true
                    } label: {
                        HStack(spacing: 8) {
                            Text(assistant.selectedModel?.name ?? "Model seç")
                                .font(.subheadline.weight(.semibold)).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2.bold())
                        }.foregroundStyle(.white).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("ai.models")
                    .accessibilityLabel("Yapay zekâ modeli")
                    .accessibilityValue(assistant.selectedModel?.name ?? assistant.selectedModelID)
                    .disabled(assistant.isLoading)
                }
            }.frame(minHeight: 28)
            if !assistant.models.isEmpty {
                Text("\(assistant.models.count) sohbet modeli · Model seçmek için dokun")
                    .font(.caption2).foregroundStyle(RitimTheme.muted)
                    .accessibilityIdentifier("ai.models.count").accessibilityValue("\(assistant.models.count)")
            }
            if let model = assistant.selectedModel {
                HStack(spacing: 5) {
                    Circle().fill(statusColor(model.availability)).frame(width: 6, height: 6)
                    Text("\(model.provider) • CLIProxy")
                    if let availability = availabilityText(model.availability) { Text("• \(availability)") }
                }.font(.caption2).foregroundStyle(RitimTheme.muted)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("ai.status")
                if let note = model.note, !note.isEmpty {
                    Text(note).font(.caption2).foregroundStyle(RitimTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                Text("\(AIDayPart(date: Date()).greeting), bugün ne dinleyelim?").font(.title3.bold())
                Text("Ruh hâlini söyle; kitaplığından bir liste hazırlayıp çalayım, sıraya ekleyeyim veya yeni parçalar keşfedelim.")
                    .font(.subheadline).foregroundStyle(RitimTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(RitimTheme.mint)
                    Text("AI DJ").font(.subheadline.bold())
                    Text("Ruh hâlini seç, set kendini sürdürsün").font(.caption).foregroundStyle(RitimTheme.muted)
                }
                DJMoodStrip()
                DJStatusCard()
            }.padding(14).background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                .aiGlow(radius: 18, active: assistant.djLoading)
            VStack(spacing: 8) {
                ForEach(Array(starters.enumerated()), id: \.element) { index, suggestion in
                    Button { prompt = suggestion; composerFocused = true } label: {
                        HStack(spacing: 10) {
                            Text(suggestion).font(.subheadline).multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.up.left").font(.caption.bold())
                        }.foregroundStyle(.white).padding(14)
                            .background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(RitimPressStyle()).staggeredAppear(index)
                        .accessibilityIdentifier("ai.starter.\(index)")
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Label("Kitaplığında \(library.tracks.count) parça", systemImage: "music.note.list")
                    .font(.caption.weight(.semibold)).foregroundStyle(RitimTheme.lavender)
                Text("Parça adları, sanatçılar, süreler ve favori/dinleme bilgileri seçtiğin modele gönderilir. Ses dosyaları gönderilmez.")
                    .font(.caption).foregroundStyle(RitimTheme.muted)
                if library.tracks.isEmpty {
                    Text("Kitaplığına parça eklediğinde sana özel listeler de hazırlayabilirim.")
                        .font(.caption).foregroundStyle(RitimTheme.muted)
                } else if library.tracks.count > 500 {
                    Text("Bu sohbette kitaplığındaki ilk 500 parça değerlendiriliyor.")
                        .font(.caption).foregroundStyle(RitimTheme.muted)
                }
            }.fixedSize(horizontal: false, vertical: true)
        }.padding(.top, 8)
    }

    private func messageCard(_ message: AIMessage) -> some View {
        let isUser = message.role == "user"
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: isUser ? "person.fill" : "sparkles")
                Text(isUser ? "Sen" : "Ritim Asistan").fontWeight(.semibold)
                Spacer(minLength: 0)
            }.font(.caption).foregroundStyle(isUser ? RitimTheme.muted : RitimTheme.lavender)
            Text(message.content).font(.subheadline).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                .accessibilityIdentifier(isUser ? "ai.message.user" : "ai.message.reply")
            if !isUser, let note = message.appliedNote {
                Label(note, systemImage: message.action == .play ? "play.circle.fill" : "text.line.first.and.arrowtriangle.forward")
                    .font(.caption.weight(.semibold)).foregroundStyle(RitimTheme.mint)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RitimTheme.mint.opacity(0.1), in: Capsule())
                    .accessibilityIdentifier("ai.message.applied")
            }
            if !isUser, let proposal = message.playlist { playlistCard(proposal) }
            if !isUser, !message.searchQueries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("YouTube’da keşfet").font(.caption.weight(.semibold)).foregroundStyle(RitimTheme.muted)
                    ForEach(Array(message.searchQueries.enumerated()), id: \.offset) { _, query in
                        Button { search(query) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                Text(query).multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "arrow.right").font(.caption)
                            }.font(.caption.weight(.semibold)).foregroundStyle(RitimTheme.mint)
                                .padding(11).background(RitimTheme.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                        }.buttonStyle(.plain).disabled(assistant.isSearching).accessibilityIdentifier("ai.search")
                    }
                }
            }
            if !isUser, let model = message.model {
                Text(model).font(.system(size: 10)).foregroundStyle(RitimTheme.muted)
                    .lineLimit(2).accessibilityLabel("Yanıtlayan model: \(model)")
                    .accessibilityIdentifier("ai.message.model").accessibilityValue(model)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(isUser ? RitimTheme.elevated.opacity(0.7) : RitimTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                if !isUser {
                    RoundedRectangle(cornerRadius: 18).strokeBorder(LinearGradient(colors: [RitimTheme.lavender.opacity(0.35), .clear, RitimTheme.mint.opacity(0.2)],
                                                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                        .accessibilityHidden(true)
                }
            }
            .padding(isUser ? .leading : .trailing, 24)
    }

    private func playlistCard(_ proposal: AIPlaylistProposal) -> some View {
        let tracks = proposal.trackIDs.compactMap { id in library.tracks.first { $0.id == id } }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "music.note.list").foregroundStyle(RitimTheme.mint).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(proposal.name).font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
                    Text("Kitaplığından \(tracks.count) parça").font(.caption).foregroundStyle(RitimTheme.muted)
                }
            }
            ForEach(Array(tracks.prefix(5).enumerated()), id: \.element.id) { index, track in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text("\(index + 1)").monospacedDigit().foregroundStyle(RitimTheme.muted).frame(width: 14)
                    Text(track.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                }.font(.caption)
            }
            if tracks.count > 5 { Text("ve \(tracks.count - 5) parça daha").font(.caption).foregroundStyle(RitimTheme.muted) }
            Button {
                assistant.excludeRecommendation(proposal.trackIDs)
            } label: {
                Label(proposal.trackIDs.allSatisfy { assistant.excludedTrackIDs.contains($0) } ? "Öneri tercihin kaydedildi" : "Bu parçaları tekrar önerme", systemImage: "hand.thumbsdown")
            }.font(.caption).disabled(proposal.trackIDs.allSatisfy { assistant.excludedTrackIDs.contains($0) })
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { playlistActions(proposal, tracks: tracks) }
                VStack(spacing: 8) { playlistActions(proposal, tracks: tracks) }
            }
        }.padding(13).background(RitimTheme.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 13))
    }

    @ViewBuilder
    private func playlistActions(_ proposal: AIPlaylistProposal, tracks: [MediaTrack]) -> some View {
        Button {
            guard let first = tracks.first else { return }
            playback.play(first, in: tracks)
        } label: {
            Label("Çal", systemImage: "play.fill").font(.caption.bold())
                .frame(maxWidth: .infinity, minHeight: 42)
                .foregroundStyle(RitimTheme.background).background(RitimTheme.mint, in: Capsule())
        }.buttonStyle(.plain).disabled(tracks.isEmpty).accessibilityIdentifier("ai.playlist.play")
        Button {
            lastProposal = proposal; retryAction = .playlist
            assistant.createPlaylist(proposal, library: library)
        } label: {
            Label("Listeyi kaydet", systemImage: "plus").font(.caption.bold())
                .frame(maxWidth: .infinity, minHeight: 42)
                .foregroundStyle(.white).background(RitimTheme.elevated, in: Capsule())
        }.buttonStyle(.plain).disabled(tracks.isEmpty).accessibilityIdentifier("ai.playlist.create")
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            TypingDots()
            VStack(alignment: .leading, spacing: 4) {
                Text("Ritmini buluyorum…").font(.subheadline.weight(.semibold))
                Text(assistant.selectedModel?.name ?? assistant.selectedModelID).font(.caption).foregroundStyle(RitimTheme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button("Durdur") { assistant.cancel() }.font(.caption.bold()).foregroundStyle(RitimTheme.mint)
                .accessibilityIdentifier("ai.cancel")
        }.padding(15).background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .aiGlow(radius: 16).shimmer()
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("YouTube sonuçları").font(.headline)
                    if let query = assistant.searchQuery {
                        Text(query).font(.caption).foregroundStyle(RitimTheme.muted).lineLimit(2)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { assistant.clearSearch(); downloadNotice = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(RitimTheme.muted)
                        .frame(width: 36, height: 36)
                }.buttonStyle(.plain).accessibilityLabel("Arama sonuçlarını kapat")
            }
            YouTubeDiscoverResults(idPrefix: "ai")
            if let downloadNotice { notice(downloadNotice, icon: "arrow.down.circle", color: RitimTheme.mint) }
        }.padding(16).background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ai.search.results")
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            notice(message, icon: "exclamationmark.circle", color: .orange)
            Button("Tekrar dene") { retry() }.font(.subheadline.bold()).foregroundStyle(RitimTheme.mint)
                .disabled(assistant.isLoading || assistant.isSearching || assistant.isLoadingModels)
                .accessibilityIdentifier("ai.retry")
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ai.error")
    }

    private func notice(_ message: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon).foregroundStyle(color)
            Text(message).font(.caption).foregroundStyle(RitimTheme.muted)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Bir liste iste veya müzik sor…", text: $prompt, axis: .vertical)
                .font(.subheadline).lineLimit(1...4).focused($composerFocused)
                .padding(.vertical, 13).padding(.horizontal, 15)
                .background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 19))
                .accessibilityIdentifier("ai.prompt")
                .onChange(of: prompt) { _, value in if value.count > 4_000 { prompt = String(value.prefix(4_000)) } }
            Button { submit() } label: {
                Image(systemName: "arrow.up").font(.headline.bold())
                    .foregroundStyle(canSend ? RitimTheme.background : RitimTheme.muted)
                    .frame(width: 44, height: 44).background(canSend ? RitimTheme.mint : RitimTheme.surface, in: Circle())
            }.buttonStyle(.plain).disabled(!canSend).accessibilityLabel("Gönder").accessibilityIdentifier("ai.send")
        }.padding(.horizontal, 20).padding(.vertical, 10).background(RitimTheme.background)
    }

    private func submit() {
        guard canSend else { return }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        lastPrompt = text; retryAction = .message; prompt = ""; composerFocused = false
        Task { await assistant.send(text, library: library, playback: playback) }
    }

    private func search(_ query: String) {
        composerFocused = false; lastSearch = query; retryAction = .search; downloadNotice = nil
        Task { await assistant.search(query) }
    }

    private func retry() {
        switch retryAction {
        case .models: Task { await assistant.loadModels() }
        case .message:
            guard !lastPrompt.isEmpty else { return }
            Task { await assistant.send(lastPrompt, library: library, playback: playback) }
        case .search: search(lastSearch)
        case .playlist:
            guard let lastProposal else { return }
            assistant.createPlaylist(lastProposal, library: library)
        }
    }

    private func availabilityText(_ availability: String?) -> String? {
        switch availability {
        case "ready", "available", "ok", "verified": return "Hazır"
        case "quota_exceeded", "rate_limited", "quota": return "Kota sınırı"
        case "unavailable", "error": return "Şu an kullanılamıyor"
        case "unknown": return "Durum kontrol edilmedi"
        default: return nil
        }
    }

    private func statusColor(_ availability: String?) -> Color {
        switch availability {
        case "quota_exceeded", "rate_limited", "quota", "unavailable", "error": return .orange
        case "ready", "available", "ok", "verified": return RitimTheme.mint
        default: return RitimTheme.muted
        }
    }

    private func durationText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < 864_000 else { return "—" }
        let whole = Int(seconds)
        return whole >= 3_600 ? String(format: "%d:%02d:%02d", whole / 3_600, whole / 60 % 60, whole % 60) : String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

private struct AssistantModelPicker: View {
    @EnvironmentObject private var assistant: AIAssistantStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [AIModel] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return assistant.models.filter {
            term.isEmpty || [$0.name, $0.id, $0.provider, $0.providerGroup].contains { $0.localizedStandardContains(term) }
        }
    }
    private var providers: [String] {
        let preferred = ["ChatGPT", "Claude", "Gemini", "Antigravity", "Qwen"]
        return Set(filtered.map(\.providerGroup)).sorted {
            let left = preferred.firstIndex(of: $0) ?? preferred.count
            let right = preferred.firstIndex(of: $1) ?? preferred.count
            return left == right ? $0.localizedStandardCompare($1) == .orderedAscending : left < right
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(assistant.models.count) sohbet modeli")
                        .font(.headline).accessibilityIdentifier("ai.models.catalogCount")
                    Text("Bir model seç; yanıtlar bu modelden gelir. Kullanım sınırı veya bağlantı sorunu olursa başka modele otomatik geçilmez.")
                        .font(.caption).foregroundStyle(RitimTheme.muted)
                    if assistant.selectedModel == nil, !assistant.selectedModelID.isEmpty {
                        Text("Önceki seçimin listede yok: \(assistant.selectedModelID)")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if let error = assistant.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                }.listRowBackground(RitimTheme.surface)
                if filtered.isEmpty {
                    Text(assistant.isLoadingModels ? "Modeller yükleniyor…" : "Aramana uygun model bulunamadı.")
                        .foregroundStyle(RitimTheme.muted).listRowBackground(RitimTheme.surface)
                }
                ForEach(providers, id: \.self) { provider in
                    Section(provider) {
                        ForEach(filtered.filter { $0.providerGroup == provider }) { model in
                            Button {
                                assistant.selectedModelID = model.id
                                assistant.errorMessage = nil
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(model.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                        Text(model.id).font(.caption).foregroundStyle(RitimTheme.muted)
                                            .fixedSize(horizontal: false, vertical: true)
                                        if model.availability == "verified" {
                                            Text("Bu oturumda yanıt verdi").font(.caption2).foregroundStyle(RitimTheme.mint)
                                        } else if model.availability == "error" {
                                            Text("Son istekte hata oluştu").font(.caption2).foregroundStyle(.orange)
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    if assistant.selectedModelID == model.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(RitimTheme.mint)
                                    }
                                }.padding(.vertical, 5).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(assistant.isLoading || assistant.isLoadingModels)
                                .accessibilityIdentifier("ai.model.\(model.id)")
                                .accessibilityLabel("\(model.name), \(model.provider)")
                                .accessibilityValue(model.availability == "verified" ? "Bu oturumda yanıt verdi" : (model.availability == "error" ? "Son istekte hata oluştu" : "Durum kontrol edilmedi"))
                                .accessibilityAddTraits(assistant.selectedModelID == model.id ? .isSelected : [])
                                .listRowBackground(RitimTheme.surface)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(RitimTheme.background)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Model veya sağlayıcı ara")
            .navigationTitle("Yapay zekâ modelleri").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await assistant.loadModels() } } label: {
                        if assistant.isLoadingModels { ProgressView() }
                        else { Image(systemName: "arrow.clockwise") }
                    }.accessibilityLabel("Modelleri yenile").accessibilityIdentifier("ai.models.reload")
                        .disabled(assistant.isLoadingModels || assistant.isLoading)
                }
            }
        }.preferredColorScheme(.dark).tint(RitimTheme.mint)
    }
}
