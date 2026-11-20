import Foundation

/// Uygulama ile widget aynı App Group'u kullanır: takip listesi ve indirilen güzergâhlar ortaktır.
enum SharedStore {
    static let group = "group.com.mehmetderin.iettasistan"
    static let favoritesKey = "favorites.v1"
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }
    static var routesFolder: URL {
        (FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) ?? URL.cachesDirectory).appending(path: "guzergah-v1", directoryHint: .isDirectory)
    }
    static func loadFavorites(from defaults: UserDefaults = SharedStore.defaults) -> [Favorite] {
        defaults.data(forKey: favoritesKey).flatMap { try? JSONDecoder().decode([Favorite].self, from: $0) } ?? []
    }
    static func save(_ favorites: [Favorite], to defaults: UserDefaults = SharedStore.defaults) {
        if let data = try? JSONEncoder().encode(favorites) { defaults.set(data, forKey: favoritesKey) }
    }
    static let notesKey = "notes.v1"
    static func loadNotes(from defaults: UserDefaults = SharedStore.defaults) -> [String: String] {
        defaults.data(forKey: notesKey).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }
    static func saveNotes(_ notes: [String: String], to defaults: UserDefaults = SharedStore.defaults) {
        if let data = try? JSONEncoder().encode(notes) { defaults.set(data, forKey: notesKey) }
    }
    static let tripsKey = "trips.v1"
    static func loadTrips(from defaults: UserDefaults = SharedStore.defaults) -> [SavedTrip] {
        defaults.data(forKey: tripsKey).flatMap { try? JSONDecoder().decode([SavedTrip].self, from: $0) } ?? []
    }
    static func saveTrips(_ trips: [SavedTrip], to defaults: UserDefaults = SharedStore.defaults) {
        if let data = try? JSONEncoder().encode(trips) { defaults.set(data, forKey: tripsKey) }
    }
    static let favoriteStopsKey = "favstops.v1"
    static func loadFavoriteStops(from defaults: UserDefaults = SharedStore.defaults) -> [Int] { (defaults.array(forKey: favoriteStopsKey) as? [Int]) ?? [] }
    static func saveFavoriteStops(_ stops: [Int], to defaults: UserDefaults = SharedStore.defaults) { defaults.set(stops, forKey: favoriteStopsKey) }
    /// Arka plan işi için hat süre/uzunluk özeti: kod → [uzunluk km, sefer süresi dk].
    static let hatStatsKey = "hatstats.v1"
    static func loadHatStats(from defaults: UserDefaults = SharedStore.defaults) -> [String: [Double]] { (defaults.dictionary(forKey: hatStatsKey) as? [String: [Double]]) ?? [:] }
    static func saveHatStats(_ lines: [Hat], to defaults: UserDefaults = SharedStore.defaults) {
        var stats: [String: [Double]] = [:]
        for hat in lines { if let km = hat.lengthKm, let minutes = hat.tripMinutes { stats[hat.code] = [km, minutes] } }
        defaults.set(stats, forKey: hatStatsKey)
    }
    static let rulesKey = "alertrules.v1"
    static func loadRules(from defaults: UserDefaults = SharedStore.defaults) -> [String: AlertRule] {
        defaults.data(forKey: rulesKey).flatMap { try? JSONDecoder().decode([String: AlertRule].self, from: $0) } ?? [:]
    }
    static func saveRules(_ rules: [String: AlertRule], to defaults: UserDefaults = SharedStore.defaults) {
        if let data = try? JSONEncoder().encode(rules) { defaults.set(data, forKey: rulesKey) }
    }
    /// Eski sürüm takip listesini (standart UserDefaults) ortak alana bir kez taşır.
    static func migrateIfNeeded() {
        guard defaults.data(forKey: favoritesKey) == nil, let old = UserDefaults.standard.data(forKey: favoritesKey) else { return }
        defaults.set(old, forKey: favoritesKey)
    }
}

/// Widget satırı: takipteki bir durak için ilk araç.
struct FavoriteSnapshot: Identifiable, Hashable {
    let favorite: Favorite, eta: BusETA?
    var id: String { favorite.id }

    /// Her hat için bir kez canlı araç ve güzergâh çeker; güzergâh yoksa kuş uçuşu tahmine düşer. Widget süreci kısa yaşar:
    /// konum geçmişi olmadığı için hız hat ortalamasıdır, tarihçe oluşmaz.
    static func load(_ favorites: [Favorite], client: IETTClient = .shared, store: RouteStore = .shared) async -> [FavoriteSnapshot] {
        var result: [FavoriteSnapshot] = []
        var busesByLine: [String: [Bus]] = [:]
        // Kota (saatte 100) uygulamayla ortak: payın yarısından azı kaldıysa widget ağa gitmez, uygulamaya bırakır.
        let canFetch = await FleetBudget.shared.remaining >= FleetBudget.hourlyLimit / 3
        for favorite in favorites {
            if busesByLine[favorite.line] == nil { busesByLine[favorite.line] = canFetch ? ((try? await client.buses(line: favorite.line, maxAge: 300)) ?? []) : [] }
            let buses = busesByLine[favorite.line] ?? [], tracker = LiveTracker()
            var etas: [BusETA]
            if let route = try? await store.route(favorite.line), !route.directions(serving: favorite.stopCode).isEmpty {
                etas = RouteETAEngine.etas(buses: buses, route: route, stopCode: favorite.stopCode, tracker: tracker)
            } else {
                etas = tracker.etas(buses: buses, stop: favorite.coordinate, stopCode: favorite.stopCode)
            }
            result.append(.init(favorite: favorite, eta: etas.first))
        }
        return result
    }
}
