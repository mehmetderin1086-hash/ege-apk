import SwiftUI

/// Uygulamadaki bütün hedefler: her sekme kendi yığınında bunları açar; asistan, widget ve bildirimler de aynı yolu kullanır.
enum Route: Hashable {
    case line(code: String, stop: Int?)
    case timetable(code: String, direction: String?, stop: Int?)
    case lineInfo(code: String)
    case stop(code: Int)
    case notes
    case settings
    case trip(id: String)
    case favoriteStops
    case railStations
}

extension Route {
    /// `iettasistan://line/500T?stop=1`, `…://stop/1`, `…://timetable/500T`
    init?(url: URL) {
        guard let link = DeepLink.parse(url) else { return nil }
        switch link.kind {
        case "line": self = .line(code: link.id, stop: link.stop)
        case "timetable": self = .timetable(code: link.id, direction: nil, stop: link.stop)
        case "stop": guard let code = Int(link.id) else { return nil }; self = .stop(code: code)
        default: return nil
        }
    }
}

/// Bir sekmenin gezinme durumu: yığın + ileri yığını (tarayıcı gibi geri/ileri).
@Observable @MainActor final class Navigator {
    var path: [Route] = []
    private(set) var forward: [Route] = []
    private var programmatic = false
    var canBack: Bool { !path.isEmpty }
    var canForward: Bool { !forward.isEmpty }

    func push(_ route: Route) { path.append(route) }
    func back() {
        guard let last = path.last else { return }
        programmatic = true; forward.append(last); path.removeLast()
    }
    func goForward() {
        guard let next = forward.last else { return }
        programmatic = true; forward.removeLast(); path.append(next)
    }
    /// Kök ekrana dön; geri dönülebilsin diye yığın ileri listesine taşınır.
    func home() {
        guard !path.isEmpty else { return }
        programmatic = true; forward.append(contentsOf: path.reversed()); path.removeAll()
    }
    /// Sistem hareketi (kenardan kaydırma) ya da NavigationLink yığını değiştirdiğinde ileri listesini tutarlı tutar.
    func pathChanged(old: [Route], new: [Route]) {
        if programmatic { programmatic = false; return }
        if new.count < old.count { forward.append(contentsOf: old.suffix(old.count - new.count).reversed()) }
        else if new.count > old.count { forward.removeAll() }
    }
}

struct NavNamespaceKey: EnvironmentKey { static let defaultValue: Namespace.ID? = nil }
extension EnvironmentValues { var zoomNamespace: Namespace.ID? { get { self[NavNamespaceKey.self] } set { self[NavNamespaceKey.self] = newValue } } }

/// Sekme kökü: NavigationStack + yüzen geri/ileri/ana sayfa çubuğu.
struct TabStack<Root: View>: View {
    @Bindable var nav: Navigator
    @ViewBuilder var root: () -> Root
    var body: some View {
        NavigationStack(path: $nav.path) {
            root().navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .environment(nav)
        .onChange(of: nav.path) { old, new in nav.pathChanged(old: old, new: new) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if nav.canBack || nav.canForward { NavBar(nav: nav).padding(.bottom, 4).transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .animation(.spring(duration: 0.45, bounce: 0.3), value: nav.canBack || nav.canForward)
    }
}

struct NavBar: View {
    @Bindable var nav: Navigator
    var body: some View {
        HStack(spacing: 6) {
            Button { nav.back() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 36) }.disabled(!nav.canBack).accessibilityLabel("Geri")
            Divider().frame(height: 18)
            Button { nav.home() } label: { Image(systemName: "house.fill").frame(width: 44, height: 36) }.disabled(!nav.canBack).accessibilityLabel("Sekmenin ana sayfasına dön")
            Divider().frame(height: 18)
            Button { nav.goForward() } label: { Image(systemName: "chevron.right").frame(width: 44, height: 36) }.disabled(!nav.canForward).accessibilityLabel("İleri")
        }
        .font(.body.weight(.semibold))
        .padding(.horizontal, 8)
        .background(.regularMaterial, in: .capsule)
        .overlay(Capsule().stroke(.white.opacity(0.15)))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        .sensoryFeedback(.selection, trigger: nav.path)
    }
}

/// Rota → ekran. Eksik veri (örn. hat listesi henüz yüklenmedi) için yer tutucu gösterir.
struct RouteView: View {
    let route: Route
    @Environment(AppModel.self) private var model
    @Environment(\.zoomNamespace) private var zoom
    var body: some View {
        switch route {
        case .line(let code, let stopCode):
            if let hat = model.line(code) {
                let favorite = stopCode.flatMap { model.stop(code: $0) }.map { Favorite(line: code, stopCode: $0.code, stopName: $0.name, lat: $0.lat, lon: $0.lon) }
                LineDetailView(hat: hat, preselected: favorite)
                    .modifier(ZoomIfPossible(id: "\(code)-\(stopCode ?? 0)", namespace: zoom))
            } else { Missing(title: "\(code) hattı") }
        case .timetable(let code, let direction, let stopCode):
            if let hat = model.line(code) { TimetableView(hat: hat, initialDirection: direction, stop: stopCode.flatMap { model.stop(code: $0) }) } else { Missing(title: "\(code) hattı") }
        case .lineInfo(let code):
            if let hat = model.line(code) { LineInfoView(hat: hat) } else { Missing(title: "\(code) hattı") }
        case .stop(let code):
            if let stop = model.stop(code: code) { StopDetailView(stop: stop) } else { Missing(title: "\(code) numaralı durak") }
        case .notes: NotesView()
        case .favoriteStops: FavoriteStopsView()
        case .railStations: RailStationsView().navigationTitle("Raylı sistem").navigationBarTitleDisplayMode(.inline)
        case .settings: SettingsView()
        case .trip(let id):
            if let trip = model.savedTrips.first(where: { $0.id == id }), let to = model.stop(code: trip.toCode) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("\(trip.fromName) → \(trip.toName)", systemImage: "star.circle.fill").font(.headline).foregroundStyle(.orange)
                        TripResultsView(fromStop: trip.fromCode.flatMap { model.stop(code: $0) }, destination: to, allowSave: false)
                    }.padding(.horizontal).padding(.bottom, 24)
                }.background { AuroraBackground() }.navigationTitle(trip.name).navigationBarTitleDisplayMode(.inline)
            } else { Missing(title: "Kayıtlı yolculuk") }
        }
    }
}

struct ZoomIfPossible: ViewModifier {
    let id: String, namespace: Namespace.ID?
    func body(content: Content) -> some View {
        if let namespace { content.navigationTransition(.zoom(sourceID: id, in: namespace)) } else { content }
    }
}

struct Missing: View {
    let title: String
    @Environment(AppModel.self) private var model
    var body: some View {
        ContentUnavailableView(model.isLoading ? "Yükleniyor…" : "\(title) bulunamadı", systemImage: "questionmark.folder", description: Text("Hat ve durak listesi yüklenince bu sayfa açılır."))
    }
}
