import SwiftUI
import MapKit
import CoreLocation

struct MosquePlace: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: Double?
    let mapItem: MKMapItem
}

/// Ezan Vakti Pro "Yakındaki Camiler" (s10.png) Modülü — MapKit MKLocalSearch ile gerçek zamanlı cami bulucu ve yol tarifi.
struct NearbyMosquesView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var mosques: [MosquePlace] = []
    @State private var isLoading = false

    @State private var radius = 5000.0
    @State private var searchError: String?

    private var searchKey: String { "\(settings.location?.id ?? "none")|\(radius)" }


    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(settings.location.map { "\($0.name) çevresinde" } ?? "Önce Ayarlar’dan konum seçin")
                        .font(.subheadline).foregroundStyle(Palette.textPrimary)
                    Picker("Arama mesafesi", selection: $radius) {
                        Text("2 km").tag(2000.0)
                        Text("5 km").tag(5000.0)
                        Text("10 km").tag(10000.0)
                    }.pickerStyle(.segmented)
                    Text("Mesafeler seçili konumdan kuş uçuşudur.")
                        .font(.caption).foregroundStyle(Palette.textSecondary)
                }.padding()

                Map(position: $cameraPosition) {
                    ForEach(mosques) { m in
                        Annotation(m.name, coordinate: m.coordinate) {
                            VStack(spacing: 2) {
                                Image(systemName: "moon.stars.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(Palette.accent)
                                    .background(Circle().fill(.white))
                                Text(m.name)
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .frame(height: 250)

                if isLoading {
                    ProgressView("Yakındaki camiler aranıyor…")
                        .padding(.top, 36)
                    Spacer()
                } else if mosques.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "building.columns.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Palette.textSecondary)
                        Text(searchError ?? "Seçilen mesafede cami bulunamadı. Arama mesafesini artırabilirsiniz.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Palette.textSecondary)
                        Button("Tekrar Ara") {
                            Task { await searchMosques() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 40)
                    Spacer()
                } else {
                    List(mosques) { m in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Palette.accent.opacity(0.15))
                                    .frame(width: 42, height: 42)
                                Image(systemName: "moon.stars.fill")
                                    .foregroundStyle(Palette.accent)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(m.name)
                                    .font(.headline)
                                    .foregroundStyle(Palette.textPrimary)
                                HStack(spacing: 6) {
                                    if let d = m.distanceMeters {
                                        Text(d < 1000 ? "\(Int(d)) m" : String(format: "%.1f km", d / 1000))
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(Palette.gold)
                                    }
                                    if !m.subtitle.isEmpty {
                                        Text(m.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(Palette.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            Spacer()
                            Button {
                                m.mapItem.openInMaps(launchOptions: [
                                    MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
                                ])
                            } label: {
                                Label("Yol Tarifi", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(Palette.accent)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                    .safeAreaPadding(.bottom, 90)
                }
            }
        }
        .navigationTitle("Yakındaki Camiler")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: searchKey) {
            await searchMosques()
        }
    }

    @MainActor
    private func searchMosques() async {
        guard let center = settings.location?.coordinate,
              CLLocationCoordinate2DIsValid(center) else {
            mosques = []
            searchError = "Konum bulunamadı. Ayarlar’dan konum seçip tekrar deneyin."
            return
        }
        isLoading = true
        searchError = nil
        mosques = []
        let requestedKey = searchKey
        let searchRadius = radius
        cameraPosition = .region(MKCoordinateRegion(center: center,
            latitudinalMeters: searchRadius * 2.4, longitudinalMeters: searchRadius * 2.4))
        do {
            let results = try await MosqueSearch.find(center: center, radius: searchRadius)
            guard !Task.isCancelled, requestedKey == searchKey else { return }
            mosques = results
        } catch {
            guard !Task.isCancelled, requestedKey == searchKey else { return }
            searchError = "Cami arama servisine ulaşılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin."
        }
        guard !Task.isCancelled, requestedKey == searchKey else { return }
        isLoading = false
    }
}

/// MapKit's region is only a bias unless explicitly required. Always apply a
/// geodesic radius too, and request POIs so the Tuzla neighbourhood “Cami” is excluded.
enum MosqueSearch {
    static func nearby(_ items: [MKMapItem], center: CLLocationCoordinate2D, radius: Double) -> [MosquePlace] {
        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
        var places: [MosquePlace] = []
        for item in items {
            let coordinate = item.placemark.coordinate
            guard CLLocationCoordinate2DIsValid(coordinate) else { continue }
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let distance = origin.distance(from: location)
            guard distance <= radius else { continue }
            let name = item.name ?? "Cami"
            guard !places.contains(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame &&
                CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude).distance(from: location) < 80
            }) else { continue }
            places.append(MosquePlace(name: name,
                subtitle: item.placemark.thoroughfare ?? item.placemark.locality ?? "",
                coordinate: coordinate, distanceMeters: distance, mapItem: item))
        }
        return places.sorted { ($0.distanceMeters ?? 0) < ($1.distanceMeters ?? 0) }
    }

    @MainActor
    static func find(center: CLLocationCoordinate2D, radius: Double) async throws -> [MosquePlace] {
        var items: [MKMapItem] = []
        var lastError: Error?
        var succeeded = false
        for query in ["camiler", "mosque", "mescit"] {
            try Task.checkCancellation()
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = .pointOfInterest
            request.region = MKCoordinateRegion(center: center,
                latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
            if #available(iOS 18.0, *) { request.regionPriority = .required }
            do {
                let response = try await MKLocalSearch(request: request).start()
                items += response.mapItems
                succeeded = true
            } catch {
                // No matches is a valid empty result, not a connection failure.
                if let error = error as? MKError, error.code == .placemarkNotFound {
                    succeeded = true
                } else { lastError = error }
            }
        }
        try Task.checkCancellation()
        if !succeeded, let lastError { throw lastError }
        return nearby(items, center: center, radius: radius)
    }
}
