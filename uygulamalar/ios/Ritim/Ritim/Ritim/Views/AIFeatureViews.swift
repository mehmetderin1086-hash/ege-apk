import SwiftUI

/// AI note about the playing track, with similar library picks and discovery searches.
struct TrackInsightView: View {
    @EnvironmentObject private var assistant: AIAssistantStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackStore
    @Environment(\.dismiss) private var dismiss
    @State private var queuedNotice: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let track = playback.current {
                        HStack(spacing: 14) {
                            CoverArt(track: track, radius: 12).frame(width: 64, height: 64)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title).font(.headline).lineLimit(2)
                                Text(track.artist).font(.caption).foregroundStyle(RitimTheme.muted).lineLimit(1)
                            }
                        }
                        content(for: track)
                    } else {
                        EmptyLibrary(title: "Önce bir parça çal", message: "Yapay zekâ notu şimdi çalan parça için hazırlanır.", icon: "sparkles")
                    }
                }.padding(20)
            }
            .background(RitimTheme.background)
            .navigationTitle("Yapay zekâ notu").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() }.accessibilityIdentifier("insight.close") }
                if let track = playback.current, assistant.insights[track.id] != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button { Task { await assistant.loadInsight(for: track, library: library, playback: playback, force: true) } } label: {
                            Image(systemName: "arrow.clockwise")
                        }.accessibilityLabel("Notu yenile").disabled(assistant.insightLoading != nil)
                    }
                }
            }
            .task(id: playback.current?.id) {
                guard let track = playback.current else { return }
                await assistant.loadInsight(for: track, library: library, playback: playback)
            }
        }.preferredColorScheme(.dark).tint(RitimTheme.mint)
    }

    @ViewBuilder
    private func content(for track: MediaTrack) -> some View {
        if assistant.insightLoading == track.id {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) { TypingDots(); Text("Parçayı dinleme bilgilerinle yorumluyorum…").font(.subheadline).foregroundStyle(RitimTheme.muted) }
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 6).fill(RitimTheme.surface).frame(height: 14)
                        .frame(maxWidth: index == 2 ? 180 : .infinity, alignment: .leading)
                }
            }.shimmer().accessibilityIdentifier("insight.loading")
        } else if let insight = assistant.insights[track.id] {
            let similar = insight.similarIDs.compactMap { id in library.tracks.first { $0.id == id } }
            VStack(alignment: .leading, spacing: 18) {
                Text(insight.text).font(.body).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                    .aiGlow(radius: 18, active: false)
                    .accessibilityIdentifier("insight.text")
                    .staggeredAppear(0)
                if !similar.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Kitaplığından benzerleri").font(.headline)
                            Spacer()
                            Button {
                                assistant.queueNext(similar, playback: playback)
                                queuedNotice = "\(similar.count) parça sıradaki olarak eklendi."
                            } label: { Label("Sıraya ekle", systemImage: "text.line.first.and.arrowtriangle.forward").font(.caption.bold()) }
                                .accessibilityIdentifier("insight.queueSimilar")
                        }
                        ForEach(Array(similar.enumerated()), id: \.element.id) { index, item in
                            TrackRow(track: item, context: similar).staggeredAppear(index + 1)
                        }
                        if let queuedNotice {
                            Label(queuedNotice, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(RitimTheme.mint)
                                .accessibilityIdentifier("insight.queued")
                        }
                    }
                }
                if !insight.searchQueries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Yeni keşif fikirleri").font(.caption.weight(.semibold)).foregroundStyle(RitimTheme.muted)
                        ForEach(insight.searchQueries, id: \.self) { query in
                            Label(query, systemImage: "magnifyingglass").font(.caption.weight(.semibold)).foregroundStyle(RitimTheme.lavender)
                        }
                        Text("Bunları Asistan sekmesinden YouTube’da arayabilirsin.").font(.caption2).foregroundStyle(RitimTheme.muted)
                    }
                }
                Text(insight.model).font(.system(size: 10)).foregroundStyle(RitimTheme.muted)
            }
        } else if let error = assistant.insightError {
            VStack(alignment: .leading, spacing: 10) {
                Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Tekrar dene") { Task { await assistant.loadInsight(for: track, library: library, playback: playback, force: true) } }
                    .font(.subheadline.bold()).accessibilityIdentifier("insight.retry")
            }.accessibilityIdentifier("insight.error")
        }
    }
}

/// One-tap mood buttons that start an AI DJ set.
struct DJMoodStrip: View {
    @EnvironmentObject private var assistant: AIAssistantStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackStore
    var compact = false
    private var part: AIDayPart { AIDayPart(date: Date()) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(part.presets) { preset in
                    Button { Task { await assistant.startDJ(mood: preset.prompt, library: library, playback: playback) } } label: {
                        HStack(spacing: 7) {
                            Image(systemName: preset.icon)
                            Text(preset.title)
                        }
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, compact ? 9 : 11)
                        .background(RitimTheme.lavender.opacity(0.14), in: Capsule())
                        .overlay(Capsule().strokeBorder(RitimTheme.lavender.opacity(0.25)))
                    }.buttonStyle(RitimPressStyle())
                        .disabled(assistant.djLoading || !assistant.isReady || library.tracks.isEmpty)
                        .accessibilityIdentifier("dj.preset.\(preset.id)")
                        .accessibilityLabel("AI DJ: \(preset.title)")
                }
            }
        }
    }
}

/// Live DJ status shown in the assistant and on the home screen.
struct DJStatusCard: View {
    @EnvironmentObject private var assistant: AIAssistantStore
    @EnvironmentObject private var playback: PlaybackStore

    var body: some View {
        if assistant.djLoading {
            HStack(spacing: 12) {
                TypingDots(color: RitimTheme.mint)
                Text("AI DJ setini kuruyor…").font(.subheadline.weight(.semibold))
                Spacer()
            }.padding(16).background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                .aiGlow(radius: 18).shimmer()
                .accessibilityElement(children: .combine).accessibilityIdentifier("dj.loading")
        } else if let dj = assistant.dj {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    LiveWaveSymbol(isPlaying: playback.isPlaying)
                    Text("AI DJ YAYINDA").font(.system(size: 10, weight: .bold)).tracking(1.6).foregroundStyle(RitimTheme.mint)
                    Spacer()
                    Button("Durdur") { assistant.stopDJ() }.font(.caption.bold()).foregroundStyle(RitimTheme.mint)
                        .accessibilityIdentifier("dj.stop")
                }
                Text(dj.note).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dj.note")
                Text("\(dj.played.count) çalındı · \(dj.trackIDs.count) parçalık set" + (dj.isExtending ? " · yeni parçalar seçiliyor" : ""))
                    .font(.caption2).foregroundStyle(RitimTheme.muted)
                    .accessibilityIdentifier("dj.count").accessibilityValue("\(dj.trackIDs.count)")
            }.padding(16).background(RitimTheme.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                .aiGlow(radius: 18, active: dj.isExtending || playback.isPlaying)
                .accessibilityElement(children: .contain).accessibilityIdentifier("dj.card")
                .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
        if let message = assistant.djMessage {
            Label(message, systemImage: "info.circle").font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("dj.message")
        }
    }
}

/// The proactive home card: today's AI mix plus mood-based DJ shortcuts.
struct AIDailyCard: View {
    @EnvironmentObject private var assistant: AIAssistantStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackStore
    let openAssistant: () -> Void
    @State private var savedNotice: String?
    private var part: AIDayPart { AIDayPart(date: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.headline).foregroundStyle(RitimTheme.lavender)
                    .frame(width: 34, height: 34).background(RitimTheme.lavender.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(part.greeting), yapay zekân hazır").font(.subheadline.bold())
                    Text(assistant.selectedModel?.name ?? "Asistan").font(.caption2).foregroundStyle(RitimTheme.muted).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button(action: openAssistant) {
                    Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold)).frame(width: 36, height: 36)
                }.buttonStyle(RitimPressStyle()).foregroundStyle(RitimTheme.lavender)
                    .accessibilityLabel("Asistanı aç").accessibilityIdentifier("home.assistant")
            }
            dailyBody
            DJStatusCard()
            if assistant.dj == nil && !assistant.djLoading && assistant.isReady {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tek dokunuşla AI DJ").font(.caption.weight(.semibold)).foregroundStyle(RitimTheme.muted)
                    DJMoodStrip(compact: true)
                }
            }
        }
        .padding(16)
        .background {
            ZStack {
                RitimTheme.surface
                AnimatedBackdrop(colors: [RitimTheme.lavender.opacity(0.5), RitimTheme.mint.opacity(0.35)],
                                 active: assistant.dailyLoading || assistant.djLoading, intensity: 0.5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .aiGlow(radius: 22, active: assistant.dailyLoading || assistant.djLoading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.ai")
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: assistant.dailyMix)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: assistant.dj)
    }

    @ViewBuilder
    private var dailyBody: some View {
        if !assistant.hasAccessToken {
            Text("Asistan bağlantısını kurduğunda her gün sana özel bir karışım ve tek dokunuşla AI DJ burada olacak.")
                .font(.caption).foregroundStyle(RitimTheme.muted).fixedSize(horizontal: false, vertical: true)
        } else if !assistant.proactiveEnabled {
            Text("Günlük öneriler kapalı. Ayarlardan açabilirsin.").font(.caption).foregroundStyle(RitimTheme.muted)
        } else if assistant.dailyLoading {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12).fill(RitimTheme.elevated).frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 5).fill(RitimTheme.elevated).frame(width: 140, height: 13)
                    RoundedRectangle(cornerRadius: 5).fill(RitimTheme.elevated).frame(height: 10)
                    HStack(spacing: 6) { TypingDots(); Text("Günün karışımı hazırlanıyor").font(.caption2).foregroundStyle(RitimTheme.muted) }
                }
            }.shimmer().accessibilityElement(children: .combine).accessibilityIdentifier("daily.loading")
        } else if let mix = assistant.dailyMix, mix.isFresh() {
            let tracks = mix.trackIDs.compactMap { id in library.tracks.first { $0.id == id } }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    CoverStack(tracks: tracks, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GÜNÜN KARIŞIMI · \(mix.dayPart.uppercased(with: Locale(identifier: "tr_TR")))")
                            .font(.system(size: 9, weight: .bold)).tracking(1.4).foregroundStyle(RitimTheme.mint)
                        Text(mix.title).font(.headline).lineLimit(2).accessibilityIdentifier("daily.title")
                        Text("\(tracks.count) parça").font(.caption2).foregroundStyle(RitimTheme.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(mix.note).font(.caption).foregroundStyle(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button {
                        guard let first = tracks.first else { return }
                        assistant.stopDJ(); playback.play(first, in: tracks)
                    } label: {
                        Label("Çal", systemImage: "play.fill").font(.caption.bold()).frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(RitimTheme.background).background(RitimTheme.mint, in: Capsule())
                    }.buttonStyle(RitimPressStyle()).disabled(tracks.isEmpty).accessibilityIdentifier("daily.play")
                    Button {
                        do {
                            let playlist = try library.createPlaylist(name: mix.title, trackIDs: tracks.map(\.id))
                            savedNotice = "\(playlist.name) kaydedildi."
                        } catch { savedNotice = error.localizedDescription }
                    } label: {
                        Image(systemName: "text.badge.plus").font(.subheadline.bold()).frame(width: 44, height: 40)
                            .background(RitimTheme.elevated, in: Capsule())
                    }.buttonStyle(RitimPressStyle()).foregroundStyle(.white).disabled(tracks.isEmpty)
                        .accessibilityLabel("Karışımı liste olarak kaydet").accessibilityIdentifier("daily.save")
                    Button { Task { await assistant.refreshDaily(library: library, playback: playback) } } label: {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.subheadline.bold()).frame(width: 44, height: 40)
                            .background(RitimTheme.elevated, in: Capsule())
                    }.buttonStyle(RitimPressStyle()).foregroundStyle(.white)
                        .accessibilityLabel("Yeni karışım öner").accessibilityIdentifier("daily.refresh")
                }
                if let savedNotice {
                    Label(savedNotice, systemImage: "checkmark.circle.fill").font(.caption2).foregroundStyle(RitimTheme.mint)
                        .accessibilityIdentifier("daily.saved")
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("daily.card")
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else if let error = assistant.dailyError {
            VStack(alignment: .leading, spacing: 8) {
                Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Tekrar dene") { Task { await assistant.refreshDaily(library: library, playback: playback) } }
                    .font(.caption.bold()).accessibilityIdentifier("daily.retry")
            }
        } else if assistant.isReady {
            Button { Task { await assistant.refreshDaily(library: library, playback: playback) } } label: {
                Label("Günün karışımını hazırla", systemImage: "wand.and.stars").font(.caption.bold())
                    .frame(maxWidth: .infinity, minHeight: 40).background(RitimTheme.elevated, in: Capsule())
            }.buttonStyle(RitimPressStyle()).foregroundStyle(.white).disabled(library.tracks.isEmpty)
                .accessibilityIdentifier("daily.create")
        }
    }
}
