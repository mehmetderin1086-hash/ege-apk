import Foundation

/// What the app should do with a reply. The model only proposes; the app applies
/// local playback actions (never downloads or library deletions) and says so.
enum AIAction: String, Codable, Equatable {
    case none, play, queueNext = "queue_next"

    init(raw: Any?) {
        guard let text = raw as? String else { self = .none; return }
        self = AIAction(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .none
    }
}

/// The kind of request; each adds a short instruction to the shared system prompt.
enum AITask: String {
    case chat, dj, djContinue = "dj_continue", insight, daily, discover

    var instruction: String {
        switch self {
        case .chat:
            return "Görev: sohbet. Kullanıcı açıkça çalmak/dinlemek istiyorsa action=\"play\", sıraya eklemek istiyorsa action=\"queue_next\" ver; yoksa \"none\". Kullanıcı YouTube'da bir şey bulmak, aramak veya indirmek istiyorsa search_queries'in ilki onun aradığı, diğer ikisi benzer sanatçı/tür/havada somut aramalar olsun."
        case .dj:
            return "Görev: DJ seti. request alanındaki ruh hâline uygun, akışı düşünülmüş 10-15 parçalık sıralı bir liste kur. reply, DJ gibi 1-2 cümlelik sıcak bir açılış anonsu olsun. action=\"play\"."
        case .djContinue:
            return "Görev: DJ setini sürdür. listening_context.exclude_ids içindeki parçaları KULLANMA. Aynı ruh hâlinde 6-10 yeni parça seç ve geçişi anlatan tek cümlelik reply yaz. action=\"queue_next\"."
        case .insight:
            return "Görev: şimdi çalan parça hakkında not. reply en fazla 3 kısa cümle: parçanın/sanatçının havası ve ne zaman dinlenir. Kesin olmayan bilgi uydurma; emin değilsen genel konuş. playlist, kitaplıktan bu parçaya benzeyen en fazla 5 parça olsun (şimdi çalanı katma). search_queries'e 2 benzer keşif araması koy. action=\"none\"."
        case .daily:
            return "Görev: günün karışımı. listening_context'teki gün bölümüne ve dinleme geçmişine göre 8-15 parçalık bir liste seç. playlist.name kısa ve yaratıcı olsun; reply 1-2 cümlelik kişisel bir not olsun. action=\"none\"."
        case .discover:
            return "Görev: YouTube keşfi. request bir YouTube arama ifadesidir. search_queries alanına bu ifadeyle aynı sanatçı, tür, dönem veya havada 3 farklı benzer arama koy: somut sanatçı ve şarkı adları, isteğin dilinde. İsteği aynen tekrarlama. reply bu aramaları anlatan tek kısa cümle olsun. playlist null, action=\"none\"."
        }
    }
}

/// A short, cached AI note about one track.
struct AITrackInsight: Codable, Equatable {
    let trackID: UUID
    let text: String
    let similarIDs: [UUID]
    let searchQueries: [String]
    let model: String
    let createdAt: Date
}

/// One proactive mix per calendar day; regenerated only on request or the next day.
struct AIDailyMix: Codable, Equatable {
    let title: String
    let note: String
    let trackIDs: [UUID]
    let model: String
    let createdAt: Date
    let dayPart: String

    func isFresh(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        calendar.isDate(createdAt, inSameDayAs: now)
    }
}

/// A one-tap mood that turns into a DJ request.
struct AIMoodPreset: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String
    let prompt: String
}

enum AIDayPart: String, CaseIterable {
    case morning = "sabah", noon = "öğle", afternoon = "ikindi", evening = "akşam", night = "gece"

    init(date: Date, calendar: Calendar = .current) {
        switch calendar.component(.hour, from: date) {
        case 5..<11: self = .morning
        case 11..<14: self = .noon
        case 14..<18: self = .afternoon
        case 18..<23: self = .evening
        default: self = .night
        }
    }

    var greeting: String {
        switch self {
        case .morning: return "Günaydın"
        case .noon: return "İyi öğlenler"
        case .afternoon: return "İyi günler"
        case .evening: return "İyi akşamlar"
        case .night: return "İyi geceler"
        }
    }

    /// Presets change with the time of day so the first suggestion is already relevant.
    var presets: [AIMoodPreset] {
        let common = AIMoodPreset(id: "favorites", title: "Favorilerimden", icon: "heart.fill",
                                  prompt: "En sevdiğim ve çok dinlediğim parçalardan akıcı bir set")
        switch self {
        case .morning:
            return [AIMoodPreset(id: "wake", title: "Güne başla", icon: "sunrise.fill", prompt: "Sabah uyanışı: yumuşak başlayıp enerjisi yükselen bir set"),
                    AIMoodPreset(id: "focus", title: "Odak", icon: "brain.head.profile", prompt: "Çalışırken dikkat dağıtmayan odak seti"), common]
        case .noon, .afternoon:
            return [AIMoodPreset(id: "energy", title: "Enerji", icon: "bolt.fill", prompt: "Enerjimi yükseltecek tempolu bir set"),
                    AIMoodPreset(id: "focus", title: "Odak", icon: "brain.head.profile", prompt: "Çalışırken dikkat dağıtmayan odak seti"), common]
        case .evening:
            return [AIMoodPreset(id: "unwind", title: "Akşam sakinliği", icon: "sunset.fill", prompt: "Günün yorgunluğunu alan sakin bir akşam seti"),
                    AIMoodPreset(id: "energy", title: "Enerji", icon: "bolt.fill", prompt: "Akşam için hareketli bir set"), common]
        case .night:
            return [AIMoodPreset(id: "sleep", title: "Uykuya doğru", icon: "moon.stars.fill", prompt: "Gece için yavaşça sakinleşen, uykuya hazırlayan bir set"),
                    AIMoodPreset(id: "deep", title: "Derin düşünce", icon: "sparkles", prompt: "Gece yarısı düşünceli ve atmosferik bir set"), common]
        }
    }
}

/// Builds the non-audio listening context that accompanies every request.
enum AIContextBuilder {
    static func make(now: Date = Date(), calendar: Calendar = .current, library: [MediaTrack], playlists: [MediaPlaylist],
                     current: MediaTrack?, queue: [MediaTrack], exclude: [UUID] = []) -> [String: Any] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE HH:mm"
        let recent = library.filter { $0.lastPlayedAt != nil }
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
            .prefix(10).map(\.id.uuidString)
        var context: [String: Any] = [
            "local_time": formatter.string(from: now),
            "day_part": AIDayPart(date: now, calendar: calendar).rawValue,
            "recent_ids": Array(recent),
            "playlists": playlists.prefix(20).map { ["name": String($0.name.prefix(80)), "count": $0.trackIDs.count] }
        ]
        if let current {
            context["now_playing"] = ["id": current.id.uuidString, "title": String(current.title.prefix(200)),
                                      "artist": String(current.artist.prefix(200))]
        }
        if !queue.isEmpty {
            context["queue_ids"] = queue.prefix(100).map(\.id.uuidString)
        }
        if !exclude.isEmpty {
            context["exclude_ids"] = exclude.prefix(300).map(\.uuidString)
        }
        return context
    }
}

/// Lets the store use a deterministic client in UI tests and unit tests.
protocol AIChatting: AnyObject {
    func models(connection: AIConnectionSettings, token: String) async throws -> [AIModel]
    func chat(connection: AIConnectionSettings, token: String, model: String, prompt: String,
              history: [[String: String]], tracks: [[String: Any]], context: [String: Any], task: AITask) async throws -> AIChatReply
}

#if DEBUG
/// Offline, deterministic replies for UI automation (`RITIM_UI_TEST_AI_STUB=1`).
/// It only ever selects IDs it was given, so it exercises the same validation path.
final class StubAIClient: AIChatting {
    static let modelID = "ritim-stub-1"

    func models(connection: AIConnectionSettings, token: String) async throws -> [AIModel] {
        [AIModel(id: Self.modelID, name: "Ritim Test Modeli", provider: "Test", availability: "unknown")]
    }

    func chat(connection: AIConnectionSettings, token: String, model: String, prompt: String,
              history: [[String: String]], tracks: [[String: Any]], context: [String: Any], task: AITask) async throws -> AIChatReply {
        try await Task.sleep(for: .milliseconds(600))
        let excluded = Set((context["exclude_ids"] as? [String]) ?? [])
        let nowID = (context["now_playing"] as? [String: Any])?["id"] as? String
        let ids = tracks.compactMap { $0["id"] as? String }.filter { !excluded.contains($0) && $0 != nowID }
        let allowed = Set(ids.compactMap(UUID.init(uuidString:)))
        var value: [String: Any] = ["search_queries": [String](), "action": "none", "playlist": NSNull()]
        switch task {
        case .chat:
            let wantsPlay = prompt.localizedCaseInsensitiveContains("çal")
            value["reply"] = wantsPlay ? "Hemen başlatıyorum: kitaplığından sakin bir seçki." : "Kitaplığından sana bir liste hazırladım."
            value["playlist"] = ["name": "Test seçkisi", "track_ids": ids]
            value["action"] = wantsPlay ? "play" : "none"
            value["search_queries"] = ["sakin akustik"]
        case .dj:
            value["reply"] = "Ritim DJ yayında. Sakin başlıyoruz, sonra tempoyu biraz artıracağız."
            value["playlist"] = ["name": "DJ seti", "track_ids": ids]
            value["action"] = "play"
        case .djContinue:
            value["reply"] = "Set devam ediyor; aynı havada yeni parçalar sıraya girdi."
            value["playlist"] = ["name": "DJ devamı", "track_ids": ids]
            value["action"] = "queue_next"
        case .insight:
            value["reply"] = "Bu parça sakin bir akşam havası taşıyor. Yürüyüşte veya çalışırken iyi gider."
            value["playlist"] = ["name": "Benzerleri", "track_ids": Array(ids.prefix(5))]
            value["search_queries"] = ["benzer sakin parçalar"]
        case .daily:
            value["reply"] = "Bugün için dinleme geçmişinden yumuşak bir seçki."
            value["playlist"] = ["name": "Günün ritmi", "track_ids": ids]
        case .discover:
            value["reply"] = "Benzer havada üç arama daha ekledim."
            value["search_queries"] = ["\(prompt) canlı", "\(prompt) akustik", "\(prompt) benzeri"]
        }
        let content = String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
        return try DirectAIClient.normalize(content, model: model, allowedIDs: allowed)
    }
}

/// Offline YouTube search for UI automation: three deterministic rows per query.
enum StubYouTubeSearch {
    static func search(_ query: String) async throws -> [PlaylistItem] {
        try await Task.sleep(for: .milliseconds(300))
        return (0..<(query.hasPrefix("sayfa") ? 12 : 3)).map { index in
            let seed = String(UInt(bitPattern: (query + "\(index)").hashValue), radix: 36)
            let id = String((seed + "aaaaaaaaaaa").prefix(11))
            return PlaylistItem(id: id, url: "https://www.youtube.com/watch?v=\(id)", title: "\(query) · sonuç \(index + 1)",
                                artist: "Test kanalı", duration: 180 + Double(index * 30), index: index)
        }
    }
}
#endif
