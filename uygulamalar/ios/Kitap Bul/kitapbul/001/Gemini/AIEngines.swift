import Foundation
import SwiftData

// MARK: - Katalog arama dizini (büyük kataloglar için)

/// `CatalogBook.searchKey` alanını dolduran ve onun üzerinden veritabanında ön süzme
/// yapan yardımcı. Asistan 50 bin kitapta her soruda tüm kayıtları bellekte
/// normalize etmek yerine yalnızca eşleşen birkaç yüz kaydı çeker.
enum CatalogSearchIndex {
    /// `searchKey` boş kayıtları 500'lük partiler hâlinde doldurur (eski kayıtlar için bir kez).
    static func backfillIfNeeded(context: ModelContext, requireCurrent: (@MainActor () throws -> Void)? = nil) async {
        var descriptor = FetchDescriptor<CatalogBook>(predicate: #Predicate { $0.searchKey == nil })
        descriptor.fetchLimit = 500
        for _ in 0..<200 { // en fazla 100 bin kayıt
            do { try Task.checkCancellation(); try requireCurrent?() } catch { return }
            guard let batch = try? context.fetch(descriptor), !batch.isEmpty else { return }
            for book in batch { book.refreshSearchKey() }
            try? context.save()
            await Task.yield()
        }
    }

    /// Anahtar sözcüklerden herhangi birini içeren kitaplar (en fazla `limit`).
    static func candidates(for terms: [String], context: ModelContext, limit: Int = 300) -> [CatalogBook] {
        var seen = Set<UUID>()
        var result: [CatalogBook] = []
        for term in terms.prefix(5) where term.count >= 3 {
            var descriptor = FetchDescriptor<CatalogBook>(
                predicate: #Predicate { ($0.searchKey?.contains(term) ?? false) && !$0.isWithdrawn }
            )
            descriptor.fetchLimit = limit
            for book in (try? context.fetch(descriptor)) ?? [] where seen.insert(book.id).inserted {
                result.append(book)
            }
        }
        return result
    }
}

// MARK: - ISBN'den Gemini bilgisi (Amazon/Kitapyurdu bulamazsa)

extension GeminiBookRecognizer {
    /// Barkodu okunmuş ama çevrimiçi kaynaklarda bulunamayan kitap için Gemini'nin kendi
    /// bilgisinden alanları getirir. Model bilgisi ISBN'de yanılabileceği için ad/yazar her
    /// zaman "kontrol edilmeli" işaretli kalır.
    static func lookupISBN(_ isbn: String, into draft: inout BookDraft) async {
        guard GeminiSettings.isOCREnabled, !isbn.isEmpty else { return }
        let prompt = """
        ISBN \(isbn) numaralı kitabı tanıyorsan bilgilerini ver. Tanımıyorsan {"isBook": false} döndür; \
        tahmin yürütme. YALNIZCA JSON: {"isBook": true, "title": "", "author": "", "publisher": "", \
        "publicationYear": "", "pageCount": "", "language": "", "category": "", "summary": "", "uncertain": []}
        category şu listeden: \(KitapKategorileri.liste.joined(separator: ", ")).
        """
        guard var fields = try? await GeminiClient.shared.generateJSON(
            GeminiBookFields.self, prompt: prompt, temperature: 0.1, maxOutputTokens: 1024,
            timeout: 20, maxAttempts: 1
        ), fields.isBook != false else { return }
        fields = normalized(fields)
        fields.isbn = nil // barkod ISBN'i esas
        fields.uncertain = Array(Set((fields.uncertain ?? []) + ["title", "author"]))
        merge(fields, into: &draft)
    }
}

// MARK: - Raf / çoklu kitap tarama

nonisolated struct ShelfScanReply: Codable, Sendable {
    var books: [GeminiBookFields]
    var note: String?
    /// Raf üstünde/altında yazılı etiket ("6 TÜRK EDEBİYATI"); yoksa boş.
    var shelfLabel: String?
    /// Raf kenarındaki dolap kodu ("B"); yoksa boş.
    var cabinetLabel: String?
}

/// Dilimli raf taramasının toplu sonucu (tüm fotoğraflar ve dilimler birleşik).
nonisolated struct ShelfScanResult: Codable, Sendable, Equatable {
    var books: [GeminiBookFields] = []
    var photoRelation: ScanPhotoRelation = .overlapping
    var tiles: [ShelfTileReading] = []
    var successfulTileCount: Int { tiles.filter { $0.status == .read }.count }
    var failedTileCount: Int { tiles.filter { $0.status == .failed }.count }
    var unfinishedTileCount: Int { tiles.filter { $0.status != .read }.count }
    var isComplete: Bool { !tiles.isEmpty && unfinishedTileCount == 0 }
    /// Dilimlerde okunan FARKLI raf/dolap etiketleri (okunma sırasıyla, tekil).
    var shelfLabels: [String] = []
    var cabinetLabels: [String] = []
    /// Tek ve tutarlı etiket varsa o; birden çok farklı etiket (tam dolap karesi) varsa nil —
    /// hangi kitabın hangi rafta olduğu bilinmediği için raf alanı otomatik doldurulmaz.
    var shelfLabel: String? { shelfLabels.count == 1 ? shelfLabels[0] : nil }
    var cabinetLabel: String? { cabinetLabels.count == 1 ? cabinetLabels[0] : nil }
    /// Okunan dilim sayısı (bilgi amaçlı).
    var tileCount = 0
    /// Bir fotoğrafta görülen en çok raf satırı. Birden çok satır varsa tek raf etiketi bile
    /// bütün kitaplara yazılmaz (etiket yalnız bir rafa aittir).
    var satirSayisi = 1
    /// Raf alanı otomatik doldurulabilir mi: tek raf ve tek tutarlı etiket.
    var rafOtomatikDolabilir: Bool { satirSayisi <= 1 && shelfLabel != nil }
    /// Etiketten çözülen raf numarası ("6 TÜRK EDEBİYATI" → "6").
    var shelfNumber: String? { ShelfScanEngine.shelfNumber(from: shelfLabel) }
    /// Toplam nüsha (kitap × adet).
    var totalCopies: Int { books.reduce(0) { $0 + $1.nusha } }
}

nonisolated struct ShelfTileReading: Identifiable, Codable, Sendable, Equatable {
    enum Status: String, Codable, Sendable { case waiting, read, failed }
    var id = UUID()
    var jpeg: Data
    var photo: Int
    var row: Int
    var column: Int
    var overlapsAbove: Bool
    var status: Status = .waiting
    var books: [GeminiBookFields] = []
    var shelfLabel: String?
    var cabinetLabel: String?
    var errorMessage: String?
}

/// Tek fotoğrafta birden çok kitap: raftaki sırtlar ya da masadaki kapaklar.
enum ShelfScanEngine {
    static let systemPrompt = """
    Sen bir okul kütüphanesi kataloglama asistanısın. Fotoğrafta BİRDEN ÇOK kitap olabilir: rafta \
    yan yana dizili kitap sırtları, üst üste yatay konmuş kitaplar ya da masaya konmuş kapaklar. \
    Soldan sağa, yukarıdan aşağıya HER kitabı ayrı kayıt olarak çıkar; hiçbirini atlama. Sırt \
    yazıları dikey olabilir (aşağıdan yukarıya ya da yukarıdan aşağıya); döndürerek oku. \
    Okunamayanı boş bırak ve confidence (0–1) değerini düşük ver. Kitabı tanıyorsan eksik \
    yayınevi/kategoriyi bilginle doldur ve uncertain'e ekle.
    Kurallar:
    - copies: aynı kitabın birden çok nüshası yan yana duruyorsa TEK kayıt yaz ve nüsha sayısını \
    copies alanına koy (tek nüsha için 1). Farklı kitapları asla tek kayıtta birleştirme.
    - box_2d: kaydın temsil ettiği kitap sırtlarının bu görüntüdeki sınır kutusu; \
    [ymin, xmin, ymax, xmax], 0–1000 ölçeği. Kaynak fotoğrafı kontrol etmek için her kayıtta ver.
    - Sırtta yazar adı genelde bir uçta büyük harfle, kitap adı ortada yer alır; yazar adını title'a, \
    kitap adını author'a yazma. Alt başlık varsa iki nokta ile ada ekle.
    - Sırt altındaki dizi numaraları (141, 72 gibi) ve yer numarası çıkartmaları (4, 26 gibi) kitap \
    adının parçası DEĞİLDİR; yazma.
    - publisher: sırttaki logo ya da dizi tasarımından çıkar (ör. beyaz "Hasan Âli Yücel Klasikler \
    Dizisi" sırtları → "Türkiye İş Bankası Kültür Yayınları", "YKY" → "Yapı Kredi Yayınları", \
    "İletişim", "Ötüken", "Can Yayınları", "İthaki").
    - shelfLabel: rafın üstünde/altında yazılı etiket varsa aynen ("6 TÜRK EDEBİYATI"); yoksa boş.
    - cabinetLabel: raf kenarındaki tek harf ya da kısa kod etiketi ("B"); yoksa boş.
    - Türkçe karakterleri (ş, ğ, ı, İ, ö, ü, ç) doğru yaz; tümü büyük harfli adları Başlık Biçimine çevir.
    YALNIZCA JSON: {"books": [{"title": "", "author": "", "publisher": "", "isbn": "", \
    "publicationYear": "", "category": "", "copies": 1, "confidence": 0.9, "box_2d": [0,0,1000,1000], "uncertain": []}], \
    "note": "", "shelfLabel": "", "cabinetLabel": ""}
    category şu listeden: \(KitapKategorileri.liste.joined(separator: ", ")).
    """

    /// Geriye dönük kısa yol: yalnız kitap listesi.
    static func scan(images: [Data]) async throws -> [GeminiBookFields] {
        try await scanDetailed(images: images).books
    }

    /// Bir dilimin okuma sonucu ve fotoğraftaki yeri (birleştirmede komşuluk için).
    nonisolated struct DilimSonucu: Sendable {
        var books: [GeminiBookFields]
        var foto: Int
        var satir: Int
        var sutun: Int
        /// Kesit bir üst satırla piksel paylaşıyor (RafDilimleyici.Dilim.ustBindirmeli).
        var ustBindirmeli = false

        init(books: [GeminiBookFields], foto: Int, satir: Int, sutun: Int, ustBindirmeli: Bool = false) {
            self.books = books
            self.foto = foto
            self.satir = satir
            self.sutun = sutun
            self.ustBindirmeli = ustBindirmeli
        }
    }

    /// Dilimli tarama: her fotoğraf raf satırlarına ve dikey şeritlere bölünür (RafDilimleme.swift),
    /// dilimler 3'erli paralel okunur, sonuçlar nüsha sayısı korunarak birleştirilir.
    /// - Parameter progress: (okunan dilim, toplam dilim) — arayüz ilerleme gösterir.
    /// Görev iptal edilirse (sayfadan çıkış) `CancellationError` fırlatır; yarım sonuç dönmez.
    static func scanDetailed(images: [Data], photoRelation: ScanPhotoRelation = .overlapping,
                             retrying previous: ShelfScanResult? = nil,
                             progress: ((Int, Int) -> Void)? = nil,
                             checkpoint: ((ShelfScanResult) -> Void)? = nil,
                             reader: (@Sendable (Data) async throws -> ShelfScanReply)? = nil) async throws -> ShelfScanResult {
        var result = previous ?? ShelfScanResult()
        result.photoRelation = photoRelation
        if previous == nil {
            for (photo, image) in images.prefix(4).enumerated() {
                try Task.checkCancellation()
                let rows = await RafDilimleyici.satirlar(image)
                // Ana aktörün dışında ve iptale duyarlı: sayfadan çıkılınca sonuç yazılmadan CancellationError döner
                let slices = try await sliceOffMain(image, rows: rows)
                result.tiles.append(contentsOf: slices.map { slice in
                    ShelfTileReading(jpeg: slice.data, photo: photo, row: slice.satir,
                                     column: slice.sutun, overlapsAbove: slice.ustBindirmeli)
                })
                result.satirSayisi = max(result.satirSayisi, (slices.map(\.satir).max() ?? 0) + 1)
            }
        }
        guard !result.tiles.isEmpty else { throw GeminiError.decoding("Görüntü işlenemedi") }
        result.tileCount = result.tiles.count
        checkpoint?(result)
        let targets = result.tiles.indices.filter { result.tiles[$0].status != .read }
        var attempted = 0
        progress?(0, targets.count)
        for start in stride(from: 0, to: targets.count, by: 3) {
            try Task.checkCancellation()
            let indices = Array(targets[start..<min(start + 3, targets.count)])
            let inputs = indices.map { ($0, result.tiles[$0].jpeg) }
            let replies = await withTaskGroup(of: (Int, Result<ShelfScanReply, Error>).self) { group in
                for (index, jpeg) in inputs {
                    group.addTask {
                        do {
                            let response: ShelfScanReply
                            if let reader { response = try await reader(jpeg) }
                            else { response = try await readTile(jpeg) }
                            return (index, .success(response))
                        }
                        catch { return (index, .failure(error)) }
                    }
                }
                var collected: [(Int, Result<ShelfScanReply, Error>)] = []
                for await item in group { collected.append(item) }
                return collected.sorted { $0.0 < $1.0 }
            }
            for (index, reply) in replies {
                attempted += 1
                switch reply {
                case .success(let response):
                    result.tiles[index].books = response.books.map(GeminiBookRecognizer.normalized)
                        .filter { !($0.title ?? "").isEmpty }
                    result.tiles[index].shelfLabel = cleaned(response.shelfLabel)
                    result.tiles[index].cabinetLabel = cleaned(response.cabinetLabel)
                    result.tiles[index].errorMessage = nil
                    result.tiles[index].status = .read
                case .failure(let error):
                    result.tiles[index].errorMessage = (error as? GeminiError)?.errorDescription ?? error.localizedDescription
                    result.tiles[index].status = .failed
                }
            }
            rebuild(&result)
            checkpoint?(result)
            progress?(attempted, targets.count)
        }
        try Task.checkCancellation()
        rebuild(&result)
        return result
    }

    /// Ağır dilimleme ana aktör dışında koşar. İptal, hem başlamadan önce hem bittikten sonra denetlenir;
    /// iptal edilen çağrı yarım sonuç döndürmez.
    @concurrent
    nonisolated static func sliceOffMain(_ image: Data, rows: [ClosedRange<Double>]) async throws -> [RafDilimleyici.Dilim] {
        try Task.checkCancellation()
        let slices = RafDilimleyici.dilimle(image, satirlar: rows)
        try Task.checkCancellation()
        return slices
    }

    nonisolated static func rebuild(_ result: inout ShelfScanResult) {
        result.shelfLabels = []
        result.cabinetLabels = []
        let read = result.tiles.filter { $0.status == .read }
        for tile in read {
            if let label = tile.shelfLabel { appendLabel(label, to: &result.shelfLabels) }
            if let label = tile.cabinetLabel { appendLabel(label, to: &result.cabinetLabels) }
        }
        let perPhoto = Dictionary(grouping: read, by: \.photo)
        let photoBooks = perPhoto.keys.sorted().map { photo in
            merged(tiles: (perPhoto[photo] ?? []).map {
                DilimSonucu(books: $0.books, foto: $0.photo, satir: $0.row,
                            sutun: $0.column, ustBindirmeli: $0.overlapsAbove)
            })
        }
        result.books = combinePhotos(photoBooks, relation: result.photoRelation)
    }

    /// Önce her fotoğrafın nüshaları hesaplanır; örtüşen açılarda en yüksek sayı tutulur.
    /// Farklı raflar kullanıcı tarafından açıkça seçilmişse fotoğraf toplamları eklenir.
    nonisolated static func combinePhotos(_ photos: [[GeminiBookFields]], relation: ScanPhotoRelation) -> [GeminiBookFields] {
        var combined: [GeminiBookFields] = []
        for photo in photos {
            for book in photo {
                if let index = combined.firstIndex(where: { isSameBook($0, book) }) {
                    let copies = relation == .overlapping ? max(combined[index].nusha, book.nusha)
                        : min(GeminiBookFields.enFazlaNusha, combined[index].nusha + book.nusha)
                    if (book.confidence ?? 0) > (combined[index].confidence ?? 0) { combined[index] = book }
                    combined[index].copies = copies
                } else { combined.append(book) }
            }
        }
        return combined
    }

    /// Tek dilimi okur (hazır JPEG).
    private static func readTile(_ jpeg: Data) async throws -> ShelfScanReply {
        try await GeminiClient.shared.generateJSON(
            ShelfScanReply.self,
            prompt: "Bu fotoğraftaki tüm kitapları ayrı ayrı listele.",
            system: systemPrompt + CorrectionMemory.promptExamples(),
            images: [jpeg],
            temperature: 0.1,
            maxOutputTokens: 8192,
            timeout: 90
        )
    }

    nonisolated private static func cleaned(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Etiket listesine büyük/küçük harf ve boşluk farkını yok sayarak tekil ekler.
    nonisolated private static func appendLabel(_ label: String, to labels: inout [String]) {
        let key = CatalogMatcher.normalize(label)
        guard !labels.contains(where: { CatalogMatcher.normalize($0) == key }) else { return }
        labels.append(label)
    }

    /// Raf etiketindeki ilk sayı raf numarasıdır ("6 TÜRK EDEBİYATI" → "6").
    nonisolated static func shelfNumber(from label: String?) -> String? {
        guard let label else { return nil }
        let digits = label.split(whereSeparator: { !$0.isNumber }).first
        return digits.map(String.init)
    }

    /// Aynı kitap mı? Ad benzer (sayılar/cilt dahil aynı) ve yazar (ikisinde de varsa) benzer.
    /// "Sefiller 1. Cilt" ile "Sefiller 2. Cilt" ayrı kitaptır; cilt alanı ikisinde de doluysa eşit olmalı.
    nonisolated static func isSameBook(_ a: GeminiBookFields, _ b: GeminiBookFields) -> Bool {
        let isbnA = ISBNFormatter.normalize(a.isbn ?? ""), isbnB = ISBNFormatter.normalize(b.isbn ?? "")
        if !isbnA.isEmpty, !isbnB.isEmpty { return isbnA == isbnB }
        guard CatalogMatcher.isSimilarTitle(a.title ?? "", b.title ?? "") else { return false }
        let publisherA = a.publisher ?? "", publisherB = b.publisher ?? ""
        if !publisherA.isEmpty, !publisherB.isEmpty,
           !CatalogMatcher.isSimilar(publisherA, publisherB) { return false }
        let volumeA = (a.volume ?? "").trimmingCharacters(in: .whitespaces)
        let volumeB = (b.volume ?? "").trimmingCharacters(in: .whitespaces)
        if !volumeA.isEmpty, !volumeB.isEmpty, volumeA != volumeB { return false }
        let authorA = a.author ?? ""
        let authorB = b.author ?? ""
        return authorA.isEmpty || authorB.isEmpty || CatalogMatcher.isSimilar(authorA, authorB)
    }

    nonisolated static func signature(_ book: GeminiBookFields) -> String {
        let isbn = ISBNFormatter.normalize(book.isbn ?? "")
        if !isbn.isEmpty { return "isbn:" + isbn }
        return [book.title, book.author, book.publisher, book.volume]
            .map { CatalogMatcher.normalize($0 ?? "") }.joined(separator: "|")
    }

    /// Kısa yol: sırayla verilen dilimler aynı fotoğrafın aynı rafındaki komşu şeritler sayılır.
    nonisolated static func merged(tiles: [[GeminiBookFields]]) -> [GeminiBookFields] {
        merged(tiles: tiles.enumerated().map { DilimSonucu(books: $0.element, foto: 0, satir: 0, sutun: $0.offset) })
    }

    /// Dilim sonuçlarını nüsha sayısını koruyarak birleştirir.
    /// - Aynı dilimde aynı kitap birden çok kayıt çıktıysa nüshalar TOPLANIR (yan yana kopyalar).
    /// - Aynı fotoğrafta KOMŞU dilimlerde aynı kitap görülürse yalnız önceki dilimin kendi sayısını
    ///   AŞAN kısım eklenir: bindirmedeki aynı sırt iki kez sayılmaz, yeni nüsha kaybolmaz. Komşu:
    ///   aynı rafta yan yana şerit (kesitler %8 bindirir) ya da aynı şeritte, kesitleri gerçekten
    ///   piksel paylaşan alt/üst raf. Çapraz dilimler komşu DEĞİLDİR (yalnız köşe paylaşırlar).
    /// - Komşu olmayan dilimlerde ya da farklı fotoğrafta aynı kitap → gerçekten ayrı nüshalar: TOPLANIR.
    nonisolated static func merged(tiles: [DilimSonucu]) -> [GeminiBookFields] {
        var result: [GeminiBookFields] = []
        // result[i] en son hangi dilimden ve o dilimde kaç nüshayla güncellendi (komşuluk kararı için)
        var kaynak: [(foto: Int, satir: Int, sutun: Int, ustBindirmeli: Bool, adet: Int)] = []
        for tile in tiles {
            var inTile: [GeminiBookFields] = []
            for var book in tile.books {
                book.copies = book.nusha
                if let index = inTile.firstIndex(where: { isSameBook($0, book) }) {
                    let total = min(GeminiBookFields.enFazlaNusha, inTile[index].nusha + book.nusha)
                    if (book.confidence ?? 0) > (inTile[index].confidence ?? 0) { inTile[index] = book }
                    inTile[index].copies = total
                } else {
                    inTile.append(book)
                }
            }
            for book in inTile {
                let adet = book.nusha
                if let index = result.firstIndex(where: { isSameBook($0, book) }) {
                    let onceki = kaynak[index]
                    let yatayKomsu = onceki.satir == tile.satir && abs(onceki.sutun - tile.sutun) == 1
                    let dikeyKomsu = onceki.sutun == tile.sutun
                        && ((tile.satir == onceki.satir + 1 && tile.ustBindirmeli)
                            || (onceki.satir == tile.satir + 1 && onceki.ustBindirmeli))
                    let komsu = onceki.foto == tile.foto && (yatayKomsu || dikeyKomsu)
                    let toplam = min(GeminiBookFields.enFazlaNusha, result[index].nusha + (komsu ? max(0, adet - onceki.adet) : adet))
                    if (book.confidence ?? 0) > (result[index].confidence ?? 0) { result[index] = book }
                    result[index].copies = toplam
                    kaynak[index] = (tile.foto, tile.satir, tile.sutun, tile.ustBindirmeli, adet)
                } else {
                    result.append(book)
                    kaynak.append((tile.foto, tile.satir, tile.sutun, tile.ustBindirmeli, adet))
                }
            }
        }
        return result
    }

    /// Örtüşen fotoğraflarda (video kareleri, üst üste çekimler) aynı kitap bir kez kalır;
    /// daha emin olunan kayıt tutulur.
    static func deduplicated(_ books: [GeminiBookFields]) -> [GeminiBookFields] {
        var result: [GeminiBookFields] = []
        for book in books {
            if let index = result.firstIndex(where: { CatalogMatcher.isSimilar($0.title ?? "", book.title ?? "") }) {
                if (book.confidence ?? 0) > (result[index].confidence ?? 0) { result[index] = book }
            } else {
                result.append(book)
            }
        }
        return result
    }

    /// Raf sayımı: fotoğraftaki kitapları o rafa kayıtlı kitaplarla karşılaştırır.
    struct ShelfComparison {
        var found: [CatalogBook] = []
        var missing: [CatalogBook] = []
        /// Katalogda başka yere kayıtlı ama bu rafta görülen kitaplar (kayıtlı yeriyle).
        var misplaced: [(book: CatalogBook, registered: String)] = []
        /// Katalogda hiç olmayan kitaplar.
        var unknown: [GeminiBookFields] = []
        /// Ödünç, kayıp ve dolaşım dışı nüshalar rafta beklenen adetten ayrılır.
        var quantityDifferences: [(book: CatalogBook, seen: Int, expected: Int, loaned: Int)] = []
    }

    static func compare(_ seen: [GeminiBookFields], catalog: [CatalogBook], cabinet: String, shelf: String,
                        loans: [ActiveLoan] = [], copies: [BookCopy] = [], reservations: [Reservation] = []) -> ShelfComparison {
        func place(_ book: CatalogBook) -> String {
            [book.cabinet, book.shelf].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "/")
        }
        let wantedCabinet = CatalogMatcher.normalize(cabinet)
        let wantedShelf = CatalogMatcher.normalize(shelf)
        let live = catalog.filter { !$0.isDeleted && $0.modelContext != nil && !$0.isWithdrawn }
        let onThisShelf = live.filter {
            CatalogMatcher.normalize($0.cabinet ?? "") == wantedCabinet
                && (wantedShelf.isEmpty || CatalogMatcher.normalize($0.shelf ?? "") == wantedShelf)
        }

        var result = ShelfComparison()
        var matchedIDs = Set<UUID>()
        var observed: [UUID: Int] = [:]
        for fields in seen {
            let match = live.first {
                CatalogSaveEngine.sameEdition($0, VoiceBookEngine.book(from: SesliKitapKaydi(fields: fields)))
            }
            guard let match else {
                result.unknown.append(fields)
                continue
            }
            observed[match.id, default: 0] += fields.nusha
            guard matchedIDs.insert(match.id).inserted else { continue }
            if onThisShelf.contains(where: { $0.id == match.id }) {
                result.found.append(match)
            } else {
                result.misplaced.append((match, place(match).isEmpty ? "yer kaydı yok" : place(match)))
            }
        }
        result.missing = onThisShelf.filter { !matchedIDs.contains($0.id) }
        for book in onThisShelf {
            let stock = SchoolLibraryService.stock(for: book, loans: loans, copies: copies, reservations: reservations)
            let expected = stock.available + stock.reserved
            let count = observed[book.id, default: 0]
            if expected != count { result.quantityDifferences.append((book, count, expected, stock.loaned)) }
        }
        return result
    }
}

extension GeminiBookFields {
    /// Modelin saçma büyük değeri toplamda taşma yapmasın: 1–99 arasına kırpılmış nüsha.
    nonisolated static let enFazlaNusha = 99
    nonisolated var nusha: Int { min(max(1, copies ?? 1), Self.enFazlaNusha) }
}

extension SesliKitapKaydi {
    /// Görsel tarama sonucundan kayıt taslağı (raf taraması ve kaydedici için ortak yol).
    init(fields: GeminiBookFields, cabinet: String? = nil, shelf: String? = nil) {
        self.init()
        isBook = true
        title = fields.title
        author = fields.author
        publisher = fields.publisher
        isbn = fields.isbn
        publicationYear = fields.publicationYear
        edition = fields.edition
        volume = fields.volume
        pageCount = fields.pageCount
        category = fields.category
        language = fields.language
        summary = fields.summary
        // Raf taramasında yan yana duran nüshalar tek kayıtta sayılır
        quantity = fields.nusha
        self.cabinet = cabinet.flatMap { $0.isEmpty ? nil : $0 }
        self.shelf = shelf.flatMap { $0.isEmpty ? nil : $0 }
        uncertain = fields.uncertain
    }
}

// MARK: - Sesli / asistan ödünç ve iade

/// Asistanın çıkardığı ödünç/iade isteği ("Ali Veli'ye Kürk Mantolu Madonna'yı ver").
nonisolated struct LoanIntent: Codable, Sendable, Equatable {
    /// "lend" | "return"
    var kind: String
    var bookTitle: String?
    var person: String?
    var className: String?
}

enum LoanActionEngine {
    struct LoanError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func findBook(_ title: String, in books: [CatalogBook]) -> CatalogBook? {
        AssistantContext.matchTitles([title], in: books).first
            ?? books.first { !$0.isWithdrawn && CatalogMatcher.isSimilar($0.title, title) }
    }

    /// Kişinin sınıfı: verilmişse o, yoksa öğrenci listesinden.
    static func className(for person: String, given: String?) -> String {
        if let given, !given.isEmpty { return given }
        let wanted = CatalogMatcher.normalize(person)
        return StudentStore.all().first { CatalogMatcher.normalize($0.name) == wanted }?.className ?? ""
    }

    /// Ödünç verir (çok nüshalı `ActiveLoan` kaydıyla); boşta nüsha yoksa hata.
    @discardableResult
    static func lend(book: CatalogBook, person: String, className: String?, loans: [ActiveLoan],
                     context: ModelContext, defaultDays: Int = 15, studentID: UUID? = nil, copyID: UUID? = nil,
                     operationID: UUID? = nil, memberID: UUID? = nil, resolveKnownStudent: Bool = true) throws -> String {
        let studentClass = className ?? ""
        let loan: ActiveLoan
        do {
            // Otomatik vade merkezi serviste üye türü / kademe / genel süreyle hesaplanır.
            // Burada varsayılan günlerden vade üretmek özel üye kuralını geçersiz kılardı.
            loan = try SchoolLibraryService.lend(book: book, person: person, className: studentClass,
                context: context, studentID: studentID, copyID: copyID, operationID: operationID, memberID: memberID, resolveKnownStudent: resolveKnownStudent)
        } catch { throw LoanError(message: error.localizedDescription) }
        return "“\(book.title)” \(loan.studentName) adına ödünç verildi (son gün \(loan.dueDate.formatted(date: .abbreviated, time: .omitted)))."
    }

    /// İade alır: önce çok nüshalı kayıtlarda, sonra eski tekil `loanedTo` alanında arar.
    @discardableResult
    static func giveBack(book: CatalogBook, person: String?, loans: [ActiveLoan], context: ModelContext,
                         studentID: UUID? = nil, copyID: UUID? = nil, memberID: UUID? = nil, loanID: UUID? = nil) throws -> String {
        let wanted = CatalogMatcher.normalize(person ?? "")
        let candidates = loans.filter { $0.bookID == book.id }
        if !candidates.isEmpty {
            let matching = candidates.filter { loan in
                if let loanID, loan.id != loanID { return false }
                if let copyID, loan.copyID != copyID { return false }
                if let studentID { return loan.studentID == studentID }
                if let memberID { return loan.memberID == memberID }
                return wanted.isEmpty || CatalogMatcher.normalize(loan.studentName) == wanted
            }
            guard matching.count == 1, let loan = matching.first else {
                throw LoanError(message: matching.isEmpty
                    ? "Bu kişi veya nüsha adına ödünç kaydı bulunamadı."
                    : "Birden çok ödünç var; öğrenci veya nüsha seçin.")
            }
            let name = loan.studentName
            // Geçmiş, hatırlatma iptali ve rezervasyon bildirimi tek merkezden
            let notice = try SchoolLibraryService.giveBack(book: book, person: name, className: loan.studentClass,
                studentID: studentID ?? loan.studentID, copyID: copyID ?? loan.copyID, context: context, memberID: memberID ?? loan.memberID, loanID: loanID ?? loan.id)
            return "“\(book.title)” \(name) tarafından iade edildi." + (notice.map { " " + $0 } ?? "")
        }
        if let holder = book.loanedTo, !holder.isEmpty,
           studentID == nil, copyID == nil, memberID == nil, loanID == nil,
           wanted.isEmpty || CatalogMatcher.normalize(holder) == wanted {
            let dueDate = book.loanDueDate
            let wasLate = book.isOverdue
            book.loanedTo = nil
            book.loanDueDate = nil
            do { try context.save() }
            catch { book.loanedTo = holder; book.loanDueDate = dueDate; throw error }
            LoanHistoryStore.record(LoanEvent(bookID: book.id, bookTitle: book.title, person: holder,
                                              kind: .returned, date: .now, dueDate: dueDate, wasLate: wasLate))
            LoanReminders.cancel(bookID: book.id)
            let notice = OduncMerkezi.rezervasyonuBildir(bookID: book.id, title: book.title, context: context)
            return "“\(book.title)” \(holder) tarafından iade edildi." + (notice.map { " " + $0 } ?? "")
        }
        throw LoanError(message: "“\(book.title)” için \(person.map { "\($0) adına " } ?? "")ödünç kaydı bulunamadı.")
    }
}

extension PersonAliases {
    private struct Sozcuk {
        let range: Range<String.Index>
        let text: String
        let folded: String
    }

    /// Harf/rakam öbekleri. Kesme işareti ayırıcıdır: "Ayşe'ye" → "Ayşe", "ye".
    private static func sozcukler(_ text: String) -> [Sozcuk] {
        var result: [Sozcuk] = []
        var start: String.Index?
        var index = text.startIndex
        func close(at end: String.Index) {
            guard let s = start else { return }
            let piece = String(text[s..<end])
            result.append(Sozcuk(range: s..<end, text: piece, folded: CatalogMatcher.normalize(piece)))
            start = nil
        }
        while index < text.endIndex {
            let ch = text[index]
            if ch.isLetter || ch.isNumber { if start == nil { start = index } } else { close(at: index) }
            index = text.index(after: index)
        }
        close(at: text.endIndex)
        return result
    }

    /// Ad sonuna tek başına gelebilen Türkçe hâl ekleri (normalize edilmiş biçim); "Mehmetin kitabı" sızmasın.
    private static let adEkleri: Set<String> = [
        "in", "un", "nin", "nun", "e", "a", "ye", "ya", "i", "u", "yi", "yu",
        "de", "da", "te", "ta", "den", "dan", "ten", "tan", "le", "la", "yle", "yla"
    ]

    /// Kullanıcının sorusunda geçen öğrenci/üye adlarını Google'a göndermeden önce takma adla değiştirir.
    /// - Eşleşme Türkçe harf sınırlıdır: "Can" adı "Canlı" sözcüğünü bozmaz; "Ayşe'ye" ve "Mehmetin"
    ///   (5+ harfli adlarda hâl eki) yakalanır, ek korunur.
    /// - `authors`: katalogdaki yazar adları. Öğrenci adı bir yazar adının parçasıysa ("Orhan" / "Orhan Pamuk")
    ///   o yazar geçişi değiştirilmez.
    func pseudonymize(_ text: String, names: [String], protecting authors: [String] = []) -> String {
        let tokens = Self.sozcukler(text)
        guard !tokens.isEmpty else { return text }

        var seen = Set<[String]>()
        let entries: [(words: [String], name: String)] = names.compactMap { raw in
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.count >= 3 else { return nil }
            let words = Self.sozcukler(name).map(\.folded)
            guard !words.isEmpty, seen.insert(words).inserted else { return nil }
            return (words, name)
        }
        // Uzun adlar önce: "Ali Veli Kaya" içindeki "Ali Veli" yanlış değiştirilmesin
        .sorted { ($0.words.count, $0.words.joined().count) > ($1.words.count, $1.words.joined().count) }
        guard !entries.isEmpty else { return text }
        let authorSequences = Set(authors.map { Self.sozcukler($0).map(\.folded) }.filter { !$0.isEmpty })

        func boslukla(_ a: Sozcuk, _ b: Sozcuk) -> Bool {
            text[a.range.upperBound..<b.range.lowerBound].allSatisfy { $0 == " " || $0 == "\u{00A0}" }
        }

        /// Adın `i`. sözcükten başlayan eşleşmesi: kullanılan sözcük sayısı ve atılan hâl eki (yoksa "").
        func match(_ words: [String], at i: Int) -> (count: Int, suffix: String)? {
            guard i + words.count <= tokens.count else { return nil }
            var suffix = ""
            for k in 0..<words.count {
                let token = tokens[i + k]
                if k > 0, !boslukla(tokens[i + k - 1], token) { return nil }
                if token.folded == words[k] { continue }
                guard k == words.count - 1, words[k].count >= 5, token.folded.hasPrefix(words[k]),
                      Self.adEkleri.contains(String(token.folded.dropFirst(words[k].count))) else { return nil }
                suffix = String(token.text.dropFirst(words[k].count))
            }
            return (words.count, suffix)
        }

        /// Eşleşen aralık, metinde tam yazılmış bir yazar adının parçası mı?
        func yazarParcasi(_ words: [String], at i: Int) -> Bool {
            for sequence in authorSequences where sequence.count >= words.count {
                for offset in 0...(sequence.count - words.count) where Array(sequence[offset..<offset + words.count]) == words {
                    let first = i - offset
                    guard first >= 0, first + sequence.count <= tokens.count else { continue }
                    if (0..<sequence.count).allSatisfy({ tokens[first + $0].folded == sequence[$0] }) { return true }
                }
            }
            return false
        }

        var output = ""
        var cursor = text.startIndex
        var i = 0
        while i < tokens.count {
            var advanced = false
            for entry in entries {
                guard let found = match(entry.words, at: i) else { continue }
                if yazarParcasi(entry.words, at: i) { i += found.count; advanced = true; break }
                output += text[cursor..<tokens[i].range.lowerBound]
                output += alias(for: entry.name) + (found.suffix.isEmpty ? "" : "'" + found.suffix)
                cursor = tokens[i + found.count - 1].range.upperBound
                i += found.count
                advanced = true
                break
            }
            if !advanced { i += 1 }
        }
        output += text[cursor...]
        return output
    }

    /// "Ayşe'ye ver", "Ali Kaya iade etti" gibi ÖDÜNÇ fiilli cümlelerde geçen, kayıtlı olmayan kişi adlarını bulur.
    /// Serbest metinde her büyük harfli sözcüğü ad saymamak için yalnız bu kalıplar taranır; katalogdaki
    /// kitap adlarının parçası olan sözcükler atlanır. Dönüş, bu istek için geçici takma adla eşlenmelidir.
    static func kayitsizAdlar(in text: String, known: [String], bookTitles: [String] = []) -> [String] {
        let ad = #"(\p{Lu}\p{L}{2,}(?:[ \t]+\p{Lu}\p{L}{2,})?)"#
        let fiiller = #"(?:ver|verir|verelim|vereyim|veriyorum|verdim|ödünç|iade|teslim)(?![\p{L}])"#
        let kaliplar = [
            ad + #"['’](?:y?[ea])(?![\p{L}])[^.?!\n]{0,80}?(?<![\p{L}])"# + fiiller,
            ad + #"[ \t]+(?:kitabı[ \t]+|kitabını[ \t]+)?(?:iade etti|geri getirdi|getirdi|geri verdi|ödünç aldı)"#
        ]
        let knownTokens = Set(known.flatMap { sozcukler($0).map(\.folded) })
        let titles = bookTitles.map { " " + CatalogMatcher.normalize($0) + " " }
        var result: [String] = []
        var seen = Set<String>()
        for pattern in kaliplar {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let whole = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: whole) {
                guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { continue }
                let candidate = String(text[range]).trimmingCharacters(in: .whitespaces)
                let folded = CatalogMatcher.normalize(candidate)
                guard candidate.count >= 3, !folded.isEmpty, seen.insert(folded).inserted else { continue }
                // Kayıtlı bir kişinin adı zaten ayrıca değiştirilir
                if sozcukler(candidate).allSatisfy({ knownTokens.contains($0.folded) }) { continue }
                let probe = " " + folded + " "
                if titles.contains(where: { $0.contains(probe) }) { continue }
                result.append(candidate)
            }
        }
        return result
    }
}

// MARK: - Kayıt sonrası zenginleştirme ve çevrimdışı kuyruk

/// Yeni eklenen kitaplar bu kuyruğa girer; arka planda (ve internet gelince) kapaktan Gemini
/// OCR ile boş alanlar doldurulur, kategori/dil/özet tamamlanır. Kullanıcı hiç beklemez.
/// Yalnızca BOŞ alanlar doldurulur; elle girilen bilgi asla değişmez.
enum EnrichmentQueue {
    static let enabledKey = "autoEnrichAfterSave"
    private static let storeKey = "enrichmentQueueIDs"
    nonisolated struct RunningScope: Equatable {
        let container: ObjectIdentifier
        let generation: UUID?
    }
    nonisolated struct RunningOperation {
        let id: UUID
        let scope: RunningScope
    }
    private static var runningOperation: RunningOperation?

    static var isEnabled: Bool {
        GeminiSettings.isActive && (UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true)
    }

    static var pendingIDs: [UUID] {
        (UserDefaults.standard.stringArray(forKey: storeKey) ?? []).compactMap(UUID.init(uuidString:))
    }

    static func enqueue(_ id: UUID) {
        var ids = UserDefaults.standard.stringArray(forKey: storeKey) ?? []
        guard !ids.contains(id.uuidString) else { return }
        ids.append(id.uuidString)
        UserDefaults.standard.set(Array(ids.suffix(2000)), forKey: storeKey)
    }

    private static func remove(_ done: Set<UUID>) {
        let ids = (UserDefaults.standard.stringArray(forKey: storeKey) ?? [])
            .filter { UUID(uuidString: $0).map { !done.contains($0) } ?? false }
        UserDefaults.standard.set(ids, forKey: storeKey)
    }

    static func needsWork(_ book: CatalogBook) -> Bool {
        (book.category ?? "").isEmpty || (book.language ?? "").isEmpty || book.notes.isEmpty
            || (book.publisher ?? "").isEmpty
    }

    /// Inject only external work/queue storage for deterministic tests. This does
    /// not replace role authorization; production uses the live provider below.
    struct ProcessProvider {
        var pending: @MainActor () -> [UUID]
        var removeCompleted: @MainActor (Set<UUID>) -> Void
        var recognizeCover: @MainActor (Data) async throws -> GeminiBookFields
        var completeText: @MainActor ([CatalogBook]) async throws -> [AICompletionItem]
    }

    private static func canContinue(_ check: (@MainActor () throws -> Void)?) -> Bool {
        do { try Task.checkCancellation(); try check?(); return true }
        catch { return false }
    }

    /// The UI passes a captured catalog lease. Isolated callers may omit it;
    /// cancellation always stops both DB writes and queue cleanup.
    static func process(context: ModelContext, requireCurrent: (@MainActor () throws -> Void)? = nil,
                        provider: ProcessProvider? = nil) async {
        guard canContinue(requireCurrent), (provider != nil || isEnabled), YetkiDurumu.shared.yonetici else { return }
        let scope = RunningScope(container: ObjectIdentifier(context.container),
            generation: requireCurrent == nil ? nil : ActiveCatalogGeneration.current)
        guard runningOperation?.scope != scope else { return }
        let source = provider ?? ProcessProvider(pending: { pendingIDs }, removeCompleted: { remove($0) },
            recognizeCover: { try await GeminiBookRecognizer.recognize(images: [$0], timeout: 30, maxAttempts: 1) },
            completeText: { try await AICompletionEngine.complete($0) })
        let operationID = UUID()
        runningOperation = RunningOperation(id: operationID, scope: scope)
        defer { if runningOperation?.id == operationID { runningOperation = nil } }
        let ownedCheck: @MainActor () throws -> Void = {
            guard runningOperation?.id == operationID else { throw ActiveCatalogLease.Expired() }
            try requireCurrent?()
        }
        let ids = source.pending()
        guard !ids.isEmpty else { return }
        // Arka planda sessizce yazılan alanlar günlüğe girer; Ayarlar › Yapay Zekâ'dan geri alınabilir
        let journal = AIDegisiklikToplayici(tool: "zenginlestirme")
        defer { journal.commit() }
        var done = Set<UUID>()
        var textBatch: [CatalogBook] = []
        for id in ids {
            guard canContinue(ownedCheck) else { return }
            guard YetkiDurumu.shared.yonetici else { break }
            guard let book = try? context.fetch(FetchDescriptor<CatalogBook>(predicate: #Predicate { $0.id == id })).first,
                  !book.isDeleted else { done.insert(id); continue }
            guard needsWork(book) else { done.insert(id); continue }
            if let cover = book.coverData, (book.publisher ?? "").isEmpty || (book.category ?? "").isEmpty {
                do {
                    let fields = try await source.recognizeCover(cover)
                    guard canContinue(ownedCheck) else { return }
                    guard YetkiDurumu.shared.yonetici else { break }
                    guard !book.isDeleted, book.modelContext === context else { done.insert(id); continue }
                    let previous = book.book
                    fillEmpty(book, from: fields, journal: journal)
                    do { try context.save() }
                    catch { journal.discard(); book.update(from: previous); throw error }
                    journal.commit()
                } catch {
                    guard canContinue(ownedCheck) else { return }
                    if case GeminiError.network = error { break }
                }
            }
            guard canContinue(ownedCheck) else { return }
            if needsWork(book) { textBatch.append(book) } else { done.insert(id) }
            if textBatch.count == 8 {
                let completed = await complete(textBatch, context: context, requireCurrent: ownedCheck, provider: source, journal: journal)
                guard canContinue(ownedCheck) else { return }
                if completed { textBatch.forEach { done.insert($0.id) } } else { break }
                textBatch = []
            }
        }
        if !textBatch.isEmpty {
            let completed = await complete(textBatch, context: context, requireCurrent: ownedCheck, provider: source, journal: journal)
            guard canContinue(ownedCheck) else { return }
            if completed { textBatch.forEach { done.insert($0.id) } }
        }
        guard canContinue(ownedCheck) else { return }
        source.removeCompleted(done)
    }

    private static func complete(_ books: [CatalogBook], context: ModelContext,
                                 requireCurrent: (@MainActor () throws -> Void)?, provider: ProcessProvider,
                                 journal: AIDegisiklikToplayici? = nil) async -> Bool {
        do {
            guard canContinue(requireCurrent), YetkiDurumu.shared.yonetici else { return false }
            let items = try await provider.completeText(books)
            guard canContinue(requireCurrent), YetkiDurumu.shared.yonetici else { return false }
            let snapshots = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0.book) })
            do {
                for item in items where books.indices.contains(item.index) {
                    let book = books[item.index]
                    guard !book.isDeleted, book.modelContext === context else { continue }
                    _ = AICompletionEngine.apply(item, to: book, journal: journal)
                }
                try context.save()
                journal?.commit()
                return true
            } catch {
                journal?.discard()
                for book in books where !book.isDeleted {
                    if let snapshot = snapshots[book.id] { book.update(from: snapshot) }
                }
                return false
            }
        } catch { return false }
    }

    static func fillEmpty(_ book: CatalogBook, from fields: GeminiBookFields, journal: AIDegisiklikToplayici? = nil) {
        guard YetkiDurumu.shared.yonetici, fields.isBook != false else { return }
        let previous = book.book
        if !BookFieldMetadata.isLocked("title", on: book), book.title.isEmpty, let v = fields.title { book.title = v }
        if !BookFieldMetadata.isLocked("author", on: book), book.author.isEmpty, let v = fields.author { book.author = v }
        if !BookFieldMetadata.isLocked("publisher", on: book), (book.publisher ?? "").isEmpty, let v = fields.publisher { book.publisher = v }
        if !BookFieldMetadata.isLocked("publicationYear", on: book), (book.publicationYear ?? "").isEmpty, let v = fields.publicationYear { book.publicationYear = v }
        if !BookFieldMetadata.isLocked("pageCount", on: book), (book.pageCount ?? "").isEmpty, let v = fields.pageCount { book.pageCount = v }
        if !BookFieldMetadata.isLocked("language", on: book), (book.language ?? "").isEmpty, let v = fields.language { book.language = v }
        if !BookFieldMetadata.isLocked("category", on: book), (book.category ?? "").isEmpty, let v = fields.category { book.category = v }
        if !BookFieldMetadata.isLocked("location", on: book), (book.location ?? "").isEmpty, let v = fields.dewey { book.location = v }
        if !BookFieldMetadata.isLocked("notes", on: book), book.notes.isEmpty, let v = fields.summary { book.notes = v }
        if !BookFieldMetadata.isLocked("isbn", on: book), (book.isbn ?? "").isEmpty, let v = fields.isbn { book.isbn = v }
        book.fieldMetadata = BookFieldMetadata.stampChanges(before: previous, after: book.book, source: "gemini").fieldMetadata
        book.refreshSearchKey()
        journal?.note(book, before: previous)
    }
}

// MARK: - Canlı dikte ön ayrıştırıcı (ağsız) ve sesle düzeltme

extension VoiceBookEngine {
    private static let numberWords: [String: Int] = [
        "bir": 1, "iki": 2, "üç": 3, "dört": 4, "beş": 5, "altı": 6, "yedi": 7, "sekiz": 8, "dokuz": 9, "on": 10,
        "birinci": 1, "ikinci": 2, "üçüncü": 3, "dördüncü": 4, "beşinci": 5, "altıncı": 6, "yedinci": 7,
        "sekizinci": 8, "dokuzuncu": 9, "onuncu": 10
    ]

    private static func number(_ token: String) -> Int? {
        Int(token) ?? numberWords[token.lowercased(with: Locale(identifier: "tr_TR"))]
    }

    /// Konuşulurken kelimeler geldikçe alanları anlık gösterir (Gemini son sözü söyler):
    /// "ad, yazar, yayınevi, iki adet, B dolabı, üçüncü raf".
    static func quickParse(_ text: String) -> SesliKitapKaydi {
        var kaydi = SesliKitapKaydi()
        let turkish = Locale(identifier: "tr_TR")
        var remaining: [String] = []
        for rawPart in text.split(separator: ",") {
            let part = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !part.isEmpty else { continue }
            let words = part.split(separator: " ").map(String.init)
            let lower = words.map { $0.lowercased(with: turkish) }

            if let unit = lower.firstIndex(where: { ["adet", "tane", "nüsha"].contains($0) }), unit > 0,
               let value = number(lower[unit - 1]) {
                kaydi.quantity = value
                continue
            }
            if let index = lower.firstIndex(where: { $0.hasPrefix("dolab") || $0 == "dolap" }), index > 0 {
                kaydi.cabinet = words[index - 1].uppercased(with: turkish)
                continue
            }
            if let index = lower.firstIndex(of: "raf") {
                if index > 0, let value = number(lower[index - 1]) { kaydi.shelf = String(value); continue }
                if index + 1 < lower.count { kaydi.shelf = number(lower[index + 1]).map(String.init) ?? words[index + 1]; continue }
            }
            remaining.append(part)
        }
        if remaining.count > 0 { kaydi.title = remaining[0] }
        if remaining.count > 1 { kaydi.author = remaining[1] }
        if remaining.count > 2 { kaydi.publisher = remaining[2] }
        return kaydi
    }

    /// Kısa bir cümle önizlemedeki kaydı düzeltme isteği mi? ("yazarı Orhan Pamuk yap", "adet üç")
    static func looksLikeEdit(_ text: String) -> Bool {
        let words = CatalogMatcher.normalize(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !words.isEmpty, words.count <= 12 else { return false }
        let editWords = ["yap", "olsun", "degistir", "duzelt", "adet", "raf", "rafi", "dolap", "dolabi",
                         "yazari", "yazar", "adi", "yayinevi", "yili", "kategori", "kategorisi", "isbn", "sil", "ekle"]
        return words.contains { editWords.contains($0) }
    }

    /// Önizlemedeki kayda sesle düzeltme uygular. Talimat yeni bir kitapsa `command == "new"` döner.
    static func applyEdit(_ current: SesliKitapKaydi, instruction: String) async throws -> SesliKitapKaydi {
        let currentJSON = String(decoding: (try? JSONEncoder().encode(current)) ?? Data(), as: UTF8.self)
        let prompt = """
        MEVCUT KAYIT: \(currentJSON)
        KULLANICININ SÖZLÜ DÜZELTMESİ: \(instruction)
        Düzeltmeyi uygulayıp kaydın TAMAMINI aynı şemada döndür (değişmeyen alanlar aynen kalsın). \
        Söylenen şey düzeltme değil YENİ bir kitap tanımıysa yalnızca {"command": "new"} döndür.
        """
        var updated = try await GeminiClient.shared.generateJSON(
            SesliKitapKaydi.self, prompt: prompt, system: systemPrompt,
            temperature: 0.1, maxOutputTokens: 1024, timeout: 25
        )
        if updated.command?.lowercased() == "new" { return updated }
        updated = normalized(updated)
        if !updated.hasBookContent { updated.title = current.title }
        return updated
    }
}

// MARK: - Haftalık rapor

/// Son 7 günün özeti: ödünç/iade, en çok ödünç verilenler, gecikmeler, eksik alanlar.
/// Öğrenci adları rapora ve Gemini'ye girmez; yalnızca sayılar ve kitap adları.
struct WeeklyReportData {
    var from: Date
    var to: Date
    var lentCount = 0
    var returnedCount = 0
    var lateReturns = 0
    var overdueNow = 0
    var newBooks = 0
    var totalBooks = 0
    var neverLoaned = 0
    var topBooks: [(title: String, count: Int)] = []
    var missingCategory = 0
    var missingCover = 0
    var missingISBN = 0

    static func build(books: [CatalogBook], loans: [ActiveLoan], events: [LoanEvent], now: Date = .now) -> WeeklyReportData {
        let from = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        var data = WeeklyReportData(from: from, to: now)
        let active = books.filter { !$0.isWithdrawn }
        let recent = events.filter { $0.date >= from && $0.date <= now }
        data.lentCount = recent.filter { $0.kind == .lent }.count
        data.returnedCount = recent.filter { $0.kind == .returned }.count
        data.lateReturns = recent.filter { $0.kind == .returned && $0.wasLate }.count
        data.overdueNow = loans.filter(\.isOverdue).count + active.filter(\.isOverdue).count
        data.newBooks = active.filter { $0.addedAt >= from }.count
        data.totalBooks = active.count
        let everLent = Set(events.filter { $0.kind == .lent }.map(\.bookID)).union(loans.map(\.bookID))
        data.neverLoaned = active.filter { !everLent.contains($0.id) }.count
        var counts: [String: Int] = [:]
        for event in recent where event.kind == .lent { counts[event.bookTitle, default: 0] += 1 }
        data.topBooks = counts.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
        data.missingCategory = active.filter { ($0.category ?? "").isEmpty }.count
        data.missingCover = active.filter { $0.coverData == nil }.count
        data.missingISBN = active.filter { ($0.isbn ?? "").isEmpty }.count
        return data
    }

    /// Gemini'ye giden özet (ad yok, yalnızca sayılar ve kitap adları).
    var promptSummary: String {
        """
        Dönem: \(from.formatted(date: .abbreviated, time: .omitted)) – \(to.formatted(date: .abbreviated, time: .omitted))
        Ödünç verilen: \(lentCount), iade alınan: \(returnedCount) (gecikmeli: \(lateReturns)), şu an gecikmiş: \(overdueNow)
        Yeni eklenen kitap: \(newBooks), toplam: \(totalBooks), hiç ödünç verilmemiş: \(neverLoaned)
        En çok ödünç verilenler: \(topBooks.map { "\($0.title) (\($0.count))" }.joined(separator: ", "))
        Eksik: kategori \(missingCategory), kapak \(missingCover), ISBN \(missingISBN)
        """
    }

    var pdfSections: [PDFReportBuilder.Section] {
        [
            .init(title: "Ödünç Hareketleri", rows: [
                ("Ödünç verilen", "\(lentCount)"), ("İade alınan", "\(returnedCount)"),
                ("Gecikmeli iade", "\(lateReturns)"), ("Şu an gecikmiş", "\(overdueNow)")
            ]),
            .init(title: "Koleksiyon", rows: [
                ("Toplam kitap", "\(totalBooks)"), ("Bu hafta eklenen", "\(newBooks)"),
                ("Hiç ödünç verilmemiş", "\(neverLoaned)")
            ]),
            .init(title: "En Çok Ödünç Verilenler", rows: topBooks.isEmpty ? [("—", "")] : topBooks.map { ($0.title, "\($0.count)") }),
            .init(title: "Eksik Alanlar", rows: [
                ("Kategorisiz", "\(missingCategory)"), ("Kapaksız", "\(missingCover)"), ("ISBN'siz", "\(missingISBN)")
            ])
        ]
    }
}

/// PDF'i paylaşılabilir geçici dosyaya yazar.
enum SharedPDF {
    static func write(_ data: Data, name: String) -> URL? {
        let safe = name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
