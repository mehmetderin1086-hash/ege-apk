import Foundation

/// Bir durağın hizmet verdiği yön: varış (güzergâh sonu), güzergâhın o duraktaki gidiş yönü (derece) ve o yönde geçen hatlar.
struct StopDirectionInfo: Identifiable, Hashable {
    var destination: String
    /// Durağın güzergâhta bir sonraki durağa doğru yönü (kuzey = 0°, saat yönünde); belirlenemezse nil.
    var bearing: Double?
    var lines: [String]
    var id: String { destination + "|" + String(Int((bearing ?? -1) / 45)) }
    var compass: String? { bearing.map(CompassText.name) }
}

enum CompassText {
    /// 8 yön, Türkçe: "Kuzey", "Kuzeydoğu", "Doğu", "Güneydoğu", "Güney", "Güneybatı", "Batı", "Kuzeybatı".
    static func name(_ degrees: Double) -> String {
        let names = ["Kuzey", "Kuzeydoğu", "Doğu", "Güneydoğu", "Güney", "Güneybatı", "Batı", "Kuzeybatı"]
        let index = Int((degrees.truncatingRemainder(dividingBy: 360) + 360 + 22.5).truncatingRemainder(dividingBy: 360) / 45)
        return names[index]
    }
    /// "Güneydoğuya doğru", "Kuzeye doğru" (ünlü uyumu için bilinen sekiz yön).
    static func heading(_ degrees: Double) -> String {
        let base = name(degrees)
        let dative = ["Kuzey": "Kuzeye", "Kuzeydoğu": "Kuzeydoğuya", "Doğu": "Doğuya", "Güneydoğu": "Güneydoğuya", "Güney": "Güneye", "Güneybatı": "Güneybatıya", "Batı": "Batıya", "Kuzeybatı": "Kuzeybatıya"]
        return (dative[base] ?? base) + " doğru"
    }
}

enum StopDirections {
    /// `entries`: durağa uğrayan (hat, yön) çiftleri; `routes`: hat güzergâhları. Aynı varışa ve aynı yöne (45° dilim) giden hatlar gruplanır,
    /// hat sayısı çok olan yön önce gelir.
    static func make(stopCode: Int, entries: [RouteStore.Entry], routes: [String: LineRoute]) -> [StopDirectionInfo] {
        struct Key: Hashable { var destination: String; var sector: Int }
        var groups: [Key: (bearings: [Double], lines: [String])] = [:]
        for entry in entries {
            guard let route = routes[entry.line], let stops = route.stops[entry.direction], let index = stops.firstIndex(where: { $0.code == stopCode }) else { continue }
            let destination = route.destination(entry.direction)
            var bearing: Double?
            if index + 1 < stops.count { bearing = stops[index].coordinate.bearing(to: stops[index + 1].coordinate) }
            else if index > 0 { bearing = stops[index - 1].coordinate.bearing(to: stops[index].coordinate) }
            let key = Key(destination: destination, sector: bearing.map { Int((($0 + 22.5).truncatingRemainder(dividingBy: 360)) / 45) } ?? -1)
            var group = groups[key] ?? ([], [])
            if let bearing { group.bearings.append(bearing) }
            if !group.lines.contains(entry.line) { group.lines.append(entry.line) }
            groups[key] = group
        }
        return groups.map { key, group in
            // Ortalama yön: birim vektör toplamı (0°/360° sınırında doğru çalışır).
            let bearing = group.bearings.isEmpty ? nil : {
                let x = group.bearings.map { cos($0 * .pi / 180) }.reduce(0, +), y = group.bearings.map { sin($0 * .pi / 180) }.reduce(0, +)
                return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
            }()
            return StopDirectionInfo(destination: key.destination, bearing: bearing, lines: group.lines.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        }.sorted { ($1.lines.count, $0.destination) < ($0.lines.count, $1.destination) }
    }
}
