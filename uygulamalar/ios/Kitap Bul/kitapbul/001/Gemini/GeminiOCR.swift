import Foundation

/// Gemini'nin kapak/künye fotoğrafından çıkardığı yapılandırılmış kitap bilgisi.
nonisolated struct GeminiBookFields: Codable, Sendable, Equatable {
    var title: String?
    var author: String?
    var publisher: String?
    var isbn: String?
    var publicationYear: String?
    var edition: String?
    var pageCount: String?
    var language: String?
    var category: String?
    var summary: String?
    /// Görüntüde net okunamayan alan adları (title, author, isbn …).
    var uncertain: [String]?
    /// Görüntü bir kitap kapağı/künyesi mi? (Değilse alanlar boş bırakılır.)
    var isBook: Bool?
    // Künyeden ek bibliyografya (MEB kütüphane defteri için)
    var translator: String?
    var illustrator: String?
    var printPlace: String?
    /// Dewey onlu sınıflama numarası (ör. "813.4") — yer numarası/sırt etiketi için.
    var dewey: String?
    /// Fotoğraf kalitesi: "good" | "blurry" | "dark" | "partial" | "glare"
    var imageQuality: String?
    /// Çoklu kitap taramasında bu kaydın modeli ne kadar emin (0–1).
    var confidence: Double?
    /// Raf taramasında yan yana duran aynı kitabın nüsha sayısı (tek nüsha 1).
    var copies: Int?
    /// Raf dilimindeki sınır kutusu [ymin,xmin,ymax,xmax], 0–1000 ölçeği.
    var box_2d: [Double]?
    // Arka kapak/kapaktan: seri, cilt, konu etiketleri, okuma düzeyi, içerik uyarısı
    var series: String?
    var volume: String?
    var tags: [String]?
    var readingLevel: String?
    var contentWarning: String?

    init(
        title: String? = nil, author: String? = nil, publisher: String? = nil, isbn: String? = nil,
        publicationYear: String? = nil, edition: String? = nil, pageCount: String? = nil,
        language: String? = nil, category: String? = nil, summary: String? = nil,
        uncertain: [String]? = nil, isBook: Bool? = nil
    ) {
        self.title = title
        self.author = author
        self.publisher = publisher
        self.isbn = isbn
        self.publicationYear = publicationYear
        self.edition = edition
        self.pageCount = pageCount
        self.language = language
        self.category = category
        self.summary = summary
        self.uncertain = uncertain
        self.isBook = isBook
    }

    /// Esnek çözümleme: Gemini sayfa sayısını sayı (320), nüshayı metin ("2"), ISBN'i sayı
    /// döndürebilir. Tek alanın türü yüzünden bütün yanıt (ve taranan kitap) düşmesin diye her
    /// alan sayı/metin farkına bakılmadan okunur; eksik ya da bozuk alan nil olur.
    /// Kodlama (encode) sentezlenmiş kalır; anahtarlar aynıdır.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = GevsekDeger.metin(c, .title)
        author = GevsekDeger.metin(c, .author)
        publisher = GevsekDeger.metin(c, .publisher)
        isbn = GevsekDeger.metin(c, .isbn)
        publicationYear = GevsekDeger.metin(c, .publicationYear)
        edition = GevsekDeger.metin(c, .edition)
        pageCount = GevsekDeger.metin(c, .pageCount)
        language = GevsekDeger.metin(c, .language)
        category = GevsekDeger.metin(c, .category)
        summary = GevsekDeger.metin(c, .summary)
        uncertain = GevsekDeger.metinListe(c, .uncertain)
        isBook = GevsekDeger.mantik(c, .isBook)
        translator = GevsekDeger.metin(c, .translator)
        illustrator = GevsekDeger.metin(c, .illustrator)
        printPlace = GevsekDeger.metin(c, .printPlace)
        dewey = GevsekDeger.metin(c, .dewey)
        imageQuality = GevsekDeger.metin(c, .imageQuality)
        confidence = GevsekDeger.ondalik(c, .confidence)
        copies = GevsekDeger.tamsayi(c, .copies)
        box_2d = GevsekDeger.ondalikListe(c, .box_2d)
        series = GevsekDeger.metin(c, .series)
        volume = GevsekDeger.metin(c, .volume)
        tags = GevsekDeger.metinListe(c, .tags)
        readingLevel = GevsekDeger.metin(c, .readingLevel)
        contentWarning = GevsekDeger.metin(c, .contentWarning)
    }
}

/// Katalogda kullanılan sabit kategori listesi; Gemini'den bu listeden seçmesi istenir
/// ki filtreler ve raporlar tutarlı kalsın.
nonisolated enum KitapKategorileri {
    static let liste = [
        "Roman", "Hikâye", "Şiir", "Masal", "Çocuk", "Gençlik", "Macera", "Bilim Kurgu",
        "Fantastik", "Polisiye", "Tarih", "Biyografi", "Bilim", "Matematik", "Doğa",
        "Sanat", "Din", "Felsefe", "Psikoloji", "Kişisel Gelişim", "Ders Kitabı",
        "Yardımcı Kaynak", "Sözlük", "Ansiklopedi", "Deneme", "Tiyatro", "Mizah", "Diğer"
    ]

    /// Listede olmayan kategoriyi en uzun eşleşen liste ögesine indirir ("bilim kurgu
    /// romanı" → "Bilim Kurgu", "Roman" değil); bulunamazsa "Diğer". Karşılaştırma
    /// Türkçe harf katlamasıyla ("TARİH", "Hikaye") ve sözcük başından yapılır
    /// ("Uzay Bilimleri" → "Bilim"; ama "Kadın" içindeki "din" eşleşmez).
    static func enYakin(_ category: String) -> String {
        if liste.contains(category) { return category }
        let aranan = sozcukler(category)
        return liste
            .filter { oge in
                let ogeSozcukleri = sozcukler(oge)
                guard !ogeSozcukleri.isEmpty, aranan.count >= ogeSozcukleri.count else { return false }
                return (0...(aranan.count - ogeSozcukleri.count)).contains { start in
                    zip(aranan[start...], ogeSozcukleri).allSatisfy { $0.hasPrefix($1) }
                }
            }
            .max { $0.count < $1.count } ?? "Diğer"
    }

    private static func sozcukler(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }
}

/// Kapak / künye fotoğraflarını Gemini ile okur ve Vision OCR taslağını zenginleştirir.
///
/// Vision motoru satır satır metin verir; kitap adı ile yazarı ayırmak, künyedeki
/// "1. Baskı: 2021" gibi kalıpları çözmek kural tabanlıdır ve el yazısı/süslü
/// yazı tiplerinde kolay şaşar. Gemini görüntüyü bütün olarak anlar; bu yüzden
/// Gemini'nin doldurduğu alanlar Vision tahminine baskın gelir. ISBN ise doğrulanır:
/// barkoddan okunan geçerli bir ISBN varsa o korunur.
enum GeminiBookRecognizer {
    static var systemPrompt: String {
        basePrompt + CorrectionMemory.promptExamples()
    }

    static let basePrompt = """
    Sen bir okul kütüphanesi kataloglama asistanısın. Sana bir kitabın kapak, arka kapak \
    ya da künye (iç kapak) fotoğrafları verilecek. Görüntülerden kitap bilgilerini çıkar ve \
    YALNIZCA JSON döndür. Şema:
    {"isBook": true, "title": "", "author": "", "publisher": "", "isbn": "", \
    "publicationYear": "", "edition": "", "pageCount": "", "language": "", "category": "", \
    "summary": "", "translator": "", "illustrator": "", "printPlace": "", "dewey": "", \
    "imageQuality": "good", "series": "", "volume": "", "tags": [], "readingLevel": "",     "contentWarning": "", "uncertain": []}
    Kurallar:
    - series/volume: kitap bir serinin parçasıysa seri adı ve cilt numarası (yalnız sayı); değilse boş.
    - tags: arka kapak metnine göre en fazla 4 kısa Türkçe konu etiketi (ör. "dostluk", "uzay", "doğa"); küçük harf.
    - readingLevel: şu listeden biri ya da boş: \(OkumaDuzeyi.liste.joined(separator: ", ")). Yaş/sınıf ibaresi \
    ya da dil düzeyine göre seç.
    - contentWarning: yalnızca okul kütüphanesinde dikkat gerektiren içerik varsa (şiddet, korku, yetişkin \
    teması) tek kısa cümle; yoksa boş.
    - translator/illustrator/printPlace künyede yazıyorsa doldur (yoksa boş). dewey: kitabın konusuna göre \
    Dewey onlu sınıflama numarası (ör. roman 813.3 ya da Türk edebiyatı için 894.35; emin değilsen boş).
    - imageQuality: fotoğraf bulanıksa "blurry", karanlıksa "dark", kitap kesikse "partial", parlama varsa "glare", iyiyse "good".
    - Kitap adı: kapaktaki asıl ad; alt başlığı iki nokta ile ekle. Seri adını ada katma.
    - Yazar: yalnızca yazar adı; "Çeviren", "Resimleyen", "Editör" gibi kişileri yazma.
    - isbn: yalnızca rakamlar (13 hane, 978/979 ile başlar). Yoksa boş bırak. Tahmin etme.
    - publicationYear: 4 haneli yıl. edition: "3" gibi yalnız sayı. pageCount: yalnız sayı.
    - language: "Türkçe", "İngilizce" gibi. category: şu listeden bir tanesi: \(KitapKategorileri.liste.joined(separator: ", ")).
    - summary: Türkçe, en fazla 2 cümle; arka kapak metninden özetle; yoksa boş bırak.
    - Emin olmadığın alanların adlarını "uncertain" listesine yaz (title, author, isbn, publisher, publicationYear, pageCount).
    - Görüntü kitapla ilgili değilse {"isBook": false} döndür.
    - Türkçe karakterleri (ş, ğ, ı, İ, ö, ü, ç) doğru yaz. Tümü büyük harfli adları Başlık Biçimine çevir.
    """

    /// Görüntülerden kitap alanlarını çıkarır (görüntüler küçültülüp JPEG olarak gider).
    /// - Parameters:
    ///   - timeout: İstek üst süresi; tarama akışında kullanıcı bekletilmez (kısa).
    ///   - maxAttempts: Ağ/sunucu hatasında deneme sayısı.
    ///   - extraText: PDF'in gömülü metni gibi ek kaynak; görüntülerle birlikte değerlendirilir.
    static func recognize(
        images: [Data], extraText: String? = nil, model: GeminiModel? = nil,
        timeout: TimeInterval = 60, maxAttempts: Int = 2
    ) async throws -> GeminiBookFields {
        let sources = Array(images.prefix(4))
        // 12 MP fotoğrafları küçültmek yüzlerce ms sürer; ana iş parçacığında yapılmaz
        let prepared = await Task.detached(priority: .userInitiated) {
            sources.compactMap { GeminiImagePreparer.jpegData(from: $0) }
        }.value
        let text = extraText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !prepared.isEmpty || !text.isEmpty else { throw GeminiError.decoding("Görüntü işlenemedi") }
        var prompt = prepared.count <= 1
            ? "Bu kitap fotoğrafından bilgileri çıkar."
            : "Bu \(prepared.count) fotoğraf AYNI kitaba ait (kapak, arka kapak, künye). Hepsini birlikte değerlendirip tek kayıt çıkar."
        if !text.isEmpty {
            prompt += "\n\nKİTABIN İÇİNDEN OKUNAN METİN (kapak/künye sayfaları):\n\(text.prefix(6000))"
        }
        // Okul ağı Google'ı engelliyorsa tek kısa deneme: kullanıcı cihaz OCR'ına hızla düşsün
        let blocked = GeminiReachability.shared.durum == .engelliYavas
        var fields = try await GeminiClient.shared.generateJSON(
            GeminiBookFields.self,
            prompt: prompt,
            system: systemPrompt,
            images: prepared,
            model: model,
            temperature: 0.1,
            timeout: blocked ? min(timeout, GeminiReachability.blockedOCRTimeout) : timeout,
            maxAttempts: blocked ? 1 : maxAttempts,
            thinking: .off
        )
        fields = normalized(fields)
        return fields
    }

    /// Alanları temizler: boşluk, geçersiz ISBN, sayı olmayan sayfa/yıl.
    static func normalized(_ fields: GeminiBookFields) -> GeminiBookFields {
        var result = fields
        func clean(_ value: String?) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        result.title = clean(fields.title)
        result.author = clean(fields.author)
        result.publisher = clean(fields.publisher)
        result.language = clean(fields.language)
        result.category = clean(fields.category)
        result.summary = clean(fields.summary)
        result.translator = clean(fields.translator)
        result.illustrator = clean(fields.illustrator)
        result.printPlace = clean(fields.printPlace)
        result.imageQuality = clean(fields.imageQuality)?.lowercased()
        result.series = clean(fields.series)
        result.volume = clean(fields.volume).map { $0.filter(\.isNumber) }.flatMap { $0.isEmpty || $0.count > 3 ? nil : $0 }
        let tags = (fields.tags ?? []).compactMap(clean).map { $0.lowercased(with: Locale(identifier: "tr_TR")) }
        result.tags = tags.isEmpty ? nil : Array(tags.prefix(4))
        result.readingLevel = clean(fields.readingLevel).flatMap { OkumaDuzeyi.liste.contains($0) ? $0 : nil }
        result.contentWarning = clean(fields.contentWarning)
        if let dewey = clean(fields.dewey) {
            let allowed = dewey.filter { $0.isNumber || $0 == "." }
            result.dewey = allowed.count >= 3 ? allowed : nil
        } else {
            result.dewey = nil
        }
        result.edition = clean(fields.edition).map { $0.filter(\.isNumber) }.flatMap { $0.isEmpty ? nil : $0 }
        result.pageCount = clean(fields.pageCount).map { $0.filter(\.isNumber) }.flatMap { $0.isEmpty ? nil : $0 }
        if let year = clean(fields.publicationYear) {
            let digits = year.filter(\.isNumber)
            result.publicationYear = digits.count == 4 ? digits : nil
        } else {
            result.publicationYear = nil
        }
        if let isbn = clean(fields.isbn) {
            let normalizedISBN = ISBNFormatter.normalize(isbn)
            result.isbn = normalizedISBN.isEmpty ? nil : normalizedISBN
        } else {
            result.isbn = nil
        }
        if let category = result.category {
            result.category = KitapKategorileri.enYakin(category)
        }
        return result
    }

    /// Gemini alanlarını Vision taslağına işler. Boş olmayan Gemini alanı kazanır;
    /// geçerli barkod ISBN'i korunur; Gemini'nin doldurduğu alanlar "düşük güven" listesinden çıkar.
    static func merge(_ fields: GeminiBookFields, into draft: inout BookDraft) {
        guard fields.isBook != false else { return }
        let previous = draft.snapshot
        draft.recognizedByGemini = true
        let uncertain = Set(fields.uncertain ?? [])

        func apply(_ value: String?, to keyPath: WritableKeyPath<BookDraft, String>, field: String) {
            guard !BookFieldMetadata.isLocked(field, metadata: draft.fieldMetadata) else { return }
            guard let value, !value.isEmpty else { return }
            draft[keyPath: keyPath] = value
            if uncertain.contains(field) {
                draft.lowConfidenceFields.insert(field)
            } else {
                draft.lowConfidenceFields.remove(field)
            }
        }

        apply(fields.title, to: \.title, field: "title")
        apply(fields.author, to: \.author, field: "author")
        apply(fields.publisher, to: \.publisher, field: "publisher")
        apply(fields.publicationYear, to: \.publicationYear, field: "publicationYear")
        apply(fields.edition, to: \.edition, field: "edition")
        apply(fields.pageCount, to: \.pageCount, field: "pageCount")
        apply(fields.language, to: \.language, field: "language")
        apply(fields.category, to: \.category, field: "category")

        // ISBN: barkoddan okunmuş geçerli ISBN her zaman daha güvenilirdir
        let existing = ISBNFormatter.normalize(draft.isbn)
        if !BookFieldMetadata.isLocked("isbn", metadata: draft.fieldMetadata), existing.isEmpty, let isbn = fields.isbn {
            draft.isbn = isbn
            draft.lowConfidenceFields.remove("isbn")
        }

        if !BookFieldMetadata.isLocked("notes", metadata: draft.fieldMetadata), draft.notes.isEmpty, let summary = fields.summary {
            draft.notes = summary
        }
        // Künye ek bilgileri şemayı değiştirmeden notlara "Künye:" satırı olarak eklenir
        let extras = [
            fields.translator.map { "Çeviren: \($0)" },
            fields.illustrator.map { "Resimleyen: \($0)" },
            fields.printPlace.map { "Baskı yeri: \($0)" }
        ].compactMap { $0 }
        if !BookFieldMetadata.isLocked("notes", metadata: draft.fieldMetadata), !extras.isEmpty, !draft.notes.contains("Künye:") {
            let line = "Künye: " + extras.joined(separator: " · ")
            draft.notes = draft.notes.isEmpty ? line : draft.notes + "\n" + line
        }
        // Dewey numarası yer numarası (konum) alanına — sırt etiketleri standarda uysun
        if draft.location.isEmpty, let dewey = fields.dewey {
            draft.location = dewey
        }
        // Seri/etiket/düzey/uyarı yalnız boşsa yazılır (kullanıcının girdiği korunur)
        if draft.series.isEmpty, let series = fields.series { draft.series = series }
        if draft.volume == 0, let volume = fields.volume.flatMap(Int.init) { draft.volume = volume }
        if draft.tags.isEmpty, let tags = fields.tags { draft.tags = tags.joined(separator: ", ") }
        if draft.readingLevel.isEmpty, let level = fields.readingLevel { draft.readingLevel = level }
        if draft.contentWarning.isEmpty, let warning = fields.contentWarning { draft.contentWarning = warning }
        if fields.category == "Ders Kitabı" || fields.category == "Yardımcı Kaynak" {
            draft.isTextbook = true
        }
        // Fotoğraf kalitesi düşükse düzenleyicide uyarı çıkar (imageQuality alanı)
        if let quality = fields.imageQuality, quality != "good" {
            draft.lowConfidenceFields.insert("imageQuality:" + quality)
        }
        draft.fieldMetadata = BookFieldMetadata.stampChanges(before: previous, after: draft.snapshot, source: "gemini").fieldMetadata
        if let confidence = fields.confidence, confidence.isFinite {
            var metadata = BookFieldMetadata.decode(draft.fieldMetadata)
            for field in BookFieldMetadata.fields where metadata[field]?.source == "gemini" && !uncertain.contains(field) {
                metadata[field]?.confidence = min(1, max(0, confidence))
            }
            draft.fieldMetadata = BookFieldMetadata.encode(metadata)
        }
    }

    /// Kalite uyarısı metni (düzenleyici rozeti için).
    static func imageQualityWarning(for draft: BookDraft) -> String? {
        guard let flag = draft.lowConfidenceFields.first(where: { $0.hasPrefix("imageQuality:") }) else { return nil }
        switch flag.dropFirst("imageQuality:".count) {
        case "blurry": return "Fotoğraf bulanık; daha net bir kapak çekmeniz önerilir."
        case "dark": return "Fotoğraf karanlık; daha aydınlık ortamda yeniden çekin."
        case "partial": return "Kitap kadrajda tam görünmüyor; kapağın tamamını çekin."
        case "glare": return "Kapakta parlama var; açıyı değiştirip yeniden çekin."
        default: return "Fotoğraf kalitesi düşük; yeniden çekmeniz önerilir."
        }
    }

    /// Hızlı mod kararı: Gemini okudu, şüpheli alan yok, kalite iyi, ad+yazar dolu ve
    /// (ISBN geçerli ya da yayınevi de dolu) → onaysız kaydedilebilir.
    static func isConfidentEnoughToAutoSave(_ draft: BookDraft) -> Bool {
        guard draft.recognizedByGemini, draft.lowConfidenceFields.isEmpty else { return false }
        guard !draft.title.trimmingCharacters(in: .whitespaces).isEmpty,
              !draft.author.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        let hasISBN = !ISBNFormatter.normalize(draft.isbn).isEmpty
        return hasISBN || !draft.publisher.isEmpty
    }

    /// Ana OCR akışı için: ayar açıksa alanları getirir, kapalıysa/hata olursa `nil`
    /// (tarama akışı bekletilmez: 25 sn, tek deneme). Vision ile EŞZAMANLI çağrılır.
    static func fieldsIfEnabled(images: [Data], extraText: String? = nil) async -> GeminiBookFields? {
        guard GeminiSettings.isOCREnabled, !images.isEmpty || !(extraText ?? "").isEmpty else { return nil }
        do {
            return try await recognize(images: images, extraText: extraText, timeout: 25, maxAttempts: 1)
        } catch {
#if DEBUG
            print("🤖 Gemini OCR atlandı: \(error.localizedDescription)")
#endif
            return nil
        }
    }

    /// Vision hiç sonuç veremediyse (görüntü çözülemedi/metin yok) taslak doğrudan Gemini'den kurulur.
    static func draft(from fields: GeminiBookFields, cover: Data?) -> BookDraft {
        var draft = BookDraft()
        draft.coverData = cover
        merge(fields, into: &draft)
        return draft
    }

    /// Barkod taramasında çekilen arka kapak fotoğrafından YALNIZ boş alanları doldurur:
    /// barkoddan gelen künye (ad/yazar/yayınevi) korunur; özet, etiket, düzey, seri, içerik
    /// uyarısı arka kapak metninden eklenir.
    static func fillEmptyFromBackCover(_ draft: inout BookDraft, photo: Data) async {
        guard GeminiSettings.isOCREnabled,
              let fields = try? await recognize(images: [photo], timeout: 25, maxAttempts: 1),
              fields.isBook != false else { return }
        var candidate = BookDraft()
        merge(fields, into: &candidate)
        let keys: [(WritableKeyPath<BookDraft, String>, String)] = [
            (\.title, "title"), (\.author, "author"), (\.publisher, "publisher"),
            (\.publicationYear, "publicationYear"), (\.pageCount, "pageCount"), (\.language, "language"),
            (\.category, "category"), (\.notes, "notes"), (\.series, "series"), (\.tags, "tags"),
            (\.readingLevel, "readingLevel"), (\.contentWarning, "contentWarning")
        ]
        var applied = false
        for (keyPath, field) in keys where draft[keyPath: keyPath].isEmpty && !candidate[keyPath: keyPath].isEmpty {
            guard !BookFieldMetadata.isLocked(field, metadata: draft.fieldMetadata) else { continue }
            draft[keyPath: keyPath] = candidate[keyPath: keyPath]
            if candidate.lowConfidenceFields.contains(field) { draft.lowConfidenceFields.insert(field) }
            applied = true
        }
        if draft.volume == 0, candidate.volume > 0 { draft.volume = candidate.volume }
        if applied { draft.recognizedByGemini = true }
    }

    /// Ayar açıksa taslağı Gemini ile zenginleştirir; hata olursa Vision sonucu olduğu gibi kalır.
    static func enrichIfEnabled(_ draft: inout BookDraft, images: [Data]) async {
        guard GeminiSettings.isOCREnabled, !images.isEmpty else { return }
        do {
            // Tarama akışını bekletme: 25 sn, tek deneme; olmazsa Vision sonucu kalır
            let fields = try await recognize(images: images, timeout: 25, maxAttempts: 1)
            merge(fields, into: &draft)
        } catch {
#if DEBUG
            print("🤖 Gemini OCR atlandı: \(error.localizedDescription)")
#endif
        }
    }
}
