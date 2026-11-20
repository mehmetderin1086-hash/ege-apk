import SwiftUI

/// All dashboard numbers come from the on-device library, queue and measured playback.
struct DashboardView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var downloads: DownloadStore
    @EnvironmentObject private var listening: ListeningStore
    @EnvironmentObject private var assistant: AIAssistantStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    let importFiles: () -> Void
    let openDownloads: () -> Void
    let openSettings: () -> Void
    let openAssistant: () -> Void

    @State private var period = 7
    @State private var selectedDay: Date?
    @State private var collection: DashboardCollection?
    @State private var appeared = false
    @State private var chartGrown = false
    @ScaledMetric(relativeTo: .largeTitle) private var brandSize: CGFloat = 36
    @ScaledMetric(relativeTo: .largeTitle) private var timeSize: CGFloat = 48

    private var chartDays: [ListeningDay] { listening.recentDays(count: period) }
    private var todaySeconds: Double { listening.totalSeconds(days: 1) }
    private var periodSeconds: Double { listening.totalSeconds(days: period) }
    private var weekSeconds: Double { listening.totalSeconds(days: 7) }
    private var favorites: [MediaTrack] { library.tracks.filter(\.isFavorite) }
    private var audioTracks: [MediaTrack] { library.tracks.filter { $0.kind == .audio } }
    private var videoTracks: [MediaTrack] { library.tracks.filter { $0.kind == .video } }
    private var recent: [MediaTrack] {
        Array(library.tracks.filter { $0.lastPlayedAt != nil }.sorted {
            ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast)
        }.prefix(4))
    }
    private var mostPlayed: [MediaTrack] {
        Array(library.tracks.filter { $0.playCount > 0 }.sorted {
            if $0.playCount != $1.playCount { return $0.playCount > $1.playCount }
            return ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast)
        }.prefix(3))
    }
    private var activeDownloads: Int { downloads.entries.filter(\.isActive).count }
    private var motionAllowed: Bool { !reduceMotion && scenePhase == .active }
    private var selectedListeningDay: ListeningDay? {
        chartDays.first { $0.dayStart == selectedDay } ?? chartDays.last
    }
    private var adaptiveColumns: [GridItem] {
        [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 142), spacing: 12)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header.staggeredAppear(0)
                if let current = playback.current { continueCard(current).staggeredAppear(1) }
                HomeShelves().staggeredAppear(1)
                hero.staggeredAppear(2).scrollFlow()
                listeningCard.staggeredAppear(3).scrollFlow()
                AIDailyCard(openAssistant: openAssistant).staggeredAppear(4)
                quickActions.staggeredAppear(5)
                librarySection.staggeredAppear(6).scrollFlow()
                downloadsCard.staggeredAppear(7).scrollFlow()
                if !mostPlayed.isEmpty { mostPlayedSection }
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Yeniden buluşalım", caption: "Son çaldıkların")
                        ForEach(recent) { track in TrackRow(track: track, context: recent) }
                    }
                } else if !library.tracks.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "İlk ritmini seç", caption: "Kütüphanenden")
                        ForEach(Array(library.tracks.prefix(3))) { track in
                            TrackRow(track: track, context: library.tracks)
                        }
                    }
                }
                Label("Müziklerin ve istatistiklerin bu cihazda.", systemImage: "iphone")
                    .font(.caption).foregroundStyle(RitimTheme.muted)
                    .frame(maxWidth: .infinity).padding(.top, 2)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 28)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("dashboard")
        .onAppear {
            withAnimation(motionAllowed ? .easeOut(duration: 0.35) : nil) { appeared = true }
            withAnimation(motionAllowed ? .spring(response: 0.7, dampingFraction: 0.75).delay(0.2) : nil) { chartGrown = true }
        }
        .task { await assistant.prepareProactive(library: library, playback: playback) }
        .sheet(item: $collection) { selection in collectionSheet(selection) }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("KİŞİSEL ALANIN").font(.system(size: 9, weight: .bold))
                    .tracking(2.4).foregroundStyle(RitimTheme.muted)
                Text("ritim").font(.system(size: brandSize, weight: .black, design: .rounded)).tracking(-1.8)
            }
            Spacer(minLength: 12)
            Button(action: openSettings) {
                Image(systemName: "slider.horizontal.3").font(.title3)
                    .frame(width: 46, height: 46).background(RitimTheme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.06)))
            }.buttonStyle(RitimPressStyle()).foregroundStyle(.white).accessibilityLabel("Ayarlar")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Circle().fill(RitimTheme.mint).frame(width: 6, height: 6)
                Text("BUGÜNÜN RİTMİ").font(.system(size: 10, weight: .bold)).tracking(1.8)
                Spacer(minLength: 4)
                Text(Date().formatted(.dateTime.locale(Locale(identifier: "tr_TR")).day().month(.abbreviated)))
                    .font(.caption).foregroundStyle(.white.opacity(0.65))
            }.foregroundStyle(RitimTheme.mint)
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .center, spacing: 16))) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(durationText(todaySeconds))
                        .font(.system(size: timeSize, weight: .bold, design: .rounded)).tracking(-1.8)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.65).lineLimit(1)
                        .accessibilityIdentifier("dashboard.todayTime")
                        .accessibilityLabel("Bugünkü dinleme süresi")
                        .accessibilityValue("\(Int(todaySeconds))")
                    Text(todaySeconds > 0 ? "bugün müziğe ayırdığın zaman" : "Bugün ritmini başlat.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.74))
                }.frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Circle().strokeBorder(RitimTheme.mint.opacity(0.15), lineWidth: 1).frame(width: 84, height: 84)
                    Circle().fill(RitimTheme.mint.opacity(0.08)).frame(width: 66, height: 66)
                    PlayingBars(isPlaying: playback.isPlaying && motionAllowed)
                        .scaleEffect(1.7)
                }.accessibilityHidden(true)
            }
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SON 7 GÜN").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.white.opacity(0.55))
                    Text(durationText(weekSeconds)).font(.subheadline.weight(.semibold)).contentTransition(.numericText())
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
                Button {
                    if playback.current != nil { playback.togglePlayPause() }
                    else if let first = library.tracks.first { playback.play(first, in: library.tracks) }
                    else { importFiles() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: playback.current != nil ? (playback.isPlaying ? "pause.fill" : "play.fill") : (library.tracks.isEmpty ? "plus" : "play.fill"))
                        Text(playback.current != nil ? (playback.isPlaying ? "Duraklat" : "Devam et") : (library.tracks.isEmpty ? "Parça ekle" : "Müziği başlat"))
                    }.font(.subheadline.bold()).foregroundStyle(RitimTheme.background)
                        .padding(.horizontal, 17).padding(.vertical, 13)
                        .background(RitimTheme.mint, in: Capsule())
                }.buttonStyle(RitimPressStyle())
                    .accessibilityLabel(playback.current != nil ? (playback.isPlaying ? "Müziği duraklat" : "Müziğe kaldığın yerden devam et") : (library.tracks.isEmpty ? "İlk parçanı ekle" : "Kütüphaneyi çal"))
            }
        }
        .padding(22)
        .background {
            ZStack(alignment: .topTrailing) {
                LinearGradient(colors: [Color(red: 0.18, green: 0.24, blue: 0.24), Color(red: 0.13, green: 0.14, blue: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
                AnimatedBackdrop(colors: [RitimTheme.mint.opacity(0.35), RitimTheme.lavender.opacity(0.4)], active: playback.isPlaying, intensity: 0.6)
                Circle().stroke(RitimTheme.lavender.opacity(0.12), lineWidth: 26)
                    .frame(width: 220, height: 220).offset(x: 100, y: -105)
                Circle().stroke(RitimTheme.mint.opacity(0.07), lineWidth: 1)
                    .frame(width: 272, height: 272).offset(x: 126, y: -131)
            }.accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.07)))
        .animation(motionAllowed ? .easeOut(duration: 0.2) : nil, value: Int(todaySeconds))
    }

    private var quickActions: some View {
        LazyVGrid(columns: adaptiveColumns, spacing: 12) {
            shortcut("Dosya ekle", subtitle: "Cihazından içe aktar", icon: "plus", color: RitimTheme.mint, action: importFiles)
                .accessibilityIdentifier("import.files")
            shortcut("MP3 / MP4 indir", subtitle: "Bağlantı veya liste", icon: "arrow.down", color: RitimTheme.lavender, action: openDownloads)
                .accessibilityIdentifier("dashboard.addDownload")
        }
    }

    private var listeningCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack { Text("Dinleme ritmin").font(.headline); Spacer(minLength: 10); periodPicker }
                VStack(alignment: .leading, spacing: 12) { Text("Dinleme ritmin").font(.headline); periodPicker }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(durationText(periodSeconds)).font(.system(.title, design: .rounded, weight: .bold))
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("dashboard.totalTime")
                    .accessibilityLabel("Son \(period) gün dinleme süresi")
                    .accessibilityValue("\(Int(periodSeconds))")
                Text("toplam").font(.caption).foregroundStyle(RitimTheme.muted)
            }
            chart
            if let error = listening.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dashboard.historyError")
            }
            if periodSeconds == 0 {
                Text("Henüz dinleme kaydı yok. Süreler bu sürümden itibaren gerçekten çaldığın zamanla oluşur.")
                    .font(.caption).foregroundStyle(RitimTheme.muted).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dashboard.emptyHistory")
            } else if let day = selectedListeningDay {
                HStack(alignment: .firstTextBaseline) {
                    Text(day.dayStart.formatted(.dateTime.locale(Locale(identifier: "tr_TR")).day().month(.abbreviated)))
                        .foregroundStyle(RitimTheme.muted)
                    Spacer(minLength: 8)
                    Text(durationText(day.seconds)).foregroundStyle(RitimTheme.mint).monospacedDigit()
                }.font(.caption.weight(.medium)).accessibilityIdentifier("dashboard.selectedDay")
            }
        }
        .padding(18).background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 22))
        .animation(motionAllowed ? .easeInOut(duration: 0.25) : nil, value: period)
    }

    private var periodPicker: some View {
        HStack(spacing: 3) {
            ForEach([7, 30], id: \.self) { count in
                Button {
                    period = count; selectedDay = nil
                } label: {
                    Text("\(count) gün").font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .foregroundStyle(period == count ? RitimTheme.background : RitimTheme.muted)
                        .background(period == count ? RitimTheme.mint : .clear, in: Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("dashboard.period\(count)")
                    .accessibilityAddTraits(period == count ? .isSelected : [])
            }
        }.padding(3).background(RitimTheme.background.opacity(0.6), in: Capsule())
    }

    private var chart: some View {
        let days = chartDays
        let peak = max(days.map(\.seconds).max() ?? 0, 1)
        return VStack(spacing: 9) {
            HStack(alignment: .bottom, spacing: period == 7 ? 12 : 3) {
                ForEach(days, id: \.dayStart) { day in
                    let selected = selectedListeningDay?.dayStart == day.dayStart
                    Button { withAnimation(motionAllowed ? .spring(response: 0.3) : nil) { selectedDay = day.dayStart } } label: {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: period == 7 ? 5 : 2)
                                .fill(day.seconds == 0 ? RitimTheme.elevated : (selected ? RitimTheme.mint : RitimTheme.lavender.opacity(0.75)))
                                .frame(height: day.seconds > 0 ? max(5, CGFloat(day.seconds / peak) * 100 * (chartGrown ? 1 : 0.05)) : 3)
                                .shadow(color: selected && day.seconds > 0 ? RitimTheme.mint.opacity(0.5) : .clear, radius: 6)
                        }.frame(maxWidth: .infinity).frame(height: 108).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel(day.dayStart.formatted(.dateTime.locale(Locale(identifier: "tr_TR")).day().month(.wide).weekday(.wide)))
                        .accessibilityValue(durationText(day.seconds))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            if period == 7 {
                HStack(spacing: 12) {
                    ForEach(days, id: \.dayStart) { day in
                        Text(day.dayStart.formatted(.dateTime.locale(Locale(identifier: "tr_TR")).weekday(.abbreviated)))
                            .font(.system(size: 9, weight: .medium)).lineLimit(1)
                            .foregroundStyle(Calendar.current.isDateInToday(day.dayStart) ? RitimTheme.mint : RitimTheme.muted)
                            .frame(maxWidth: .infinity)
                    }
                }.accessibilityHidden(true)
            } else if let first = days.first {
                HStack {
                    Text(first.dayStart.formatted(.dateTime.locale(Locale(identifier: "tr_TR")).day().month(.abbreviated)))
                    Spacer()
                    Text("Bugün")
                }.font(.system(size: 10, weight: .medium)).foregroundStyle(RitimTheme.muted).accessibilityHidden(true)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("dashboard.chart")
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Kütüphanene bir bakış", caption: "Cihazında")
            LazyVGrid(columns: adaptiveColumns, spacing: 12) {
                metric("Tüm parçalar", value: "\(library.tracks.count)", detail: "\(library.playlists.count) çalma listesi", icon: "square.stack.fill", color: RitimTheme.mint) { collection = .all }
                    .accessibilityIdentifier("dashboard.libraryCount").accessibilityValue("\(library.tracks.count)")
                metric("Favoriler", value: "\(favorites.count)", detail: "En sevdiklerin", icon: "heart.fill", color: Color(red: 1, green: 0.59, blue: 0.68)) { collection = .favorites }
                    .accessibilityIdentifier("dashboard.favorites")
                metric("Müzik", value: "\(audioTracks.count)", detail: "Ses dosyası", icon: "waveform", color: RitimTheme.lavender) { collection = .audio }
                metric("Video", value: "\(videoTracks.count)", detail: "Çevrimdışı izle", icon: "play.rectangle.fill", color: Color(red: 0.5, green: 0.76, blue: 1)) { collection = .video }
            }
            Button(action: openSettings) {
                HStack(spacing: 12) {
                    Image(systemName: "internaldrive").foregroundStyle(RitimTheme.muted)
                    Text("Medya alanı").font(.subheadline)
                    Spacer(minLength: 8)
                    Text(ByteCountFormatter.string(fromByteCount: library.storageBytes, countStyle: .file))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(RitimTheme.mint)
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(RitimTheme.muted)
                }.padding(16).background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(RitimPressStyle()).accessibilityIdentifier("dashboard.storage")
        }
    }

    private var downloadsCard: some View {
        Button(action: openDownloads) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill").font(.title2).foregroundStyle(RitimTheme.mint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("İndirme merkezi").font(.headline).foregroundStyle(.white)
                        Text(activeDownloads > 0 ? (downloads.isQueuePaused ? "Sıra duraklatıldı" : "\(downloads.runningCount) işleniyor · \(downloads.pendingCount) sırada") : "Yeni keşiflerine yer var.")
                            .font(.caption).foregroundStyle(RitimTheme.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(RitimTheme.muted)
                }
                HStack(alignment: .top, spacing: 12) {
                    downloadNumber("Etkin", count: activeDownloads, color: RitimTheme.lavender)
                    downloadNumber("Tamamlanan", count: downloads.completedCount, color: RitimTheme.mint)
                    downloadNumber("Hata", count: downloads.failedCount, color: downloads.failedCount > 0 ? .orange : RitimTheme.muted)
                }
            }.padding(18).background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(RitimPressStyle()).accessibilityIdentifier("dashboard.downloads")
            .accessibilityLabel("İndirme merkezi, \(activeDownloads) etkin, \(downloads.completedCount) tamamlanan, \(downloads.failedCount) hata")
    }

    private func continueCard(_ track: MediaTrack) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: playback.isPlaying ? "Şimdi seninle" : "Kaldığın yerden")
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .center, spacing: 14))) {
                if !typeSize.isAccessibilitySize {
                    CoverArt(track: track, radius: 13).frame(width: 66, height: 66).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(track.title).font(.subheadline.bold()).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .accessibilityIdentifier("dashboard.resume.title")
                    Text("\(timeLabel(playback.elapsed)) / \(timeLabel(playback.duration))")
                        .font(.caption).monospacedDigit().foregroundStyle(RitimTheme.muted)
                        .accessibilityIdentifier("dashboard.resume.elapsed")
                        .accessibilityLabel("Kaldığın konum")
                        .accessibilityValue(timeLabel(playback.elapsed))
                    ProgressView(value: min(max(playback.elapsed, 0), max(playback.duration, 1)), total: max(playback.duration, 1))
                        .tint(RitimTheme.mint).accessibilityHidden(true)
                    Text("Çalma sırasında \(playback.queue.count) parça")
                        .font(.caption).foregroundStyle(RitimTheme.muted)
                        .accessibilityIdentifier("dashboard.resume.queueCount")
                        .accessibilityValue("\(playback.queue.count)")
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { playback.togglePlayPause() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        if typeSize.isAccessibilitySize {
                            Text(playback.isPlaying ? "Duraklat" : "Devam et")
                        }
                    }
                    .font(.headline).foregroundStyle(RitimTheme.background)
                    .padding(.horizontal, typeSize.isAccessibilitySize ? 18 : 0)
                    .padding(.vertical, typeSize.isAccessibilitySize ? 12 : 0)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(RitimTheme.mint, in: Capsule())
                }.buttonStyle(RitimPressStyle()).accessibilityLabel(playback.isPlaying ? "Dinlemeyi duraklat" : "Dinlemeye devam et")
                    .accessibilityIdentifier("dashboard.resume")
            }.padding(16).background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var mostPlayedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Vazgeçemediklerin", caption: "Tüm zamanlar")
            ForEach(Array(mostPlayed.enumerated()), id: \.element.id) { index, track in
                HStack(spacing: 12) {
                    Text(String(format: "%02d", index + 1)).font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(RitimTheme.lavender.opacity(0.7)).frame(width: 26).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        TrackRow(track: track, context: mostPlayed)
                        Text("\(track.playCount) kez çaldın").font(.caption2).foregroundStyle(RitimTheme.muted).padding(.leading, 66)
                    }
                }
            }
        }
    }

    private func shortcut(_ title: String, subtitle: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.headline).foregroundStyle(color)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.caption.weight(.bold)).foregroundStyle(.white)
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(RitimTheme.muted)
                }
                Spacer(minLength: 0)
            }.padding(14).frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                .background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 17))
        }.buttonStyle(RitimPressStyle())
    }

    private func metric(_ title: String, value: String, detail: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon).foregroundStyle(color)
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(RitimTheme.muted)
                }.font(.subheadline)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(value).font(.system(.title, design: .rounded, weight: .bold)).contentTransition(.numericText())
                    Text(title).font(.caption.weight(.medium)).foregroundStyle(RitimTheme.muted)
                }
                Text(detail).font(.caption2).foregroundStyle(RitimTheme.muted)
            }.foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                .padding(16).background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(RitimPressStyle()).accessibilityLabel("\(title), \(value), \(detail)")
    }

    private func downloadNumber(_ title: String, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(count)").font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(color).contentTransition(.numericText())
            Text(title).font(.caption2).foregroundStyle(RitimTheme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func collectionSheet(_ selection: DashboardCollection) -> some View {
        DashboardCollectionSheet(title: selection.title, tracks: tracks(for: selection))
    }

    private func tracks(for selection: DashboardCollection) -> [MediaTrack] {
        switch selection {
        case .all: library.tracks
        case .audio: audioTracks
        case .video: videoTracks
        case .favorites: favorites
        }
    }

    private func durationText(_ seconds: Double) -> String {
        let safe = seconds.isFinite ? max(0, Int(seconds)) : 0
        if safe < 60 { return "\(safe) sn" }
        if safe < 3_600 { return "\(safe / 60) dk" }
        return "\(safe / 3_600) sa \((safe % 3_600) / 60) dk"
    }
}

private enum DashboardCollection: String, Identifiable {
    case all, audio, video, favorites
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Tüm parçalar"
        case .audio: "Müziklerim"
        case .video: "Videolarım"
        case .favorites: "Favorilerim"
        }
    }
}

private struct DashboardCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let tracks: [MediaTrack]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if tracks.isEmpty {
                        EmptyLibrary(title: "Burada henüz parça yok", message: title == "Favorilerim" ? "Parça menüsündeki Beğen ile favorilerini burada topla." : "Cihazından dosya ekleyebilir veya İndir bölümünü kullanabilirsin.")
                    } else {
                        Text("\(tracks.count) parça").font(.caption).foregroundStyle(RitimTheme.muted)
                        ForEach(tracks) { track in TrackRow(track: track, context: tracks) }
                    }
                }.padding(20)
            }
            .background(RitimTheme.background).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }.accessibilityIdentifier("dashboard.collection.close")
                }
            }
        }.preferredColorScheme(.dark).tint(RitimTheme.mint)
    }
}
