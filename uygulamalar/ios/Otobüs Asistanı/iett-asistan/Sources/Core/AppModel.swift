import CoreLocation
import Foundation
import Observation
import UserNotifications
import WidgetKit

@MainActor @Observable
final class AppModel: NSObject, CLLocationManagerDelegate, UNUserNotificationCenterDelegate {
    var lines: [Hat] = []
    var stops: [Durak] = []
    var loadError: String?
    var isLoading = false
    var syncDone = 0
    var savedTrips: [SavedTrip] = SharedStore.loadTrips()
    /// Durak seçmeden hat düzeyinde takip edilen hatlar ve özetleri.
    var followedLines: [String] = SharedStore.defaults.stringArray(forKey: "followlines.v1") ?? []
    var lineSummaries: [String: LineSummary] = [:]
    /// Favori başına bildirim kuralları (App Group'ta saklanır).
    var rules: [String: AlertRule] = SharedStore.loadRules()
    var plannedAlertCount = 0
    /// Ekranda gösterilen canlı uyarılar (gecikme gibi).
    var liveAlerts: [LiveAlert] = []
    /// Yıldızlı (favori) duraklar; hat bağımsızdır. Widget ve pano da kullanır.
    var favoriteStops: [Int] = SharedStore.loadFavoriteStops()
    var stopsByCode: [Int: Durak] = [:]
    /// Son bakılan hatlar/duraklar ve sabitlenen hatlar (App Group'ta saklanır).
    var recentLines: [String] = SharedStore.defaults.stringArray(forKey: "recent.lines") ?? []
    var recentStops: [Int] = (SharedStore.defaults.array(forKey: "recent.stops") as? [Int]) ?? []
    var pinnedLines: [String] = SharedStore.defaults.stringArray(forKey: "pinned.lines") ?? []
    /// Takip ve sabit hatların güncel duyuruları (kotasız servis).
    var boardNotices: [Duyuru] = []
    /// Kişisel notlar: "line:500T" / "stop:301341" → metin (App Group'ta saklanır).
    var notes: [String: String] = [:]
    /// Son canlı çağrı başarısızsa kullanıcıya gösterilecek anlaşılır neden (başarıda nil).
    var liveError: String?
    /// Son canlı çekimin yaşı ve kalan saatlik kota (İBB canlı konumu saatte 100 istekle sınırlı).
    var liveAge: Date?
    var quotaRemaining = FleetBudget.hourlyLimit
    var quota: QuotaSnapshot?
    /// Hat ekranı açıkken o hat da kotadan pay alır.
    var viewedLine: String?
    /// Durak panosunun canlı sorguladığı hatlar (kotadan pay alır).
    var boardLines: Set<String> = []
    var syncTotal = 0
    var routeIndexReady = false
    var favorites: [Favorite] = []
    var favoriteETAs: [String: [BusETA]] = [:]
    var lastRefresh: Date?
    var location: CLLocation?
    var locationError: String?
    var requestingLocation = false
    var authorization: CLAuthorizationStatus = .notDetermined
    let tracker = LiveTracker()
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let client: IETTClient
    @ObservationIgnored private var notified: [String: Date] = [:]
    @ObservationIgnored private var syncStarted = false
    #if DEBUG
    @ObservationIgnored private var routeVerificationStarted = false
    #endif

    init(client: IETTClient = .shared) {
        self.client = client
        super.init()
        UNUserNotificationCenter.current().delegate = self
        manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorization = manager.authorizationStatus
        SharedStore.migrateIfNeeded()
        favorites = SharedStore.loadFavorites()
        notes = SharedStore.loadNotes()
        #if DEBUG
        try? FileManager.default.removeItem(at: URL.cachesDirectory.appending(path: "route-location-diagnostic.json"))
        #endif
    }

    // MARK: Veri
    func load() async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        async let linesTask = client.lines(), stopsTask = client.stops()
        do { lines = try await linesTask; loadError = nil } catch { loadError = error.localizedDescription }
        do { stops = try await stopsTask; stopsByCode = Dictionary(stops.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first }) } catch { loadError = loadError ?? error.localizedDescription }
        // Uygulamayla gelen güzergâh tohumu: ilk açılışta ağ gerekmeden "durağa uğrayan hatlar" hazır olur.
        if await RouteStore.shared.seed(from: Bundle.main.url(forResource: "Seed", withExtension: nil)?.appending(path: "guzergah")) > 0 {
            await RouteStore.shared.buildIndex(lines: lines.map(\.code))
        }
        SharedStore.saveHatStats(lines)
        routeIndexReady = await RouteStore.shared.hasIndex()
        startRouteSync()
        #if DEBUG
        await verifyCurrentRouteIfRequested()
        #endif
        Task { await rescheduleAlerts() }
    }
    /// Tüm hatların sıralı duraklarını bir kez arka planda indirir (≈ birkaç dakika); "durağa uğrayan hatlar" bununla çalışır.
    func startRouteSync() {
        guard !syncStarted, !lines.isEmpty else { return }
        syncStarted = true
        let codes = lines.map(\.code)
        Task(priority: .utility) { [weak self] in
            await RouteStore.shared.sync(lines: codes) { done, total in Task { @MainActor in self?.syncDone = done; self?.syncTotal = total } }
            self?.routeIndexReady = true; self?.syncTotal = 0
        }
    }
    func route(_ line: String) async -> LineRoute? { try? await RouteStore.shared.route(line) }
    func linesAtStop(_ code: Int) async -> [RouteStore.Entry] { await RouteStore.shared.lines(atStop: code) }
    /// Güzergâh biliniyorsa hat üzerinden (durak sayısı dâhil), değilse kuş uçuşu canlı konumdan varış süresi.
    func etas(line: String, buses: [Bus], stop: CLLocationCoordinate2D, stopCode: Int) async -> [BusETA] {
        if let route = await route(line), !route.directions(serving: stopCode).isEmpty {
            return RouteETAEngine.etas(buses: buses, route: route, stopCode: stopCode, hat: self.line(line), tracker: tracker)
        }
        return tracker.etas(buses: buses, stop: stop, stopCode: stopCode)
    }
    /// Yalnız Debug: `-demo` canlı servis olmadan örnek takip listesi ve süreleri yükler (ekran doğrulaması).
    func loadDemoIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-demo") else { return }
        isDemo = true
        lines = [Hat(code: "500T", name: "TUZLA ŞİFA MAHALLESİ - 4. LEVENT METRO"), Hat(code: "14M", name: "KADIKÖY - ÜMRANİYE"), Hat(code: "15F", name: "BEYKOZ - KADIKÖY"), Hat(code: "E-10", name: "ÜSKÜDAR - ÇEKMEKÖY")]
        favorites = [.init(line: "500T", stopCode: 1, stopName: "4.LEVENT METRO", lat: 41.08, lon: 29.0, alertMinutes: 5),
                     .init(line: "14M", stopCode: 2, stopName: "KADIKÖY ÇARŞI", lat: 41.0, lon: 29.02),
                     .init(line: "15F", stopCode: 3, stopName: "BEYKOZ MEYDAN", lat: 41.13, lon: 29.1)]
        favoriteStops = [2, 3]
        quota = QuotaSnapshot(used: 47, limit: 90, remaining: 43, waitSeconds: 0, blockedUntil: nil, buckets: [4, 9, 11, 8, 10, 5], nextFree: nil)
        followedLines = ["14M"]
        lineSummaries = ["14M": LineSummary(line: "14M", total: 7, byDirection: ["G": 4, "D": 3], stopName: "KADIKÖY ÇARŞI", stopCode: 2, stopMeters: 240, eta: BusETA(id: "A-12", minutes: 3.5, distance: 900, state: .approaching, speedKmh: 20, stopsLeft: 2), tracks: [LineSummary.Track(direction: "G", destination: "ÜMRANİYE", buses: [0.08, 0.31, 0.47, 0.88], user: 0.42), LineSummary.Track(direction: "D", destination: "KADIKÖY", buses: [0.22, 0.6, 0.93], user: 0.58)])]
        boardNotices = [Duyuru(line: "500T", message: "Maç nedeniyle akşam seferleri ertelenmiştir."), Duyuru(line: "14M", message: "Recep Peker Caddesi kapalıdır; araçlarımız farklı güzergâh kullanacaktır."), Duyuru(line: "15F", message: "Yeni durak bilgilendirme ekranları hizmete girdi.")]
        liveAlerts = [LiveAlert(id: "d", line: "500T", text: "500T · 4.LEVENT METRO: planlıdan ~9 dk gecikmeli", severity: .warning)]
        rules["500T-1"] = .morning
        pinnedLines = ["E-10"]; recentLines = ["137"]
        favoriteETAs = [favorites[0].id: [.init(id: "C-461", minutes: 4.4, distance: 1250, state: .approaching, speedKmh: 20, stopsLeft: 3), .init(id: "C-455", minutes: 13, distance: 4300, state: .approaching, speedKmh: 18, stopsLeft: 11), .init(id: "C-442", minutes: 22, distance: 7000, state: .approaching, speedKmh: 18, stopsLeft: 18)],
                        favorites[1].id: [.init(id: "A-12", minutes: 0, distance: 20, state: .atStop, speedKmh: 0, stopsLeft: 0)],
                        favorites[2].id: []]
        if ProcessInfo.processInfo.arguments.contains("-demoOnlyLines") { favorites = []; favoriteETAs = [:] }
        lastRefresh = .now
        // Sefer saatleri ekranı için çevrimdışı örnek veri (500T): hafta içi 15 dk, hafta sonu 20 dk aralık.
        var trips: [PlannedTrip] = []
        for (day, gap) in [("I", 15), ("C", 20), ("P", 25)] {
            for (direction, start) in [("G", 350), ("D", 365)] {
                var t = start, n = 0
                while t <= 1430 {
                    n += 1
                    // Her 3. sefer ÖHO (kırmızı), her 5. sefer farklı güzergâhtan çıkan "(-1)" işaretli sefer.
                    trips.append(.init(line: "500T", routeCode: n % 5 == 0 ? "500T_\(direction)_D2629" : "500T_\(direction)_D0", direction: direction, dayType: day, time: Timetable.format(t),
                                       marker: n % 5 == 0 ? "-1" : "", serviceType: n % 3 == 0 ? "ÖHO" : (n % 7 == 0 ? "Gareli" : "Normal")))
                    t += gap
                }
            }
        }
        try? FileManager.default.createDirectory(at: IETTClient.timetableFolder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(trips).write(to: IETTClient.timetableFolder.appending(path: "500T.json"))
        stops = [Durak(code: 301341, name: "4.LEVENT METRO", lat: 41.08417, lon: 29.00731, district: "Şişli", direction: "ŞİFA SONDURAK", kind: "CCMODERN", smart: true, physical: "AÇIK")]
        stopsByCode = [301341: stops[0]]
        let codes = lines.map(\.code)
        Task { await RouteStore.shared.seed(from: Bundle.main.url(forResource: "Seed", withExtension: nil)?.appending(path: "guzergah")); await RouteStore.shared.buildIndex(lines: codes); routeIndexReady = true }
        #endif
    }
    var isDemo = false
    func line(_ code: String) -> Hat? { lines.first { fold($0.code) == fold(code) } }
    /// Canlı konum kotasından pay alan hatlar: takipteki, izlenen, pano ve hat takibi.
    var activeLines: Set<String> { Set(favorites.map(\.line)).union(viewedLine.map { [$0] } ?? []).union(boardLines).union(followedLines) }
    func buses(line: String) async -> [Bus] {
        let interval = FleetBudget.refreshInterval(activeLines: activeLines.count)
        do {
            let buses = try await client.buses(line: line, maxAge: interval)
            let fetched = await client.lastFetch(line: line)
            liveAge = fetched; quotaRemaining = await FleetBudget.shared.remaining; quota = await FleetBudget.shared.snapshot()
            // Kota yüzünden eski veri geliyorsa kullanıcıya söylenir; veri yine de gösterilir.
            let wait = await FleetBudget.shared.waitSeconds()
            liveError = wait > 0 && (fetched.map { Date().timeIntervalSince($0) > interval * 2 } ?? true) ? IETTError.rateLimited(seconds: wait).localizedDescription : nil
            tracker.ingest(buses); return buses
        } catch { liveError = Self.friendly(error); quotaRemaining = await FleetBudget.shared.remaining; quota = await FleetBudget.shared.snapshot(); return [] }
    }
    static func friendly(_ error: Error) -> String {
        if case IETTError.fault(let message) = error, message.contains("Policy") {
            return "İETT servisi isteklerimizi geçici olarak sınırladı. Birkaç dakika içinde kendiliğinden düzelir."
        }
        if let limited = error as? IETTError, case .rateLimited = limited { return limited.localizedDescription }
        if error is URLError { return "İnternet bağlantısı yok ya da İETT servisine ulaşılamıyor." }
        return error.localizedDescription
    }
    func timetable(line: String) async -> [PlannedTrip] { (try? await client.timetable(line: line)) ?? [] }
    func notices(line: String? = nil) async -> [Duyuru] {
        let all = (try? await client.notices()) ?? []
        guard let line else { return all }
        return all.filter { fold($0.line) == fold(line) }
    }

    // MARK: Konum ve durak arama
    func requestLocation() {
        if isDemo {
            if let previous = location { location = CLLocation(latitude: previous.coordinate.latitude, longitude: previous.coordinate.longitude) }
            return
        }
        locationError = nil
        switch manager.authorizationStatus {
        case .denied, .restricted:
            requestingLocation = false
            locationError = "Konum izni kapalı. Ayarlar’dan izin ver veya bir başlangıç durağı seç."
        case .notDetermined:
            requestingLocation = true
            manager.requestWhenInUseAuthorization()
        default:
            requestingLocation = true
            manager.requestLocation()
        }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedWhenInUse || status == .authorizedAlways { self.requestLocation() }
            else if status == .denied || status == .restricted {
                self.requestingLocation = false
                self.locationError = "Konum izni kapalı. Ayarlar’dan izin ver veya bir başlangıç durağı seç."
            }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in
            self.requestingLocation = false
            guard last.horizontalAccuracy >= 0 else { self.locationError = "Geçerli konum alınamadı. Yeniden dene."; return }
            self.locationError = nil
            self.location = last
            #if DEBUG
            await self.verifyCurrentRouteIfRequested()
            #endif
        }
    }
    #if DEBUG
    private func verifyCurrentRouteIfRequested() async {
        guard !routeVerificationStarted, let location, !stops.isEmpty,
              let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-verifyCurrentRoute=") }),
              let code = Int(argument.dropFirst("-verifyCurrentRoute=".count)), let destination = stop(code: code) else { return }
        routeVerificationStarted = true
        guard let result = await planTrip(from: nil, to: destination) else { return }
        let proof: [String: Any] = ["destination": code, "locationAgeSeconds": Date().timeIntervalSince(location.timestamp), "accuracyMeters": location.horizontalAccuracy,
                                   "direct": result.direct.count, "oneTransfer": result.transfers.count,
                                   "multi": result.multi.map { $0.legs.map { ["line": $0.line, "board": String($0.board.code), "alight": String($0.alight.code)] } }]
        if let data = try? JSONSerialization.data(withJSONObject: proof) { try? data.write(to: URL.cachesDirectory.appending(path: "route-verification.json"), options: .atomic) }
    }
    #endif
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.requestingLocation = false
            self.locationError = "Konum alınamadı. Açık bir alanda yeniden dene veya bir başlangıç durağı seç."
        }
    }

    static func isUsableLocation(_ location: CLLocation?, now: Date = .now) -> Bool {
        guard let location else { return false }
        return location.horizontalAccuracy >= 0 && abs(now.timeIntervalSince(location.timestamp)) <= 120
    }

    func nearestStops(to point: CLLocationCoordinate2D, limit: Int = 25, within meters: Double = 3000) -> [(stop: Durak, meters: Double)] {
        stops.map { ($0, point.distance(to: $0.coordinate)) }.filter { $0.1 <= meters }.sorted { $0.1 < $1.1 }.prefix(limit).map { $0 }
    }
    /// Ad (aksan/harf büyüklüğü duyarsız) ve isteğe bağlı konuma yakınlığa göre durak bulur.
    func searchStops(_ query: String, near point: CLLocationCoordinate2D? = nil, limit: Int = 8) -> [Durak] {
        let needle = fold(query).trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        let tokens = needle.split(separator: " ").map(String.init)
        // Adı bütün sözcükleri taşıyan duraklar önce; yalnız ilçe adıyla eşleşenler (ör. "İskele" + Kadıköy) sonra gelir.
        var named: [Durak] = [], byDistrict: [Durak] = []
        for stop in stops {
            let name = fold(stop.name)
            if tokens.allSatisfy({ name.contains($0) }) { named.append(stop) }
            else if tokens.allSatisfy({ (name + " " + fold(stop.district)).contains($0) }) { byDistrict.append(stop) }
        }
        func order(_ list: inout [Durak]) {
            if let point { list.sort { $0.coordinate.distance(to: point) < $1.coordinate.distance(to: point) } }
            else { list.sort { $0.name.count < $1.name.count } }
        }
        order(&named); order(&byDistrict)
        return Array((named + byDistrict).prefix(limit))
    }
    func stops(inRegionCenter center: CLLocationCoordinate2D, latSpan: Double, lonSpan: Double, limit: Int = 80) -> [Durak] {
        let found = stops.filter { abs($0.lat - center.latitude) <= latSpan / 2 && abs($0.lon - center.longitude) <= lonSpan / 2 }
        return Array(found.sorted { $0.coordinate.distance(to: center) < $1.coordinate.distance(to: center) }.prefix(limit))
    }

    // MARK: Takip listesi
    func isFollowing(line: String) -> Bool { followedLines.contains(line) }
    func toggleFollow(line: String) {
        if let index = followedLines.firstIndex(of: line) { followedLines.remove(at: index); lineSummaries[line] = nil } else { followedLines.append(line) }
        SharedStore.defaults.set(followedLines, forKey: "followlines.v1")
        Task { await refreshLineSummaries() }
    }
    /// Takip edilen hatların özeti: yoldaki araç sayısı ve konuma en yakın durağa varış (kota: hat başına önbellekli tek çağrı).
    func refreshLineSummaries() async {
        if isDemo { return }
        var result: [String: LineSummary] = [:]
        for line in followedLines {
            let buses = await self.buses(line: line)
            result[line] = LineSummary.make(line: line, buses: buses, route: await route(line), user: location?.coordinate, hat: self.line(line), tracker: tracker)
        }
        lineSummaries = result
    }
    func isFavoriteStop(_ code: Int) -> Bool { favoriteStops.contains(code) }
    func toggleFavoriteStop(_ code: Int) {
        if let index = favoriteStops.firstIndex(of: code) { favoriteStops.remove(at: index) } else { favoriteStops.append(code) }
        SharedStore.saveFavoriteStops(favoriteStops)
        WidgetCenter.shared.reloadAllTimelines()
    }
    /// Yıldızlı duraklar (adlarıyla); durak listesi yüklenmediyse takip kayıtlarından ad bulunur.
    var favoriteStopList: [Durak] { favoriteStops.compactMap { stop(code: $0) } }
    func saveTrip(_ trip: SavedTrip) { savedTrips.append(trip); SharedStore.saveTrips(savedTrips) }
    func removeTrip(_ trip: SavedTrip) { savedTrips.removeAll { $0.id == trip.id }; SharedStore.saveTrips(savedTrips) }

    /// Nereden (durak ya da konumum) nereye: aktarmasız ve (aktarmasız azsa) tek aktarmalı seçenekler. Konum yoksa nil.
    func planTrip(from fromStop: Durak?, to destination: Durak) async -> (direct: [TripOption], transfers: [TransferOption], multi: [MultiTripOption])? {
        guard !Task.isCancelled, fromStop != nil || Self.isUsableLocation(location),
              let origin = fromStop?.coordinate ?? location?.coordinate else { return nil }
        var origins = nearestStops(to: origin, limit: 30, within: 900).map { (stop: $0.stop, meters: $0.meters) }
        var destinations = nearestStops(to: destination.coordinate, limit: 30, within: 650).map { (stop: $0.stop, meters: $0.meters) }
        if let fromStop, !origins.contains(where: { $0.stop.code == fromStop.code }) { origins.insert((fromStop, 0), at: 0) }
        if !destinations.contains(where: { $0.stop.code == destination.code }) { destinations.insert((destination, 0), at: 0) }
        let direct = await TripPlanner.direct(origins: origins, destinations: destinations, lines: { await self.linesAtStop($0) }, route: { await self.route($0) }, hat: { self.line($0) })
        guard !Task.isCancelled else { return nil }
        // Yakın aktarma durakları için mekânsal hücreler: her güzergâh noktasında tüm durakları taramayız.
        let cell = 0.003
        func key(_ lat: Double, _ lon: Double) -> String { "\(Int(floor(lat / cell))):\(Int(floor(lon / cell)))" }
        var buckets: [String: [Durak]] = [:]
        for stop in stops { buckets[key(stop.lat, stop.lon), default: []].append(stop) }
        let transfers = direct.count >= 3 ? [] : await TripPlanner.withTransfer(origins: origins, destinations: destinations, lines: { await self.linesAtStop($0) }, route: { await self.route($0) }, hat: { self.line($0) }, transferStops: { stop in
            let latCell = Int(floor(stop.lat / cell)), lonCell = Int(floor(stop.lon / cell))
            var found: [(code: Int, meters: Double)] = [(stop.code, 0)]
            for x in -1...1 { for y in -1...1 {
                let items = buckets["\(latCell + x):\(lonCell + y)"] ?? []
                for candidate in items where candidate.code != stop.code {
                    let distance = stop.coordinate.distance(to: candidate.coordinate)
                    if distance <= 250 { found.append((candidate.code, distance)) }
                }
            } }
            return found.sorted { $0.meters < $1.meters }
        })
        var multi: [MultiTripOption] = []
        if direct.isEmpty && transfers.isEmpty && !Task.isCancelled {
            let routes = await RouteStore.shared.cachedRoutes()
            let start = origins, end = destinations, hats = lines
            let work = Task.detached(priority: .userInitiated) {
                TripPlanner.multiTransfer(origins: start, destinations: end, routes: routes, hats: hats)
            }
            multi = await withTaskCancellationHandler(operation: { await work.value }, onCancel: { work.cancel() })
        }
        return (direct, transfers, multi)
    }
    /// Binişe sıradaki planlı geçişe kalan dakika (kotasız sefer saatleri + biniş durağı kayması).
    func nextScheduledWait(_ option: TripOption) async -> Int? {
        let trips = await timetable(line: option.line)
        let times = Timetable.times(trips, dayType: IETTDates.dayType(), direction: option.direction)
        guard let hat = line(option.line), let route = await route(option.line), let stops = route.stops[option.direction],
              let index = route.stopIndex(code: option.board.code, direction: option.direction) else { return nil }
        let geometry = RouteGeometry(stops: stops)
        let offset = Timetable.offsetMinutes(tripMinutes: hat.tripMinutes, stopAlong: geometry.cumulative[index], routeLength: geometry.length) ?? 0
        let now = Timetable.nowMinutes()
        return Timetable.upcoming(times, offset: offset, nowMinutes: now, count: 1).first.map { $0 - now }
    }
    func stop(code: Int) -> Durak? {
        if let found = stopsByCode[code] { return found }
        if let favorite = favorites.first(where: { $0.stopCode == code }) { return Durak(code: code, name: favorite.stopName, lat: favorite.lat, lon: favorite.lon) }
        return nil
    }
    func noteVisit(line: String) {
        recentLines.removeAll { $0 == line }; recentLines.insert(line, at: 0); recentLines = Array(recentLines.prefix(8))
        SharedStore.defaults.set(recentLines, forKey: "recent.lines")
    }
    func noteVisit(stop: Int) {
        recentStops.removeAll { $0 == stop }; recentStops.insert(stop, at: 0); recentStops = Array(recentStops.prefix(8))
        SharedStore.defaults.set(recentStops, forKey: "recent.stops")
    }
    func togglePin(line: String) {
        if pinnedLines.contains(line) { pinnedLines.removeAll { $0 == line } } else { pinnedLines.append(line) }
        SharedStore.defaults.set(pinnedLines, forKey: "pinned.lines")
    }
    func refreshBoardNotices() async {
        if isDemo { return }
        let wanted = Set(favorites.map(\.line)).union(pinnedLines)
        guard !wanted.isEmpty else { boardNotices = []; return }
        let all = (try? await client.notices()) ?? []
        boardNotices = all.filter { wanted.contains($0.line) }.sorted { NoticeClassifier.severity($0.message) > NoticeClassifier.severity($1.message) }
        await processNotices(all)
    }
    func note(for key: String) -> String { notes[key] ?? "" }
    func setNote(_ text: String, for key: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { notes[key] = nil } else { notes[key] = text }
        SharedStore.saveNotes(notes)
    }
    func isFavorite(line: String, stop: Int) -> Bool { favorites.contains { $0.line == line && $0.stopCode == stop } }
    func toggleFavorite(line: String, stop: Durak) {
        if let index = favorites.firstIndex(where: { $0.line == line && $0.stopCode == stop.code }) { favorites.remove(at: index) }
        else { favorites.append(.init(line: line, stopCode: stop.code, stopName: stop.name, lat: stop.lat, lon: stop.lon)) }
        persistFavorites()
    }
    func remove(_ favorite: Favorite) {
        favorites.removeAll { $0.id == favorite.id }
        rules[favorite.id] = nil; SharedStore.saveRules(rules)
        persistFavorites()
        Task { await rescheduleAlerts() }
    }
    func refreshFavorites() async {
        if isDemo { return }
        var byLine: [String: [Bus]] = [:]
        for line in Set(favorites.map(\.line)) { byLine[line] = await buses(line: line) }
        var result: [String: [BusETA]] = [:]
        for favorite in favorites {
            result[favorite.id] = await etas(line: favorite.line, buses: byLine[favorite.line] ?? [], stop: favorite.coordinate, stopCode: favorite.stopCode)
        }
        favoriteETAs = result; lastRefresh = .now
        checkAlerts()
        await updateDelayAlerts()
        await refreshLineSummaries()
    }

    // MARK: Yaklaşınca haber ver
    /// Eski hızlı alarm menüsü: kural yoksa tek "yaklaşınca" kuralı üretir; `nil` bildirimi kapatır.
    func setAlert(_ favorite: Favorite, minutes: Int?) {
        guard let index = favorites.firstIndex(where: { $0.id == favorite.id }) else { return }
        favorites[index].alertMinutes = minutes
        persistFavorites()
        if let minutes { setRule(AlertRule(leadMinutes: minutes, days: Set(1...7), startMinute: 0, endMinute: 24 * 60 - 1, passing: false, origin: false, live: true, delay: false, notices: false), for: favorite) }
        else { setRule(nil, for: favorite) }
    }
    private func persistFavorites() {
        SharedStore.save(favorites)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Bildirim kuralları
    func rule(for favorite: Favorite) -> AlertRule? { rules[favorite.id] }
    func setRule(_ rule: AlertRule?, for favorite: Favorite) {
        if let rule { rules[favorite.id] = rule } else { rules[favorite.id] = nil }
        SharedStore.saveRules(rules)
        if rule?.enabled == true { Task { await Notifier.authorize() } }
        Task { await rescheduleAlerts() }
    }
    /// Planlı geçiş/kalkış bildirimlerini güncel favori ve kurallarla yeniden kurar.
    func rescheduleAlerts() async {
        if isDemo { return }
        plannedAlertCount = await AlertScheduler.reschedule(favorites: favorites, rules: rules, hat: { self.line($0) })
    }
    /// Favori hatlardaki yeni duyuruları (iptal/ertelendi/uyarı) bildirir; rule.notices kapalı olanlar hariç.
    func processNotices(_ all: [Duyuru]) async {
        let lines = Set(favorites.filter { rules[$0.id]?.notices ?? true }.map(\.line))
        await NoticeAlerts.process(all, lines: lines)
    }

    /// Favorinin bugünkü planlı geçiş anları (kotasız sefer saatleri + durak kayması).
    func scheduledPassings(for favorite: Favorite, now: Date = .now) async -> [Date] {
        let trips = await timetable(line: favorite.line)
        guard !trips.isEmpty else { return [] }
        let route = await route(favorite.line)
        let directions = route?.directions(serving: favorite.stopCode) ?? []
        var minutes: Set<Int> = []
        for direction in directions.isEmpty ? Array(Set(trips.map(\.direction))) : directions {
            var offset = 0
            if let route, let stops = route.stops[direction], let index = route.stopIndex(code: favorite.stopCode, direction: direction), let hat = line(favorite.line) {
                let geometry = RouteGeometry(stops: stops)
                offset = Timetable.offsetMinutes(tripMinutes: hat.tripMinutes, stopAlong: geometry.cumulative[index], routeLength: geometry.length) ?? 0
            }
            for m in Timetable.times(trips, dayType: IETTDates.dayType(now), direction: direction) { minutes.insert(m + offset) }
        }
        return minutes.sorted().map { BoardFormat.date(minutes: $0, on: now) }
    }

    /// Alarmlı takipte ilk araç eşiğe girince tek bildirim (aynı araç için 15 dk tekrar yok). Kural varsa gün/saat penceresi ve süre ondan gelir.
    func checkAlerts(now: Date = .now) {
        for favorite in favorites {
            let rule = rules[favorite.id]
            let limit: Double
            if let rule { guard rule.live, rule.isActive(on: now) else { continue }; limit = Double(rule.leadMinutes) }
            else if let minutes = favorite.alertMinutes { limit = Double(minutes) } else { continue }
            guard let eta = favoriteETAs[favorite.id]?.first, eta.minutes(at: now) <= limit else { continue }
            let key = favorite.id + "|" + eta.id
            if let last = notified[key], now.timeIntervalSince(last) < 900 { continue }
            notified[key] = now
            let title = eta.state == .atStop ? "🟢 \(favorite.line) durakta" : "🟢 \(favorite.line) yaklaşıyor: \(eta.text)"
            let body = favorite.stopName + (eta.stopsLeft.map { $0 > 0 ? " · \($0) durak kaldı" : "" } ?? "")
            Task { await Notifier.post(id: key, title: title, body: body, important: true) }
        }
    }

    /// Gecikme: canlı araç planlı geçişten ≥6 dk geç gösteriliyorsa ekranda uyarı, kural açıksa bildirim (aynı favori için 30 dk'da bir).
    func updateDelayAlerts(now: Date = .now) async {
        var alerts: [LiveAlert] = []
        for favorite in favorites {
            let rule = rules[favorite.id]
            guard rule?.delay ?? true, rule?.isActive(on: now) ?? true, let eta = favoriteETAs[favorite.id]?.first, eta.state != .atStop else { continue }
            let arrival = eta.asOf.addingTimeInterval(eta.minutes * 60)
            let scheduled = await scheduledPassings(for: favorite, now: now)
            guard let late = DelayEstimator.delay(scheduled: scheduled, arrival: arrival) else { continue }
            let minutes = Int((late / 60).rounded())
            alerts.append(LiveAlert(id: "delay|\(favorite.id)", line: favorite.line, text: "\(favorite.line) · \(favorite.stopName): planlıdan ~\(minutes) dk gecikmeli", severity: .warning))
            if rule?.delay == true {
                let key = "delay|\(favorite.id)|\(Int(now.timeIntervalSince1970 / 1800))"
                if notified[key] == nil { notified[key] = now; await Notifier.post(id: key, title: "🟠 \(favorite.line) gecikiyor", body: "\(favorite.stopName): planlıdan ~\(minutes) dk geç gelecek") }
            }
        }
        liveAlerts = alerts
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
}

/// Takip ekranındaki canlı uyarı (gecikme vb.).
struct LiveAlert: Identifiable, Hashable {
    let id: String, line: String, text: String
    let severity: AlertSeverity
}
