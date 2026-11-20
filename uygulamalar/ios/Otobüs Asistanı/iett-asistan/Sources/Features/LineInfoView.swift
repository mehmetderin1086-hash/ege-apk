import SwiftUI

/// Hat künyesi: tarife, uzunluk, süre, hız, yönler, sefer özeti, duraklar ve her durağın tahmini geçiş saati, duyurular, not.
struct LineInfoView: View {
    let hat: Hat
    @Environment(AppModel.self) private var model
    @State private var route: LineRoute?
    @State private var trips: [PlannedTrip] = []
    @State private var notices: [Duyuru] = []
    @State private var dayType = IETTDates.dayType()
    @State private var direction = "G"

    private var info: LineInfo { LineInfo.compute(hat: hat, route: route) }
    private var stops: [RouteStop] { route?.stops[direction] ?? [] }
    private var times: [Int] { Timetable.times(trips, dayType: dayType, direction: direction) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) { LineBadge(code: hat.code); Text(hat.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }
                general.cascadeIn(0)
                directionsCard.cascadeIn(1)
                if !trips.isEmpty { scheduleSummary.cascadeIn(2) }
                stopsCard.cascadeIn(3)
                ForEach(notices) { notice in
                    Label(notice.message, systemImage: "exclamationmark.triangle.fill").font(.footnote).padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading).background(.yellow.opacity(0.2), in: .rect(cornerRadius: 12))
                }
                NoteCard(key: "line:\(hat.code)", title: "Bu hat için notum")
                NavigationLink(value: Route.timetable(code: hat.code, direction: direction, stop: nil)) {
                    Label("Tüm sefer saatleri", systemImage: "clock.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            .padding(.horizontal).padding(.bottom, 24)
        }
        .background { AuroraBackground() }
        .navigationTitle("Hat bilgisi").navigationBarTitleDisplayMode(.inline)
        .task {
            async let r = model.route(hat.code), t = model.timetable(line: hat.code), n = model.notices(line: hat.code)
            (route, trips, notices) = await (r, t, n)
            if let first = route?.directions.first, !(route?.directions.contains(direction) ?? true) { direction = first }
        }
    }

    private var general: some View {
        VStack(spacing: 0) {
            row("Tarife", hat.tariff ?? "—", "ticket")
            Divider()
            row("Hat uzunluğu", hat.lengthKm.map { String(format: "%.1f km", $0).replacingOccurrences(of: ".", with: ",") } ?? "—", "ruler")
            Divider()
            row("Sefer süresi", info.tripText ?? "—", "timer")
            Divider()
            row("Ortalama hız", info.averageSpeedKmh.map { String(format: "%.0f km/sa", $0) } ?? "—", "speedometer")
            Divider()
            row("Durak sayısı", info.directions.isEmpty ? "—" : info.directions.map { "\($0.code == "G" ? "Gidiş" : "Dönüş") \($0.stopCount)" }.joined(separator: " · "), "mappin.and.ellipse")
        }.card()
    }
    private func row(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack { Label(title, systemImage: icon).font(.subheadline).foregroundStyle(.secondary); Spacer(); Text(value).font(.subheadline.weight(.semibold)).multilineTextAlignment(.trailing) }.padding(.vertical, 9)
    }

    @ViewBuilder private var directionsCard: some View {
        if !info.directions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Yönler", systemImage: "arrow.left.arrow.right").font(.headline)
                ForEach(info.directions, id: \.code) { d in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("→ \(d.destination)").font(.subheadline.weight(.bold)).foregroundStyle(Theme.color(for: hat.code))
                        Text("\(d.firstStop)  ›  \(d.lastStop)").font(.caption).foregroundStyle(.secondary)
                        Text("\(d.stopCount) durak · \(String(format: "%.1f", d.lengthKm).replacingOccurrences(of: ".", with: ",")) km").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).card()
        }
    }

    private var scheduleSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sefer özeti", systemImage: "calendar").font(.headline)
            Picker("Gün", selection: $dayType) { ForEach(Timetable.dayTypes, id: \.code) { Text($0.title).tag($0.code) } }.pickerStyle(.segmented)
            ForEach(route?.directions ?? ["G", "D"], id: \.self) { d in
                let t = Timetable.times(trips, dayType: dayType, direction: d), s = Timetable.summary(t)
                VStack(alignment: .leading, spacing: 2) {
                    Text("→ \(route?.destination(d) ?? d)").font(.subheadline.weight(.semibold))
                    if let s {
                        Text("İlk \(Timetable.format(s.first)) · Son \(Timetable.format(s.last)) · \(s.count) sefer").font(.caption).foregroundStyle(.secondary)
                        if let avg = s.averageGap, let low = s.shortestGap, let high = s.longestGap { Text("Aralık ortalama ~\(Int(avg.rounded())) dk (en sık \(low), en seyrek \(high) dk)").font(.caption2).foregroundStyle(.tertiary) }
                    } else { Text("Bu gün tipinde sefer yok").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }

    /// Her durak için "sıradaki seferin buraya tahmini varışı".
    private var stopsCard: some View {
        let geometry = stops.count >= 2 ? RouteGeometry(stops: stops) : nil
        let now = Timetable.nowMinutes(), today = dayType == IETTDates.dayType()
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Duraklar ve tahmini saatler", systemImage: "list.number").font(.headline)
                Spacer()
            }
            if let route, route.directions.count > 1 {
                Picker("Yön", selection: $direction) { ForEach(route.directions, id: \.self) { Text("→ " + route.destination($0)).tag($0) } }.pickerStyle(.segmented).padding(.vertical, 8)
            }
            Text("Saatler, planlı kalkışa durağın hat üzerindeki konumuna göre süre eklenerek hesaplanır (tahmin).").font(.caption2).foregroundStyle(.secondary).padding(.bottom, 6)
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    let offset = geometry.flatMap { Timetable.offsetMinutes(tripMinutes: hat.tripMinutes, stopAlong: $0.cumulative[index], routeLength: $0.length) } ?? 0
                    let next = Timetable.upcoming(times, offset: offset, nowMinutes: today ? now : 0, count: 2)
                    NavigationLink(value: Route.stop(code: stop.code)) {
                        HStack(spacing: 10) {
                            Text("\(stop.seq)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(stop.name).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                                if model.note(for: "stop:\(stop.code)").isEmpty == false { Label("notun var", systemImage: "note.text").font(.caption2).foregroundStyle(.orange) }
                            }
                            Spacer()
                            if !next.isEmpty { Text(next.map(Timetable.format).joined(separator: " · ")).font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.color(for: hat.code)) }
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }.padding(.vertical, 7)
                    }.buttonStyle(.plain)
                    if index < stops.count - 1 { Divider().padding(.leading, 38) }
                }
            }
        }.card()
    }
}
