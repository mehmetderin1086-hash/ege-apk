import SwiftUI
import AVKit

struct MiniPlayer: View {
    @EnvironmentObject private var playback: PlaybackStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let track: MediaTrack
    let expand: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: expand) {
                    HStack(spacing: 12) {
                        CoverArt(track: track, radius: 8).frame(width: 43, height: 43)
                            .overlay(alignment: .bottomTrailing) {
                                if playback.isPlaying {
                                    PlayingBars(isPlaying: playback.isPlaying)
                                        .scaleEffect(0.65)
                                        .frame(width: 18, height: 18)
                                        .background(RitimTheme.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 5))
                                        .padding(2)
                                }
                            }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title).font(.subheadline.bold()).lineLimit(1).foregroundStyle(.white)
                            Text(track.artist.isEmpty ? "Şimdi çalıyor" : track.artist).font(.caption2).foregroundStyle(RitimTheme.muted).lineLimit(1)
                        }
                        .id(track.id)
                        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                                         removal: .move(edge: .leading).combined(with: .opacity)))
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(RitimPressStyle()).accessibilityIdentifier("player.expand").accessibilityLabel("Çaları aç: \(track.title)")
                Button { playback.togglePlayPause() } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width: 44, height: 44).foregroundStyle(.white)
                        .contentTransition(reduceMotion || scenePhase != .active ? .identity : .symbolEffect(.replace))
                }.buttonStyle(RitimPressStyle()).accessibilityLabel(playback.isPlaying ? "Duraklat" : "Çal").accessibilityIdentifier("miniPlayer.playPause")
                    .sensoryFeedback(.impact(weight: .light), trigger: playback.isPlaying)
                Button { playback.next() } label: { Image(systemName: "forward.end.fill").font(.headline).frame(width: 44, height: 44).foregroundStyle(.white) }.buttonStyle(RitimPressStyle()).accessibilityLabel("Sonraki parça")
            }.padding(.horizontal, 10).padding(.vertical, 8)
            GeometryReader { geometry in
                let progress = playback.elapsed.isFinite && playback.duration.isFinite ? min(1, max(0, playback.elapsed / max(1, playback.duration))) : 0
                let width = geometry.size.width.isFinite ? max(0, geometry.size.width) : 0
                Capsule().fill(RitimTheme.mint).frame(width: width * progress)
            }.frame(height: 2).background(.white.opacity(0.08)).padding(.horizontal, 10)
        }
        .background {
            ZStack {
                RitimTheme.elevated
                LinearGradient(colors: [RitimTheme.palettes[track.colorIndex % RitimTheme.palettes.count][0].opacity(0.35), .clear],
                               startPoint: .leading, endPoint: .trailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.06)))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .animation(reduceMotion || scenePhase != .active ? nil : .easeInOut(duration: 0.3), value: track.id)
        // High priority: once a real drag is recognised the row buttons must not also fire a tap.
        .highPriorityGesture(DragGesture(minimumDistance: 24).onEnded { value in
            // Horizontal swipe skips; an upward swipe opens the full player.
            if value.translation.height < -40, abs(value.translation.width) < 60 { expand() }
            else if value.translation.width < -60 { playback.next() }
            else if value.translation.width > 60 { playback.previous() }
        })
    }
}

struct FullPlayerView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var showAddToPlaylist = false
    @State private var favoriteAnimationTrigger = 0
    @State private var showInsight = false
    @State private var artworkDrag: CGFloat = 0
    @State private var sheetDrag: CGFloat = 0
    @EnvironmentObject private var assistant: AIAssistantStore
    private var canAnimate: Bool { !reduceMotion && scenePhase == .active }
    private var palette: [Color] { RitimTheme.palettes[(playback.current?.colorIndex ?? 0) % RitimTheme.palettes.count] }
    private var favorite: Bool { library.tracks.first { $0.id == playback.current?.id }?.isFavorite ?? false }
    private var repeatIcon: String {
        switch playback.repeatMode { case .one: return "repeat.1"; default: return "repeat" }
    }
    private var loopLabel: String {
        func t(_ v: Double) -> String { String(format: "%d:%02d", Int(v) / 60, Int(v) % 60) }
        switch (playback.loopStart, playback.loopEnd) {
        case (nil, _): return "A–B"
        case (let a?, nil): return "A \(t(a))"
        case (let a?, let b?): return "\(t(a))–\(t(b))"
        }
    }
    private var repeatActive: Bool {
        switch playback.repeatMode { case .off: return false; default: return true }
    }
    private var repeatDescription: String {
        switch playback.repeatMode { case .off: return "Kapalı"; case .all: return "Tümü"; case .one: return "Tek parça" }
    }
    var body: some View {
        playerBody
            .offset(y: sheetDrag)
            .scaleEffect(1 - min(sheetDrag, 400) / 3000, anchor: .top)
            .clipShape(RoundedRectangle(cornerRadius: sheetDrag > 0 ? 28 : 0, style: .continuous))
            // Pull the player down from its top area to close it, like the music apps do.
            .simultaneousGesture(DragGesture(minimumDistance: 14)
                .onChanged { value in
                    guard canAnimate, value.startLocation.y < 170, value.translation.height > 0,
                          abs(value.translation.width) < value.translation.height else { return }
                    sheetDrag = value.translation.height
                }
                .onEnded { value in
                    if sheetDrag > 130 || value.predictedEndTranslation.height > 420, sheetDrag > 0 { dismiss() }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { sheetDrag = 0 }
                })
    }

    private var playerBody: some View {
        GeometryReader { geometry in
            let viewportWidth = geometry.size.width.isFinite ? max(1, geometry.size.width) : 1
            let inset: CGFloat = viewportWidth < 360 ? 16 : 28
            let contentWidth = max(1, min(viewportWidth - inset * 2, 520))
            let artworkSize = min(contentWidth, 380)
            let controlGap: CGFloat = contentWidth < 300 ? 4 : 8
            let playButtonSize: CGFloat = contentWidth < 300 ? 68 : 76
            ZStack {
                RitimTheme.background.ignoresSafeArea()
                AnimatedBackdrop(colors: [palette[0], palette[1], RitimTheme.lavender.opacity(0.6)], active: playback.isPlaying,
                                 intensity: 0.75)
                    .ignoresSafeArea()
                    .animation(canAnimate ? .easeInOut(duration: 0.8) : nil, value: playback.current?.colorIndex)
                LinearGradient(colors: [.clear, RitimTheme.background.opacity(0.85), RitimTheme.background], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea().accessibilityHidden(true)
                ScrollView {
                    VStack(spacing: 25) {
                        Capsule().fill(.white.opacity(0.28)).frame(width: 38, height: 5).padding(.top, -6)
                        HStack {
                            Button { dismiss() } label: { Image(systemName: "chevron.down").font(.title3).frame(width: 44, height: 44) }.accessibilityLabel("Çaları küçült")
                            Spacer()
                            VStack(spacing: 4) {
                                Text(assistant.dj != nil ? "AI DJ YAYINDA" : "ŞİMDİ ÇALIYOR").font(.system(size: 9, weight: .bold)).tracking(2)
                                    .foregroundStyle(assistant.dj != nil ? RitimTheme.mint : .white)
                                    .accessibilityIdentifier("player.header")
                                if let dj = assistant.dj {
                                    Text(dj.mood).font(.caption).foregroundStyle(RitimTheme.muted).lineLimit(1)
                                } else {
                                    Text("Senin kütüphanen").font(.caption).foregroundStyle(RitimTheme.muted)
                                }
                            }
                            Spacer()
                            if let track = playback.current {
                                ShareLink(item: library.url(for: track)) { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44) }.accessibilityLabel("Dosyayı paylaş")
                            } else { Color.clear.frame(width: 44, height: 44) }
                        }.foregroundStyle(.white)
                        if let track = playback.current {
                            if track.kind == .video {
                                VideoPlayer(player: playback.player).frame(width: contentWidth, height: contentWidth * 9 / 16)
                                    .clipShape(RoundedRectangle(cornerRadius: 20)).padding(.vertical, 30)
                            } else {
                                RhythmPulse(track: track) { level in
                                    CoverArt(track: track, radius: 24, animated: true, level: level)
                                        .scaleEffect(1 + level * 0.025)
                                }
                                    .frame(width: artworkSize, height: artworkSize)
                                    .id(track.id)
                                    .transition(canAnimate ? .asymmetric(insertion: .scale(scale: 0.86).combined(with: .opacity),
                                                                         removal: .scale(scale: 1.06).combined(with: .opacity)) : .identity)
                                    .scaleEffect(playback.isPlaying || reduceMotion ? 1 : 0.9)
                                    .offset(x: artworkDrag)
                                    .rotationEffect(.degrees(Double(artworkDrag) / 40))
                                    .shadow(color: palette[1].opacity(playback.isPlaying ? 0.45 : 0.15), radius: playback.isPlaying ? 36 : 18, y: 18)
                                    .animation(canAnimate ? .spring(response: 0.55, dampingFraction: 0.72) : nil, value: playback.isPlaying)
                                    .animation(canAnimate ? .spring(response: 0.5, dampingFraction: 0.8) : nil, value: track.id)
                                    // Simultaneous so vertical scrolling still works; only clearly horizontal drags skip.
                                    .simultaneousGesture(DragGesture(minimumDistance: 12)
                                        .onChanged { value in
                                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                            artworkDrag = value.translation.width * 0.6
                                        }
                                        .onEnded { value in
                                            let horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.5
                                            if horizontal, value.translation.width < -80 { playback.next() }
                                            else if horizontal, value.translation.width > 80 { playback.previous() }
                                            withAnimation(canAnimate ? .spring(response: 0.4, dampingFraction: 0.75) : nil) { artworkDrag = 0 }
                                        })
                                    .accessibilityIdentifier("player.artwork")
                                    .padding(.top, 10).padding(.bottom, 10)
                            }
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(track.title).font(.title2.bold()).foregroundStyle(.white).lineLimit(2)
                                        .accessibilityIdentifier("player.title")
                                        .contentTransition(.opacity)
                                    Text(track.artist.isEmpty ? track.subtitle : track.artist).font(.subheadline).foregroundStyle(RitimTheme.muted).lineLimit(2)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Button {
                                    library.toggleFavorite(track)
                                    if canAnimate { favoriteAnimationTrigger += 1 }
                                } label: {
                                    Image(systemName: favorite ? "heart.fill" : "heart").font(.title2)
                                        .symbolEffect(.bounce, options: .nonRepeating, value: favoriteAnimationTrigger)
                                        .foregroundStyle(favorite ? RitimTheme.mint : .white).frame(width: 44, height: 44)
                                        .overlay { if favorite { HeartBurst(trigger: favoriteAnimationTrigger) } }
                                }.accessibilityLabel(favorite ? "Beğenilerden kaldır" : "Beğen")
                                Button { showAddToPlaylist = true } label: {
                                    Image(systemName: "text.badge.plus").font(.title3)
                                        .foregroundStyle(.white).frame(width: 44, height: 44)
                                }.accessibilityLabel("Listeye ekle").accessibilityIdentifier("player.addToPlaylist")
                            }
                            VStack(spacing: 0) {
                                Slider(value: Binding(get: { min(max(0, playback.elapsed), max(1, playback.duration)) }, set: { playback.seek(to: $0) }), in: 0...max(1, playback.duration))
                                    .tint(RitimTheme.mint).accessibilityLabel("Çalma konumu").accessibilityIdentifier("player.position")
                                HStack {
                                    Text(timeLabel(playback.elapsed)).accessibilityIdentifier("player.elapsed")
                                    Spacer()
                                    Text("−" + timeLabel(max(0, playback.duration - playback.elapsed)))
                                        .accessibilityIdentifier("player.remaining")
                                }.font(.caption.monospacedDigit()).foregroundStyle(RitimTheme.muted)
                            }
                            HStack(spacing: 0) {
                                Button { playback.shuffleEnabled.toggle() } label: {
                                    Image(systemName: "shuffle").font(.title3).foregroundStyle(playback.shuffleEnabled ? RitimTheme.mint : RitimTheme.muted).frame(width: 44, height: 48)
                                }.accessibilityLabel(playback.shuffleEnabled ? "Karışık çalmayı kapat" : "Karışık çal")
                                    .accessibilityIdentifier("player.shuffle").accessibilityValue(playback.shuffleEnabled ? "Açık" : "Kapalı")
                                Spacer(minLength: controlGap)
                                Button { playback.previous() } label: { Image(systemName: "backward.end.fill").font(.system(size: 27)).frame(width: 48, height: 48) }.accessibilityLabel("Önceki parça")
                                Spacer(minLength: controlGap)
                                Button { playback.togglePlayPause() } label: {
                                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 28, weight: .bold))
                                        .contentTransition(canAnimate ? .symbolEffect(.replace) : .identity)
                                        .foregroundStyle(RitimTheme.background).frame(width: playButtonSize, height: playButtonSize).background(RitimTheme.mint, in: Circle())
                                }.accessibilityLabel(playback.isPlaying ? "Duraklat" : "Çal").accessibilityIdentifier("player.playPause")
                                    .shadow(color: RitimTheme.mint.opacity(playback.isPlaying ? 0.45 : 0), radius: 18)
                                    .sensoryFeedback(.impact(weight: .medium), trigger: playback.isPlaying)
                                Spacer(minLength: controlGap)
                                Button { playback.next() } label: { Image(systemName: "forward.end.fill").font(.system(size: 27)).frame(width: 48, height: 48) }.accessibilityLabel("Sonraki parça")
                                Spacer(minLength: controlGap)
                                Button { playback.cycleRepeatMode() } label: {
                                    Image(systemName: repeatIcon).font(.title3).foregroundStyle(repeatActive ? RitimTheme.mint : RitimTheme.muted).frame(width: 44, height: 48)
                                }.accessibilityLabel(repeatActive ? "Tekrar açık, değiştir" : "Tekrar kapalı, değiştir")
                                    .accessibilityIdentifier("player.repeat").accessibilityValue(repeatDescription)
                            }.foregroundStyle(.white)
                            HStack {
                                Button { playback.skip(by: -15) } label: {
                                    Image(systemName: "gobackward.15").font(.title3).frame(width: 44, height: 40)
                                }.accessibilityLabel("15 saniye geri").accessibilityIdentifier("player.skipBack")
                                Spacer()
                                Button { playback.cycleLoop() } label: {
                                    VStack(spacing: 2) {
                                        Image(systemName: "repeat").font(.title3)
                                        Text(loopLabel).font(.system(size: 10, weight: .semibold))
                                    }.frame(minWidth: 56, minHeight: 40).foregroundStyle(playback.loopStart == nil ? RitimTheme.muted : RitimTheme.mint)
                                }.accessibilityLabel("A–B döngüsü").accessibilityValue(loopLabel).accessibilityIdentifier("player.loop")
                                Spacer()
                                Button { playback.skip(by: 15) } label: {
                                    Image(systemName: "goforward.15").font(.title3).frame(width: 44, height: 40)
                                }.accessibilityLabel("15 saniye ileri").accessibilityIdentifier("player.skipForward")
                            }.foregroundStyle(RitimTheme.muted)
                            HStack {
                                VStack(spacing: 4) {
                                    AirPlayButton().frame(width: 44, height: 40).accessibilityLabel("AirPlay")
                                    Text("AirPlay").font(.system(size: 10))
                                }
                                Spacer()
                                Menu {
                                    ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 1.75, 2], id: \.self) { rate in
                                        Button { playback.setRate(rate) } label: { if playback.playbackRate == rate { Label("\(rate.formatted())×", systemImage: "checkmark") } else { Text("\(rate.formatted())×") } }
                                            .accessibilityIdentifier("player.rate.\(rate)")
                                    }
                                } label: { VStack(spacing: 4) { Text("\(playback.playbackRate.formatted())×").font(.headline).frame(height: 40); Text("Hız").font(.system(size: 10)) }.frame(minWidth: 44) }.accessibilityLabel("Çalma hızı")
                                    .accessibilityIdentifier("player.rate").accessibilityValue("\(playback.playbackRate.formatted())×")
                                Spacer()
                                Menu {
                                    ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in Button("\(minutes) dakika") { playback.setSleepTimer(minutes: minutes) } }
                                    Button("Parça bitince") { playback.setSleepAtTrackEnd(true) }.accessibilityIdentifier("player.sleep.trackEnd")
                                    if playback.sleepDeadline != nil || playback.sleepAtTrackEnd { Button("Zamanlayıcıyı kapat", role: .destructive) { playback.setSleepTimer(minutes: nil) } }
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: playback.sleepDeadline == nil && !playback.sleepAtTrackEnd ? "moon" : "moon.zzz.fill").font(.title3).frame(height: 40)
                                        Text("Uyku").font(.system(size: 10))
                                    }.frame(minWidth: 44).foregroundStyle(playback.sleepDeadline == nil && !playback.sleepAtTrackEnd ? RitimTheme.muted : RitimTheme.mint)
                                }.accessibilityLabel("Uyku zamanlayıcısı")
                                Spacer()
                                Button { showQueue = true } label: {
                                    VStack(spacing: 4) { Image(systemName: "text.line.first.and.arrowtriangle.forward").font(.title3).frame(height: 40); Text("Sıradaki").font(.system(size: 10)) }.frame(minWidth: 44)
                                }.accessibilityLabel("Çalma sırası")
                            }.foregroundStyle(RitimTheme.muted).padding(.top, 4)
                            HStack(spacing: 10) {
                                Button { showLyrics = true } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "text.quote").font(.title3).foregroundStyle(RitimTheme.lavender)
                                        Text("Şarkı sözleri").font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                        Spacer(minLength: 0)
                                    }.foregroundStyle(.white).padding(16)
                                        .background(RitimTheme.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
                                }.accessibilityIdentifier("player.lyrics")
                                Button { showInsight = true } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "sparkles").font(.title3).foregroundStyle(RitimTheme.mint)
                                        Text("AI notu").font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                        Spacer(minLength: 0)
                                    }.foregroundStyle(.white).padding(16)
                                        .background(RitimTheme.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
                                        .aiGlow(radius: 16, active: assistant.insightLoading == track.id)
                                }.accessibilityIdentifier("player.insight").accessibilityLabel("Yapay zekâ notu")
                            }
                            if let dj = assistant.dj {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(RitimTheme.mint)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(dj.isExtending ? "DJ sıradaki parçaları seçiyor…" : dj.note)
                                            .font(.caption).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                                        Text("\(dj.played.count) çalındı · \(dj.trackIDs.count) parçalık set").font(.caption2).foregroundStyle(RitimTheme.muted)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Button("Durdur") { assistant.stopDJ() }.font(.caption.bold()).foregroundStyle(RitimTheme.mint)
                                        .accessibilityIdentifier("player.dj.stop")
                                }.padding(14).background(RitimTheme.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                                    .aiGlow(radius: 16, active: dj.isExtending)
                                    .accessibilityElement(children: .contain).accessibilityIdentifier("player.dj")
                            }
                            if track.kind == .audio { RhythmVisualizer(track: track, color: palette[1]).padding(.top, 2) }
                            if playback.sleepAtTrackEnd {
                                HStack(spacing: 6) { Image(systemName: "moon.zzz"); Text("Müzik bu parça bitince duracak") }.font(.caption).foregroundStyle(RitimTheme.mint)
                            }
                            if let deadline = playback.sleepDeadline {
                                HStack(spacing: 6) { Image(systemName: "moon.zzz"); Text("Müzik \(deadline, style: .timer) sonra duracak") }.font(.caption).foregroundStyle(RitimTheme.mint)
                            }
                        } else { EmptyLibrary(title: "Bir parça seç", message: "Kütüphanenden çalmaya başla.") }
                    }
                    // Custom control labels already include their hit targets. System button
                    // chrome can add padding and force the whole scroll content past the screen.
                    .buttonStyle(RitimPressStyle())
                    .frame(width: contentWidth)
                    .padding(.horizontal, inset)
                    .frame(width: viewportWidth)
                    .padding(.top, 10).padding(.bottom, 24)
                }.scrollIndicators(.hidden)
            }
        }.preferredColorScheme(.dark).sheet(isPresented: $showQueue) { QueueView() }
            .sheet(isPresented: $showLyrics) { LyricsView() }
            .sheet(isPresented: $showAddToPlaylist) {
                if let track = playback.current { AddToPlaylistView(track: track) }
            }
            .sheet(isPresented: $showInsight) { TrackInsightView().presentationDetents([.medium, .large]) }
    }
}

private struct QueueView: View {
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var queueQuery = ""
    @State private var showSave = false
    @State private var playlistName = "Çalma sıram"
    @State private var savedName: String?
    @State private var saveError: String?
    var body: some View {
        NavigationStack {
            List {
                if !playback.queue.isEmpty {
                    Section {
                        HStack {
                            Label("\(playback.queue.count) parça", systemImage: "music.note.list")
                            Spacer()
                            Text("Düzenle ile taşı veya kaldır").font(.caption).foregroundStyle(RitimTheme.muted)
                        }.font(.subheadline).listRowBackground(RitimTheme.surface)
                    }
                }
                if let savedName {
                    Label("\(savedName) kitaplığına kaydedildi", systemImage: "checkmark.circle.fill")
                        .font(.subheadline).foregroundStyle(RitimTheme.mint)
                        .listRowBackground(RitimTheme.surface).accessibilityIdentifier("player.queue.saved")
                }
                if let saveError {
                    Text(saveError).font(.caption).foregroundStyle(.orange).listRowBackground(RitimTheme.surface)
                }
                if playback.queue.isEmpty { Text("Çalma sıran boş.").foregroundStyle(RitimTheme.muted) }
                // Queue entries have stable UUIDs. Using the current array offset here made
                // every row acquire a new identity after a drag, which caused List to redraw
                // the whole editor while the player was publishing its time updates.
                ForEach(playback.queue.filter { LibrarySearch.matches($0, query: queueQuery) }, id: \.id) { track in
                    Button { playback.play(track, in: playback.queue) } label: {
                        HStack(spacing: 12) {
                            CoverArt(track: track, radius: 8).frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title).font(.subheadline.bold()).foregroundStyle(track.id == playback.current?.id ? RitimTheme.mint : .white)
                                Text(track.id == playback.current?.id ? "Şimdi çalıyor" : track.subtitle).font(.caption).foregroundStyle(RitimTheme.muted)
                            }
                        }
                    }.listRowBackground(RitimTheme.surface)
                        .accessibilityIdentifier("player.queue.track.\(track.id.uuidString)")
                }.onDelete { offsets in
                    let visible = playback.queue.filter { LibrarySearch.matches($0, query: queueQuery) }
                    let ids = Set(offsets.compactMap { visible.indices.contains($0) ? visible[$0].id : nil })
                    playback.removeFromQueue(at: IndexSet(playback.queue.indices.filter { ids.contains(playback.queue[$0].id) }))
                }.onMove { offsets, destination in
                    if queueQuery.isEmpty { playback.moveQueue(from: offsets, to: destination) }
                }.moveDisabled(!queueQuery.isEmpty)
            }.scrollContentBackground(.hidden).background(RitimTheme.background)
                .searchable(text: $queueQuery, prompt: "Sırada ara")
                .navigationTitle("Çalma sırası").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { EditButton() }
                    ToolbarItem(placement: .secondaryAction) {
                        Button("Sıradakileri temizle") {
                            playback.removeFromQueue(at: IndexSet(playback.queue.indices.filter { playback.queue[$0].id != playback.current?.id }))
                        }.disabled(playback.queue.count < 2)
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Liste olarak kaydet", systemImage: "text.badge.plus") { showSave = true }
                            .disabled(playback.queue.isEmpty).accessibilityIdentifier("player.queue.save")
                    }
                }
                .alert("Sırayı liste olarak kaydet", isPresented: $showSave) {
                    TextField("Liste adı", text: $playlistName)
                    Button("Vazgeç", role: .cancel) {}
                    Button("Kaydet") {
                        do {
                            let playlist = try library.createPlaylist(name: playlistName, trackIDs: playback.queue.map(\.id))
                            savedName = playlist.name; saveError = nil
                        } catch { saveError = error.localizedDescription; savedName = nil }
                    }.disabled(playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } message: { Text("Çalma sırandaki \(playback.queue.count) parça aynı sırayla yeni bir listeye eklenir.") }
        }.preferredColorScheme(.dark).tint(RitimTheme.mint)
    }
}
