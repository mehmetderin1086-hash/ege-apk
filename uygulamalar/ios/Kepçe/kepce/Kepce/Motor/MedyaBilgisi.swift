import Foundation

/// Motorun döndürdüğü bilgi: tek video, liste (oynatma listesi, kanal, arama sonucu) ya da hata.
nonisolated struct MedyaBilgisi: Codable, Sendable, Hashable {
    var kind: String
    var id: String?
    var title: String?
    var description: String?
    var uploader: String?
    var channel: String?
    var duration: Double?
    var uploadDate: String?
    var viewCount: Int?
    var thumbnail: String?
    var webpageURL: String?
    var extractorKey: String?
    var liveStatus: String?
    var chapters: [Bolum]?
    var formats: [Bicim]?
    var subtitles: [String: [AltyaziIzi]]?
    var automaticCaptions: [String: [AltyaziIzi]]?
    var entries: [ListeOgesi]?
    var error: String?
    var log: [String]?

    enum CodingKeys: String, CodingKey {
        case kind, id, title, description, uploader, channel, duration, thumbnail, chapters, formats, subtitles, entries, error, log
        case uploadDate = "upload_date", viewCount = "view_count", webpageURL = "webpage_url", extractorKey = "extractor_key"
        case liveStatus = "live_status", automaticCaptions = "automatic_captions"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "video"
        id = try? c.decodeIfPresent(String.self, forKey: .id)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        uploader = try? c.decodeIfPresent(String.self, forKey: .uploader)
        channel = try? c.decodeIfPresent(String.self, forKey: .channel)
        duration = c.sayi(.duration)
        uploadDate = try? c.decodeIfPresent(String.self, forKey: .uploadDate)
        viewCount = c.sayi(.viewCount).map { Int($0) }
        thumbnail = try? c.decodeIfPresent(String.self, forKey: .thumbnail)
        webpageURL = try? c.decodeIfPresent(String.self, forKey: .webpageURL)
        extractorKey = try? c.decodeIfPresent(String.self, forKey: .extractorKey)
        liveStatus = try? c.decodeIfPresent(String.self, forKey: .liveStatus)
        chapters = try? c.decodeIfPresent([Bolum].self, forKey: .chapters)
        formats = try c.decodeIfPresent([Bicim].self, forKey: .formats)
        subtitles = try? c.decodeIfPresent([String: [AltyaziIzi]].self, forKey: .subtitles)
        automaticCaptions = try? c.decodeIfPresent([String: [AltyaziIzi]].self, forKey: .automaticCaptions)
        entries = try c.decodeIfPresent([ListeOgesi].self, forKey: .entries)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
        log = try? c.decodeIfPresent([String].self, forKey: .log)
    }

    var yazar: String? { uploader ?? channel }
    var liste: Bool { kind == "playlist" }
}

nonisolated struct Bolum: Codable, Sendable, Hashable {
    var startTime: Double
    var endTime: Double
    var title: String?

    enum CodingKeys: String, CodingKey { case startTime = "start_time", endTime = "end_time", title }
}

nonisolated struct AltyaziIzi: Codable, Sendable, Hashable {
    var ext: String?
    var url: String
    var name: String?
}

nonisolated struct ListeOgesi: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var title: String?
    var url: String?
    var duration: Double?
    var thumbnail: String?
    var uploader: String?
    var viewCount: Int?
    var liveStatus: String?

    enum CodingKeys: String, CodingKey { case id, title, url, duration, thumbnail, uploader, viewCount = "view_count", liveStatus = "live_status" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        url = try? c.decodeIfPresent(String.self, forKey: .url)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? url ?? UUID().uuidString
        duration = c.sayi(.duration)
        thumbnail = try? c.decodeIfPresent(String.self, forKey: .thumbnail)
        uploader = try? c.decodeIfPresent(String.self, forKey: .uploader)
        viewCount = c.sayi(.viewCount).map { Int($0) }
        liveStatus = try? c.decodeIfPresent(String.self, forKey: .liveStatus)
    }

    init(id: String, title: String?, url: String?, duration: Double? = nil, thumbnail: String? = nil) {
        self.id = id; self.title = title; self.url = url; self.duration = duration; self.thumbnail = thumbnail
    }

    /// YouTube düz listelerinde `url` boş gelebilir; kimlikten izleme adresi kurulur.
    var adres: String? {
        if let url, url.hasPrefix("http") { return url }
        if id.count == 11 { return "https://www.youtube.com/watch?v=\(id)" }
        return url
    }
    var canli: Bool { liveStatus == "is_live" || liveStatus == "is_upcoming" }
}

/// Tek bir akış biçimi (yt-dlp `formats` öğesi).
nonisolated struct Bicim: Codable, Sendable, Hashable, Identifiable {
    var formatID: String
    var formatNote: String?
    var ext: String?
    var vcodec: String?
    var acodec: String?
    var width: Int?
    var height: Int?
    var fps: Double?
    var tbr: Double?
    var abr: Double?
    var asr: Double?
    var filesize: Int64?
    var filesizeApprox: Int64?
    var url: String?
    var protokol: String?
    var httpHeaders: [String: String]?
    var dynamicRange: String?
    var language: String?
    var languagePreference: Double?
    var fragments: [Parca]?
    var fragmentBaseURL: String?
    var hasDRM: Bool?
    var chunkSize: Int64?

    struct Parca: Codable, Sendable, Hashable {
        var url: String?
        var path: String?
        var duration: Double?
    }

    enum CodingKeys: String, CodingKey {
        case formatID = "format_id", formatNote = "format_note", ext, vcodec, acodec, width, height, fps, tbr, abr, asr, filesize
        case filesizeApprox = "filesize_approx", url, protokol = "protocol", httpHeaders = "http_headers", dynamicRange = "dynamic_range"
        case language, languagePreference = "language_preference", fragments, fragmentBaseURL = "fragment_base_url", hasDRM = "has_drm"
        case downloaderOptions = "downloader_options"
    }
    private enum IndiriciKeys: String, CodingKey { case httpChunkSize = "http_chunk_size" }

    var id: String { formatID }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatID = (try? c.decode(String.self, forKey: .formatID)) ?? UUID().uuidString
        formatNote = try? c.decodeIfPresent(String.self, forKey: .formatNote)
        ext = try? c.decodeIfPresent(String.self, forKey: .ext)
        vcodec = try? c.decodeIfPresent(String.self, forKey: .vcodec)
        acodec = try? c.decodeIfPresent(String.self, forKey: .acodec)
        width = c.sayi(.width).map { Int($0) }
        height = c.sayi(.height).map { Int($0) }
        fps = c.sayi(.fps)
        tbr = c.sayi(.tbr)
        abr = c.sayi(.abr)
        asr = c.sayi(.asr)
        filesize = c.sayi(.filesize).map { Int64($0) }
        filesizeApprox = c.sayi(.filesizeApprox).map { Int64($0) }
        url = try? c.decodeIfPresent(String.self, forKey: .url)
        protokol = try? c.decodeIfPresent(String.self, forKey: .protokol)
        httpHeaders = try? c.decodeIfPresent([String: String].self, forKey: .httpHeaders)
        dynamicRange = try? c.decodeIfPresent(String.self, forKey: .dynamicRange)
        language = try? c.decodeIfPresent(String.self, forKey: .language)
        languagePreference = c.sayi(.languagePreference)
        fragments = try? c.decodeIfPresent([Parca].self, forKey: .fragments)
        fragmentBaseURL = try? c.decodeIfPresent(String.self, forKey: .fragmentBaseURL)
        hasDRM = try? c.decodeIfPresent(Bool.self, forKey: .hasDRM)
        if let indirici = try? c.nestedContainer(keyedBy: IndiriciKeys.self, forKey: .downloaderOptions) {
            chunkSize = indirici.sayi(.httpChunkSize).map { Int64($0) }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(formatID, forKey: .formatID)
        try c.encodeIfPresent(formatNote, forKey: .formatNote)
        try c.encodeIfPresent(ext, forKey: .ext)
        try c.encodeIfPresent(vcodec, forKey: .vcodec)
        try c.encodeIfPresent(acodec, forKey: .acodec)
        try c.encodeIfPresent(width, forKey: .width)
        try c.encodeIfPresent(height, forKey: .height)
        try c.encodeIfPresent(fps, forKey: .fps)
        try c.encodeIfPresent(tbr, forKey: .tbr)
        try c.encodeIfPresent(abr, forKey: .abr)
        try c.encodeIfPresent(asr, forKey: .asr)
        try c.encodeIfPresent(filesize, forKey: .filesize)
        try c.encodeIfPresent(filesizeApprox, forKey: .filesizeApprox)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(protokol, forKey: .protokol)
        try c.encodeIfPresent(httpHeaders, forKey: .httpHeaders)
        try c.encodeIfPresent(dynamicRange, forKey: .dynamicRange)
        try c.encodeIfPresent(language, forKey: .language)
        try c.encodeIfPresent(languagePreference, forKey: .languagePreference)
        try c.encodeIfPresent(fragments, forKey: .fragments)
        try c.encodeIfPresent(fragmentBaseURL, forKey: .fragmentBaseURL)
        try c.encodeIfPresent(hasDRM, forKey: .hasDRM)
        if let chunkSize {
            var indirici = c.nestedContainer(keyedBy: IndiriciKeys.self, forKey: .downloaderOptions)
            try indirici.encode(chunkSize, forKey: .httpChunkSize)
        }
    }

    init(formatID: String, ext: String?, vcodec: String?, acodec: String?, height: Int? = nil, fps: Double? = nil, tbr: Double? = nil,
         abr: Double? = nil, filesize: Int64? = nil, url: String? = "https://ornek/\(UUID())", protokol: String? = "https", language: String? = nil,
         languagePreference: Double? = nil, formatNote: String? = nil) {
        self.formatID = formatID; self.ext = ext; self.vcodec = vcodec; self.acodec = acodec; self.height = height; self.fps = fps
        self.tbr = tbr; self.abr = abr; self.filesize = filesize; self.url = url; self.protokol = protokol; self.language = language
        self.languagePreference = languagePreference; self.formatNote = formatNote
    }

    // MARK: Nitelikler

    /// Kodek bilgisi verilmeyen MP4 (bazı siteler): sesli tek dosya varsayılır.
    var kodeksizMP4: Bool { vcodec == nil && acodec == nil && ["mp4", "m4v", "mov"].contains((ext ?? "").lowercased()) }
    var videoVar: Bool { if let vcodec { return vcodec != "none" } else { return kodeksizMP4 || (height != nil && acodec == nil) } }
    var sesVar: Bool {
        if let acodec { return acodec != "none" }
        return kodeksizMP4 || (!videoVar && (abr != nil || ext == "m4a" || ext == "mp3"))
    }
    var resim: Bool { protokol == "mhtml" || ext == "mhtml" }
    var drc: Bool { formatID.hasSuffix("-drc") || (formatNote?.lowercased().contains("drc") ?? false) }

    /// Kabaca kodek ailesi: avc1, hvc1, av01, vp9, mp4a, opus, mp3…
    var videoKodegi: String {
        let kod = (vcodec ?? "").lowercased()
        if kodeksizMP4 { return "avc1" }
        if kod.hasPrefix("avc") || kod.hasPrefix("h264") { return "avc1" }
        if kod.hasPrefix("hvc") || kod.hasPrefix("hev") || kod.hasPrefix("h265") { return "hvc1" }
        if kod.hasPrefix("av01") || kod == "av1" { return "av01" }
        if kod.hasPrefix("vp09") || kod.hasPrefix("vp9") { return "vp9" }
        if kod.hasPrefix("vp8") { return "vp8" }
        return kod
    }

    var sesKodegi: String {
        let kod = (acodec ?? "").lowercased()
        if kodeksizMP4 { return "aac" }
        if kod.hasPrefix("mp4a") || kod.hasPrefix("aac") { return "aac" }
        if kod.hasPrefix("opus") { return "opus" }
        if kod.hasPrefix("mp3") || kod == "mp3" { return "mp3" }
        if kod.hasPrefix("ac-3") || kod.hasPrefix("ac3") { return "ac3" }
        if kod.hasPrefix("ec-3") || kod.hasPrefix("eac3") { return "eac3" }
        if kod.hasPrefix("flac") { return "flac" }
        if kod.hasPrefix("vorbis") { return "vorbis" }
        if kod.isEmpty, ext == "m4a" { return "aac" }
        if kod.isEmpty, ext == "mp3" { return "mp3" }
        return kod
    }

    var dogrudan: Bool { (protokol ?? "https").hasPrefix("http") && !(protokol ?? "").contains("dash") && fragments == nil }
    var parcali: Bool { fragments?.isEmpty == false }
    var hls: Bool { (protokol ?? "").hasPrefix("m3u8") }

    func boyut(sure: Double?) -> Int64? {
        if let filesize { return filesize }
        if let filesizeApprox { return filesizeApprox }
        if let tbr, let sure, sure > 0 { return Int64(tbr * 125 * sure) }
        return nil
    }
}

nonisolated extension KeyedDecodingContainer {
    /// Sayıyı Int ya da Double olarak, hatta metin olarak gelse de okur.
    func sayi(_ anahtar: Key) -> Double? {
        if let deger = try? decodeIfPresent(Double.self, forKey: anahtar) { return deger }
        if let deger = try? decodeIfPresent(Int64.self, forKey: anahtar) { return Double(deger) }
        if let metin = try? decodeIfPresent(String.self, forKey: anahtar) { return Double(metin) }
        return nil
    }
}

/// Oynatma listesi ve kanal bağlantılarını tanır.
nonisolated enum ListeAdresi {
    /// YouTube listesi (`/playlist?list=`), kanal (`/@ad`, `/channel/…`, `/c/…`, `/user/…`) ya da genel "playlist" yolu.
    static func listeMi(_ adres: String) -> Bool {
        guard let b = URLComponents(string: adres) else { return false }
        let yol = b.path.lowercased()
        let sorgu = b.queryItems ?? []
        if sorgu.contains(where: { $0.name == "list" }) && !sorgu.contains(where: { $0.name == "v" }) { return true }
        if yol.contains("/playlist") { return true }
        let host = b.host?.lowercased() ?? ""
        if host.contains("youtube.com") {
            return yol.hasPrefix("/@") || yol.hasPrefix("/channel/") || yol.hasPrefix("/c/") || yol.hasPrefix("/user/")
        }
        return false
    }

    /// Kanalın ana sayfası sekmeleri döndürür; videolar sekmesine çevirir.
    static func duzelt(_ adres: String) -> String {
        guard var b = URLComponents(string: adres), let host = b.host?.lowercased(), host.contains("youtube.com") else { return adres }
        let parcalar = b.path.split(separator: "/").map(String.init)
        let kanal = parcalar.first.map { $0.hasPrefix("@") } == true ? 1 : (["channel", "c", "user"].contains(parcalar.first ?? "") ? 2 : 0)
        guard kanal > 0, parcalar.count == kanal else { return adres }
        b.path = "/" + (parcalar + ["videos"]).joined(separator: "/")
        return b.string ?? adres
    }

    /// Metindeki bütün http(s) bağlantıları (sırası korunur, yinelenenler atılır).
    static func hepsi(_ metin: String) -> [String] {
        guard let algilayici = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var gorulen = Set<String>(), sonuc: [String] = []
        for e in algilayici.matches(in: metin, range: NSRange(metin.startIndex..., in: metin)) {
            guard let url = e.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { continue }
            if gorulen.insert(url.absoluteString).inserted { sonuc.append(url.absoluteString) }
        }
        return sonuc
    }
}
