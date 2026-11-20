import Foundation
import FoundationModels
import MapKit
import UIKit

nonisolated struct HaritaAraci: Tool {
    let name = "harita"
    let description = "Yakındaki yerleri arar (örn. 'eczane', 'kahveci') ya da bir hedefe yol tarifi için Haritalar'ı açar."

    @Generable
    struct Arguments {
        @Guide(description: "'ara' ya da 'yolTarifi'") var islem: String
        @Guide(description: "Aranan yer türü ya da hedef adres/ad") var sorgu: String
        @Guide(description: "yolTarifi: 'araba', 'yuruyus' ya da 'toplu' (isteğe bağlı)") var ulasim: String?
    }

    /// Alt ajan onay soramaz: yalnız arama yapabilir, Haritalar'ı (yan etki) açamaz.
    var yalnizAra = false

    func call(arguments a: Arguments) async throws -> String {
        if yalnizAra, a.islem.lowercased() == "yoltarifi" {
            return "Bu bağlamda yol tarifi açılamaz; yalnız 'ara' kullanılabilir. Yol tarifini ana asistan açar."
        }
        var konumNotu = ""
        let konum: CLLocation?
        do { konum = try await Konum.paylasilan.al() } catch { konum = nil; konumNotu = " (Konum alınamadı, izin verilmemiş olabilir; arama konumsuz yapıldı.)" }
        let istek = MKLocalSearch.Request()
        istek.naturalLanguageQuery = a.sorgu
        if let konum {
            istek.region = MKCoordinateRegion(center: konum.coordinate, latitudinalMeters: 5000, longitudinalMeters: 5000)
        }
        let yanit = try await MKLocalSearch(request: istek).start()
        let ogeler = yanit.mapItems
        guard !ogeler.isEmpty else { return "'\(a.sorgu)' için sonuç bulunamadı." }
        switch a.islem.lowercased() {
        case "yoltarifi":
            let hedef = Kutu(oge: ogeler[0])
            let mod: String = switch (a.ulasim ?? "").lowercased() {
                case "yuruyus", "yürüyüş": MKLaunchOptionsDirectionsModeWalking
                case "toplu": MKLaunchOptionsDirectionsModeTransit
                default: MKLaunchOptionsDirectionsModeDriving
            }
            await MainActor.run { hedef.oge.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: mod]) }
            // Yalnız Aç kartı: yol tarifini yeniden açar (geri alınacak bir şey yok).
            let k = hedef.oge.location.coordinate
            let ad = hedef.oge.name ?? a.sorgu
            await EylemKaydi(tur: .harita, baslik: "Yol tarifi: \(ad)", ozet: hedef.oge.address?.shortAddress ?? "Haritalar'da açıldı", kimlikler: [],
                             acAdresi: EylemKaydi.haritaAdresi(enlem: k.latitude, boylam: k.longitude)).kartaEkle()
            return "Haritalar'da yol tarifi açıldı: \(ad)."
        default:
            return konumNotu + ogeler.prefix(6).map { o in
                var satir = "• \(o.name ?? "?")"
                if let konum { satir += String(format: " — %.1f km", o.location.distance(from: konum) / 1000) }
                if let adres = o.address?.shortAddress { satir += ", \(adres)" }
                return satir
            }.joined(separator: "\n")
        }
    }
}

nonisolated private struct Kutu: @unchecked Sendable { let oge: MKMapItem }

/// Tek seferlik konum alımı.
final class Konum: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let paylasilan = Konum()
    private let yonetici = CLLocationManager()
    private var bekleyenler: [CheckedContinuation<CLLocation, any Error>] = []
    private let kilit = NSLock()

    override init() {
        super.init()
        yonetici.delegate = self
        yonetici.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func al() async throws -> CLLocation {
        if let l = yonetici.location, l.timestamp.timeIntervalSinceNow > -300 { return l }
        return try await withCheckedThrowingContinuation { c in
            kilit.withLock { bekleyenler.append(c) }
            if yonetici.authorizationStatus == .notDetermined { yonetici.requestWhenInUseAuthorization() }
            else { yonetici.requestLocation() }
        }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        switch m.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: m.requestLocation()
        case .denied, .restricted: bitir(.failure(CLError(.denied)))
        default: break
        }
    }
    func locationManager(_ m: CLLocationManager, didUpdateLocations l: [CLLocation]) {
        if let son = l.last { bitir(.success(son)) }
    }
    func locationManager(_ m: CLLocationManager, didFailWithError e: any Error) { bitir(.failure(e)) }

    private func bitir(_ sonuc: Result<CLLocation, any Error>) {
        let liste = kilit.withLock { let l = bekleyenler; bekleyenler = []; return l }
        liste.forEach { $0.resume(with: sonuc) }
    }
}
