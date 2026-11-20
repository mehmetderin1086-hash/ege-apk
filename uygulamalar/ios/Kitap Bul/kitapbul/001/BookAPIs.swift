import Foundation
import CoreImage
import ImageIO

/// Bir ISBN sorgusunda kaynakların kaçı yanıt verdi, kaçına ulaşılamadı.
nonisolated struct KaynakDurumu: Equatable, Sendable {
    var yanitVeren = 0
    var ulasilamayan = 0

    /// Hiçbir kaynak yanıt veremedi: sonuç "kitap yok" değil, "bağlantı/erişim sorunu"dur.
    var hicbirineUlasilamadi: Bool { yanitVeren == 0 && ulasilamayan > 0 }
    /// Bazı kaynaklar yanıt verdi, bazılarına ulaşılamadı: "yok" sonucu kesin değildir
    /// (ör. Amazon engelli, Google kotada, yalnız OpenLibrary "yok" dedi).
    var kismenUlasilamadi: Bool { yanitVeren > 0 && ulasilamayan > 0 }
}

/// Künye aramasının sonucu; `meta` boşken nedeni `durum` ayırır.
nonisolated struct KunyeSonucu: Sendable {
    var meta: AmazonBookMetadata?
    var durum = KaynakDurumu()

    /// Kayıt yok ve en az bir kaynağa ulaşılamadı: "kitap yok" demek için yeterli yanıt alınmadı.
    var erisimSorunuVar: Bool { meta == nil && durum.ulasilamayan > 0 }

    /// Kayıt bulunamadığında kullanıcıya gösterilecek açıklama (kayıt varsa `nil`).
    var bulunamadiMesaji: String? {
        guard meta == nil else { return nil }
        if durum.hicbirineUlasilamadi {
            return "Çevrimiçi kaynaklara ulaşılamadı. Bağlantıyı denetleyip yeniden deneyin ya da bilgileri elle girin."
        }
        if durum.kismenUlasilamadi {
            return "Bazı çevrimiçi kaynaklara ulaşılamadı; kitap ulaşılan kaynaklarda bulunamadı. Daha sonra yeniden deneyin ya da bilgileri elle girin."
        }
        return "Bu ISBN çevrimiçi kaynaklarda bulunamadı. Bilgileri elle girin."
    }
}

/// Künye kazıyıcılarının ortak regex önbelleği: her çağrıda yeniden derlemek yerine desen başına bir kez derlenir.
/// `NSCache` iş parçacığı güvenlidir; kazıyıcılar ana aktör dışında koşar.
nonisolated enum KunyeRegex {
    nonisolated(unsafe) private static let onbellek = NSCache<NSString, NSRegularExpression>()
    static let varsayilanSecenekler: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]

    static func derle(_ desen: String, options: NSRegularExpression.Options = varsayilanSecenekler) -> NSRegularExpression? {
        let anahtar = "\(options.rawValue)|\(desen)" as NSString
        if let hazir = onbellek.object(forKey: anahtar) { return hazir }
        guard let yeni = try? NSRegularExpression(pattern: desen, options: options) else { return nil }
        onbellek.setObject(yeni, forKey: anahtar)
        return yeni
    }

    private static let etiket = try! NSRegularExpression(pattern: "<[^>]+>")

    /// HTML etiketlerini boşlukla değiştirir.
    static func etiketleriTemizle(_ html: String) -> String {
        etiket.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: " ")
    }
}

/// Oturum içi künye önbelleği. Seri taramada eşzamanlı sorgular ana aktörü beklemeden aynı önbelleğe erişir.
actor KunyeOnbellegi {
    static let paylasilan = KunyeOnbellegi()
    /// Kapak verisi taşıyan kayıtlar uzun depo taramasında bellekte sınırsız birikmesin
    private let sinir = 300
    private var kayitlar: [String: AmazonBookMetadata] = [:]

    func al(_ isbn: String) -> AmazonBookMetadata? { kayitlar[isbn] }

    func koy(_ isbn: String, _ meta: AmazonBookMetadata) {
        if kayitlar.count >= sinir { kayitlar.removeAll() }
        kayitlar[isbn] = meta
    }

    func temizle() { kayitlar.removeAll() }
}

/// Bir işi toplam süre bütçesiyle çalıştırır. Bütçe dolarsa iş iptal edilir ve `CancellationError` fırlatılır;
/// dıştan iptal edilirse de aynı hata yayılır. Zincirdeki tek tek istek zaman aşımları toplamda dakikaya çıkmasın diye.
nonisolated enum ButceliCalistir {
    static func calistir<T: Sendable>(butce: Duration, _ islem: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { grup in
            grup.addTask { try await islem() }
            grup.addTask {
                try await Task.sleep(for: butce)
                throw CancellationError()
            }
            defer { grup.cancelAll() }
            guard let ilk = try await grup.next() else { throw CancellationError() }
            return ilk
        }
    }
}

/// Kitap bilgisi kaynak zinciri: Amazon → Google Books → Kitapyurdu → OpenLibrary.
/// Amazon engellenir ya da kitabı bulamazsa sırayla diğer kaynaklara düşer;
/// bulunan kaydın eksik alanları (sayfa, kapak) sonraki kaynaklardan tamamlanır.
/// Kitapyurdu özellikle Amazon/Google'da olmayan yerli yayınları yakalar.
nonisolated enum BookMetadataService {
    /// Bir künye aramasının toplam süre bütçesi: kaynak başına zaman aşımları üst üste binip dakikalarca beklemesin.
    static let toplamButce: Duration = .seconds(20)

    /// Kitapyurdu ISBN aramasına sonuç vermediği için, elde varsa kitap adı /
    /// yazar / yayınevi bilgisi de geçilir: o kaynak bu alanlarla aranır.
    @concurrent static func fetch(
        isbn: String,
        title: String = "",
        author: String = "",
        publisher: String = ""
    ) async -> AmazonBookMetadata? {
        await fetchSonucu(isbn: isbn, title: title, author: author, publisher: publisher).meta
    }

    /// `fetch` ile aynı arama; kayıt çıkmadığında nedenini de bildirir: kaynaklar yanıt verip
    /// "yok" mu dedi, yoksa hiçbirine ulaşılamadı mı (çevrimdışı, engel, sunucu hatası, bütçe aşımı).
    /// Dıştan iptal edilirse eldeki (varsa önbellekteki) sonuçla döner; iptali ayırmak için
    /// `fetchSonucuButceli` kullanılır.
    @concurrent static func fetchSonucu(
        isbn: String,
        title: String = "",
        author: String = "",
        publisher: String = ""
    ) async -> KunyeSonucu {
        do {
            return try await fetchSonucuButceli(isbn: isbn, title: title, author: author, publisher: publisher)
        } catch {
            var durum = KaynakDurumu()
            durum.ulasilamayan = 1
            return KunyeSonucu(meta: await KunyeOnbellegi.paylasilan.al(isbn), durum: durum)
        }
    }

    /// Toplam `toplamButce` içinde biter; bütçe dolarsa ya da çağıran görev iptal edilirse `CancellationError` fırlatır
    /// (kullanıcı "İptal → elle gir" diyebilsin). Başarısız kaynak "kitap yok" sayılmaz.
    @concurrent static func fetchSonucuButceli(
        isbn: String,
        title: String = "",
        author: String = "",
        publisher: String = "",
        butce: Duration = toplamButce
    ) async throws -> KunyeSonucu {
        // Eksik (yazarsız/kapaksız) önbellek kaydı, ad/yazar ipucuyla yapılan yeni denemeyi
        // engellemez: Kitapyurdu ancak bu ipuçlarıyla aranabilir
        let hasHints = ![title, author, publisher].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let onbellek = KunyeOnbellegi.paylasilan
        let previous = await onbellek.al(isbn)
        if let cached = previous,
           !hasHints || (!cached.title.isEmpty && !cached.author.isEmpty && cached.coverData != nil) {
            return KunyeSonucu(meta: cached)
        }
        let (taze, durum) = try await ButceliCalistir.calistir(butce: butce) {
            await fetchFresh(isbn: isbn, title: title, author: author, publisher: publisher)
        }
        try Task.checkCancellation()
        guard let fresh = taze else {
            // Yenileme başarısız (ör. çevrimdışı): eldeki eksik kayıt yine de "bulunamadı"dan iyidir
            return KunyeSonucu(meta: previous, durum: durum)
        }
        let result = previous.map { merged(fresh, fillingFrom: $0) } ?? fresh
        await onbellek.koy(isbn, result)
        return KunyeSonucu(meta: result)
    }

    /// ISBN yoksa ad + yazar + yayınevi ile arama (Amazon → Google Books → Kitapyurdu).
    @concurrent static func search(title: String, author: String, publisher: String = "") async -> AmazonBookMetadata? {
        let query = [title, author, publisher]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard query.count >= 4 else { return nil }

        if let amazon = try? await AmazonBookScraper.fetchBook(searchText: query) {
            return amazon
        }
        if let google = await GoogleBooksAPI.search(query: query) {
            return google
        }
        // Yerli yayınlarda son durak: Kitapyurdu doğrudan ad aramasıyla çalışır
        return try? await KitapyurduScraper.fetch(title: title, author: author, publisher: publisher)
    }

    @concurrent private static func fetchFresh(
        isbn: String,
        title: String = "",
        author: String = "",
        publisher: String = ""
    ) async -> (AmazonBookMetadata?, KaynakDurumu) {
        var durum = KaynakDurumu()
        var meta = await dene(&durum) { try await withRetryThrowing { try await AmazonBookScraper.fetchBook(isbn: isbn) } }

        if meta == nil {
            meta = await dene(&durum) { try await GoogleBooksAPI.fetchThrowing(isbn: isbn) }
        } else if let current = meta,
                  current.pageCount.isEmpty || current.coverData == nil || current.author.isEmpty {
            if let google = await GoogleBooksAPI.fetch(isbn: isbn) {
                meta = merged(current, fillingFrom: google)
            }
        }

        // Türkçe kitaplarda Amazon/Google çoğu zaman boş döner: Kitapyurdu'na düş,
        // bulunmuşsa da eksik kalan kapak/sayfa bilgisini oradan tamamla.
        // Kitapyurdu ISBN'le arama yapamadığı için ad/yazar/yayınevi gerekir:
        // önceki kaynaktan gelen bilgi, yoksa çağıranın verdiği ipucu kullanılır.
        let searchTitle = firstNonEmpty(meta?.title, title)
        let searchAuthor = firstNonEmpty(meta?.author, author)
        let searchPublisher = firstNonEmpty(meta?.publisher, publisher)
        if !searchTitle.isEmpty,
           meta == nil || meta?.coverData == nil || meta?.pageCount.isEmpty == true {
            let kitapyurdu = await dene(&durum) {
                try await withRetryThrowing {
                    try await KitapyurduScraper.fetch(
                        title: searchTitle,
                        author: searchAuthor,
                        publisher: searchPublisher,
                        isbn: isbn
                    )
                }
            }
            if let kitapyurdu {
                meta = meta.map { merged($0, fillingFrom: kitapyurdu) } ?? kitapyurdu
            }
        }

        if meta == nil {
            meta = await dene(&durum) { try await OpenLibraryAPI.fetchThrowing(isbn: isbn) }
        }
        return (meta, durum)
    }

    /// Bir kaynağı dener ve yanıt verip vermediğini sayar: hata fırlatan kaynak "ulaşılamadı",
    /// boş dönen kaynak "yanıt verdi ama kitap yok" sayılır.
    private static func dene(
        _ durum: inout KaynakDurumu,
        _ operation: () async throws -> AmazonBookMetadata?
    ) async -> AmazonBookMetadata? {
        do {
            let sonuc = try await operation()
            durum.yanitVeren += 1
            return sonuc
        } catch {
            durum.ulasilamayan += 1
            return nil
        }
    }

    /// İlk boş olmayan değer (kaynaktan gelen bilgi, yoksa çağıranın ipucu).
    private static func firstNonEmpty(_ values: String?...) -> String {
        for value in values {
            let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    /// Ana kaydın BOŞ alanlarını ikinci kaynaktan doldurur.
    static func merged(_ base: AmazonBookMetadata, fillingFrom other: AmazonBookMetadata) -> AmazonBookMetadata {
        var result = base
        if result.title.isEmpty { result.title = other.title }
        if result.author.isEmpty { result.author = other.author }
        if result.publisher.isEmpty { result.publisher = other.publisher }
        if result.publicationYear.isEmpty { result.publicationYear = other.publicationYear }
        if result.pageCount.isEmpty { result.pageCount = other.pageCount }
        if result.language.isEmpty { result.language = other.language }
        if result.category.isEmpty { result.category = other.category }
        if result.notes.isEmpty { result.notes = other.notes }
        if result.coverData == nil { result.coverData = other.coverData }
        return result
    }

    /// ISBN'den resmi kapak görseli. Dört kaynaktan aday toplar (Amazon, Kitapyurdu,
    /// OpenLibrary, Google Books) ve EN YÜKSEK ÇÖZÜNÜRLÜKLÜ, kenarı temiz olanı seçer.
    /// Elle çekilmiş eğri/gölgeli fotoğraf yerine matbu kapak kullanılır.
    @concurrent static func officialCover(
        isbn: String,
        title: String = "",
        author: String = "",
        publisher: String = ""
    ) async -> Data? {
        var candidates: [Data] = []

        // 1. Amazon — genelde en büyük ve en temiz kapak
        if let amazon = try? await AmazonBookScraper.fetchBook(isbn: isbn),
           let cover = amazon.coverData {
            candidates.append(cover)
        }

        // 2. Kitapyurdu — yerli yayınlarda Amazon'un bulamadığını yakalar.
        // ISBN'le arama sonuç vermediği için ad/yazar/yayınevi gerekir; ad yoksa atlanır.
        if candidates.isEmpty, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let kitapyurdu = try? await KitapyurduScraper.fetch(
               title: title,
               author: author,
               publisher: publisher,
               isbn: isbn
           ),
           let cover = kitapyurdu.coverData {
            candidates.append(cover)
        }

        // 3. OpenLibrary büyük boy
        if let url = URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg?default=false"),
           let data = await downloadImage(from: url) {
            candidates.append(data)
        }

        // 4. Google Books — küçük önizleme yerine yüksek yakınlaştırma istenir
        if let google = await GoogleBooksAPI.fetch(isbn: isbn), let cover = google.coverData {
            candidates.append(cover)
        }

        // En geniş görseli seç; 300 pikselden küçükler (yer tutucu/ikon) atlanır
        return candidates
            .map { (data: $0, width: imageWidth(of: $0)) }
            .filter { $0.width >= 300 }
            .max { $0.width < $1.width }?
            .data
    }

    /// Görselin piksel genişliği (çözünürlük karşılaştırması için, tam kod çözme yapmadan).
    static func imageWidth(of data: Data) -> Int {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int else { return 0 }
        return width
    }

    /// Geçici ağ hatalarında artan aralıklarla yeniden dener (1 sn, 3 sn).
    /// Kalıcı hatalarda (bulunamadı/engellendi) boşuna beklemez.
    static func withRetry<T>(_ operation: () async throws -> T?) async -> T? {
        try? await withRetryThrowing(operation)
    }

    /// `withRetry` ile aynı; denemeler tükenince ya da kalıcı hatada son hatayı fırlatır
    /// (çağıran "kitap yok" ile "kaynağa ulaşılamadı"yı ayırabilsin diye).
    static func withRetryThrowing<T>(_ operation: () async throws -> T?) async throws -> T? {
        for attempt in 0..<3 {
            do {
                return try await operation()
            } catch {
                guard isRetriable(error), attempt < 2 else { throw error }
                // İptal edilmişse beklemeden çık
                try await Task.sleep(for: .seconds(attempt == 0 ? 1 : 3))
            }
        }
        return nil
    }

    /// Geçici ağ hataları ve sunucunun "sonra dene" dediği durumlar (429, 502, 503, 504) yeniden denenir;
    /// kalıcı hatalar (engel, 403, ayrıştırma) boşuna beklemez.
    static func isRetriable(_ error: Error) -> Bool {
        if let hata = error as? KitapyurduHata {
            if case .sunucu(let kod) = hata { return [429, 502, 503, 504].contains(kod) }
            return false
        }
        guard let url = error as? URLError else { return false }
        return [.timedOut, .networkConnectionLost, .cannotFindHost, .notConnectedToInternet].contains(url.code)
    }

    @concurrent static func downloadImage(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              !data.isEmpty else { return nil }
        return data
    }
}

// MARK: - Google Books (resmi API, anahtar gerektirmez)

nonisolated enum GoogleBooksAPI {
    @concurrent static func fetch(isbn: String) async -> AmazonBookMetadata? {
        try? await fetchThrowing(isbn: isbn)
    }

    /// `fetch` ile aynı; ağ ya da sunucu hatasını "kitap yok"tan ayırmak için fırlatır.
    @concurrent static func fetchThrowing(isbn: String) async throws -> AmazonBookMetadata? {
        try await request(query: "isbn:\(isbn)", fallbackISBN: isbn)
    }

    /// ISBN'i olmayan kitaplar için ad + yazar aramasi.
    @concurrent static func search(query: String) async -> AmazonBookMetadata? {
        try? await request(query: query, fallbackISBN: "")
    }

    private static func request(query: String, fallbackISBN: String) async throws -> AmazonBookMetadata? {
        // URLQueryItem "&" ve "+" karakterlerini de kodlar ("Suç & Ceza" sorgusu "Suç"ta kesilmez)
        var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")
        components?.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "country", value: "TR")]
        let encodedQuery = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        components?.percentEncodedQuery = encodedQuery
        guard let url = components?.url else {
            return nil
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        // Kota/sunucu hatası (429, 5xx) "kitap yok" değildir
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard case (var meta, let coverURL)? = parse(data, fallbackISBN: fallbackISBN) else { return nil }

        if let coverURL {
            meta.coverData = await BookMetadataService.downloadImage(from: coverURL)
        }
        return meta
    }

    /// JSON ayrıştırma — ağdan bağımsız test edilebilir.
    static func parse(_ data: Data, fallbackISBN: String) -> (AmazonBookMetadata, URL?)? {
        struct Yanit: Codable {
            struct Cilt: Codable {
                struct Bilgi: Codable {
                    struct Gorseller: Codable {
                        let thumbnail: String?
                    }
                    let title: String?
                    let authors: [String]?
                    let publisher: String?
                    let publishedDate: String?
                    let pageCount: Int?
                    let categories: [String]?
                    let language: String?
                    let description: String?
                    let imageLinks: Gorseller?
                }
                let volumeInfo: Bilgi
            }
            let items: [Cilt]?
        }

        guard let yanit = try? JSONDecoder().decode(Yanit.self, from: data),
              let bilgi = yanit.items?.first?.volumeInfo,
              let title = bilgi.title, !title.isEmpty else { return nil }

        var meta = AmazonBookMetadata()
        meta.title = title
        meta.author = (bilgi.authors ?? []).joined(separator: ", ")
        meta.publisher = bilgi.publisher ?? ""
        meta.isbn = fallbackISBN
        if let date = bilgi.publishedDate, date.count >= 4 {
            meta.publicationYear = String(date.prefix(4))
        }
        if let pages = bilgi.pageCount, pages > 0 {
            meta.pageCount = String(pages)
        }
        meta.category = bilgi.categories?.first ?? ""
        if bilgi.language == "tr" { meta.language = "Türkçe" }
        else if bilgi.language == "en" { meta.language = "İngilizce" }
        meta.notes = bilgi.description ?? ""

        var coverURL: URL?
        if let thumbnail = bilgi.imageLinks?.thumbnail {
            // Küçük önizleme yerine yüksek çözünürlüklü, kıvrık kenarsız sürüm istenir
            let highRes = thumbnail
                .replacingOccurrences(of: "http://", with: "https://")
                .replacingOccurrences(of: "zoom=1", with: "zoom=3")
                .replacingOccurrences(of: "&edge=curl", with: "")
            coverURL = URL(string: highRes)
        }
        return (meta, coverURL)
    }
}

// MARK: - OpenLibrary (resmi API)

nonisolated enum OpenLibraryAPI {
    @concurrent static func fetch(isbn: String) async -> AmazonBookMetadata? {
        try? await fetchThrowing(isbn: isbn)
    }

    /// `fetch` ile aynı; ağ ya da sunucu hatasını "kitap yok"tan (404) ayırmak için fırlatır.
    @concurrent static func fetchThrowing(isbn: String) async throws -> AmazonBookMetadata? {
        guard let url = URL(string: "https://openlibrary.org/isbn/\(isbn).json") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 404, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard var meta = parse(data, fallbackISBN: isbn) else { return nil }

        if let coverURL = URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg?default=false") {
            meta.coverData = await BookMetadataService.downloadImage(from: coverURL)
        }
        return meta
    }

    static func parse(_ data: Data, fallbackISBN: String) -> AmazonBookMetadata? {
        struct Yanit: Codable {
            let title: String?
            let publishers: [String]?
            let publish_date: String?
            let number_of_pages: Int?
        }
        guard let yanit = try? JSONDecoder().decode(Yanit.self, from: data),
              let title = yanit.title, !title.isEmpty else { return nil }

        var meta = AmazonBookMetadata()
        meta.title = title
        meta.publisher = yanit.publishers?.first ?? ""
        meta.isbn = fallbackISBN
        if let date = yanit.publish_date,
           let match = date.range(of: #"(?:19|20)\d{2}"#, options: .regularExpression) {
            meta.publicationYear = String(date[match])
        }
        if let pages = yanit.number_of_pages, pages > 0 {
            meta.pageCount = String(pages)
        }
        return meta
    }
}

// MARK: - Kurum içi barkod (ISBN'siz kitaplar için)

/// ISBN'i olmayan kitaplara GS1 "kurum içi" (200 ile başlayan) geçerli EAN-13 üretir.
/// Bu kodlar uygulamadaki tüm barkod akışlarıyla (arama, sayım, ödünç) uyumludur.
nonisolated enum InternalBarcode {
    static func generate(existingCodes: Set<String>) -> String {
        var counter = 1
        while true {
            let body = "200" + String(format: "%09d", counter)
            let code = body + String(checkDigit(for: body))
            if !existingCodes.contains(code) {
                return code
            }
            counter += 1
        }
    }

    static func isInternal(_ code: String) -> Bool {
        code.count == 13 && code.hasPrefix("200")
    }

    private static func checkDigit(for firstTwelve: String) -> Int {
        let sum = firstTwelve.enumerated().reduce(0) { result, item in
            result + (Int(String(item.element)) ?? 0)
                * (item.offset.isMultiple(of: 2) ? 1 : 3)
        }
        return (10 - (sum % 10)) % 10
    }

    private static let barkodBaglami = CIContext()

    /// Etikete basılabilir Code128 barkod görseli üretir.
    static func barcodeImage(for code: String) -> CGImage? {
        guard let filter = CIFilter(name: "CICode128BarcodeGenerator") else { return nil }
        filter.setValue(Data(code.utf8), forKey: "inputMessage")
        filter.setValue(0, forKey: "inputQuietSpace")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 3, y: 3))
        return barkodBaglami.createCGImage(scaled, from: scaled.extent)
    }
}
