import MapKit
import SwiftUI

/// Yakınımda sekmesi: Liste / Harita / Rota planla.
struct NearbyView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @AppStorage("nearby.mode") private var mode = 0

    var body: some View {
        Group {
            switch mode {
            case 1: NearbyMapView()
            case 2: TripPlannerView()
            case 3: RailStationsView()
            default: list
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Görünüm", selection: $mode.animation(.spring(duration: 0.4))) {
                Text("Durak").tag(0); Text("Harita").tag(1); Text("Rota").tag(2); Text("Raylı").tag(3)
            }.pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 6).background(.bar)
        }
        .navigationTitle(mode == 2 ? "Rota planla" : mode == 3 ? "Raylı sistem" : "Yakınımda").navigationBarTitleDisplayMode(.inline)
        .onAppear { model.requestLocation() }
    }

    private var list: some View {
        List {
            Section { SyncBanner() }.listRowBackground(Color.clear)
            if model.authorization == .denied || model.authorization == .restricted {
                Text("Konum izni kapalı. Yakın durakları görmek için Ayarlar'dan izin ver; ya da yukarıdan durak ara.").font(.footnote).foregroundStyle(.secondary)
            }
            if query.isEmpty, !model.recentStops.isEmpty {
                Section { ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(model.recentStops, id: \.self) { code in
                    if let stop = model.stop(code: code) { NavigationLink(value: Route.stop(code: code)) { Text(stop.name).font(.caption.weight(.semibold)).lineLimit(1).padding(.horizontal, 12).padding(.vertical, 7).background(.regularMaterial, in: .capsule) }.buttonStyle(.plain) }
                } } } } header: { Label("Son baktığın duraklar", systemImage: "clock.arrow.circlepath") }
            }
            if !query.isEmpty {
                ForEach(model.searchStops(query, near: model.location?.coordinate, limit: 30)) { stop in row(stop, meters: model.location.map { $0.coordinate.distance(to: stop.coordinate) }) }
            } else if let here = model.location?.coordinate {
                Section("En yakın duraklar") { ForEach(Array(model.nearestStops(to: here).enumerated()), id: \.element.stop.id) { index, item in row(item.stop, meters: item.meters).cascadeIn(index) } }
            } else {
                Button("Konumumu kullan", systemImage: "location") { model.requestLocation() }
            }
        }
        .scrollContentBackground(.hidden).background { AuroraBackground() }
        .searchable(text: $query, prompt: "Durak ara (örn. Üsküdar)")
        .refreshable { model.requestLocation() }
    }

    private func row(_ stop: Durak, meters: Double?) -> some View {
        NavigationLink(value: Route.stop(code: stop.code)) {
            HStack(spacing: 12) {
                Image(systemName: stop.smart ? "display" : "signpost.right.fill").foregroundStyle(Theme.accent).frame(width: 26)
                VStack(alignment: .leading, spacing: 5) {
                    Text(stop.name).font(.title3.weight(.bold))
                    if !stop.district.isEmpty { Label(stop.district, systemImage: "building.2").font(.subheadline.weight(.medium)).foregroundStyle(.secondary) }
                    DirectionTag(text: stop.direction)
                }
                Spacer()
                if model.isFavoriteStop(stop.code) { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
                if let meters { Text(meters < 1000 ? "\(Int(meters)) m" : String(format: "%.1f km", meters / 1000)).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary) }
            }
        }
        .swipeActions(edge: .leading) {
            Button(model.isFavoriteStop(stop.code) ? "Favoriden çıkar" : "Favori yap", systemImage: model.isFavoriteStop(stop.code) ? "star.slash" : "star") { withAnimation(.spring) { model.toggleFavoriteStop(stop.code) } }.tint(.yellow)
        }
    }
}

/// Durak haritası: yakınlaştırdıkça görünür bölgedeki duraklar çıkar; dokununca özet kart.
struct NearbyMapView: View {
    @Environment(AppModel.self) private var model
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var visible: [Durak] = []
    @State private var selected: Durak?
    var body: some View {
        Map(position: $camera) {
            UserAnnotation()
            ForEach(visible) { stop in
                Annotation(stop.name, coordinate: stop.coordinate, anchor: .bottom) {
                    Button { withAnimation(.spring(duration: 0.35)) { selected = stop } } label: {
                        Image(systemName: stop.smart ? "display" : "bus.fill").font(.caption.bold()).foregroundStyle(.white).padding(6)
                            .background(selected?.code == stop.code ? Color.orange : Theme.accent, in: .circle).overlay(Circle().stroke(.white, lineWidth: 2))
                            .scaleEffect(selected?.code == stop.code ? 1.3 : 1)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls { MapUserLocationButton(); MapCompass(); MapScaleView() }
        .onMapCameraChange(frequency: .onEnd) { context in
            let r = context.region
            visible = r.span.latitudeDelta < 0.03 ? model.stops(inRegionCenter: r.center, latSpan: r.span.latitudeDelta, lonSpan: r.span.longitudeDelta, limit: 120) : []
        }
        .overlay(alignment: .top) {
            if visible.isEmpty { Label("Durakları görmek için haritayı yakınlaştır", systemImage: "plus.magnifyingglass").font(.caption.bold()).padding(8).background(.regularMaterial, in: .capsule).padding(.top, 8) }
        }
        .overlay(alignment: .bottom) {
            if let stop = selected {
                NavigationLink(value: Route.stop(code: stop.code)) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stop.name).font(.headline).foregroundStyle(.primary)
                            Text([stop.district, stop.direction].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label("Aç", systemImage: "chevron.right").labelStyle(.titleAndIcon).font(.subheadline.weight(.bold))
                    }.card().padding()
                }.buttonStyle(.plain).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sensoryFeedback(.selection, trigger: selected?.code)
    }
}

/// İBB Metro İstanbul servisindeki her kayıt hat- istasyon çiftidir.
struct RailStation: Codable, Identifiable, Hashable {
    struct Details: Codable, Hashable {
        let Latitude: String?, Longitude: String?
        let Lift: Int?, Escolator: Int?, WC: Bool?
    }
    let Id: Int
    let Description: String
    let LineName: String
    let Order: Int
    let IsActive: Bool?
    let DetailInfo: Details?
    var id: String { "\(LineName):\(Id)" }
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = DetailInfo?.Latitude.flatMap(Double.init), let lon = DetailInfo?.Longitude.flatMap(Double.init),
              (40.5...41.6).contains(lat), (27.5...30.0).contains(lon) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

struct RailResponse: Decodable {
    let Success: Bool
    let Data: [FailableDecodable<RailStation>]
    var stations: [RailStation] { Data.compactMap(\.value).filter { $0.IsActive != false && !$0.LineName.isEmpty && !$0.Description.isEmpty } }
}

struct RailServiceStatus: Decodable, Identifiable {
    let LineName: String, Description: String, UpdateDate: String?
    let IsActive: Bool?
    var id: String { LineName + "|" + Description }
}

struct RailStatusResponse: Decodable {
    let Success: Bool
    let Data: [FailableDecodable<RailServiceStatus>]
    var active: [RailServiceStatus] { Data.compactMap(\.value).filter { $0.IsActive != false && !$0.Description.isEmpty } }
}

actor RailStationStore {
    static let shared = RailStationStore()
    struct Snapshot: Codable {
        let stations: [RailStation]
        let fetchedAt: Date
    }
    private let cache = URL.cachesDirectory.appending(path: "metro-stations-v1.json")
    func cached() -> Snapshot? {
        guard let data = try? Data(contentsOf: cache), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data), !snapshot.stations.isEmpty else { return nil }
        return snapshot
    }
    func refresh() async throws -> Snapshot {
        let url = URL(string: "https://api.ibb.gov.tr/MetroIstanbul/api/MetroMobile/V2/GetStations")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw IETTError.badResponse }
        let decoded = try JSONDecoder().decode(RailResponse.self, from: data)
        guard decoded.Success, !decoded.stations.isEmpty else { throw IETTError.badResponse }
        let snapshot = Snapshot(stations: decoded.stations, fetchedAt: .now)
        if let encoded = try? JSONEncoder().encode(snapshot) { try? encoded.write(to: cache, options: .atomic) }
        return snapshot
    }
    func serviceStatuses() async throws -> [RailServiceStatus] {
        let url = URL(string: "https://api.ibb.gov.tr/MetroIstanbul/api/MetroMobile/V2/GetServiceStatuses")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw IETTError.badResponse }
        let decoded = try JSONDecoder().decode(RailStatusResponse.self, from: data)
        guard decoded.Success else { throw IETTError.badResponse }
        return decoded.active
    }
}

struct RailStationsView: View {
    @Environment(AppModel.self) private var model
    @State private var snapshot: RailStationStore.Snapshot?
    @State private var loading = false
    @State private var error: String?
    @State private var query = ""
    @State private var selected: RailStation?
    @State private var onlyFavorites = false
    @State private var statuses: [RailServiceStatus] = []
    @State private var statusUpdated: Date?
    @State private var statusError = false
    @AppStorage("rail.favorite-stations.v1") private var favoritesRaw = ""
    private var favoriteIDs: Set<String> { Set(favoritesRaw.split(separator: ",").map(String.init)) }
    private var stations: [RailStation] {
        let needle = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return (snapshot?.stations ?? []).filter { station in
            (!onlyFavorites || favoriteIDs.contains(station.id)) && (needle.isEmpty || fold(station.Description + " " + station.LineName).contains(needle))
        }.sorted { a, b in
            if needle.isEmpty, let here = model.location?.coordinate, let ac = a.coordinate, let bc = b.coordinate {
                let ad = here.distance(to: ac), bd = here.distance(to: bc)
                if ad != bd { return ad < bd }
            } else if needle.isEmpty, model.location != nil, (a.coordinate != nil) != (b.coordinate != nil) { return a.coordinate != nil }
            return (a.LineName, a.Order, a.id) < (b.LineName, b.Order, b.id)
        }
    }
    var body: some View {
        List {
            Section {
                Toggle("Yalnız favoriler", isOn: $onlyFavorites)
                if let snapshot {
                    Text("Kaynak: Metro İstanbul · Veri alındı: \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { Label(error, systemImage: "wifi.slash").font(.footnote).foregroundStyle(.orange) }
                if loading { ProgressView("İstasyonlar güncelleniyor…") }
            } footer: {
                Text("İstasyon listesi canlı araç veya arıza bilgisi değildir. Metro İstanbul servisindeki hatlarla sınırlıdır; diğer işletmecilerin hatları bu listede bulunmayabilir.")
            }
            Section("Metro İstanbul işletme duyuruları") {
                if let updated = statusUpdated { Text("Kontrol: \(updated.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                if statusError { Text("İşletme durumu güncellenemedi. Resmî duyuruları ayrıca kontrol et.").font(.footnote).foregroundStyle(.orange) }
                if !statusError && statusUpdated != nil && statuses.isEmpty { Text("Servis şu anda işletme duyurusu bildirmiyor.").font(.footnote).foregroundStyle(.secondary) }
                ForEach(statuses) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.LineName).font(.subheadline.bold()).foregroundStyle(.orange)
                        Text(item.Description).font(.footnote)
                        if let date = item.UpdateDate { Text("Kaynak güncellemesi: \(date.replacingOccurrences(of: "T", with: " "))").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
            Section("\(stations.count) istasyon kaydı") {
                ForEach(stations) { station in
                    Button { selected = station } label: {
                        HStack(spacing: 10) {
                            Text(station.LineName).font(.caption.bold()).frame(width: 48).padding(.vertical, 7).background(Theme.accent.opacity(0.15), in: .capsule)
                            VStack(alignment: .leading) {
                                Text(station.Description).font(.headline)
                                if let here = model.location?.coordinate, let point = station.coordinate {
                                    let meters = here.distance(to: point)
                                    Text(meters < 1000 ? "\(Int(meters)) m" : String(format: "%.1f km", meters / 1000)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if favoriteIDs.contains(station.id) { Image(systemName: "star.fill").foregroundStyle(.orange) }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.foregroundStyle(.primary)
                    }
                }
                if stations.isEmpty && !loading { Text(snapshot == nil ? "İstasyon verisi yüklenemedi." : "Eşleşen istasyon yok.").foregroundStyle(.secondary) }
            }
        }
        .searchable(text: $query, prompt: "İstasyon veya hat ara")
        .refreshable { await refresh() }
        .task {
            if snapshot == nil { snapshot = await RailStationStore.shared.cached() }
            await refresh()
        }
        .sheet(item: $selected) { station in
            NavigationStack {
                List {
                    Section {
                        LabeledContent("Hat", value: station.LineName)
                        if let count = station.DetailInfo?.Lift { LabeledContent("Asansör sayısı", value: "\(count)") }
                        if let count = station.DetailInfo?.Escolator { LabeledContent("Yürüyen merdiven sayısı", value: "\(count)") }
                        if let wc = station.DetailInfo?.WC { LabeledContent("Tuvalet", value: wc ? "Var" : "Yok") }
                    } header: { Text("İstasyon") } footer: { Text("Tesis sayıları servis bilgisidir; cihazların şu anda çalıştığı anlamına gelmez.") }
                    Section {
                        Button(favoriteIDs.contains(station.id) ? "Favorilerden çıkar" : "Favorilere ekle", systemImage: favoriteIDs.contains(station.id) ? "star.slash" : "star") { toggleFavorite(station.id) }
                        if let coordinate = station.coordinate {
                            Button("Harita'da göster", systemImage: "map") {
                                let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate)); item.name = station.Description
                                item.openInMaps()
                            }
                        } else { Text("Bu istasyon için konum bilgisi sağlanmamış.").foregroundStyle(.secondary) }
                    }
                }
                .navigationTitle(station.Description).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { selected = nil } } }
            }
        }
    }
    private func toggleFavorite(_ id: String) {
        var ids = favoriteIDs
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        favoritesRaw = ids.sorted().joined(separator: ",")
    }
    private func refresh() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        async let stationsTask = RailStationStore.shared.refresh()
        async let statusTask = RailStationStore.shared.serviceStatuses()
        do { snapshot = try await stationsTask; error = nil }
        catch { self.error = snapshot == nil ? "İstasyonlar alınamadı. Yeniden dene." : "Güncellenemedi; son kayıtlı veri gösteriliyor." }
        do { statuses = try await statusTask; statusUpdated = .now; statusError = false }
        catch { statusError = true }
    }
}
