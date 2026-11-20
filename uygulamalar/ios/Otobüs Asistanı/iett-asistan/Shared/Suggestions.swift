import Foundation

/// Asistan için kişiselleştirilmiş hazır soru.
struct Suggestion: Hashable, Identifiable {
    var text: String, icon: String, group: String
    var id: String { text }
}

enum SuggestionBuilder {
    static let groupStops = "Favori duraklarım", groupLines = "Hatlarım", groupGeneral = "Genel"

    /// Favori (hat, durak) çiftlerinden, yıldızlı duraklardan, sabit/son bakılan hatlardan ve konumdan soru üretir.
    /// Hiç kişisel veri yoksa genel örnekler döner. Sorular `LocalAssistant.parse` ile çözülebilecek biçimdedir.
    static func make(favorites: [Favorite], favoriteStops: [(code: Int, name: String)], pinned: [String], recent: [String], hasLocation: Bool, limit: Int = 18) -> [Suggestion] {
        var result: [Suggestion] = []
        func add(_ text: String, _ icon: String, _ group: String) { if !result.contains(where: { $0.text == text }) { result.append(.init(text: text, icon: icon, group: group)) } }

        // Favori durak soruları: önce takip edilen (hat, durak) çiftleri, sonra yıldızlı duraklar.
        for favorite in favorites.prefix(4) { add("\(favorite.stopName) durağına \(favorite.line) kaç dk?", "bus", groupStops) }
        var seenStops = Set(favorites.map(\.stopCode))
        for stop in favoriteStops.prefix(5) {
            add("\(stop.name) durağından hangi hatlar geçer?", "mappin.and.ellipse", groupStops)
            seenStops.insert(stop.code)
        }
        for favorite in favorites.prefix(3) where !favoriteStops.contains(where: { $0.code == favorite.stopCode }) {
            add("\(favorite.stopName) durağından hangi hatlar geçer?", "mappin.and.ellipse", groupStops)
        }

        // Hat soruları: takip edilen, sabitlenen ve son bakılan hatlar (tekrarsız, en çok 4 hat).
        var lines: [String] = []
        for code in favorites.map(\.line) + pinned + recent where !lines.contains(code) { lines.append(code) }
        for code in lines.prefix(4) {
            add("\(code) nerede?", "dot.radiowaves.left.and.right", groupLines)
            add("\(code) sefer saatleri", "clock", groupLines)
            add("\(code) duyuru var mı?", "exclamationmark.bubble", groupLines)
        }

        if hasLocation { add("Yakınımdaki duraklar", "location", groupGeneral) }
        add("Bugün hangi hatlarda duyuru var?", "megaphone", groupGeneral)
        if result.filter({ $0.group != groupGeneral }).isEmpty {
            // Henüz favori yok: başlangıç örnekleri.
            for s in [("500T nerede?", "dot.radiowaves.left.and.right"), ("500T sefer saatleri", "clock"), ("Kadıköy çarşı durağından hangi hatlar geçer?", "mappin.and.ellipse"),
                      ("14M duyuru var mı?", "exclamationmark.bubble"), ("4.Levent metro durağına 500T kaç dk?", "bus")] { add(s.0, s.1, groupGeneral) }
        }
        return Array(result.prefix(limit))
    }

    /// Bir cevaptan sonra önerilen devam soruları (hat ya da durak bağlamına göre).
    static func followUps(line: String?, stopName: String?) -> [Suggestion] {
        var list: [Suggestion] = []
        if let line {
            list += [.init(text: "\(line) sefer saatleri", icon: "clock", group: "Devam"), .init(text: "\(line) duyuru var mı?", icon: "exclamationmark.bubble", group: "Devam")]
            if let stopName { list.append(.init(text: "\(stopName) durağına \(line) kaç dk?", icon: "bus", group: "Devam")) }
            list.append(.init(text: "\(line) nerede?", icon: "dot.radiowaves.left.and.right", group: "Devam"))
        }
        if let stopName { list.append(.init(text: "\(stopName) durağından hangi hatlar geçer?", icon: "mappin.and.ellipse", group: "Devam")) }
        return list
    }
}
