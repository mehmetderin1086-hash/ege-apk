import Foundation
import SwiftUI

nonisolated struct AmazonBookMetadata: Sendable {
    var title: String = ""
    var author: String = ""
    var publisher: String = ""
    var isbn: String = ""
    var publicationYear: String = ""
    var edition: String = ""
    var pageCount: String = ""
    var language: String = ""
    var category: String = ""
    var notes: String = ""
    var coverData: Data?
    var coverURL: URL?
    var productURL: URL?
}

/// Ağ ve HTML ayrıştırması ana aktörden ayrı koşar: seri taramada kamera kadrajı ve dokunuşlar takılmaz.
nonisolated enum AmazonBookScraper {
    @concurrent static func fetchBook(isbn: String) async throws -> AmazonBookMetadata? {
        let cleanQuery = isbn.filter { $0.isNumber || $0.isLetter }
        guard !cleanQuery.isEmpty else { return nil }

        // amazon.com.tr, bulunamazsa amazon.com
        return try await scrapeDomains(query: cleanQuery, fallbackISBN: cleanQuery)
    }

    /// Önce amazon.com.tr, sonra amazon.com. İlk alan adı robot doğrulaması gösterirse ikincisi yine
    /// denenir; ikisi de kayıt vermezse robot engeli "kitap yok" sayılmasın diye hata fırlatılır.
    private static func scrapeDomains(query: String, fallbackISBN: String) async throws -> AmazonBookMetadata? {
        var robotEngeli: Error?
        for domain in ["amazon.com.tr", "amazon.com"] {
            do {
                if let meta = try await scrape(query: query, domain: domain, fallbackISBN: fallbackISBN) { return meta }
            } catch let error as URLError where error.code == .resourceUnavailable {
                robotEngeli = error
            }
        }
        if let robotEngeli { throw robotEngeli }
        return nil
    }

    /// Ad + yazar gibi serbest metinle arama (ISBN'i olmayan kitaplar için).
    @concurrent static func fetchBook(searchText: String) async throws -> AmazonBookMetadata? {
        let cleanQuery = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard cleanQuery.count >= 4 else { return nil }

        return try await scrapeDomains(query: cleanQuery, fallbackISBN: "")
    }

    /// Aynı arama için birden çok baskı adayı döndürür (kullanıcı seçsin diye).
    @concurrent static func fetchCandidates(query: String, limit: Int = 4) async -> [AmazonBookMetadata] {
        let cleanQuery = query.filter { $0.isNumber || $0.isLetter || $0 == " " }
        guard !cleanQuery.isEmpty else { return [] }

        for domain in ["amazon.com.tr", "amazon.com"] {
            var components = URLComponents(string: "https://www.\(domain)/s")
            components?.queryItems = [
                URLQueryItem(name: "k", value: cleanQuery),
                URLQueryItem(name: "i", value: "stripbooks")
            ]
            guard let searchURL = components?.url,
                  let searchHTML = try? await fetchHTML(url: searchURL) else { continue }

            // Arama sonucundaki ilk birkaç ASIN
            var asins: [String] = []
            for match in allMatches(in: searchHTML, pattern: #"/dp/([A-Z0-9]{10})"#) {
                if !asins.contains(match) { asins.append(match) }
                if asins.count >= limit { break }
            }
            guard !asins.isEmpty else { continue }

            var results: [AmazonBookMetadata] = []
            for asin in asins {
                guard let productURL = URL(string: "https://www.\(domain)/dp/\(asin)"),
                      let html = try? await fetchHTML(url: productURL) else { continue }
                var meta = parseProduct(html: html, fallbackISBN: "")
                meta.productURL = productURL
                guard !meta.title.isEmpty else { continue }

                if let coverURL = meta.coverURL {
                    meta.coverData = await BookMetadataService.downloadImage(from: coverURL)
                }
                results.append(meta)
            }
            if !results.isEmpty { return results }
        }
        return []
    }

    private static func scrape(query: String, domain: String, fallbackISBN: String) async throws -> AmazonBookMetadata? {
        var components = URLComponents(string: "https://www.\(domain)/s")
        components?.queryItems = [
            URLQueryItem(name: "k", value: query),
            URLQueryItem(name: "i", value: "stripbooks")
        ]
        guard let searchURL = components?.url else { return nil }

        let searchHTML = try await fetchHTML(url: searchURL)

        // Find ASIN from search results
        var asin = firstMatch(
            in: searchHTML,
            pattern: #"data-component-type="s-search-result"[^>]*data-asin="([A-Z0-9]{10})""#
        )
        if asin == nil {
            // Amazon iki özniteliği ters sırada da yazar
            asin = firstMatch(
                in: searchHTML,
                pattern: #"data-asin="([A-Z0-9]{10})"[^>]*data-component-type="s-search-result""#
            )
        }
        if asin == nil {
            asin = firstMatch(in: searchHTML, pattern: #"/dp/([A-Z0-9]{10})"#)
        }
        if asin == nil {
            asin = firstMatch(in: searchHTML, pattern: #"/gp/product/([A-Z0-9]{10})"#)
        }

        guard let matchedASIN = asin,
              let productURL = URL(string: "https://www.\(domain)/dp/\(matchedASIN)") else {
            return nil
        }

        let productHTML = try await fetchHTML(url: productURL)
        var metadata = parseProduct(html: productHTML, fallbackISBN: fallbackISBN)
        metadata.productURL = productURL

        // ISBN aramasında ilk sonuç sponsorlu/önerilen başka bir kitap olabilir: sayfanın
        // ISBN'i sorgulananla çelişiyorsa sonuç kullanılmaz (yanlış kitap kataloğa girmesin)
        let wantedISBN = ISBNFormatter.normalize(fallbackISBN)
        if !wantedISBN.isEmpty, ISBNFormatter.isValidISBN13(metadata.isbn), metadata.isbn != wantedISBN {
            return nil
        }

        // Download cover image if available
        if let coverURL = metadata.coverURL {
            do {
                var imgRequest = URLRequest(url: coverURL)
                imgRequest.timeoutInterval = 10
                let (imageData, response) = try await URLSession.shared.data(for: imgRequest)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), !imageData.isEmpty {
                    metadata.coverData = imageData
                }
            } catch {
                // If cover image download fails, keep text metadata
            }
        }

        return metadata.title.isEmpty ? nil : metadata
    }

    private static func fetchHTML(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        request.setValue("\"Google Chrome\";v=\"131\", \"Chromium\";v=\"131\", \"Not_A Brand\";v=\"24\"", forHTTPHeaderField: "sec-ch-ua")
        request.setValue("?0", forHTTPHeaderField: "sec-ch-ua-mobile")
        request.setValue("\"macOS\"", forHTTPHeaderField: "sec-ch-ua-platform")
        request.setValue("document", forHTTPHeaderField: "sec-fetch-dest")
        request.setValue("navigate", forHTTPHeaderField: "sec-fetch-mode")
        request.setValue("none", forHTTPHeaderField: "sec-fetch-site")
        request.setValue("?1", forHTTPHeaderField: "sec-fetch-user")
        request.setValue("1", forHTTPHeaderField: "upgrade-insecure-requests")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let html = String(decoding: data, as: UTF8.self)
        // Robot doğrulama sayfası 200 ile gelir; boş kayıt gibi ayrıştırılırsa "kitap yok" sanılır
        guard !isRobotCheck(html: html) else { throw URLError(.resourceUnavailable) }
        return html
    }

    /// Amazon'un robot/captcha doğrulama sayfası mı (ürün ya da arama sonucu yerine).
    static func isRobotCheck(html: String) -> Bool {
        ["/errors/validateCaptcha", "api-services-support@amazon.com", "opfcaptcha.amazon"]
            .contains { html.contains($0) }
    }

    static func parseProduct(html: String, fallbackISBN: String) -> AmazonBookMetadata {
        var result = AmazonBookMetadata()
        result.isbn = fallbackISBN

        // 2-4 MB'lık sayfanın tamamını ~15 desenle taramak yerine ilgili bölümler kesilip taranır;
        // bölüm bulunamazsa (düzen değişmiş) eski gibi sayfanın tamamına düşülür.
        let titleScope = bolum(html, markers: [#"id="productTitle""#, "id='productTitle'"], uzunluk: 4_000)
        let bylineScope = bolum(html, markers: [#"id="bylineInfo""#, "id='bylineInfo'", #"id="bylineInfo_feature_div""#], uzunluk: 8_000)

        // Title
        if let rawTitle = firstMatch(in: titleScope ?? html, pattern: #"id=["']productTitle["'][^>]*>(.*?)</span>"#)
            ?? (titleScope == nil ? nil : firstMatch(in: html, pattern: #"id=["']productTitle["'][^>]*>(.*?)</span>"#)) {
            result.title = cleanText(rawTitle)
        }

        // Author(s)
        let authorSnippets = allMatches(in: bylineScope ?? html, pattern: #"<span class=["']author[^"']*["'][^>]*>.*?<a[^>]*>(.*?)</a>"#)
        let authors = authorSnippets.map { cleanText($0) }.filter { !$0.isEmpty }
        if !authors.isEmpty {
            result.author = authors.joined(separator: ", ")
        } else if let byline = firstMatch(in: bylineScope ?? html, pattern: #"id=["']bylineInfo["'][^>]*>(.*?)</div>"#) {
            let cleaned = cleanText(byline)
            if !cleaned.isEmpty {
                result.author = cleaned
            }
        }

        // Details Section (bullets)
        let detailScope = bolum(html, markers: ["detailBullets_feature_div"], uzunluk: 40_000)
        let detailSection = detailScope.flatMap { firstMatch(in: $0, pattern: #"id=["']detailBullets_feature_div["'](.*?)</ul>"#) } ?? ""
        let bulletItems = allMatches(in: detailSection, pattern: #"<li[^>]*>\s*<span class=["']a-list-item["']>(.*?)</li>"#)
        for bullet in bulletItems {
            parseDetailLine(cleanText(bullet), into: &result)
        }

        // Table Rows (product details fallback)
        // Etiket (th) ile değer (td) birlikte yakalanır; araya ":" konarak ayrıştırıcıya verilir
        let tableScope = bolum(html, markers: ["productDetails_techSpec", "productDetails_detailBullets", "prodDetails"], uzunluk: 60_000)
        let tableRows = html.contains("<th") ? allMatches(in: tableScope ?? html, pattern: #"<tr[^>]*>\s*(<th[^>]*>.*?</th>\s*<td[^>]*>.*?</td>)"#) : []
        for row in tableRows {
            parseDetailLine(cleanText(row.replacingOccurrences(of: "</th>", with: ":</th>", options: .caseInsensitive)), into: &result)
        }

        // Yeni Amazon düzeni: "Baskı Uzunluğu / 1368 sayfa" gibi bilgiler
        // rpi-attribute etiket/değer bloklarında gelir
        let rpiScope = bolum(html, markers: ["rpi-attribute-label"], uzunluk: 40_000)
        let rpiLabels = rpiScope.map { allMatches(in: $0, pattern: #"rpi-attribute-label[^>]*>\s*<span>(.*?)</span>"#) } ?? []
        let rpiValues = rpiScope.map { allMatches(in: $0, pattern: #"rpi-attribute-value[^>]*>\s*<span>(.*?)</span>"#) } ?? []
        for (label, value) in zip(rpiLabels, rpiValues) {
            parseDetailLine(cleanText(label) + ": " + cleanText(value), into: &result)
        }

        // Category from breadcrumbs
        let crumbScope = bolum(html, markers: ["a-link-normal a-color-tertiary"], uzunluk: 6_000)
        let breadcrumbs = crumbScope.map { allMatches(in: $0, pattern: #"<a class=["']a-link-normal a-color-tertiary["'][^>]*>(.*?)</a>"#) } ?? []
        let filteredCats = breadcrumbs
            .map { cleanText($0) }
            .filter { cat in
                let lower = cat.lowercased()
                return !lower.isEmpty && lower != "kitap" && lower != "books" && lower != "kategoriler"
            }
        if let bestCat = filteredCats.last {
            result.category = bestCat
        }

        // Cover Image (dynamic image JSON - pick maximum resolution)
        if let rawAttr = bolum(html, markers: ["data-a-dynamic-image="], uzunluk: 20_000)
            .flatMap({ firstMatch(in: $0, pattern: #"data-a-dynamic-image="([^"]+)""#) }) {
            let unescaped = rawAttr.replacingOccurrences(of: "&quot;", with: "\"")
            if let jsonData = unescaped.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: [Int]],
               let best = dict.max(by: { ($0.value.first ?? 0) < ($1.value.first ?? 0) }) {
                result.coverURL = URL(string: fullResolutionImageURL(best.key))
            }
        }

        // Fallbacks for cover image
        if result.coverURL == nil {
            if let img = bolum(html, markers: ["data-old-hires="], uzunluk: 4_000).flatMap({ firstMatch(in: $0, pattern: #"data-old-hires="([^"]+)""#) }) {
                result.coverURL = URL(string: img)
            } else if let img = bolum(html, markers: ["landingImage"], uzunluk: 4_000).flatMap({ firstMatch(in: $0, pattern: #"id=["']landingImage["'][^>]*src="([^"]+)""#) }) {
                result.coverURL = URL(string: img)
            } else if let img = bolum(html, markers: [#"property="og:image""#, "property='og:image'"], uzunluk: 1_500).flatMap({ firstMatch(in: $0, pattern: #"<meta property=["']og:image["'] content="([^"]+)""#) }) {
                result.coverURL = URL(string: img)
            }
        }

        // Description / Notes
        if let descSection = bolum(html, markers: ["bookDescription_feature_div"], uzunluk: 30_000)
            .flatMap({ firstMatch(in: $0, pattern: #"id=["']bookDescription_feature_div["'](.*?)</div>\s*</div>"#) }) {
            let spans = allMatches(in: descSection, pattern: #"<span[^>]*>(.*?)</span>"#)
            let longestSpan = spans.map { cleanText($0) }.max(by: { $0.count < $1.count }) ?? ""
            if longestSpan.count > 30 {
                result.notes = longestSpan
            }
        }

        return result
    }

    /// İlk işaretten başlayıp `uzunluk` karakterlik parça; işaret yoksa `nil` (çağıran eski yola düşer ya da atlar).
    /// Düz metin araması, desenle tüm sayfayı taramaktan kat kat hızlıdır.
    private static func bolum(_ html: String, markers: [String], uzunluk: Int) -> String? {
        for marker in markers {
            guard let range = html.range(of: marker) else { continue }
            // Desenler işaretin öncesindeki etiketi de ister (`id="…"`, `<a class="…`): pencere biraz geriden başlar.
            let start = html.index(range.lowerBound, offsetBy: -48, limitedBy: html.startIndex) ?? html.startIndex
            let end = html.index(range.lowerBound, offsetBy: uzunluk, limitedBy: html.endIndex) ?? html.endIndex
            return String(html[start..<end])
        }
        return nil
    }

    private static func parseDetailLine(_ line: String, into result: inout AmazonBookMetadata) {
        let parts = line.components(separatedBy: ":")
        guard parts.count >= 2 else { return }
        let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let val = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)

        if key.contains("yayıncı") || key.contains("yayınevi") || key.contains("publisher") {
            if result.publisher.isEmpty { result.publisher = val }
        } else if key.contains("yayınlanma tarihi") || key.contains("yayın tarihi") || key.contains("publication date") {
            if result.publicationYear.isEmpty, let year = firstMatch(in: val, pattern: #"((?:18|19|20)\d{2})"#) {
                result.publicationYear = year
            }
        } else if key.contains("baskı uzunluğu") || key.contains("sayfa sayısı") || key.contains("print length") {
            if result.pageCount.isEmpty, let pages = firstMatch(in: val, pattern: #"(\d+)"#) {
                result.pageCount = pages
            }
        } else if key.contains("baskı") || key.contains("edition") {
            if result.edition.isEmpty { result.edition = val }
        } else if key.contains("dil") || key.contains("language") {
            if result.language.isEmpty { result.language = val }
        } else if key.contains("isbn-13") {
            let digits = val.filter(\.isNumber)
            if digits.count == 13 { result.isbn = digits }
        } else if key.contains("isbn-10") && result.isbn.isEmpty {
            let norm = ISBNFormatter.normalize(val)
            if !norm.isEmpty { result.isbn = norm }
        }
    }

    @MainActor static func apply(metadata: AmazonBookMetadata, to draft: inout BookDraft, overwrite: Bool = false) {
        if overwrite || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !metadata.title.isEmpty { draft.title = metadata.title }
        }
        if overwrite || draft.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !metadata.author.isEmpty { draft.author = metadata.author }
        }
        if overwrite || draft.publisher.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !metadata.publisher.isEmpty { draft.publisher = metadata.publisher }
        }
        if overwrite || draft.isbn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !metadata.isbn.isEmpty { draft.isbn = metadata.isbn }
        }
        if overwrite || draft.publicationYear.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !metadata.publicationYear.isEmpty { draft.publicationYear = metadata.publicationYear }
        }
        if overwrite || draft.edition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !metadata.edition.isEmpty { draft.edition = metadata.edition }
        }
        if overwrite || draft.pageCount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !metadata.pageCount.isEmpty { draft.pageCount = metadata.pageCount }
        }
        if overwrite || draft.language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !metadata.language.isEmpty { draft.language = metadata.language }
        }
        if overwrite || draft.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !metadata.category.isEmpty { draft.category = metadata.category }
        }
        if overwrite || draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !metadata.notes.isEmpty { draft.notes = metadata.notes }
        }
        if overwrite || draft.coverData == nil {
            if let cover = metadata.coverData { draft.coverData = cover }
        }

        if !draft.title.isEmpty { draft.lowConfidenceFields.remove("title") }
        if !draft.author.isEmpty { draft.lowConfidenceFields.remove("author") }
        if !draft.publisher.isEmpty { draft.lowConfidenceFields.remove("publisher") }
        if !draft.isbn.isEmpty { draft.lowConfidenceFields.remove("isbn") }
        if !draft.publicationYear.isEmpty { draft.lowConfidenceFields.remove("publicationYear") }
        if !draft.edition.isEmpty { draft.lowConfidenceFields.remove("edition") }
        if !draft.pageCount.isEmpty { draft.lowConfidenceFields.remove("pageCount") }
    }

    /// Amazon görsel adreslerindeki boyut belirtecini ("._SY522_", "._SL500_") kaldırarak
    /// kapağın tam çözünürlüklü hâlini ister — 522 piksel yerine ~2000 piksel, net kapak.
    static func fullResolutionImageURL(_ url: String) -> String {
        url.replacingOccurrences(
            of: #"\._[A-Z]{2}[0-9_,]*_(?=\.[a-zA-Z]{3,4}$)"#,
            with: ".",
            options: .regularExpression
        )
        .replacingOccurrences(of: "..", with: ".")
    }

    private static func firstMatch(in text: String, pattern: String, group: Int = 1) -> String? {
        guard let regex = KunyeRegex.derle(pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > group,
              let range = Range(match.range(at: group), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func allMatches(in text: String, pattern: String, group: Int = 1) -> [String] {
        guard let regex = KunyeRegex.derle(pattern) else {
            return []
        }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match in
            guard match.numberOfRanges > group, let range = Range(match.range(at: group), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func decodeHTMLEntities(_ string: String) -> String {
        var text = string
        let namedEntities: [String: String] = [
            "&amp;": "&", "&quot;": "\"", "&apos;": "'", "&#39;": "'",
            "&lt;": "<", "&gt;": ">", "&nbsp;": " ",
            "&rlm;": "", "&lrm;": "", "\u{200E}": "", "\u{200F}": "",
            "&Uuml;": "Ü", "&uuml;": "ü", "&Ouml;": "Ö", "&ouml;": "ö",
            "&Ccedil;": "Ç", "&ccedil;": "ç", "&Idot;": "İ", "&inodot;": "ı",
            "&Scedil;": "Ş", "&scedil;": "ş", "&Gbreve;": "Ğ", "&gbreve;": "ğ",
            "&Acirc;": "Â", "&acirc;": "â", "&Icirc;": "Î", "&icirc;": "î",
            "&Ucirc;": "Û", "&ucirc;": "û"
        ]
        for (entity, replacement) in namedEntities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        if let decRegex = KunyeRegex.derle(#"&#(\d+);"#, options: []) {
            let matches = decRegex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed()
            for m in matches {
                if let r = Range(m.range(at: 1), in: text),
                   let code = UInt32(text[r]),
                   let scalar = UnicodeScalar(code),
                   let fullR = Range(m.range, in: text) {
                    text.replaceSubrange(fullR, with: String(Character(scalar)))
                }
            }
        }

        if let hexRegex = KunyeRegex.derle(#"&#x([0-9a-fA-F]+);"#, options: []) {
            let matches = hexRegex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed()
            for m in matches {
                if let r = Range(m.range(at: 1), in: text),
                   let code = UInt32(text[r], radix: 16),
                   let scalar = UnicodeScalar(code),
                   let fullR = Range(m.range, in: text) {
                    text.replaceSubrange(fullR, with: String(Character(scalar)))
                }
            }
        }

        return text
    }

    private static func cleanText(_ html: String) -> String {
        let noTags = KunyeRegex.etiketleriTemizle(html)
        let decoded = decodeHTMLEntities(noTags)
        return decoded
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
