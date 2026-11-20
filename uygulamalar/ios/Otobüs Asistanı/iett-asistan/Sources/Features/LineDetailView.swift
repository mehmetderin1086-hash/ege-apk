import MapKit
import SwiftUI

struct LineDetailView: View {
    let hat: Hat
    var preselected: Favorite?
    @Environment(AppModel.self) private var model
    @State private var buses: [Bus] = []
    @State private var trips: [PlannedTrip] = []
    @State private var notices: [Duyuru] = []
    @State private var route: LineRoute?
    @State private var direction = "G"
    @State private var selectedStop: Durak?
    @State private var camera: MapCameraPosition = .automatic
    @State private var visibleStops: [Durak] = []
    @State private var updated: Date?
    @State private var searchText = ""
    @State private var editing: Favorite?
    @State private var following = false

    private var isFollowed: Bool { model.favorites.contains { $0.line == hat.code } }
    private var routeStops: [RouteStop] { route?.stops[direction] ?? [] }
    private var shownBuses: [Bus] { buses.filter { $0.direction == direction } }
    private var etas: [BusETA] {
        guard let stop = selectedStop else { return [] }
        if let route, !route.directions(serving: stop.code).isEmpty { return RouteETAEngine.etas(buses: buses, route: route, stopCode: stop.code, hat: hat, tracker: model.tracker) }
        return model.tracker.etas(buses: buses, stop: stop.coordinate, stopCode: stop.code)
    }
    private var busesByStop: [Int: [Bus]] {
        guard let route else { return [:] }
        var map: [Int: [Bus]] = [:]
        for bus in shownBuses { if let index = RouteETAEngine.stopIndex(of: bus, in: route) { map[index, default: []].append(bus) } }
        return map
    }
    private func label(_ direction: String) -> String { route.map { "→ " + $0.destination(direction) } ?? (direction == "G" ? "Gidiş" : "Dönüş") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    LineBadge(code: hat.code)
                    Text(hat.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    if model.liveError == nil { LiveDot() }
                    ShareIconButton(label: "Hattı paylaş") {
                        ShareBuilder.line(hat, total: buses.count, byDirection: Dictionary(grouping: buses, by: \.direction).mapValues(\.count),
                                          nextDepartures: Timetable.next(trips, direction: direction, count: 3), nearestStop: selectedStop?.name, eta: etas.first)
                    }
                }
                // Belirgin Takip düğmesi: hattın duraklarını açar, durağa dokununca takibe alır.
                HStack(spacing: 10) {
                    Button { withAnimation(.spring(duration: 0.4)) { model.toggleFollow(line: hat.code) } } label: {
                        Label(model.isFollowing(line: hat.code) ? "Hat takipte" : "Hattı takip et", systemImage: model.isFollowing(line: hat.code) ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background((model.isFollowing(line: hat.code) ? Color.green : Theme.accent).opacity(0.18), in: .rect(cornerRadius: 14))
                            .foregroundStyle(model.isFollowing(line: hat.code) ? Color.green : Theme.accent)
                    }.buttonStyle(.plain).sensoryFeedback(.success, trigger: model.isFollowing(line: hat.code))
                    Button { following = true } label: {
                        Label(isFollowed ? "Duraklar" : "Durak ekle", systemImage: "mappin.and.ellipse").font(.subheadline.weight(.bold)).padding(.vertical, 10).padding(.horizontal, 14)
                            .background(Color.secondary.opacity(0.15), in: .rect(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }
                Picker("Yön", selection: $direction.animation(.spring(duration: 0.5))) {
                    ForEach(route?.directions ?? ["G", "D"], id: \.self) { Text(label($0)).tag($0) }
                }.pickerStyle(.segmented)

                if let error = model.liveError {
                    Label(error, systemImage: "wifi.exclamationmark").font(.footnote).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.15), in: .rect(cornerRadius: 12))
                }
                mapView.cascadeIn(0)
                stopCard.cascadeIn(1)
                timeline.cascadeIn(2)
                scheduleCard.cascadeIn(3)
                ForEach(notices) { notice in
                    Label(notice.message, systemImage: "exclamationmark.triangle.fill").font(.footnote).padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading).background(.yellow.opacity(0.2), in: .rect(cornerRadius: 12))
                }
                NoteCard(key: "line:\(hat.code)", title: "Bu hat için notum")
                if let age = model.liveAge {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("Canlı veri \(age, style: .relative) önce · İETT kotası: kalan \(model.quotaRemaining)/\(FleetBudget.hourlyLimit) istek/saat")
                    }.font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
        .background { AuroraBackground() }
        .sensoryFeedback(.selection, trigger: selectedStop?.code)
        .sheet(item: $editing) { AlertRuleEditor(favorite: $0, initial: model.rule(for: $0)) }
        .sheet(isPresented: $following) { FollowSheet(hat: hat) }
        .navigationTitle(hat.code).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { VStack(spacing: 0) { Text(hat.code).font(.headline); Text(hat.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1) } }
            // Ayrı öğeler: aynı grupta olunca dokunuş yanındaki bilgi bağlantısına gidebiliyordu.
            ToolbarItem(placement: .topBarTrailing) {
                Button { following = true } label: { Image(systemName: isFollowed ? "checkmark.circle.fill" : "plus.circle.fill") }
                    .accessibilityLabel(isFollowed ? "Takipte, durakları yönet" : "Hattı takibe al")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.lineInfo(code: hat.code)) { Image(systemName: "info.circle") }.accessibilityLabel("Hat bilgisi")
            }
        }
        .task {
            if let preselected {
                selectedStop = Durak(code: preselected.stopCode, name: preselected.stopName, lat: preselected.lat, lon: preselected.lon)
            }
            async let t = model.timetable(line: hat.code), n = model.notices(line: hat.code), r = model.route(hat.code)
            (trips, notices, route) = await (t, n, r)
            if let route {
                if let code = selectedStop?.code, let own = route.directions(serving: code).first { direction = own }
                else if !route.directions.contains(direction), let first = route.directions.first { direction = first }
            }
            if preselected == nil { fitRoute() }
            model.viewedLine = hat.code
            model.noteVisit(line: hat.code)
            defer { model.viewedLine = nil }
            while !Task.isCancelled {
                let fresh = await model.buses(line: hat.code)
                withAnimation(.spring(duration: 0.8)) { buses = fresh }
                updated = .now
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .onChange(of: direction) { if selectedStop == nil { fitRoute() } }
    }

    /// Haritayı seçili yönün güzergâhına sığdırır (araç görünmese de hat yerinde gözüksün).
    private func fitRoute() {
        let points = routeStops.map(\.coordinate)
        guard points.count >= 2 else { return }
        var rect = MKMapRect.null
        for point in points { rect = rect.union(MKMapRect(origin: MKMapPoint(point), size: .init(width: 0, height: 0))) }
        camera = .rect(rect.insetBy(dx: -rect.width * 0.1, dy: -rect.height * 0.1))
    }

    private var mapView: some View {
        Map(position: $camera) {
            UserAnnotation()
            if routeStops.count >= 2 {
                MapPolyline(coordinates: routeStops.map(\.coordinate)).stroke(.white, lineWidth: 8)
                MapPolyline(coordinates: routeStops.map(\.coordinate)).stroke(Theme.color(for: hat.code), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            ForEach(routeStops.isEmpty ? visibleStops : routeStops.map { Durak(code: $0.code, name: $0.name, lat: $0.lat, lon: $0.lon) }) { stop in
                Annotation(stop.name, coordinate: stop.coordinate, anchor: .center) {
                    Button { selectedStop = stop } label: {
                        Circle().fill(selectedStop?.code == stop.code ? .orange : .white).frame(width: selectedStop?.code == stop.code ? 18 : 10, height: selectedStop?.code == stop.code ? 18 : 10)
                            .overlay(Circle().stroke(.blue, lineWidth: 2))
                    }
                }
            }
            ForEach(shownBuses) { bus in
                Annotation(bus.plate, coordinate: bus.coordinate, anchor: .center) { BusMarker(heading: model.tracker.heading(of: bus.id), tint: Theme.color(for: hat.code)) }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls { MapUserLocationButton(); MapCompass() }
        .onMapCameraChange(frequency: .onEnd) { context in
            let r = context.region
            visibleStops = routeStops.isEmpty && r.span.latitudeDelta < 0.04 ? model.stops(inRegionCenter: r.center, latSpan: r.span.latitudeDelta, lonSpan: r.span.longitudeDelta) : []
        }
        .frame(height: 340).clipShape(.rect(cornerRadius: 18))
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right").symbolEffect(.pulse)
                Text(model.liveError != nil ? "Canlı veri alınamıyor" : "\(shownBuses.count) araç canlı").font(.caption.bold())
            }.padding(8).background(.ultraThinMaterial, in: .capsule).padding(8)
        }
    }

    @ViewBuilder private var stopCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let stop = selectedStop {
                let favorite = model.favorites.first { $0.line == hat.code && $0.stopCode == stop.code }
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(stop.name).font(.title3.weight(.heavy))
                        if !stop.district.isEmpty { Text(stop.district).font(.subheadline.weight(.medium)).foregroundStyle(.secondary) }
                        DirectionTag(text: stop.direction)
                        Label("Bu hatta \(label(direction))", systemImage: "bus.fill").font(.subheadline.weight(.bold)).foregroundStyle(Theme.color(for: hat.code))
                    }
                    Spacer()
                    ShareIconButton(label: "Durağı paylaş") { ShareBuilder.favorite(Favorite(line: hat.code, stopCode: stop.code, stopName: stop.name, lat: stop.lat, lon: stop.lon), etas: etas) }
                    Button(favorite != nil ? "Takipte" : "Takip et", systemImage: favorite != nil ? "checkmark" : "plus") { model.toggleFavorite(line: hat.code, stop: stop) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
                if let favorite {
                    Button { editing = favorite } label: {
                        Label(model.rule(for: favorite)?.enabled == true ? "Bildirimler açık · ayarla" : "Bildirim ayarları", systemImage: model.rule(for: favorite)?.enabled == true ? "bell.fill" : "bell")
                    }.font(.footnote)
                }
                if etas.isEmpty {
                    Text("Bu durağa yaklaşan canlı araç görünmüyor.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 14) {
                        ETARing(eta: etas.first, size: 76)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(etas[0].state == .atStop ? "Durakta" : "En yakın araç").font(.caption).foregroundStyle(.secondary)
                            Text(etas[0].id).font(.title3.monospaced().bold())
                            if let left = etas[0].stopsLeft, left > 0 { Text("\(left) durak kaldı").font(.subheadline).foregroundStyle(.secondary) }
                        }
                        Spacer()
                    }
                    ForEach(etas.dropFirst().prefix(3)) { eta in
                        HStack {
                            Image(systemName: "bus.fill").foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(eta.id).font(.subheadline.monospaced())
                                Text([eta.stopsLeft.map { $0 > 0 ? "\($0) durak kaldı" : nil } ?? nil, eta.distanceText].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(eta.text).font(.title3.bold()).foregroundStyle(eta.state == .estimated ? .orange : .green).contentTransition(.numericText())
                        }
                    }
                    Text(route == nil ? "Güzergâh yüklenemedi; süre kuş uçuşu tahmindir (“~”)." : "Süre aracın hat üzerindeki canlı konumundan hesaplanır.").font(.caption2).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Başka durak seç", systemImage: "xmark.circle") { selectedStop = nil }.font(.footnote)
                    Spacer()
                    NavigationLink(value: Route.stop(code: stop.code)) { Label("Durak bilgisi ve saatler", systemImage: "info.circle") }.font(.footnote.weight(.semibold))
                }
            } else {
                Label("Haritada ya da aşağıdaki listede bir durağa dokun: kaç dakika ve kaç durak kaldığını göster; seçince “Takip et” çıkar.", systemImage: "hand.tap").font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Bu hatta durak ara", text: $searchText).textInputAutocapitalization(.never).autocorrectionDisabled()
                }.padding(10).background(.quaternary, in: .rect(cornerRadius: 10))
                let needle = fold(searchText)
                ForEach(needle.isEmpty ? [] : routeStops.filter { fold($0.name).contains(needle) }.prefix(5)) { stop in
                    Button { selectedStop = Durak(code: stop.code, name: stop.name, lat: stop.lat, lon: stop.lon); searchText = ""; camera = .region(.init(center: stop.coordinate, span: .init(latitudeDelta: 0.012, longitudeDelta: 0.012))) } label: {
                        HStack { Text(stop.name); Spacer(); Text("\(stop.seq). durak").font(.caption).foregroundStyle(.secondary) }
                    }.buttonStyle(.plain)
                }
            }
        }
        .card().frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Hattın durakları; yoldaki araçlar bulundukları duraklar arasına yerleşir (Moovit/Transit tarzı).
    @ViewBuilder private var timeline: some View {
        if !routeStops.isEmpty {
            let byStop = busesByStop
            VStack(alignment: .leading, spacing: 0) {
                Label("Duraklar · \(label(direction))", systemImage: "point.topleft.down.curvedto.point.bottomright.up").font(.headline).padding(.bottom, 8)
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(routeStops.enumerated()), id: \.element.id) { index, stop in
                        let selected = selectedStop?.code == stop.code
                        Button { selectedStop = Durak(code: stop.code, name: stop.name, lat: stop.lat, lon: stop.lon) } label: {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(spacing: 0) {
                                    Rectangle().fill(.blue.opacity(index == 0 ? 0 : 0.5)).frame(width: 3, height: 14)
                                    Circle().fill(selected ? .orange : .white).frame(width: 12, height: 12).overlay(Circle().stroke(.blue, lineWidth: 2.5))
                                    Rectangle().fill(.blue.opacity(index == routeStops.count - 1 ? 0 : 0.5)).frame(width: 3, height: 14)
                                }
                                Text(stop.name).font(selected ? .subheadline.bold() : .subheadline).foregroundStyle(.primary)
                                Spacer()
                                if let here = byStop[index] {
                                    HStack(spacing: 3) { Image(systemName: "bus.fill").symbolEffect(.pulse); Text(here.map(\.plate).joined(separator: ", ")).font(.caption2.monospaced()) }
                                        .padding(.horizontal, 8).padding(.vertical, 3).background(Theme.color(for: hat.code), in: .capsule).foregroundStyle(.white)
                                        .transition(.scale.combined(with: .opacity))
                                }
                                if selected, let first = etas.first { Text(first.text).font(.subheadline.bold()).foregroundStyle(.green) }
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
            .card()
        } else if route == nil {
            ProgressView("Güzergâh yükleniyor…").frame(maxWidth: .infinity).padding()
        }
    }

    @ViewBuilder private var scheduleCard: some View {
        let next = Timetable.next(trips, direction: direction, count: 4)
        let all = Timetable.departures(trips, direction: direction)
        VStack(alignment: .leading, spacing: 8) {
            Label("Planlı kalkışlar (\(label(direction)))", systemImage: "clock").font(.headline)
            NavigationLink(value: Route.timetable(code: hat.code, direction: direction, stop: selectedStop?.code)) {
                Label("Tüm sefer saatlerini aç", systemImage: "list.bullet.clipboard").font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if next.isEmpty { Text(all.isEmpty ? "Bu yön için tarife bulunamadı." : "Bugün için kalan sefer yok.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(next, id: \.time) { item in
                HStack { Text(item.time).font(.title3.monospacedDigit().bold()); Spacer(); Text(item.minutes == 0 ? "şimdi" : "\(item.minutes) dk sonra").foregroundStyle(.secondary) }
            }
            if all.count > next.count {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(all.filter { $0.date >= .now }.dropFirst(next.count).prefix(24), id: \.time) { Text($0.time).font(.caption.monospacedDigit()).padding(.horizontal, 8).padding(.vertical, 4).background(.quaternary, in: .capsule) } }
                }
            }
        }
        .card().frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BusMarker: View {
    let heading: Double?, tint: Color
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.6), lineWidth: 2).frame(width: 30, height: 30).scaleEffect(pulse ? 2.0 : 1).opacity(pulse ? 0 : 0.8)
            Circle().fill(tint.gradient).frame(width: 32, height: 32).overlay(Circle().stroke(.white, lineWidth: 2)).shadow(radius: 3)
            Image(systemName: heading == nil ? "bus.fill" : "location.north.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                .rotationEffect(.degrees(heading ?? 0))
        }
        .animation(.spring(duration: 0.9, bounce: 0.3), value: heading)
        .onAppear { withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true } }
        .accessibilityElement(children: .ignore).accessibilityLabel("Canlı otobüs")
    }
}
