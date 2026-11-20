import Foundation

/// #43: adlı podcast ayar profilleri ("Sabah tekrarı", "Sınav haftası"). Kısayollar ve kuyruk tek dokunuşla kullanır.
nonisolated struct PodcastProfile: Codable, Hashable, Sendable, Identifiable {
    var name: String
    var settings: PodcastSettings
    var id: String { name }
}

nonisolated enum PodcastProfiles {
    static let key = "podcast.profiles"
    static let maxCount = 20

    static var all: [PodcastProfile] {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([PodcastProfile].self, from: $0) } ?? []
    }

    static func settings(named name: String) -> PodcastSettings? {
        let wanted = name.trimmingCharacters(in: .whitespaces)
        return all.first { $0.name == wanted }?.settings
    }

    /// Aynı adlı profil güncellenir. Bölüme özgü bağlam (seri, yönergeler, türev) saklanmaz.
    static func save(_ name: String, settings: PodcastSettings) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !trimmed.isEmpty else { return }
        store(upserting(all, name: trimmed, settings: settings))
    }

    static func delete(_ name: String) {
        store(all.filter { $0.name != name })
    }

    /// Saf: en yeni başta, en çok `maxCount`.
    static func upserting(_ list: [PodcastProfile], name: String, settings: PodcastSettings) -> [PodcastProfile] {
        let profile = PodcastProfile(name: name, settings: settings.reusable)
        return Array(([profile] + list.filter { $0.name != name }).prefix(maxCount))
    }

    private static func store(_ list: [PodcastProfile]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: key)
    }
}
