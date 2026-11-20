import Foundation

/// Reads YouTube's public catalog directly on this device. No API key or proxy.
struct NativeYouTubeCatalog {
    var session: URLSession = .shared
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"

    func search(query: String, limit: Int = 12) async throws -> [PlaylistItem] {
        var components = URLComponents(string: "https://www.youtube.com/results")!
        components.queryItems = [URLQueryItem(name: "search_query", value: String(query.prefix(300)))]
        let page = try await page(components.url!)
        return Array(Self.items(in: page.data, renderers: ["videoRenderer"]).prefix(max(1, min(50, limit))))
    }

    /// Title and channel of one public video via oEmbed; a generic row when YouTube does not answer.
    func video(url: URL) async -> PlaylistItem {
        let canonical = (try? MediaURLPolicy.singleVideo(url.absoluteString)) ?? url
        let id = URLComponents(url: canonical, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value ?? canonical.lastPathComponent
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [URLQueryItem(name: "url", value: canonical.absoluteString), URLQueryItem(name: "format", value: "json")]
        let object = (try? await request(URLRequest(url: components.url!))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        return PlaylistItem(id: id, url: canonical.absoluteString, title: (object?["title"] as? String) ?? "YouTube videosu",
                            artist: (object?["author_name"] as? String) ?? "YouTube", duration: nil, index: 0)
    }

    func resolvePlaylist(url: URL, limit: Int = 1_000) async throws -> PlaylistPreview {
        let url = try MediaURLPolicy.validatedPlaylist(url.absoluteString)
        let id = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "list" }!.value!
        let isMix = id.hasPrefix("RD")
        var components = URLComponents(string: "https://www.youtube.com/" + (isMix ? "watch" : "playlist"))!
        components.queryItems = [URLQueryItem(name: "list", value: id)]
        let first = try await page(components.url!)
        let bound = max(1, min(1_000, limit))
        var root: Any = Self.playlistRoot(first.data) ?? first.data
        let title = (root as? [String: Any])?["title"] as? String
            ?? Self.text(Self.firstValue("playlistMetadataRenderer", in: first.data).flatMap { $0 as? [String: Any] }?["title"])
            ?? "YouTube listesi"
        var result: [PlaylistItem] = [], ids: Set<String> = [], tokens: Set<String> = []
        var skipped = 0, truncated = false
        // A Mix is infinite. Stop at the requested bound, repeated page, or finite playlist end.
        for _ in 0..<100 {
            try Task.checkCancellation()
            let batch = Self.items(in: root, renderers: ["playlistVideoRenderer", "playlistPanelVideoRenderer"])
            var added = 0
            for var item in batch {
                guard ids.insert(item.id).inserted else { skipped += 1; continue }
                guard result.count < bound else { truncated = true; break }
                item.index = result.count; result.append(item); added += 1
            }
            if result.count >= bound { truncated = true; break }
            if isMix, added == 0 { break }
            if isMix, let last = result.last {
                let next = try await api("next", body: ["playlistId": id, "videoId": last.id, "index": result.count - 1], version: first.version)
                guard let panel = Self.playlistRoot(next) else { break }
                root = panel
            } else if let continuation = Self.continuation(in: root), tokens.insert(continuation).inserted {
                root = try await api("browse", body: ["continuation": continuation], version: first.version)
            } else { break }
        }
        guard !result.isEmpty else { throw RitimError.message("YouTube bu listeyi göstermedi. Liste herkese açık olmalı; bağlantıyı kontrol edip yeniden dene.") }
        if isMix { truncated = true }
        return PlaylistPreview(id: id, status: "completed", title: title, items: result, skipped: skipped, truncated: truncated, error: nil)
    }

    private func page(_ url: URL) async throws -> (data: [String: Any], version: String) {
        let data = try await request(URLRequest(url: url))
        guard let html = String(data: data, encoding: .utf8), let object = Self.initialData(html) else {
            throw RitimError.message("YouTube sayfası okunamadı. İnternet bağlantısını kontrol edip yeniden dene.")
        }
        let pattern = #"\"INNERTUBE_CLIENT_VERSION\"\s*:\s*\"([^\"]+)\""#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(html.startIndex..., in: html)
        let match = regex.firstMatch(in: html, range: range)
        let version = match.flatMap { Range($0.range(at: 1), in: html) }.map { String(html[$0]) } ?? "2.20261023.01.00"
        return (object, version)
    }

    private func api(_ name: String, body: [String: Any], version: String) async throws -> [String: Any] {
        var body = body
        body["context"] = ["client": ["clientName": "WEB", "clientVersion": version, "hl": "en", "gl": "TR"]]
        var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/\(name)")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-Youtube-Client-Name")
        request.setValue(version, forHTTPHeaderField: "X-Youtube-Client-Version")
        let data = try await self.request(request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw RitimError.message("YouTube liste yanıtı okunamadı.") }
        return object
    }

    private func request(_ input: URLRequest) async throws -> Data {
        var request = input
        request.timeoutInterval = 30
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("CONSENT=YES+cb; SOCS=CAI", forHTTPHeaderField: "Cookie")
        let (bytes, response) = try await session.bytes(for: request)
        let limit = 12 * 1_024 * 1_024
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), response.expectedContentLength <= limit else { throw RitimError.message("YouTube yanıt vermedi. Bir süre sonra yeniden dene.") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw RitimError.message("YouTube liste yanıtı çok büyük.") }
            data.append(byte)
        }
        return data
    }

    static func initialData(_ html: String) -> [String: Any]? {
        for marker in ["var ytInitialData =", "ytInitialData =", "window[\"ytInitialData\"] ="] {
            guard let range = html.range(of: marker), let start = html[range.upperBound...].firstIndex(of: "{") else { continue }
            var depth = 0, quoted = false, escaped = false
            for i in html[start...].indices {
                let c = html[i]
                if quoted {
                    if escaped { escaped = false }
                    else if c == "\\" { escaped = true }
                    else if c == "\"" { quoted = false }
                } else if c == "\"" { quoted = true }
                else if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 { return (try? JSONSerialization.jsonObject(with: Data(html[start...i].utf8))) as? [String: Any] }
                }
            }
        }
        return nil
    }

    static func items(in object: Any, renderers: Set<String>) -> [PlaylistItem] {
        var result: [PlaylistItem] = [], seen: Set<String> = []
        func visit(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                for key in renderers {
                    if let row = dictionary[key] as? [String: Any], let id = row["videoId"] as? String,
                       id.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil,
                       let title = text(row["title"]), row["isPlayable"] as? Bool != false, seen.insert(id).inserted {
                        let length = text(row["lengthText"])?.split(separator: ":").compactMap { Double($0) }.reduce(0) { $0 * 60 + $1 }
                        result.append(PlaylistItem(id: id, url: "https://www.youtube.com/watch?v=\(id)", title: title,
                                                  artist: text(row["shortBylineText"]) ?? text(row["longBylineText"]) ?? text(row["ownerText"]) ?? "YouTube", duration: length, index: result.count))
                        return
                    }
                }
                // Arrays preserve source order; dictionary keys are structural containers.
                for key in dictionary.keys.sorted() { visit(dictionary[key]!) }
            } else if let array = value as? [Any] { array.forEach(visit) }
        }
        visit(object); return result
    }
    static func playlistRoot(_ object: [String: Any]) -> Any? {
        if let contents = object["contents"] as? [String: Any], let watch = contents["twoColumnWatchNextResults"] as? [String: Any],
           let outer = watch["playlist"] as? [String: Any], let playlist = outer["playlist"] { return playlist }
        return firstValue("playlistVideoListRenderer", in: object)
    }
    static func firstValue(_ key: String, in value: Any) -> Any? {
        if let object = value as? [String: Any] {
            if let found = object[key] { return found }
            for name in object.keys.sorted() { if let found = firstValue(key, in: object[name]!) { return found } }
        } else if let array = value as? [Any] {
            for item in array { if let found = firstValue(key, in: item) { return found } }
        }
        return nil
    }
    static func continuation(in root: Any) -> String? {
        (firstValue("continuationCommand", in: root) as? [String: Any])?["token"] as? String
    }
    static func text(_ object: Any?) -> String? {
        if let string = object as? String { return string.isEmpty ? nil : string }
        guard let object = object as? [String: Any] else { return nil }
        if let text = object["simpleText"] as? String { return text }
        let runs = object["runs"] as? [[String: Any]]
        let text = runs?.compactMap { $0["text"] as? String }.joined()
        return text?.isEmpty == false ? text : nil
    }
}
