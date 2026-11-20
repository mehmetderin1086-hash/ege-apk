import Foundation
import PDFKit

// MEB kütüphanesi: Türkiye Yüzyılı Maarif Modeli sitesindeki (tymm.meb.gov.tr) ortaöğretim öğretim programları ve ders kitapları.
// Derslerin tema ağacı (öğrenme çıktıları, içerik çerçevesi) uygulamayla birlikte gelir; kitap ve program PDF'leri istenince indirilir.

nonisolated struct MEBCatalog: Codable, Sendable {
    struct Grade: Codable, Identifiable, Hashable, Sendable { var id: Int; var name: String }
    /// İçerik çerçevesinin bir alt başlığı (yoksa boş) ve altındaki konular.
    struct Content: Codable, Hashable, Sendable { var heading: String; var topics: [String] }
    struct Theme: Codable, Identifiable, Hashable, Sendable {
        var id: Int
        var title: String
        var summary: String
        var hours: Int
        var outcomes: [String]
        var content: [Content]
        var keywords: String
    }
    struct GradeThemes: Codable, Hashable, Sendable { var grade: Int; var themes: [Theme] }
    struct Course: Codable, Identifiable, Hashable, Sendable {
        var id: Int
        var name: String
        var slug: String
        /// Öğretim programının PDF yolu (yoksa boş).
        var program: String
        /// YKS'de (TYT/AYT) sorusu çıkan ders.
        var yks: Bool
        var grades: [GradeThemes]
        func themes(in grade: Int) -> [Theme] { grades.first { $0.grade == grade }?.themes ?? [] }
        /// "Biyoloji Dersi" → "Biyoloji".
        var shortName: String { name.replacingOccurrences(of: " Dersi", with: "").replacingOccurrences(of: " (Ortaöğretim)", with: "") }
    }
    struct Book: Codable, Identifiable, Hashable, Sendable {
        var id: Int
        var title: String
        /// ders | etkinlik
        var kind: String
        var grade: Int
        var course: Int
        var pdf: String
        var cover: String
        var bytes: Int
    }
    var version: String
    var source: String
    var grades: [Grade]
    var courses: [Course]
    var books: [Book]

    static let empty = MEBCatalog(version: "", source: "https://tymm.meb.gov.tr", grades: [], courses: [], books: [])
    /// Uygulamayla gelen katalog.
    static let shared: MEBCatalog = {
        guard let url = Bundle.main.url(forResource: "MEBKatalog", withExtension: "json"), let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(MEBCatalog.self, from: data) else { return .empty }
        return catalog
    }()

    /// Bu sınıfta teması ya da kitabı olan dersler: önce YKS dersleri, sonra ada göre.
    func courses(in grade: Int) -> [Course] {
        let withBooks = Set(books.filter { $0.grade == grade }.map(\.course))
        return courses.filter { !$0.themes(in: grade).isEmpty || withBooks.contains($0.id) }
            .sorted { ($0.yks ? 0 : 1, $0.name) < ($1.yks ? 0 : 1, $1.name) }
    }
    func books(course: Int, grade: Int) -> [Book] {
        books.filter { $0.course == course && $0.grade == grade }.sorted { ($0.kind == "ders" ? 0 : 1, $0.title) < ($1.kind == "ders" ? 0 : 1, $1.title) }
    }
    /// Dersin bütün sınıflardaki kitapları (sınıf sırasıyla, ders kitabı önce).
    func books(course: Int) -> [Book] {
        books.filter { $0.course == course }.sorted { ($0.grade, $0.kind == "ders" ? 0 : 1, $0.title) < ($1.grade, $1.kind == "ders" ? 0 : 1, $1.title) }
    }
    /// Yol siteye göreyse tam adrese çevrilir; yalnız https kabul edilir.
    func url(_ path: String) -> URL? {
        let text = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let url = text.hasPrefix("/") ? URL(string: source + text) : URL(string: text), url.scheme == "https" else { return nil }
        return url
    }
}

extension MEBCatalog.Theme {
    /// Konu videosu için seçilebilecek konular: içerik çerçevesinin alt başlıkları ve altlarındaki konular.
    /// Programda konu listesi verilmemişse temanın adı tek konu olarak sunulur.
    var topicGroups: [MEBCatalog.Content] {
        let groups = content.filter { !$0.topics.isEmpty }
        return groups.isEmpty ? [MEBCatalog.Content(heading: "", topics: [shortTitle])] : groups
    }
    /// "1. Tema: Yaşam" → "Yaşam".
    var shortTitle: String {
        guard let colon = title.firstIndex(of: ":") else { return title }
        let rest = title[title.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? title : rest
    }
}

/// Ders kitabının basılı "İçindekiler" sayfalarından çıkarılan konu dizini. Kitap PDF'lerinde gömülü içindekiler yoktur;
/// başlık ve sayfa numarası, sayfa metnindeki "BAŞLIK ........ 16" ya da "1.1. BAŞLIK 16" satırlarından okunur.
nonisolated struct MEBBookIndex: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var title: String
        /// Basılı sayfa numarası.
        var page: Int
        /// 0: bölüm (büyük harf), 1: numaralı konu ("1.2."), 2: alt başlık.
        var level: Int
    }
    var entries: [Entry]
    /// PDF sırası (1'den) − basılı sayfa numarası.
    var offset: Int

    /// Başlık, ardından nokta dizisi ya da boşluk, sonda sayfa numarası ("8-9" gibi aralıkta ilk sayı).
    private static let leader = try! NSRegularExpression(pattern: #"^(.*?)(?:[\s.…]*[.…]{2,}[\s.…]*|\s+)(\d{1,3})(?:\s*[-–]\s*\d{1,3})?\s*$"#)
    private static let locale = Locale(identifier: "tr_TR")

    /// İlk sayfaların metninden dizin girdilerini çıkarır. Satır sonuna sığmayıp ikiye bölünen başlıklar birleştirilir.
    static func parse(pages: [String]) -> [Entry] {
        var entries: [Entry] = [], pending = ""
        for page in pages {
            pending = ""
            let lines = page.components(separatedBy: .newlines).map { $0.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            // Dizin sayfası: satırların çoğu sayfa numarasıyla biter. Öbür sayfalardaki "... 12" ile biten tek tük satır dizin sayılmaz.
            let numbered = lines.filter { line in
                guard let match = leader.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)), let title = Range(match.range(at: 1), in: line) else { return false }
                return line[title].filter(\.isLetter).count >= 3
            }.count
            guard numbered >= 5, numbered * 4 >= lines.count else { continue }
            for line in lines {
                let range = NSRange(line.startIndex..., in: line)
                if let match = leader.firstMatch(in: line, range: range), let titleRange = Range(match.range(at: 1), in: line), let pageRange = Range(match.range(at: 2), in: line),
                   let number = Int(line[pageRange]), number > 0 {
                    let title = (pending.isEmpty ? "" : pending + " ") + line[titleRange].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".…")))
                    pending = ""
                    if title.filter(\.isLetter).count >= 3, title.count <= 140 { entries.append(Entry(title: title, page: number, level: level(title))) }
                } else {
                    // Yalnız büyük harfli ya da numarayla başlayan satır, bir sonraki satırda süren başlık olabilir.
                    let letters = line.filter(\.isLetter)
                    let continues = letters.count >= 6 && line.count <= 70 && (letters == letters.uppercased(with: locale) || line.first?.isNumber == true)
                    pending = continues ? (pending.isEmpty ? line : pending + " " + line) : ""
                }
            }
        }
        // Dizin baştan sona artan sayfa numarasıyla ilerler; sırayı bozan satır (dipnot, tablo) atılır.
        var result: [Entry] = []
        for entry in entries where entry.page >= (result.last?.page ?? 0) { result.append(entry) }
        return result
    }
    static func level(_ title: String) -> Int {
        // "1.2. BAŞLIK" konu başlığıdır; "4.2.1. Alt başlık" alt düzeydir (konuyu erken bitirmesin).
        if title.range(of: #"^\d+\.\d+\.?\s"#, options: .regularExpression) != nil { return 1 }
        if title.range(of: #"^\d+\.\d+\.\d"#, options: .regularExpression) != nil { return 2 }
        let letters = title.filter(\.isLetter)
        return letters == letters.uppercased(with: locale) ? 0 : 2
    }

    /// Karşılaştırma için sözcük kökleri: küçük harf, noktalamasız, bağlaçsız; Türkçe ekler için ilk beş harf.
    static func stems(_ text: String) -> [String] {
        let stop: Set<String> = ["ve", "ile", "bir", "için", "olan", "de", "da", "veya", "ya"]
        // "ı" ile "i" eşitlenir: İngilizce kitaplarda "LIFE" ile "Life" aynı köke düşsün.
        return text.lowercased(with: locale).replacingOccurrences(of: "ı", with: "i").components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 2 && !stop.contains($0) }.map { String($0.prefix(5)) }
    }
    /// Konuya en çok benzeyen dizin girdisi; konunun sözcüklerinin en az üçte ikisi başlıkta geçmelidir.
    func match(_ topic: String) -> Int? {
        let wanted = Set(Self.stems(topic))
        guard !wanted.isEmpty else { return nil }
        var best: (index: Int, score: Double)?
        for (index, entry) in entries.enumerated() {
            let have = Set(Self.stems(entry.title))
            guard !have.isEmpty else { continue }
            let common = Double(wanted.intersection(have).count)
            // Hem konunun başlıkta geçmesi hem başlığın konudan çok uzun olmaması ödüllendirilir.
            let score = common / Double(wanted.count) * 0.75 + common / Double(have.count) * 0.25
            if common / Double(wanted.count) >= 0.66, score > (best?.score ?? 0) { best = (index, score) }
        }
        return best?.index
    }
    /// Konunun kitapta kapladığı PDF sayfaları (0'dan): eşleşen başlıktan, aynı ya da üst düzeydeki bir sonraki başlığa kadar; en çok 30 sayfa.
    func pages(for topic: String, pageCount: Int) -> Range<Int>? {
        guard let index = match(topic) else { return nil }
        let entry = entries[index]
        let next = entries[(index + 1)...].first { $0.level <= entry.level && $0.page > entry.page }?.page ?? entries[(index + 1)...].first { $0.page > entry.page + 1 }?.page
        let start = entry.page + offset - 1
        let end = min(pageCount, min((next ?? entry.page + 12) + offset - 1, start + 30))
        guard start >= 0, start < pageCount, end > start else { return nil }
        return start..<end
    }

    /// Basılı sayfa numarası ile PDF sırası arasındaki farkı örnek sayfalardan bulur: sayfa metninin ilk ya da son satırı numaradır.
    static func offset(samples: [(index: Int, text: String)]) -> Int {
        var votes: [Int: Int] = [:]
        for sample in samples {
            let lines = sample.text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            for candidate in [lines.first, lines.last].compactMap({ $0 }) {
                if let number = Int(candidate), number > 0, number < 1000 { votes[sample.index + 1 - number, default: 0] += 1; break }
            }
        }
        // Tek tük sayı satırı (şık, tablo hücresi) farkı belirlemesin: en az üç sayfa aynı farkı göstermeli.
        guard let best = votes.max(by: { ($0.value, -abs($0.key)) < ($1.value, -abs($1.key)) }), best.value >= 3, abs(best.key) <= 40 else { return 0 }
        return best.key
    }

    /// Kitabın dizinini okur (ilk 16 sayfa) ve sayfa farkını bulur.
    static func read(_ document: PDFDocument) -> MEBBookIndex {
        let count = document.pageCount
        let front = (0..<min(16, count)).map { document.page(at: $0)?.string ?? "" }
        let samples = stride(from: 20, to: min(count, 80), by: 6).map { (index: $0, text: document.page(at: $0)?.string ?? "") }
        return MEBBookIndex(entries: parse(pages: front), offset: offset(samples: samples))
    }

    /// Konunun kitaptaki metni. `search` açıksa ve dizinde bulunamazsa konunun adının geçtiği ilk sayfadan başlayan bölüm denenir
    /// (tek sözcüklü konularda denenmez: sözcüğün geçtiği ilk sayfa çoğu kez ilgisizdir).
    /// Dönen `pages` basılı sayfa aralığıdır (kullanıcıya gösterilir). Görev iptal edilirse `nil` döner.
    static func text(for topic: String, in url: URL, search: Bool = true, limit: Int = TopicSource.maximum) -> (text: String, pages: ClosedRange<Int>)? {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { return nil }
        let index = read(document)
        var range = index.pages(for: topic, pageCount: document.pageCount)
        if range == nil, search {
            // Dizini okunamayan kitap: konunun bütün sözcükleri aynı sayfada geçen ilk içerik sayfası.
            let wanted = Set(stems(topic))
            guard wanted.count >= 2 else { return nil }
            for page in min(16, document.pageCount)..<document.pageCount {
                if Task.isCancelled { return nil }
                let found = autoreleasepool { wanted.isSubset(of: Set(stems(String((document.page(at: page)?.string ?? "").prefix(1500))))) }
                if found { range = page..<min(document.pageCount, page + 8); break }
            }
        }
        guard let range, !Task.isCancelled else { return nil }
        var text = ""
        for page in range {
            guard text.utf16.count < limit else { break }
            autoreleasepool { text += (document.page(at: page)?.string ?? "") + "\n\n" }
        }
        let cleaned = text.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= TopicSource.minimum else { return nil }
        return (cleaned, (range.lowerBound + 1 - index.offset)...(range.upperBound - index.offset))
    }
}
