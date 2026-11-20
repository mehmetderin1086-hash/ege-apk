import Foundation
import MapKit
import CoreLocation

/// Yer adı/adresini koordinata çevirir. Konum izni varsa kullanıcının çevresine öncelik verir (aynı adlı uzak yerler yerine).
nonisolated enum KonumCozucu {
    struct Sonuc: Sendable { let ad: String; let konum: CLLocation }

    static func bul(_ sorgu: String) async -> Sonuc? {
        let istek = MKLocalSearch.Request()
        istek.naturalLanguageQuery = sorgu
        let yakin: CLLocation? = await MainActor.run {
            let y = CLLocationManager()
            return [.authorizedWhenInUse, .authorizedAlways].contains(y.authorizationStatus) ? y.location : nil
        }
        if let yakin { istek.region = MKCoordinateRegion(center: yakin.coordinate, latitudinalMeters: 60_000, longitudinalMeters: 60_000) }
        guard let oge = try? await MKLocalSearch(request: istek).start().mapItems.first else { return nil }
        let k = oge.location
        return Sonuc(ad: oge.name ?? sorgu, konum: CLLocation(latitude: k.coordinate.latitude, longitude: k.coordinate.longitude))
    }
}
