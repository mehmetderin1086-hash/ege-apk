import CoreLocation
import MapKit
import SwiftUI

/// Rota planla: nereden / nereye durak ya da konum seç; sonuçlar `TripResultsView`'da (doğrudan + tek aktarmalı).
struct TripPlannerView: View {
    @Environment(AppModel.self) private var model
    @State private var fromText = ""
    @State private var toText = ""
    @State private var from: Durak?
    @State private var to: Durak?
    @State private var useLocation = true
    @State private var query: Query?
    @State private var showCityTransit = false
    @FocusState private var focus: Field?
    enum Field { case from, to }
    struct Query: Hashable { var id = UUID(); var from: Durak?; var to: Durak }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: useLocation ? "location.fill" : "circle.dotted").foregroundStyle(.blue)
                        if useLocation {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Konumum")
                                if let location = model.location {
                                    Text("Konum güncellemesi: \(location.timestamp.formatted(date: .omitted, time: .shortened)) · ±\(Int(max(0, location.horizontalAccuracy))) m")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        else { TextField("Nereden? (durak adı)", text: $fromText).focused($focus, equals: .from).textInputAutocapitalization(.never).autocorrectionDisabled() }
                        Button(useLocation ? "Değiştir" : "Konumum") { withAnimation(.snappy) { useLocation.toggle(); from = nil; fromText = ""; query = nil } }.font(.caption.weight(.semibold))
                    }
                    Divider()
                    HStack {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                        TextField("Nereye? (durak adı)", text: $toText).focused($focus, equals: .to).textInputAutocapitalization(.never).autocorrectionDisabled()
                        if to != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                }.card()
                suggestions(for: .from)
                suggestions(for: .to)
                Button {
                    guard let to else { return }
                    focus = nil; withAnimation(.spring(duration: 0.45)) { query = Query(from: useLocation ? nil : from, to: to) }
                } label: { Label("Rota bul", systemImage: "magnifyingglass").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(to == nil || (!useLocation && from == nil))
                Button { showCityTransit = true } label: {
                    Label("Metro, tramvay ve vapur için rota", systemImage: "tram.fill")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
                if let query { TripResultsView(fromStop: query.from, destination: query.to).id(query) }
                if !model.savedTrips.isEmpty && query == nil { savedList }
            }
            .padding(.horizontal).padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: fromText) { _, value in
            if let from, value != from.name { self.from = nil; query = nil }
        }
        .onChange(of: toText) { _, value in
            if let to, value != to.name { self.to = nil; query = nil }
        }
        #if DEBUG
        .task(id: model.routeIndexReady) {
            guard model.routeIndexReady, query == nil,
                  let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-previewTrip=") }) else { return }
            let codes = argument.dropFirst("-previewTrip=".count).split(separator: ":").compactMap { Int($0) }
            guard codes.count == 2, let start = model.stop(code: codes[0]), let end = model.stop(code: codes[1]) else { return }
            useLocation = false; from = start; fromText = start.name; to = end; toText = end.name
            query = Query(from: start, to: end)
        }
        #endif
        .sheet(isPresented: $showCityTransit) { CityTransitView() }
        .background { AuroraBackground() }
    }

    private var savedList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Kayıtlı yolculuklarım", systemImage: "star.fill").font(.headline).foregroundStyle(.orange)
            ForEach(model.savedTrips) { trip in
                NavigationLink(value: Route.trip(id: trip.id)) { SavedTripCard(trip: trip) }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func suggestions(for field: Field) -> some View {
        let text = field == .from ? fromText : toText
        let chosen = field == .from ? from : to
        if focus == field, !text.isEmpty, chosen == nil || chosen!.name != text {
            VStack(spacing: 0) {
                ForEach(model.searchStops(text, near: model.location?.coordinate, limit: 5)) { stop in
                    Button {
                        if field == .from { from = stop; fromText = stop.name } else { to = stop; toText = stop.name }
                        focus = nil; query = nil
                    } label: { HStack { Text(stop.name); Spacer(); Text(stop.district).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 9) }.buttonStyle(.plain)
                    Divider()
                }
            }.card()
        }
    }
}

/// Doğrudan ve tek aktarmalı seçenekler; her seçenekte yürüyüş, durak sayısı, süre ve binişe sıradaki planlı geçiş.
struct TripResultsView: View {
    let fromStop: Durak?
    let destination: Durak
    var allowSave = true
    @Environment(AppModel.self) private var model
    @State private var direct: [TripOption] = []
    @State private var transfers: [TransferOption] = []
    @State private var multi: [MultiTripOption] = []
    @State private var departures: [String: Int] = [:]
    @State private var searching = true
    @State private var noLocation = false
    @State private var saving = false
    @State private var saveName = ""
    @State private var sharing: ShareMessage?
    @State private var selectedItinerary: MultiTripOption?
    @State private var originCoordinate: CLLocationCoordinate2D?
    @State private var searchID: UUID? = UUID()
    @State private var cancelled = false
    @State private var waitingForLocation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.routeIndexReady { Label("Hat güzergâh veritabanı hazır değil; sonuçlar eksik olabilir.", systemImage: "arrow.down.circle").font(.footnote).foregroundStyle(.orange) }
            if searching {
                HStack {
                    ProgressView(); Text("Rotalar aranıyor…").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button("İptal") { searchID = nil; searching = false; cancelled = true; waitingForLocation = false }
                }.padding(.vertical)
            }
            if noLocation {
                ContentUnavailableView("Güncel konum gerekli", systemImage: "location.slash", description: Text(model.locationError ?? "Başlangıç için son iki dakika içinde alınmış bir konum veya seçilmiş bir durak gerekli."))
                if model.requestingLocation { ProgressView("Konum alınıyor…") }
                else {
                    Button("Konumu yenile ve ara", systemImage: "location.fill") { refreshLocation() }
                        .buttonStyle(.bordered)
                }
            }
            if cancelled {
                Label("Rota araması iptal edildi", systemImage: "pause.circle").foregroundStyle(.secondary)
                Button("Yeniden ara", systemImage: "arrow.clockwise") { restart() }.buttonStyle(.bordered)
            }
            if !searching && !noLocation && !cancelled && direct.isEmpty && transfers.isEmpty && multi.isEmpty {
                ContentUnavailableView("İETT rotası bulunamadı", systemImage: "arrow.triangle.branch", description: Text("İndirilen güzergâhlarda yakındaki duraklar arasında uygun bir bağlantı bulunamadı. Veri eksik olabilir; Harita'da diğer ulaşım seçeneklerini de deneyebilirsin."))
                Button {
                    let source: MKMapItem
                    if let fromStop { source = MKMapItem(placemark: MKPlacemark(coordinate: fromStop.coordinate)); source.name = fromStop.name }
                    else { source = .forCurrentLocation() }
                    let target = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate)); target.name = destination.name
                    MKMapItem.openMaps(with: [source, target], launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeTransit])
                } label: { Label("Bu rotayı Harita'da ara", systemImage: "map").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
            }
            if !direct.isEmpty { Label("Aktarmasız", systemImage: "arrow.right").font(.headline) }
            ForEach(Array(direct.prefix(10).enumerated()), id: \.element.id) { index, option in
                VStack(alignment: .leading, spacing: 8) {
                    NavigationLink(value: Route.line(code: option.line, stop: option.board.code)) { optionCard(option) }.buttonStyle(.plain)
                    itineraryButton(option.itinerary)
                }.cascadeIn(index)
                    .contextMenu { Button("Rotayı paylaş", systemImage: "square.and.arrow.up") { sharing = ShareBuilder.trip(option, waitMinutes: departures[option.id]) } }
            }
            if !transfers.isEmpty { Label("1 aktarmalı", systemImage: "arrow.triangle.swap").font(.headline).padding(.top, 6) }
            ForEach(Array(transfers.prefix(6).enumerated()), id: \.element.id) { index, option in
                VStack(alignment: .leading, spacing: 8) {
                    NavigationLink(value: Route.line(code: option.first.line, stop: option.first.board.code)) { transferCard(option) }.buttonStyle(.plain)
                    itineraryButton(option.itinerary)
                }.cascadeIn(index)
                    .contextMenu { Button("Rotayı paylaş", systemImage: "square.and.arrow.up") { sharing = ShareBuilder.transfer(option) } }
            }
            ForEach(multi) { option in
                VStack(alignment: .leading, spacing: 8) {
                    MultiTripCard(option: option)
                    itineraryButton(option)
                }
            }
            if !searching && !cancelled && !noLocation {
                Button("Rotayı yeniden hesapla", systemImage: "arrow.clockwise") {
                    if fromStop == nil { refreshLocation() } else { restart() }
                }.buttonStyle(.bordered)
            }
            if !direct.isEmpty || !transfers.isEmpty || !multi.isEmpty {
                Text("Süreler tahmindir: yürüyüş mesafeleri kuş uçuşudur ve 80 m/dk ile hesaplanır; gerçek yürüyüş yolu daha uzun olabilir. İlk aracı bekleme toplam süreye dahil değildir; aktarmada ~\(Int(TransferOption.assumedWait)) dk bekleme varsayılır.").font(.caption2).foregroundStyle(.secondary)
            }
            if allowSave && !searching && !noLocation && (!direct.isEmpty || !transfers.isEmpty || !multi.isEmpty) && !model.savedTrips.contains(where: { $0.toCode == destination.code && $0.fromCode == fromStop?.code }) {
                Button { saveName = "\(fromStop?.name ?? "Konumum") → \(destination.name)"; saving = true } label: { Label("Bu yolculuğu kaydet", systemImage: "star").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
            }
        }
        .task(id: searchID) { if searchID != nil { await plan() } }
        .onChange(of: model.location?.timestamp) { _, _ in
            if waitingForLocation && AppModel.isUsableLocation(model.location) { waitingForLocation = false; restart() }
        }
        .sheet(item: $selectedItinerary) { option in
            TripItineraryView(option: option, origin: originCoordinate, destination: destination)
        }
        .alert("Yolculuğu kaydet", isPresented: $saving) {
            TextField("Ad", text: $saveName)
            Button("Kaydet") { withAnimation(.spring) { model.saveTrip(.init(name: saveName.isEmpty ? destination.name : saveName, fromCode: fromStop?.code, fromName: fromStop?.name ?? "Konumum", toCode: destination.code, toName: destination.name)) } }
            Button("Vazgeç", role: .cancel) {}
        } message: { Text("Takip sekmesinde en iyi seçenek canlı özetlenir.") }
        .sensoryFeedback(.success, trigger: model.savedTrips.count)
        .shareSheet($sharing)
    }

    private func itineraryButton(_ option: MultiTripOption) -> some View {
        Button { selectedItinerary = option } label: {
            Label("Harita ve yolculuk adımları", systemImage: "map").frame(maxWidth: .infinity)
        }.buttonStyle(.bordered)
    }

    private func restart() {
        cancelled = false; noLocation = false; searching = true
        direct = []; transfers = []; multi = []; departures = [:]
        searchID = UUID()
    }

    private func refreshLocation() {
        searchID = nil; searching = false; noLocation = true; cancelled = false
        direct = []; transfers = []; multi = []; departures = [:]
        waitingForLocation = true
        model.requestLocation()
        if model.isDemo && AppModel.isUsableLocation(model.location) { waitingForLocation = false; restart() }
    }

    private func plan() async {
        searching = true; noLocation = false
        if fromStop == nil && !AppModel.isUsableLocation(model.location) {
            refreshLocation()
            return
        }
        originCoordinate = fromStop?.coordinate ?? model.location?.coordinate
        let result = await model.planTrip(from: fromStop, to: destination)
        guard !Task.isCancelled else { return }
        guard let result else { noLocation = true; searching = false; return }
        withAnimation(.spring(duration: 0.5)) { direct = result.direct; transfers = result.transfers; multi = result.multi; searching = false }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-previewItinerary") {
            selectedItinerary = result.direct.first?.itinerary ?? result.transfers.first?.itinerary ?? result.multi.first
        }
        #endif
        for option in result.direct.prefix(5) {
            guard !Task.isCancelled else { return }
            let wait = await model.nextScheduledWait(option)
            guard !Task.isCancelled else { return }
            if let wait { withAnimation { departures[option.id] = wait } }
        }
    }

    private func optionCard(_ o: TripOption) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                LineBadge(code: o.line)
                Text("→ \(o.destination)").font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Button { sharing = ShareBuilder.trip(o, waitMinutes: departures[o.id]) } label: { Image(systemName: "square.and.arrow.up").padding(6) }.buttonStyle(.borderless)
                VStack(alignment: .trailing, spacing: 0) { Text("~\(Int(o.totalMinutes.rounded()))").font(.title2.weight(.heavy).monospacedDigit()); Text("dk toplam").font(.caption2).foregroundStyle(.secondary) }
            }
            HStack(spacing: 8) {
                Image(systemName: "figure.walk"); Text("\(Int(o.walkToBoard)) m").font(.caption.monospacedDigit())
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                Image(systemName: "bus.fill").foregroundStyle(Theme.color(for: o.line)); Text("\(o.stops) durak · ~\(Int(o.rideMinutes.rounded())) dk").font(.caption.monospacedDigit())
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                Image(systemName: "figure.walk"); Text("\(Int(o.walkFromAlight)) m").font(.caption.monospacedDigit())
            }.foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Label("Bin: \(o.board.name)", systemImage: "arrow.up.right.circle").font(.caption)
                Label("In: \(o.alight.name)", systemImage: "arrow.down.right.circle").font(.caption)
            }
            if let wait = departures[o.id] {
                Label(wait <= 0 ? "Binişte şimdi bir sefer var" : "Binişe sıradaki planlı geçiş ~\(wait) dk sonra", systemImage: "clock").font(.caption.weight(.semibold)).foregroundStyle(Theme.color(for: o.line))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(o.line) hattı, \(o.destination) yönü, \(o.stops) durak, toplam yaklaşık \(Int(o.totalMinutes.rounded())) dakika. Binilecek durak \(o.board.name), inilecek durak \(o.alight.name).")
        .card()
    }

    private func transferCard(_ o: TransferOption) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                LineBadge(code: o.first.line)
                Image(systemName: "arrow.right").font(.caption.bold()).foregroundStyle(.secondary)
                LineBadge(code: o.second.line)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) { Text("~\(Int(o.totalMinutes.rounded()))").font(.title2.weight(.heavy).monospacedDigit()); Text("dk toplam").font(.caption2).foregroundStyle(.secondary) }
            }
            VStack(alignment: .leading, spacing: 3) {
                Label("\(o.first.line): \(o.first.board.name) → \(o.first.alight.name) · \(o.first.stops) durak", systemImage: "1.circle.fill").font(.caption)
                Label(o.transferWalkMeters > 0 ? "Aktarma: \(o.first.alight.name) → \(o.second.board.name), ~\(Int(o.transferWalkMeters.rounded())) m yürü + ~\(Int(TransferOption.assumedWait)) dk bekle" : "Aktarma: \(o.first.alight.name) (~\(Int(TransferOption.assumedWait)) dk bekleme)", systemImage: "arrow.triangle.swap").font(.caption).foregroundStyle(.orange)
                Label("\(o.second.line): → \(o.second.destination) · \(o.second.alight.name) · \(o.second.stops) durak", systemImage: "2.circle.fill").font(.caption)
            }
            HStack(spacing: 8) {
                Image(systemName: "figure.walk"); Text("\(Int(o.walkToBoard)) m").font(.caption.monospacedDigit())
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                Text("~\(Int(o.first.rideMinutes.rounded())) + \(Int(o.second.rideMinutes.rounded())) dk yolculuk").font(.caption.monospacedDigit())
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                Image(systemName: "figure.walk"); Text("\(Int(o.walkFromAlight)) m").font(.caption.monospacedDigit())
            }.foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bir aktarmalı: \(o.first.line) hattı ile \(o.first.alight.name) durağına, oradan \(o.second.line) hattı ile \(o.second.alight.name) durağına. Toplam yaklaşık \(Int(o.totalMinutes.rounded())) dakika.")
        .card()
    }
}

/// Kayıtlı yolculuğun canlı özeti: en iyi seçenek, toplam süre, binişe sıradaki planlı geçiş.
struct SavedTripCard: View {
    let trip: SavedTrip
    @Environment(AppModel.self) private var model
    @State private var summary: String?
    @State private var badges: [String] = []
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.circle.fill").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.name).font(.headline).lineLimit(1)
                Text("\(trip.fromName) → \(trip.toName)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    ForEach(Array(badges.enumerated()), id: \.offset) { _, code in LineBadge(code: code) }
                    Text(summary ?? "Hesaplanıyor…").font(.caption.weight(.semibold)).foregroundStyle(summary == nil ? .secondary : .primary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .card()
        .contextMenu { Button("Sil", systemImage: "trash", role: .destructive) { withAnimation(.spring) { model.removeTrip(trip) } } }
        .task(id: model.routeIndexReady) {
            guard let to = model.stop(code: trip.toCode) else { summary = "Durak bulunamadı"; return }
            guard let result = await model.planTrip(from: trip.fromCode.flatMap { model.stop(code: $0) }, to: to) else { summary = "Konum alınamadı"; return }
            if let best = result.direct.first {
                badges = [best.line]
                let wait = await model.nextScheduledWait(best)
                summary = "~\(Int(best.totalMinutes.rounded())) dk" + (wait.map { $0 <= 0 ? " · şimdi bir sefer var" : " · sıradaki \($0) dk sonra" } ?? "")
            } else if let best = result.transfers.first {
                badges = [best.first.line, best.second.line]; summary = "~\(Int(best.totalMinutes.rounded())) dk · 1 aktarma"
            } else if let best = result.multi.first {
                badges = best.legs.map(\.line); summary = "~\(Int(best.totalMinutes.rounded())) dk · \(best.legs.count - 1) aktarma"
            } else { badges = []; summary = "En fazla 3 aktarmalı İETT bağlantısı bulunamadı" }
        }
    }
}

struct MultiTripCard: View {
    let option: MultiTripOption
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("\(option.legs.count - 1) aktarma", systemImage: "arrow.triangle.branch").font(.headline)
                Spacer()
                Text("~\(Int(option.totalMinutes.rounded())) dk").font(.headline.monospacedDigit())
            }
            Text("Güzergâh bağlantısı · seferlerin o saatte çalıştığı ayrıca kontrol edilmeli").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(option.legs.enumerated()), id: \.offset) { index, leg in
                if option.walks[index] > 1 {
                    Label("\(leg.board.name) durağına yaklaşık \(Int(option.walks[index].rounded())) m yürü", systemImage: "figure.walk").font(.caption).foregroundStyle(.secondary)
                }
                NavigationLink(value: Route.line(code: leg.line, stop: leg.board.code)) {
                    HStack(alignment: .top, spacing: 10) {
                        LineBadge(code: leg.line)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Bin: \(leg.board.name)").font(.subheadline.weight(.semibold))
                            Text("İn: \(leg.alight.name)").font(.subheadline)
                            Text("\(leg.destination) yönü · \(leg.stops) durak").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption)
                    }
                }.buttonStyle(.plain)
            }
            if let last = option.walks.last, last > 1 { Label("Hedefe yaklaşık \(Int(last.rounded())) m yürü", systemImage: "figure.walk").font(.caption).foregroundStyle(.secondary) }
        }.card()
    }
}

/// Apple Harita, toplu taşıma rotasını kendi uygulamasında hesaplar.
struct CityTransitView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var destinationText = ""
    @State private var results: [MKMapItem] = []
    @State private var selected: MKMapItem?
    @State private var searching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Adres, istasyon veya yer ara", text: $destinationText)
                        .submitLabel(.search)
                        .onSubmit { search() }
                        .onChange(of: destinationText) { _, _ in
                            searchTask?.cancel()
                            searching = false
                            selected = nil
                            results = []
                            searchError = nil
                        }
                    Button { search() } label: {
                        if searching { ProgressView() } else { Label("İstanbul'da ara", systemImage: "magnifyingglass") }
                    }.disabled(destinationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searching)
                    if let searchError { Text(searchError).font(.footnote).foregroundStyle(.secondary) }
                    ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                        Button {
                            selected = item
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.name ?? "Konum")
                                    if let address = item.placemark.title { Text(address).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                if selected === item { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                            }
                        }.foregroundStyle(.primary)
                    }
                } header: { Text("Varış noktası") }
                Section {
                    Button {
                        guard let selected else { return }
                        MKMapItem.openMaps(with: [.forCurrentLocation(), selected], launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeTransit])
                    } label: { Label("Toplu taşıma rotasını Harita'da aç", systemImage: "map") }
                        .disabled(selected == nil)
                } footer: {
                    Text("Harita, konumundan toplu taşıma seçeneklerini kendi verilerine göre hesaplar. İstanbul'daki hat ve sefer kapsamı Apple Harita'ya bağlıdır; rota veya canlı bilgi bulunmayabilir. İETT sonuçları uygulamanın rota ekranında kalır.")
                }
            }
            .navigationTitle("İstanbul ulaşımı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { dismiss() } } }
        }
        .onDisappear { searchTask?.cancel() }
    }

    private func search() {
        let text = destinationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        searchTask?.cancel()
        selected = nil; results = []; searchError = nil; searching = true
        searchTask = Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 41.015, longitude: 28.979), span: MKCoordinateSpan(latitudeDelta: 0.8, longitudeDelta: 1.4))
            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled else { return }
                results = response.mapItems
                if results.isEmpty { searchError = "Sonuç bulunamadı. Başka bir adres veya istasyon dene." }
            } catch {
                guard !Task.isCancelled else { return }
                searchError = "Arama yapılamadı. İnternet bağlantını kontrol edip tekrar dene."
            }
            searching = false
        }
    }
}

/// Yolculuğun tüm araç ve yürüyüş adımlarını aynı haritada gösterir.
struct TripItineraryView: View {
    let option: MultiTripOption
    let origin: CLLocationCoordinate2D?
    let destination: Durak
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition = .automatic
    @State private var geometry: [Int: [RouteStop]] = [:]
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(destination.name).font(.title2.bold())
                    Text("~\(Int(option.totalMinutes.rounded())) dk · \(max(0, option.legs.count - 1)) aktarma")
                        .font(.headline).foregroundStyle(.secondary)
                    map.frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 20))
                    Button("Tüm rotayı göster", systemImage: "arrow.up.left.and.arrow.down.right") { camera = .automatic }
                    Text("Renkli çizgiler duraklar arasındaki bağlantıyı, kesikli çizgiler yürüyüş bağlantısını gösterir; gerçek yol geometrisi değildir.")
                        .font(.caption).foregroundStyle(.secondary)
                    if loading { ProgressView("Duraklar yükleniyor…") }
                    ForEach(Array(option.legs.enumerated()), id: \.offset) { index, leg in
                        legView(leg, index: index)
                    }
                    if let last = option.legs.last {
                        walkingStep(meters: option.walks.last ?? 0, name: destination.name, from: last.alight.coordinate, to: destination.coordinate)
                    }
                    Text("İlk aracı bekleme toplam süreye dahil değildir. Her aktarmada yaklaşık \(Int(TransferOption.assumedWait)) dakika bekleme varsayılır. Sefer saatlerini yolculuktan önce kontrol et. Yürüyüş mesafeleri kuş uçuşudur; gerçek yol daha uzun olabilir.")
                        .font(.footnote).foregroundStyle(.secondary)
                    ShareIconButton(label: "Yolculuğu paylaş", showsTitle: true) { ShareBuilder.itinerary(option, destination: destination) }
                }.padding()
            }
            .navigationTitle("Yolculuk adımları").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
            .task {
                for (index, leg) in option.legs.enumerated() {
                    guard !Task.isCancelled else { return }
                    let route = await model.route(leg.line)
                    guard !Task.isCancelled else { return }
                    if let route { geometry[index] = leg.routeStops(in: route) }
                }
                loading = false
            }
        }
    }

    private var map: some View {
        Map(position: $camera) {
            if let origin { Marker("Başlangıç", systemImage: "location.fill", coordinate: origin).tint(.blue) }
            Marker(destination.name, systemImage: "flag.fill", coordinate: destination.coordinate).tint(.red)
            ForEach(Array(option.legs.enumerated()), id: \.offset) { index, leg in
                MapPolyline(coordinates: coordinates(leg, index: index))
                    .stroke(Theme.color(for: leg.line), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                Marker("\(index + 1). Bin · \(leg.line)", systemImage: "bus.fill", coordinate: leg.board.coordinate).tint(Theme.color(for: leg.line))
                Marker("İn · \(leg.alight.name)", systemImage: "arrow.down", coordinate: leg.alight.coordinate).tint(Theme.color(for: leg.line))
                if let start = walkingOrigin(index) {
                    MapPolyline(coordinates: [start, leg.board.coordinate]).stroke(.secondary, style: StrokeStyle(lineWidth: 3, dash: [5, 5]))
                }
            }
            if let last = option.legs.last {
                MapPolyline(coordinates: [last.alight.coordinate, destination.coordinate]).stroke(.secondary, style: StrokeStyle(lineWidth: 3, dash: [5, 5]))
            }
        }.mapStyle(.standard(pointsOfInterest: .excludingAll)).mapControls { MapCompass(); MapScaleView() }
    }

    private func coordinates(_ leg: TripLeg, index: Int) -> [CLLocationCoordinate2D] {
        guard let points = geometry[index], points.count > 1 else { return [leg.board.coordinate, leg.alight.coordinate] }
        return points.map(\.coordinate)
    }

    private func walkingOrigin(_ index: Int) -> CLLocationCoordinate2D? {
        index == 0 ? origin : option.legs[index - 1].alight.coordinate
    }

    private func legView(_ leg: TripLeg, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if option.walks.indices.contains(index) {
                walkingStep(meters: option.walks[index], name: leg.board.name, from: walkingOrigin(index), to: leg.board.coordinate)
            }
            HStack { Text("\(index + 1)").font(.title2.bold()); LineBadge(code: leg.line); Text("\(leg.destination) yönü").font(.headline) }
            Label("Bin: \(leg.board.name) · \(String(leg.board.code))", systemImage: "arrow.up.right.circle.fill")
            Label("İn: \(leg.alight.name) · \(String(leg.alight.code))", systemImage: "arrow.down.right.circle.fill")
            Text("\(leg.stops) durak · yaklaşık \(Int(leg.rideMinutes.rounded())) dakika").font(.subheadline).foregroundStyle(.secondary)
            if let points = geometry[index], points.count > 2 {
                DisclosureGroup("Aradaki \(points.count - 2) durağı göster") {
                    ForEach(Array(points.dropFirst().dropLast().enumerated()), id: \.offset) { _, stop in
                        Text(stop.name).font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
                    }
                }
            } else if !loading && (geometry[index] ?? []).isEmpty {
                Text("Ara duraklar yüklenemedi; haritada biniş ve iniş noktaları birleştirildi.").font(.caption).foregroundStyle(.secondary)
            }
            NavigationLink(value: Route.timetable(code: leg.line, direction: leg.direction, stop: leg.board.code)) {
                Label("\(leg.line) sefer saatlerini kontrol et", systemImage: "clock")
            }.buttonStyle(.bordered)
            NavigationLink(value: Route.line(code: leg.line, stop: leg.board.code)) {
                Label("\(leg.line) hattını aç", systemImage: "bus")
            }
        }.card()
    }

    @ViewBuilder private func walkingStep(meters: Double, name: String, from: CLLocationCoordinate2D?, to: CLLocationCoordinate2D) -> some View {
        if meters > 1 {
            VStack(alignment: .leading, spacing: 6) {
                Label("\(name): yaklaşık \(Int(meters.rounded())) m yürü", systemImage: "figure.walk").font(.subheadline)
                Button("Harita’da yürüyüş yolunu aç", systemImage: "arrow.triangle.turn.up.right.diamond") {
                    let source = from.map { MKMapItem(placemark: MKPlacemark(coordinate: $0)) } ?? .forCurrentLocation()
                    source.name = "Yürüyüş başlangıcı"
                    let target = MKMapItem(placemark: MKPlacemark(coordinate: to)); target.name = name
                    MKMapItem.openMaps(with: [source, target], launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                }.font(.caption)
            }
        }
    }
}
