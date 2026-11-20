import Foundation

/// kitapyurdu.com arama sonucundaki tek satır — doğru kitabı seçmek için kullanılır.
nonisolated struct KitapyurduSearchResult: Equatable, Sendable, Identifiable {
    var url: URL
    var title: String = ""
    var author: String = ""
    var publisher: String = ""

    var id: URL { url }
}

/// kitapyurdu.com'dan kitap bilgisi ve kapak çeker — Türkçe kitaplarda en geniş katalog.
/// Amazon ve Google Books'un bulamadığı yerli yayınlar için yedek kaynak olarak
/// BookMetadataService zincirine bağlıdır.
///
/// ÖNEMLİ: Kitapyurdu aramasında ISBN sonuç döndürmüyor (site yalnız ürün adı
/// üzerinden arıyor). Bu yüzden akış KİTAP ADI + YAZAR + YAYINEVİ ile aramaya
/// dayanır: arama → sonuçlar arasından ada/yazara/yayınevine en çok uyan ürün
/// → alan ayrıştırma + kapak indirme. ISBN yalnızca çekilen kayda yazılır.
/// Kitapyurdu isteğinin sunucu tarafı sonucu. Yalnız 404 ve 500 "sonuç yok" demektir (site boş aramada 500 döndürür);
/// 429/502/503/504 gibi kodlar geçici erişim sorunudur ve "kitap yok" olarak yorumlanmaz.
nonisolated enum KitapyurduHata: Error, Equatable {
    case sunucu(Int)

    /// Sayfa gerçekten "bulunamadı / sonuç yok" anlamına mı geliyor?
    var sonucYok: Bool {
        if case .sunucu(let kod) = self { return kod == 404 || kod == 500 }
        return false
    }
}

nonisolated enum KitapyurduScraper {
    @concurrent static func fetch(
        title: String,
        author: String = "",
        publisher: String = "",
        isbn: String = ""
    ) async throws -> AmazonBookMetadata? {
        let wantedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard wantedTitle.count >= 2 else { return nil }
        let fallbackISBN = isbn.filter { $0.isNumber || $0.isLetter }

        let results = try await searchResults(title: wantedTitle, author: author, publisher: publisher)
        // En uygun baskının sayfası okunamazsa (düzen/erişim sorunu) sıradakine geçilir
        var sonHata: Error?
        for candidate in results.prefix(3) {
            do {
                if let meta = try await fetchProduct(result: candidate, isbn: fallbackISBN) { return meta }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                sonHata = error
            }
        }
        // Hiçbir sayfa okunamadıysa bu "kitap yok" değildir: hata yayılır, çağıran "ulaşılamadı" sayar
        if let sonHata { throw sonHata }
        return nil
    }

    /// Arama sonuçlarını uygunluk sırasıyla döndürür (en uygun baskı başta).
    /// Arayüzde kullanıcıya baskı listesi göstermek için kullanılır.
    @concurrent static func searchResults(
        title: String,
        author: String = "",
        publisher: String = ""
    ) async throws -> [KitapyurduSearchResult] {
        let wantedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard wantedTitle.count >= 2 else { return [] }

        // Geniş sorgudan dara: ad+yazar+yayınevi → ad+yazar → ad+yayınevi → ad.
        // Yayınevi yazımı katalogla sitede farklı olabildiği için kademeli inilir.
        for query in searchQueries(title: wantedTitle, author: author, publisher: publisher) {
            guard let searchURL = searchURL(for: query) else { continue }

            let searchHTML: String
            do {
                searchHTML = try await fetchHTML(url: searchURL)
            } catch let error as KitapyurduHata where error.sonucYok {
                // Kitapyurdu, hiç sonuç bulunmayan aramalarda HTTP 500 döndürüyor;
                // bu bir ağ arızası değil "sonuç yok" demek: sonraki sorguya geçilir.
                // 429/502/503/504 ve bot engeli ise yayılır: "kitap yok" sanılmasın.
                continue
            }

            let parsed = parseSearchResults(html: searchHTML)
            if parsed.isEmpty, searchHTML.count > 5_000, searchHTML.contains("kitapyurdu.com/kitap/") {
                await AppLog.write("Kitapyurdu arama sayfası ayrıştırılamadı; kaynak düzeni değişmiş olabilir")
            }
            let ranked = rankedMatches(
                in: parsed,
                title: wantedTitle,
                author: author,
                publisher: publisher
            )
            if !ranked.isEmpty { return ranked }
        }
        return []
    }

    /// Seçilen arama sonucunun ürün sayfasından tüm alanları ve kapağı çeker.
    @concurrent static func fetchProduct(result: KitapyurduSearchResult, isbn: String = "") async throws -> AmazonBookMetadata? {
        let fallbackISBN = isbn.filter { $0.isNumber || $0.isLetter }
        let productHTML = try await fetchHTML(url: result.url)

        var meta = parseProduct(html: productHTML, fallbackISBN: fallbackISBN)
        if meta.title.isEmpty, productHTML.count > 5_000 {
            await AppLog.write("Kitapyurdu ürün sayfası ayrıştırılamadı; kaynak düzeni değişmiş olabilir")
        }
        meta.productURL = result.url
        // Ürün sayfası düzeni değişmişse arama satırındaki bilgiler yedek kalır
        if meta.title.isEmpty { meta.title = result.title }
        if meta.author.isEmpty { meta.author = result.author }
        if meta.publisher.isEmpty { meta.publisher = result.publisher }
        guard !meta.title.isEmpty else { return nil }

        if let coverURL = meta.coverURL {
            meta.coverData = await BookMetadataService.downloadImage(from: coverURL)
        }
        return meta
    }

    /// Denenecek arama metinleri — en belirleyici olandan en genişe doğru.
    static func searchQueries(title: String, author: String, publisher: String) -> [String] {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Çok yazarlı kayıtlarda tüm adları aramak sonucu boşaltır: ilk yazar yeter
        let author = primaryAuthor(author)
        let publisher = publisher.trimmingCharacters(in: .whitespacesAndNewlines)

        var queries: [String] = []
        for parts in [[title, author, publisher], [title, author], [title, publisher], [title]] {
            let query = parts.filter { !$0.isEmpty }.joined(separator: " ")
            if !query.isEmpty, !queries.contains(query) { queries.append(query) }
        }
        return queries
    }

    static func searchURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://www.kitapyurdu.com/index.php")
        components?.queryItems = [
            URLQueryItem(name: "route", value: "product/search"),
            URLQueryItem(name: "filter_name", value: query)
        ]
        return components?.url
    }

    /// Arama sayfasındaki ürün satırlarını (ad + yazar + yayınevi + adres) çıkarır.
    /// Ağdan bağımsız test edilebilir.
    static func parseSearchResults(html: String) -> [KitapyurduSearchResult] {
        // Eşleşme <a etiketinin başından alınır: ad, title niteliğinde olabiliyor
        guard let regex = KunyeRegex.derle(
            #"<a[^>]*href="(https://www\.kitapyurdu\.com/kitap/[^"]+)"[^>]*>"#,
            options: .caseInsensitive
        ) else { return [] }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var order: [String] = []
        var byLink: [String: KitapyurduSearchResult] = [:]

        for (index, match) in matches.enumerated() {
            guard let linkRange = Range(match.range(at: 1), in: html),
                  let tagRange = Range(match.range, in: html) else { continue }
            guard let url = normalizedProductURL(String(html[linkRange])) else { continue }
            // Aynı ürün satırda hem kapak hem ad bağlantısı olarak geçer: adres anahtarı
            // sorgusuz sürüm olduğu için bu parçalar tek kayıtta birleşir
            let link = url.absoluteString

            // Bu bağlantıdan sonraki ürün bağlantısına kadarki parça aynı satıra ait:
            // ad, yazar ve yayınevi bağlantıları burada yer alır
            let end = index + 1 < matches.count
                ? (Range(matches[index + 1].range, in: html)?.lowerBound ?? html.endIndex)
                : html.endIndex
            let segment = end > tagRange.lowerBound
                ? String(html[tagRange.lowerBound..<end])
                : String(html[tagRange.lowerBound...])

            var result = byLink[link] ?? KitapyurduSearchResult(url: url)
            if result.title.isEmpty { result.title = productName(in: segment) }
            if result.author.isEmpty {
                result.author = linkedName(in: segment, path: "yazar")
            }
            if result.publisher.isEmpty {
                result.publisher = linkedName(in: segment, path: "yayinevi")
            }
            if byLink[link] == nil { order.append(link) }
            byLink[link] = result
        }

        return order.compactMap { byLink[$0] }.filter { !$0.title.isEmpty }
    }

    /// Ürün adresindeki arama parametrelerini (filter_name, s_token, s_time) atar:
    /// bu belirteçler kısa ömürlü, ürün sayfası sorgusuz adresle de açılıyor.
    static func normalizedProductURL(_ href: String) -> URL? {
        let decoded = href
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutQuery = decoded.components(separatedBy: "?").first ?? decoded
        return URL(string: withoutQuery)
    }

    /// Arama sonuçları arasından ada/yazara/yayınevine en çok uyan kaydı seçer;
    /// ad yeterince örtüşmüyorsa (yanlış kitap riski) hiçbirini seçmez.
    static func bestMatch(
        in results: [KitapyurduSearchResult],
        title: String,
        author: String = "",
        publisher: String = ""
    ) -> KitapyurduSearchResult? {
        rankedMatches(in: results, title: title, author: author, publisher: publisher).first
    }

    /// Ada uyan sonuçları uygunluk puanına göre sıralar (yazar ve yayınevi
    /// eşleşmesi puanı yükseltir). Ada hiç uymayan satırlar listeye girmez.
    static func rankedMatches(
        in results: [KitapyurduSearchResult],
        title: String,
        author: String = "",
        publisher: String = ""
    ) -> [KitapyurduSearchResult] {
        let wantedTitle = tokens(title)
        guard !wantedTitle.isEmpty else { return [] }
        let wantedAuthor = tokens(primaryAuthor(author))
        let wantedPublisher = tokens(publisher, dropping: publisherNoise)

        let wantedPhrase = normalizedPhrase(title)

        var scored: [(result: KitapyurduSearchResult, score: Double, order: Int)] = []
        for (order, result) in results.enumerated() {
            let candidateTitle = tokens(result.title)
            let hit = Double(wantedTitle.filter { candidateTitle.contains($0) }.count)
                / Double(wantedTitle.count)
            // Aranan adın çoğu tutmuyorsa bu satır başka bir kitap
            guard hit >= 0.6 else { continue }

            // Ada fazladan sözcük ekleyen baskılar ("… (Ciltli)") birebir addan geride
            // kalsın; ceza yayınevi/yazar eşleşmesini bastıramayacak kadar küçük
            let extra = candidateTitle.subtracting(wantedTitle).count
            var score = hit - 0.10 * min(Double(extra) / Double(wantedTitle.count), 1)

            // Aranan ad birebir ya da baştan eşleşiyorsa öne alınır: "Tutunamayanlar"
            // ararken "Aşka Tutunamayanlar" değil "Tutunamayanlar / Bütün Eserleri" gelsin
            let candidatePhrase = normalizedPhrase(result.title)
            if candidatePhrase == wantedPhrase {
                score += 0.35
            } else if candidatePhrase.hasPrefix(wantedPhrase) {
                score += 0.25
            }

            if !wantedAuthor.isEmpty, !wantedAuthor.isDisjoint(with: tokens(result.author)) {
                score += 0.3
            }
            if !wantedPublisher.isEmpty,
               !wantedPublisher.isDisjoint(with: tokens(result.publisher, dropping: publisherNoise)) {
                score += 0.2
            }
            scored.append((result, score, order))
        }

        // Eşit puanlarda sitenin kendi sıralaması korunur
        return scored
            .sorted { $0.score > $1.score || ($0.score == $1.score && $0.order < $1.order) }
            .map(\.result)
    }

    /// "Ahmet Ümit, Mehmet Yaşın" → "Ahmet Ümit"
    static func primaryAuthor(_ author: String) -> String {
        author
            .components(separatedBy: CharacterSet(charactersIn: ",;/&"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Hemen her yayınevi adında geçtiği için eşleşmeye katkısı olmayan sözcükler
    private static let publisherNoise: Set<String> = [
        "yayinlari", "yayinevi", "yayin", "yayincilik", "kitap", "kitaplari",
        "kitabevi", "basim", "yayinlar", "ltd", "sti", "as", "ve"
    ]

    /// Karşılaştırma için Türkçe duyarlı sözcük kümesi: küçük harf, şapkasız, noktalamasız.
    static func tokens(_ text: String, dropping noise: Set<String> = []) -> Set<String> {
        let parts = flattened(text).components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(parts.filter { $0.count >= 2 && !noise.contains($0) })
    }

    /// Birebir/baştan eşleşme karşılaştırması için sözcük sırasını koruyan sade biçim:
    /// "Kürk Mantolu Madonna (Ciltli)" → "kurk mantolu madonna ciltli"
    static func normalizedPhrase(_ text: String) -> String {
        flattened(text)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Türkçe harfleri ASCII karşılığına indirip küçük harfe çevirir.
    private static func flattened(_ text: String) -> String {
        text
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "İ", with: "i")
            .replacingOccurrences(of: "ş", with: "s")
            .replacingOccurrences(of: "Ş", with: "s")
            .replacingOccurrences(of: "ğ", with: "g")
            .replacingOccurrences(of: "Ğ", with: "g")
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "Ü", with: "u")
            .replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "Ö", with: "o")
            .replacingOccurrences(of: "ç", with: "c")
            .replacingOccurrences(of: "Ç", with: "c")
            .lowercased()
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US"))
    }

    private static func productName(in segment: String) -> String {
        // Ürün bağlantısının kendi etiketi: title niteliği en temiz addır
        if let tag = firstMatch(
            in: segment,
            pattern: #"(<a[^>]*href="https://www\.kitapyurdu\.com/kitap/[^"]*"[^>]*>)"#
        ), let title = firstMatch(in: tag, pattern: #"title="([^"]+)""#) {
            let name = cleanText(title)
            if !name.isEmpty { return name }
        }
        if let inner = firstMatch(
            in: segment,
            pattern: #"<a[^>]*href="https://www\.kitapyurdu\.com/kitap/[^"]*"[^>]*>(.*?)</a>"#
        ) {
            let name = cleanText(inner)
            if !name.isEmpty { return name }
        }
        // Yalnız kapak görseli olan satırlarda ad img alt niteliğinde kalır
        if let alt = firstMatch(in: segment, pattern: #"alt="([^"]+)""#) {
            return cleanText(alt)
        }
        return ""
    }

    /// Satır içindeki yazar/yayınevi bağlantısının metni.
    private static func linkedName(in segment: String, path: String) -> String {
        // Adres göreli (/yazar/...) ya da tam (https://www.kitapyurdu.com/yazar/...) olabilir
        guard let raw = firstMatch(
            in: segment,
            pattern: #"<a[^>]*href="[^"]*/\#(path)/[^"]*"[^>]*>(.*?)</a>"#
        ) else { return "" }
        return cleanText(raw)
    }

    /// Ürün sayfası HTML'inden alanları çıkarır — ağdan bağımsız test edilebilir.
    static func parseProduct(html: String, fallbackISBN: String) -> AmazonBookMetadata {
        var result = AmazonBookMetadata()
        result.isbn = fallbackISBN

        // 1) Birincil kaynak: sayfadaki schema.org JSON-LD "Book" düğümü.
        // Site arayüzü değiştiğinde sınıf adları kayboluyor ama bu yapı kalıyor.
        if let structured = parseStructuredBook(html: html) {
            fillEmptyFields(of: &result, from: structured)
        }

        // 2) HTML yedekleri (JSON-LD kalkarsa ya da eski düzende)
        if result.title.isEmpty,
           let title = firstMatch(in: html, pattern: #"<h1[^>]*class="[^"]*(?:ky-pd-title|pr_header__heading)[^"]*"[^>]*>(.*?)</h1>"#)
            ?? firstMatch(in: html, pattern: #"<meta property="og:title" content="([^"]+)""#) {
            result.title = cleanText(title)
        }
        if result.author.isEmpty {
            result.author = firstMatch(in: html, pattern: #"pr_producers__manufacturer[^>]*>.*?<a[^>]*>(.*?)</a>"#)
                .map { cleanText($0) } ?? linkedName(in: html, path: "yazar")
        }
        if result.publisher.isEmpty {
            result.publisher = firstMatch(in: html, pattern: #"pr_producers__publisher[^>]*>.*?<a[^>]*>(.*?)</a>"#)
                .map { cleanText($0) } ?? linkedName(in: html, path: "yayinevi")
        }

        // 3) Özellik listesi — yeni düzen (etiket/değer span'leri) ve eski tablo düzeni
        let newLayout = allMatchPairs(
            in: html,
            pattern: #"ky-pd-attributes__label"[^>]*>(.*?)</span>.*?ky-pd-attributes__value"[^>]*>(.*?)</span>"#
        )
        let oldLayout = allMatchPairs(
            in: html,
            pattern: #"<tr[^>]*>\s*<td[^>]*>(.*?)</td>\s*<td[^>]*>(.*?)</td>"#
        )
        for (label, value) in newLayout + oldLayout {
            parseDetailLine(key: cleanText(label), value: cleanText(value), into: &result)
        }

        // 4) Kategori: "İlgili Kategoriler" yolundan
        if result.category.isEmpty {
            result.category = parseCategory(html: html)
        }

        // 5) Kapak: JSON-LD adresi yoksa og:image; boyut belirteci büyütülerek net kapak istenir
        if result.coverURL == nil,
           let image = firstMatch(in: html, pattern: #"<meta property="og:image" content="([^"]+)""#) {
            result.coverURL = URL(string: highResolutionImageURL(image))
        }
        return result
    }

    /// Ürün sayfasındaki "İlgili Kategoriler" yolundan en özel kategoriyi alır:
    /// "Kitap > Edebiyat > Roman (Yerli)" → "Roman (Yerli)". Amazon kazıyıcısıyla
    /// aynı kural: en genel kök ("Kitap") atlanır, en alt basamak kullanılır.
    /// Birden çok kategori listelenirse ilk (birincil) yol esas alınır.
    static func parseCategory(html: String) -> String {
        let block = firstMatch(in: html, pattern: #"ky-pd-attributes__category-link"[^>]*>(.*?)</a>"#)
            ?? firstMatch(in: html, pattern: #"ky-pd-attributes__categories"[^>]*>(.*?)</div>\s*</div>"#)
            ?? html

        let generic = ["kitap", "kategoriler", "tüm kategoriler", "ana sayfa"]
        let steps = allMatches(in: block, pattern: #"ky-pd-attributes__category-item[^"]*"[^>]*>(.*?)</span>"#)
            .map { cleanText($0) }
            .filter { step in
                !step.isEmpty && !generic.contains(step.lowercased(with: Locale(identifier: "tr_TR")))
            }
        return steps.last ?? ""
    }

    /// Ürün sayfasındaki schema.org JSON-LD "Book" düğümünden alanları okur.
    static func parseStructuredBook(html: String) -> AmazonBookMetadata? {
        for block in allMatches(
            in: html,
            pattern: #"<script[^>]*application/ld\+json[^>]*>(.*?)</script>"#
        ) {
            guard let data = block.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data),
                  let book = findBookNode(json) else { continue }

            var result = AmazonBookMetadata()
            result.title = cleanText(nodeText(book["name"]))
            result.author = nodeNames(book["author"])
            result.publisher = nodeNames(book["publisher"])
            // Tanıtım metninde noktalama korunur (JSON içinde HTML etiketi yok)
            result.notes = nodeText(book["description"]).trimmingCharacters(in: .whitespacesAndNewlines)

            let isbn = nodeText(book["isbn"]).filter(\.isNumber)
            if isbn.count == 13 || isbn.count == 10 { result.isbn = isbn }
            if let pages = book["numberOfPages"] as? Int, pages > 0 {
                result.pageCount = String(pages)
            } else if let pages = firstMatch(in: nodeText(book["numberOfPages"]), pattern: #"(\d+)"#) {
                result.pageCount = pages
            }
            if let year = firstMatch(in: nodeText(book["datePublished"]), pattern: #"((?:18|19|20)\d{2})"#) {
                result.publicationYear = year
            }
            switch nodeText(book["inLanguage"]).lowercased() {
            case "tr", "tur", "turkish": result.language = "Türkçe"
            case "en", "eng", "english": result.language = "İngilizce"
            default: break
            }
            if let image = URL(string: highResolutionImageURL(nodeText(book["image"]))) {
                result.coverURL = image
            }
            guard !result.title.isEmpty else { continue }
            return result
        }
        return nil
    }

    /// JSON ağacında @type'ı "Book" olan ilk düğümü bulur (@graph içinde olabilir).
    private static func findBookNode(_ node: Any) -> [String: Any]? {
        if let dictionary = node as? [String: Any] {
            let type = dictionary["@type"]
            if (type as? String) == "Book" || (type as? [String])?.contains("Book") == true {
                return dictionary
            }
            for value in dictionary.values {
                if let found = findBookNode(value) { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = findBookNode(value) { return found }
            }
        }
        return nil
    }

    /// JSON-LD alanı metin, sözlük ({"name": …}) ya da dizi olabilir.
    private static func nodeText(_ value: Any?) -> String {
        switch value {
        case let text as String: return text
        case let number as Int: return String(number)
        case let dictionary as [String: Any]:
            return nodeText(dictionary["name"]) + (dictionary["name"] == nil ? nodeText(dictionary["url"]) : "")
        case let array as [Any]: return array.first.map { nodeText($0) } ?? ""
        default: return ""
        }
    }

    /// Yazar/yayınevi alanı çok değerli olabilir: adları virgülle birleştirir.
    private static func nodeNames(_ value: Any?) -> String {
        if let array = value as? [Any] {
            return array
                .map { cleanText(nodeText($0)) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
        return cleanText(nodeText(value))
    }

    private static func fillEmptyFields(of result: inout AmazonBookMetadata, from other: AmazonBookMetadata) {
        if result.title.isEmpty { result.title = other.title }
        if result.author.isEmpty { result.author = other.author }
        if result.publisher.isEmpty { result.publisher = other.publisher }
        if result.isbn.isEmpty { result.isbn = other.isbn }
        if result.publicationYear.isEmpty { result.publicationYear = other.publicationYear }
        if result.pageCount.isEmpty { result.pageCount = other.pageCount }
        if result.language.isEmpty { result.language = other.language }
        if result.notes.isEmpty { result.notes = other.notes }
        if result.coverURL == nil { result.coverURL = other.coverURL }
    }

    private static func parseDetailLine(key: String, value: String, into result: inout AmazonBookMetadata) {
        let key = key.lowercased(with: Locale(identifier: "tr_TR"))
        guard !value.isEmpty else { return }

        if key.contains("sayfa sayısı") {
            if result.pageCount.isEmpty, let pages = firstMatch(in: value, pattern: #"(\d+)"#) {
                result.pageCount = pages
            }
        } else if key.contains("basım tarihi") || key.contains("yayın tarihi") || key.contains("basım yılı") {
            if result.publicationYear.isEmpty,
               let year = firstMatch(in: value, pattern: #"((?:18|19|20)\d{2})"#) {
                result.publicationYear = year
            }
        } else if key.contains("baskı") {
            if result.edition.isEmpty { result.edition = value }
        } else if key.contains("dil") {
            // Sayfa "TÜRKÇE" gibi büyük harfle verir; katalogdaki yazıma çevrilir
            if result.language.isEmpty {
                result.language = value.capitalized(with: Locale(identifier: "tr_TR"))
            }
        } else if key.contains("isbn") || key.contains("ısbn") {
            // tr_TR küçük harfe çevrilince "ISBN" → "ısbn" olur (noktasız ı).
            // Arama adla yapıldığı için sayfadaki baskı farklı olabilir: elde ISBN
            // varsa katalogdaki korunur, sayfadaki yalnız boşluğu doldurur.
            let digits = value.filter(\.isNumber)
            if result.isbn.isEmpty, digits.count == 13 { result.isbn = digits }
        } else if key.contains("yayınevi") || key.contains("yayıncı") {
            if result.publisher.isEmpty { result.publisher = value }
        } else if key.contains("kategori") || key.contains("tür") {
            if result.category.isEmpty { result.category = value }
        }
    }

    /// Kitapyurdu görsel adreslerindeki boyut belirteçlerini ("/wi:220",
    /// "/miw:200/mih:200") büyüterek küçük önizleme yerine baskıya uygun net kapak ister.
    static func highResolutionImageURL(_ url: String) -> String {
        url
            .replacingOccurrences(of: #"/wi:\d+"#, with: "/wi:800", options: .regularExpression)
            .replacingOccurrences(of: #"/miw:\d+"#, with: "/miw:800", options: .regularExpression)
            .replacingOccurrences(of: #"/mih:\d+"#, with: "/mih:800", options: .regularExpression)
    }

    private static func fetchHTML(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("tr-TR,tr;q=0.9,en-US;q=0.8", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else { throw KitapyurduHata.sunucu(http.statusCode) }
        let html = String(decoding: data, as: UTF8.self)
        // Bot doğrulama sayfası 200 ile gelir; boş sonuç gibi ayrıştırılırsa "kitap yok" sanılır
        guard !isBotChallenge(html: html) else { throw URLError(.resourceUnavailable) }
        return html
    }

    /// Cloudflare vb. "tarayıcınızı denetliyoruz" sayfası mı (arama ya da ürün sayfası yerine).
    static func isBotChallenge(html: String) -> Bool {
        ["Just a moment...", "cf-challenge", "challenge-platform", "cf-browser-verification"]
            .contains { html.contains($0) }
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = KunyeRegex.derle(pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    /// Tek yakalama gruplu desenin tüm eşleşmeleri.
    private static func allMatches(in text: String, pattern: String) -> [String] {
        guard let regex = KunyeRegex.derle(pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    /// İki yakalama gruplu deseni (etiket + değer) çift listesi olarak döndürür.
    private static func allMatchPairs(in text: String, pattern: String) -> [(String, String)] {
        guard let regex = KunyeRegex.derle(pattern) else {
            return []
        }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match in
            guard match.numberOfRanges > 2,
                  let labelRange = Range(match.range(at: 1), in: text),
                  let valueRange = Range(match.range(at: 2), in: text) else { return nil }
            return (String(text[labelRange]), String(text[valueRange]))
        }
    }

    private static func cleanText(_ html: String) -> String {
        let noTags = KunyeRegex.etiketleriTemizle(html)
        return decodeEntities(noTags)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// HTML varlıklarını çözer. Kitapyurdu kesme işaretini "&#039;" gibi sıfır dolgulu
    /// sayısal biçimde veriyor; bu yüzden adlı varlıkların yanında sayısal (ondalık ve
    /// onaltılık) biçimler de genel olarak çözülür. "&amp;" en sona bırakılır ki
    /// "&amp;#039;" gibi iki kez kodlanmış metinler yanlışlıkla bozulmasın.
    static func decodeEntities(_ text: String) -> String {
        var result = text
        for (entity, replacement) in [
            ("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", " "),
            ("&lt;", "<"), ("&gt;", ">"),
            ("&ndash;", "–"), ("&mdash;", "—"), ("&hellip;", "…")
        ] {
            result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }

        result = replacingNumericEntities(in: result, pattern: #"&#(\d{1,7});"#, radix: 10)
        result = replacingNumericEntities(in: result, pattern: #"&#x([0-9a-fA-F]{1,6});"#, radix: 16)
        return result.replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
    }

    private static func replacingNumericEntities(in text: String, pattern: String, radix: Int) -> String {
        guard let regex = KunyeRegex.derle(pattern, options: []) else { return text }
        var result = text
        // Sondan başa gidilir ki değişen uzunluklar önceki aralıkları kaydırmasın
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let full = Range(match.range, in: text),
                  let digits = Range(match.range(at: 1), in: text),
                  let code = UInt32(text[digits], radix: radix),
                  let scalar = Unicode.Scalar(code) else { continue }
            result.replaceSubrange(full, with: String(Character(scalar)))
        }
        return result
    }
}
