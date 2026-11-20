import SwiftUI

/// Tam sefer saati listesi (resmî tablo gibi): gün tipi, yön, saat saat tablo; ÖHO seferleri kırmızı, işaretli saatler "(-1)" ile;
/// sıradaki sefer geri sayımı, notlar kartı ve (durak seçiliyse) durağa tahmini geçiş saati.
struct TimetableView: View {
    let hat: Hat
    var initialDirection: String?
    var stop: Durak?
    @Environment(AppModel.self) private var model
    @State private var trips: [PlannedTrip] = []
    @State private var route: LineRoute?
    @State private var dayType = IETTDates.dayType()
    @State private var direction = "G"
    @State private var atStop = true
    @State private var loaded = false
    @State private var failed = false
    @State private var operatorFilter = 0          // 0 tümü, 1 yalnız İETT, 2 yalnız ÖHO
    @State private var hideMarked = false
    @State private var selected: Timetable.Entry?

    private var directions: [String] { route?.directions ?? Array(Set(trips.map(\.direction))).sorted() }
    private var allEntries: [Timetable.Entry] { Timetable.entries(trips, dayType: dayType, direction: direction) }
    private var entries: [Timetable.Entry] {
        allEntries.filter { entry in
            (operatorFilter == 0 || (operatorFilter == 2) == entry.isOHO) && !(hideMarked && entry.isMarked)
        }
    }
    /// Durak seçiliyse ve güzergâhta varsa: durağın hat üzerindeki konumuna göre kalkışa eklenecek dakika.
    private var stopOffset: Int? {
        guard atStop, let stop, let route, let stops = route.stops[direction], let index = route.stopIndex(code: stop.code, direction: direction) else { return nil }
        let geometry = RouteGeometry(stops: stops)
        return Timetable.offsetMinutes(tripMinutes: hat.tripMinutes, stopAlong: geometry.cumulative[index], routeLength: geometry.length)
    }
    private func label(_ d: String) -> String { route.map { "→ " + $0.destination(d) } ?? (d == "G" ? "Gidiş" : "Dönüş") }
    private var dayTitle: String { Timetable.dayTypes.first { $0.code == dayType }?.title ?? "" }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) { LineBadge(code: hat.code); Text(hat.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                    Picker("Gün", selection: $dayType.animation(.spring(duration: 0.4))) { ForEach(Timetable.dayTypes, id: \.code) { Text($0.title).tag($0.code) } }.pickerStyle(.segmented)
                    if directions.count > 1 {
                        Picker("Yön", selection: $direction.animation(.spring(duration: 0.4))) { ForEach(directions, id: \.self) { Text(label($0)).tag($0) } }.pickerStyle(.segmented)
                    }
                    filters
                    if let stop, stopOffset != nil {
                        Toggle(isOn: $atStop.animation()) { Label("\(stop.name) durağına göre tahmini geçiş", systemImage: "mappin.and.ellipse").font(.subheadline) }
                            .toggleStyle(.switch).card()
                    }
                    content(proxy: proxy)
                }
                .padding(.horizontal).padding(.bottom, 24)
            }
        }
        .background { AuroraBackground() }
        .navigationTitle("Sefer saatleri").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareIconButton(label: "Sefer saatlerini paylaş") { ShareBuilder.timetable(hat, destination: route?.destination(direction) ?? direction, day: dayTitle, entries: entries, offset: stopOffset ?? 0) }
                    .disabled(entries.isEmpty)
            }
        }
        .sheet(item: $selected) { entry in
            EntryDetailSheet(hat: hat, entry: entry, direction: direction, destination: route?.destination(direction) ?? direction, siblings: allEntries.filter { $0.marker == entry.marker && entry.isMarked })
                .presentationDetents([.medium, .large])
        }
        .task {
            async let t = model.timetable(line: hat.code), r = model.route(hat.code)
            let (loadedTrips, loadedRoute) = await (t, r)
            trips = loadedTrips; route = loadedRoute; failed = loadedTrips.isEmpty; loaded = true
            if let initialDirection, directions.contains(initialDirection) { direction = initialDirection }
            else if let first = directions.first, !directions.contains(direction) { direction = first }
            if let stop, let own = route?.directions(serving: stop.code), !own.isEmpty, initialDirection == nil { direction = own[0] }
        }
    }

    /// Resmî tablodaki gibi: İETT / ÖHO ayrımı ve işaretli saatleri gizleme.
    @ViewBuilder private var filters: some View {
        let hasOHO = allEntries.contains(where: \.isOHO), hasMarked = allEntries.contains(where: \.isMarked)
        if hasOHO || hasMarked {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if hasOHO {
                        ForEach([(0, "Tümü", "bus"), (1, "İETT", "building.columns"), (2, "ÖHO", "bus.doubledecker")], id: \.0) { item in
                            Button { withAnimation(.spring(duration: 0.35)) { operatorFilter = item.0 } } label: {
                                Label(item.1, systemImage: item.2).font(.footnote.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(operatorFilter == item.0 ? (item.0 == 2 ? Color.red : Theme.accent) : Color.secondary.opacity(0.15), in: .capsule)
                                    .foregroundStyle(operatorFilter == item.0 ? Color.white : Color.primary)
                            }.buttonStyle(.plain)
                        }
                    }
                    if hasMarked {
                        Button { withAnimation(.spring(duration: 0.35)) { hideMarked.toggle() } } label: {
                            Label(hideMarked ? "İşaretliler gizli" : "İşaretliler açık", systemImage: hideMarked ? "eye.slash" : "number.circle").font(.footnote.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 7)
                                .background(hideMarked ? Color.orange : Color.secondary.opacity(0.15), in: .capsule).foregroundStyle(hideMarked ? Color.white : Color.primary)
                        }.buttonStyle(.plain)
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: operatorFilter)
        }
    }

    @ViewBuilder private func content(proxy: ScrollViewProxy) -> some View {
        if !loaded { ProgressView("Sefer saatleri yükleniyor…").frame(maxWidth: .infinity).padding(40) }
        else if failed { ContentUnavailableView("Sefer saati bulunamadı", systemImage: "clock.badge.xmark", description: Text("Bu hat için planlı sefer verisi yok ya da bağlantı kurulamadı.")) }
        else if allEntries.isEmpty { ContentUnavailableView("Bu gün tipinde sefer yok", systemImage: "calendar.badge.exclamationmark", description: Text("Başka bir gün tipini dene.")) }
        else if entries.isEmpty { ContentUnavailableView("Filtreye uyan sefer yok", systemImage: "line.3.horizontal.decrease.circle", description: Text("Filtreleri değiştir.")) }
        else {
            let offset = stopOffset ?? 0
            let shown = Array(Set(entries.map { $0.minutes + offset })).sorted()
            TimelineView(.periodic(from: .now, by: 20)) { context in
                let nowMin = Timetable.nowMinutes(context.date)
                let isToday = dayType == IETTDates.dayType(context.date)
                let nextIndex = isToday ? Timetable.nextIndex(shown, nowMinutes: nowMin) : nil
                VStack(alignment: .leading, spacing: 14) {
                    nextCard(shown: shown, nextIndex: nextIndex, nowMin: nowMin, isToday: isToday, offset: offset).cascadeIn(0)
                    summaryCard(shown: shown).cascadeIn(1)
                    gridCard(offset: offset, nextMinute: nextIndex.map { shown[$0] }, isToday: isToday, nowMin: nowMin).cascadeIn(2)
                    notesCard.cascadeIn(3)
                }
                .onChange(of: nextIndex) { if let nextIndex { withAnimation { proxy.scrollTo("h\(shown[nextIndex] / 60)", anchor: .center) } } }
                .task(id: dayType + direction) { if let nextIndex { try? await Task.sleep(for: .milliseconds(300)); withAnimation { proxy.scrollTo("h\(shown[nextIndex] / 60)", anchor: .center) } } }
            }
        }
    }

    private func nextCard(shown: [Int], nextIndex: Int?, nowMin: Int, isToday: Bool, offset: Int) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isToday ? (offset > 0 ? "Durağa sıradaki geçiş" : "Sıradaki kalkış") : "İlk sefer").font(.caption).foregroundStyle(.secondary)
                if let nextIndex {
                    Text(Timetable.format(shown[nextIndex])).font(.system(size: 44, weight: .heavy, design: .rounded)).foregroundStyle(Theme.color(for: hat.code)).contentTransition(.numericText())
                    let wait = shown[nextIndex] - nowMin
                    Text(wait <= 0 ? "şimdi" : wait < 60 ? "\(wait) dk sonra" : "\(wait / 60) sa \(wait % 60) dk sonra").font(.subheadline.weight(.semibold))
                } else if isToday {
                    Text("Bugün sefer bitti").font(.title3.bold())
                    if let first = shown.first { Text("Yarın ilk sefer \(Timetable.format(first))").font(.subheadline).foregroundStyle(.secondary) }
                } else if let first = shown.first {
                    Text(Timetable.format(first)).font(.system(size: 44, weight: .heavy, design: .rounded)).foregroundStyle(Theme.color(for: hat.code))
                }
            }
            Spacer()
            if let nextIndex, isToday {
                let gap = nextIndex + 1 < shown.count ? shown[nextIndex + 1] - shown[nextIndex] : nil
                VStack(alignment: .trailing, spacing: 6) {
                    if nextIndex + 1 < shown.count { VStack(alignment: .trailing, spacing: 0) { Text("Ondan sonra").font(.caption2).foregroundStyle(.secondary); Text(Timetable.format(shown[nextIndex + 1])).font(.headline.monospacedDigit()) } }
                    if let gap { Text("her ~\(gap) dk").font(.caption).padding(.horizontal, 8).padding(.vertical, 3).background(.quaternary, in: .capsule) }
                }
            }
        }
        .card()
    }

    private func summaryCard(shown: [Int]) -> some View {
        let s = Timetable.summary(shown)
        return HStack {
            stat("İlk", s.map { Timetable.format($0.first) } ?? "—", "sun.max")
            Divider()
            stat("Son", s.map { Timetable.format($0.last) } ?? "—", "moon.stars")
            Divider()
            stat("Sefer", s.map { "\($0.count)" } ?? "—", "bus")
            Divider()
            stat("Aralık", s?.averageGap.map { "~\(Int($0.rounded())) dk" } ?? "—", "arrow.left.and.right")
        }
        .card()
    }
    private func stat(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 3) { Image(systemName: icon).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline.bold().monospacedDigit()); Text(title).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity)
    }

    /// Saat saat tablo: ÖHO kırmızı, İETT siyah; işaretli saatlerde "(-1)" ve kesik çerçeve; dokununca ayrıntı.
    private func gridCard(offset: Int, nextMinute: Int?, isToday: Bool, nowMin: Int) -> some View {
        let rows = Timetable.byHourEntries(entries, offset: offset)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Tüm seferler · \(dayTitle)", systemImage: "list.bullet.clipboard").font(.headline)
                Spacer()
                if entries.contains(where: \.isOHO) { legendDot(.red, "ÖHO"); legendDot(.primary, "İETT") }
            }.padding(.bottom, 10)
            ForEach(rows, id: \.hour) { row in
                HStack(alignment: .top, spacing: 12) {
                    Text(String(format: "%02d", row.hour % 24)).font(.title3.weight(.heavy).monospacedDigit()).frame(width: 34, alignment: .trailing)
                        .foregroundStyle(isToday && row.hour == nowMin / 60 ? Theme.color(for: hat.code) : .primary)
                    FlowRow(spacing: 6) {
                        ForEach(row.entries) { entry in chip(entry, offset: offset, nextMinute: nextMinute, isToday: isToday, nowMin: nowMin) }
                    }
                }
                .padding(.vertical, 6).id("h\(row.hour)")
                if row.hour != rows.last?.hour { Divider().padding(.leading, 46) }
            }
        }
        .card()
    }
    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 8, height: 8); Text(text).font(.caption2.weight(.semibold)).foregroundStyle(.secondary) }
    }
    private func chip(_ entry: Timetable.Entry, offset: Int, nextMinute: Int?, isToday: Bool, nowMin: Int) -> some View {
        let total = entry.minutes + offset
        let isNext = nextMinute == total
        let past = isToday && total < nowMin
        let base: Color = entry.isOHO ? .red : .primary
        return Button { selected = entry } label: {
            HStack(spacing: 2) {
                Text(String(format: "%02d", total % 60)).font(.subheadline.monospacedDigit().weight(isNext ? .heavy : .regular))
                if let marker = entry.markerText { Text(marker).font(.system(size: 9, weight: .bold)) }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(isNext ? Theme.color(for: hat.code) : Color.secondary.opacity(0.12), in: .capsule)
            .overlay { if entry.isMarked && !isNext { Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2])).foregroundStyle(Color.orange.opacity(0.8)) } }
            .foregroundStyle(isNext ? Color.white : past ? base.opacity(0.35) : base)
            .scaleEffect(isNext ? 1.12 : 1)
            .animation(.spring(duration: 0.5, bounce: 0.4), value: isNext)
        }.buttonStyle(.plain)
        .accessibilityLabel("Saat \(Timetable.format(total))" + (entry.isOHO ? ", ÖHO seferi" : "") + (entry.isMarked ? ", işaret \(entry.marker)" : "") + (isNext ? ", sıradaki sefer" : past ? ", geçti" : ""))
    }

    /// Resmî sayfadaki "Notlar" gibi: renk açıklaması, işaretlerin anlamı (veriden), sefer türleri ve kendi notun.
    private var notesCard: some View {
        let groups = Timetable.markerGroups(entries), types = Timetable.serviceTypeCounts(entries)
        return VStack(alignment: .leading, spacing: 12) {
            Label("Notlar", systemImage: "note.text").font(.headline)
            if entries.contains(where: \.isOHO) {
                Text("Kırmızı renkli seferler ÖHO (özel halk otobüsü); siyah renkli seferler İETT'ye aittir.").font(.subheadline)
            }
            ForEach(groups, id: \.marker) { group in
                let mine = model.note(for: "marker:\(hat.code):\(direction):\(group.marker)")
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("(\(group.marker))").font(.subheadline.weight(.heavy)).padding(.horizontal, 8).padding(.vertical, 2).background(Color.orange.opacity(0.25), in: .capsule)
                        Text("işaretli \(group.count) sefer").font(.subheadline.weight(.semibold))
                    }
                    Text("Saatler: " + group.sampleTimes.map(Timetable.format).joined(separator: ", ") + (group.count > group.sampleTimes.count ? " …" : "")).font(.caption).foregroundStyle(.secondary)
                    Text("Asıl güzergâhtan farklı bir güzergâh koduyla çıkar: " + group.routeCodes.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    if !mine.isEmpty { Label(mine, systemImage: "note.text").font(.caption).foregroundStyle(.orange) }
                }
            }
            if !groups.isEmpty {
                Text("İETT açık verisi işaretin ayrıntısını (hangi duraktan başladığı gibi) vermez; saate dokunup kendi açıklamanı ekleyebilirsin.").font(.caption2).foregroundStyle(.tertiary)
            }
            if types.count > 0 {
                FlowRow(spacing: 6) {
                    ForEach(types, id: \.type) { item in
                        Text("\(item.type) · \(item.count)").font(.caption2.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4).background(.quaternary, in: .capsule)
                    }
                }
            }
            Divider()
            NoteCard(key: "line:\(hat.code)", title: "Bu hat için notum")
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }
}

/// İşaretli ya da normal bir saatin ayrıntısı: yön, sefer türü, güzergâh kodu, aynı işaretli diğer saatler ve açıklama notu.
struct EntryDetailSheet: View {
    let hat: Hat
    let entry: Timetable.Entry
    let direction: String
    let destination: String
    let siblings: [Timetable.Entry]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Text(Timetable.format(entry.minutes)).font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(entry.isOHO ? .red : .primary)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) { LineBadge(code: hat.code); if let m = entry.markerText { Text(m).font(.headline.weight(.heavy)).foregroundStyle(.orange) } }
                            Text("→ \(destination)").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Sefer bilgisi") {
                    LabeledContent("İşletmeci", value: entry.isOHO ? "ÖHO (özel halk otobüsü)" : "İETT")
                    if !entry.serviceTypes.isEmpty { LabeledContent("Sefer türü", value: entry.serviceTypes.joined(separator: ", ")) }
                    if !entry.routeCode.isEmpty { LabeledContent("Güzergâh kodu", value: entry.routeCode) }
                    LabeledContent("Güzergâh", value: entry.isVariant ? "Asıl güzergâhtan farklı" : "Asıl güzergâh")
                }
                if entry.isMarked {
                    Section("İşaret \(entry.markerText ?? "")") {
                        Text("Bu işaretli saatlerde sefer asıl güzergâhtan farklı bir noktadan/güzergâhla çıkar. Resmî sitedeki işaret notuna bakabilir, aşağıya kendi açıklamanı ekleyebilirsin.").font(.footnote).foregroundStyle(.secondary)
                        NoteCard(key: "marker:\(hat.code):\(direction):\(entry.marker)", title: "İşaret açıklamam")
                            .listRowInsets(.init()).listRowBackground(Color.clear)
                    }
                    Section("Aynı işaretli diğer saatler") {
                        FlowRow(spacing: 6) { ForEach(siblings) { Text(Timetable.format($0.minutes)).font(.caption.monospacedDigit()).padding(.horizontal, 8).padding(.vertical, 4).background($0.id == entry.id ? Color.orange.opacity(0.3) : Color.secondary.opacity(0.12), in: .capsule) } }
                    }
                }
            }
            .navigationTitle("Sefer ayrıntısı").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { dismiss() } } }
        }
    }
}

/// Basit sarmalayan satır (dakika kapsülleri sığmazsa alta iner).
struct FlowRow: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(in: proposal.width ?? 300, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, origin) in layout(in: bounds.width, subviews: subviews).origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }
    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        var origins: [CGPoint] = []
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y)); x += size.width + spacing; rowHeight = max(rowHeight, size.height); maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
