import SwiftUI

struct FavoritesView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Favorite?
    @State private var sharing: ShareMessage?
    /// Hiçbir takip türü yok: (hat, durak) çifti, hat takibi, favori durak ve kayıtlı yolculuk.
    /// Yalnızca Debug: `-compact` kota ve uyarı kartlarını gizler (ekran doğrulaması).
    private var compactDemo: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-compact")
        #else
        false
        #endif
    }
    private var nothingFollowed: Bool { model.favorites.isEmpty && model.followedLines.isEmpty && model.favoriteStopList.isEmpty && model.savedTrips.isEmpty }
    private var atStopCount: Int { model.favorites.filter { model.favoriteETAs[$0.id]?.first?.state == .atStop }.count }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                GreetingHeader()
                header
                StatusChips()
                if !compactDemo {
                    NavigationLink(value: Route.settings) { QuotaCard() }.buttonStyle(.plain)
                    AlertBoard()
                }
                if !model.followedLines.isEmpty { followedLinesSection }
                if !model.favoriteStopList.isEmpty { favoriteStopsSection }
                if !model.savedTrips.isEmpty { tripsSection }
                if nothingFollowed { emptyState }
                else if model.favorites.isEmpty { stopHint }
                ForEach(model.favorites) { favorite in
                    NavigationLink(value: Route.line(code: favorite.line, stop: favorite.stopCode)) {
                        FavoriteCard(favorite: favorite, etas: model.favoriteETAs[favorite.id] ?? []).zoomSource(id: "\(favorite.line)-\(favorite.stopCode)")
                    }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Bildirim ayarları", systemImage: "bell.badge") { editing = favorite }
                            Button("Paylaş", systemImage: "square.and.arrow.up") { sharing = ShareBuilder.favorite(favorite, etas: model.favoriteETAs[favorite.id] ?? []) }
                            Button("Takipten çıkar", systemImage: "trash", role: .destructive) { withAnimation(.spring) { model.remove(favorite) } }
                        }
                        .scrollTransition { content, phase in
                            content.opacity(phase.isIdentity ? 1 : 0.4).scaleEffect(phase.isIdentity ? 1 : 0.94).blur(radius: phase.isIdentity ? 0 : 2)
                        }
                        .transition(.asymmetric(insertion: .scale(scale: 0.8).combined(with: .opacity), removal: .opacity.combined(with: .move(edge: .trailing))))
                }
                if let last = model.lastRefresh, !model.favorites.isEmpty {
                    Text("Güncelleme \(last.formatted(date: .omitted, time: .standard)) · İETT kotası gereği her hat ~\(Int(FleetBudget.refreshInterval(activeLines: Set(model.favorites.map(\.line)).count))) sn'de bir yenilenir, aradaki süre otomatik sayılır · kalan kota \(model.quotaRemaining)/\(FleetBudget.hourlyLimit)")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 4)
                }
            }
            .padding(.horizontal).padding(.bottom, 24)
            .animation(.spring(duration: 0.5), value: model.favorites)
        }
        .background { AuroraBackground() }
        .navigationTitle("Takip").navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { NavigationLink(value: Route.notes) { Image(systemName: "note.text").symbolEffect(.bounce, value: model.notes.count) } }
            ToolbarItem(placement: .topBarLeading) { NavigationLink(value: Route.settings) { Image(systemName: "gearshape") } }
            ToolbarItem(placement: .topBarTrailing) { NavigationLink(value: Route.favoriteStops) { Image(systemName: "star") } }
        }
        .refreshable { await model.refreshFavorites() }
        .sensoryFeedback(.success, trigger: atStopCount)
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-share"), let first = model.favorites.first { try? await Task.sleep(for: .milliseconds(900)); sharing = ShareBuilder.favorite(first, etas: model.favoriteETAs[first.id] ?? []) }
            if ProcessInfo.processInfo.arguments.contains("-editRule") { try? await Task.sleep(for: .milliseconds(900)); editing = model.favorites.first }
            #endif
        }
        .sheet(item: $editing) { AlertRuleEditor(favorite: $0, initial: model.rule(for: $0)) }
        .shareSheet($sharing)
        .task(id: model.favorites.count * 100 + model.followedLines.count) {
            while !Task.isCancelled {
                await model.refreshFavorites()
                await model.refreshBoardNotices()
                model.quota = await FleetBudget.shared.snapshot()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            LiveDot(color: model.liveError == nil ? .green : .red)
            Text(model.liveError ?? headerText).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 4)
    }

    /// Durak seçmeden takip edilen hatlar: yoldaki araç sayısı, sana en yakın durak ve en yakın aracın varışı.
    private var followedLinesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Takip ettiğim hatlar", systemImage: "bus.doubledecker.fill").font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent)
            ForEach(Array(model.followedLines.enumerated()), id: \.element) { index, line in
                NavigationLink(value: Route.line(code: line, stop: model.lineSummaries[line]?.stopCode)) { FollowedLineCard(line: line, summary: model.lineSummaries[line]) }.buttonStyle(.plain).cascadeIn(index)
                    .contextMenu {
                        Button("Paylaş", systemImage: "square.and.arrow.up") {
                            let s = model.lineSummaries[line], hat = model.line(line) ?? Hat(code: line, name: "")
                            sharing = ShareBuilder.line(hat, total: s?.total ?? 0, byDirection: s?.byDirection ?? [:], nextDepartures: [], nearestStop: s?.stopName, eta: s?.eta)
                        }
                        Button("Hat takibini bırak", systemImage: "minus.circle", role: .destructive) { withAnimation(.spring) { model.toggleFollow(line: line) } }
                    }
            }
        }
    }

    private var favoriteStopsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Favori duraklarım", systemImage: "star.fill").font(.subheadline.weight(.bold)).foregroundStyle(.yellow)
                Spacer()
                NavigationLink(value: Route.favoriteStops) { Text("Tümü").font(.caption.weight(.semibold)) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.favoriteStopList) { stop in
                        NavigationLink(value: Route.stop(code: stop.code)) { FavoriteStopCard(stop: stop) }.buttonStyle(.plain)
                            .scrollTransition(axis: .horizontal) { c, phase in c.scaleEffect(phase.isIdentity ? 1 : 0.9).opacity(phase.isIdentity ? 1 : 0.6) }
                    }
                }
            }
        }
    }

    private var tripsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Yolculuklarım", systemImage: "star.fill").font(.subheadline.weight(.bold)).foregroundStyle(.orange)
            ForEach(model.savedTrips) { trip in NavigationLink(value: Route.trip(id: trip.id)) { SavedTripCard(trip: trip) }.buttonStyle(.plain) }
        }
    }

    private var headerText: String {
        var parts: [String] = []
        if !model.favorites.isEmpty { parts.append("\(model.favorites.count) durak") }
        if !model.followedLines.isEmpty { parts.append("\(model.followedLines.count) hat") }
        if !model.favoriteStopList.isEmpty { parts.append("\(model.favoriteStopList.count) favori durak") }
        return parts.isEmpty ? "Takip listen hazır" : parts.joined(separator: " · ") + " izleniyor"
    }

    /// Yalnızca hat ya da favori durak takibi varken: durak takibi için küçük ipucu (liste boş değil).
    private var stopHint: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse").font(.title2).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Durak takibi ekle").font(.subheadline.weight(.bold))
                Text("Hat ekranında bir durağa dokunup “Takip et” dersen otobüsün o durağa kaç dakikada geldiği burada canlı görünür.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            NavigationLink(value: Route.favoriteStops) { EmptyView() }.frame(width: 0).opacity(0)
        }
        .card()
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            DrivingBus().padding(.top, 20)
            Text("Takip listen boş").font(.title3.bold())
            Text("Bir hattı aç, haritadan ya da listeden durağını seç ve “Takip et”e dokun. Otobüs kaç dakikada ve kaç durakta geliyor, burada canlı göreceksin.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("Hatlar sekmesinde her hattın yanındaki “Takip” düğmesine dokun.").font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent).multilineTextAlignment(.center)
        }
        .card().padding(.top, 20)
    }
}

struct FavoriteCard: View {
    let favorite: Favorite
    let etas: [BusETA]
    @Environment(AppModel.self) private var model
    var body: some View {
        let first = etas.first
        VStack(spacing: 14) {
            HStack {
                LineBadge(code: favorite.line)
                if model.rule(for: favorite)?.enabled == true || favorite.alertMinutes != nil { Image(systemName: "bell.fill").font(.caption).foregroundStyle(.orange).symbolEffect(.wiggle, options: .repeat(.periodic(delay: 4))) }
                Spacer()
                if first != nil { HStack(spacing: 2) { LiveDot(); Text("canlı").font(.caption2.bold()).foregroundStyle(.green) } }
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            HStack(spacing: 16) {
                ETARing(eta: first)
                VStack(alignment: .leading, spacing: 4) {
                    Text(favorite.stopName).font(.headline).lineLimit(2)
                    if let first {
                        Text([first.stopsLeft.flatMap { $0 > 0 ? "\($0) durak kaldı" : nil }, first.distanceText + " uzakta"].compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                        if etas.count > 1 {
                            HStack(spacing: 6) {
                                Text("Sonraki").font(.caption).foregroundStyle(.secondary)
                                ForEach(etas.dropFirst().prefix(2)) { Text($0.text).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3).background(.quaternary, in: .capsule) }
                            }
                        }
                    } else { Text("Şu an yaklaşan araç yok").font(.subheadline).foregroundStyle(.secondary) }
                    if let note = model.notes["stop:\(favorite.stopCode)"] ?? model.notes["line:\(favorite.line)"] {
                        Label(note, systemImage: "note.text").font(.caption).foregroundStyle(.orange).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            ApproachTrack(eta: first)
        }
        .card()
        .overlay(alignment: .leading) { if let top = NoticeClassifier.summary(model.boardNotices.filter { $0.line == favorite.line }).top { RoundedRectangle(cornerRadius: 3).fill(top.color).frame(width: 5).padding(.vertical, 18).offset(x: 1) } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(favorite.line) hattı, \(favorite.stopName) durağı. " + (first.map { ($0.state == .atStop ? "Araç durakta." : "\(Int($0.minutes.rounded())) dakika.") + ($0.stopsLeft.flatMap { $0 > 0 ? " \($0) durak kaldı." : nil } ?? "") } ?? "Yaklaşan araç yok."))
        .accessibilityHint("Hat ayrıntısını açar")
    }
}

struct FollowedLineCard: View {
    let line: String
    let summary: LineSummary?
    @Environment(AppModel.self) private var model
    var body: some View {
        let color = Theme.color(for: line)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(spacing: 5) {
                    LineBadge(code: line)
                    HStack(spacing: 4) {
                        if (summary?.total ?? 0) > 0 { LiveDot() .scaleEffect(0.7).frame(width: 14, height: 14) }
                        Text(summary.map { "\($0.total) araç" } ?? "…").font(.caption.weight(.heavy)).foregroundStyle(summary?.total == 0 ? Color.secondary : .green).contentTransition(.numericText(value: Double(summary?.total ?? 0)))
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.line(line)?.name ?? "").font(.subheadline.weight(.bold)).lineLimit(2)
                    if let name = summary?.stopName {
                        Label(name + (summary?.stopMeters.map { " · \(Int($0)) m" } ?? ""), systemImage: "location.fill").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else if summary != nil && model.location == nil { Label("Konum açılırsa en yakın durak gösterilir", systemImage: "location.slash").font(.caption2).foregroundStyle(.tertiary) }
                }
                Spacer(minLength: 0)
                if let eta = summary?.eta { ETARing(eta: eta, size: 62) }
                else if summary?.total == 0 { Image(systemName: "moon.zzz.fill").font(.title2).foregroundStyle(.secondary).symbolEffect(.pulse, options: .repeating) }
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            ForEach(summary?.tracks ?? [], id: \.direction) { LineTrackBar(track: $0, color: color) }
        }
        .padding(16)
        .background(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 22))
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(color.opacity(0.45), lineWidth: 1.2))
        .shadow(color: color.opacity(0.25), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(line) hattı takipte. " + (summary.map { "\($0.total) araç yolda." } ?? "") + (summary?.eta.map { " En yakın durak \(summary?.stopName ?? ""), \($0.text)." } ?? ""))
    }
}
