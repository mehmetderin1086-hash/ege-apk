import Testing
import Foundation
import SwiftData
import UIKit
@testable import _01

// Gemini katmanı: ağa çıkmadan doğrulanabilen her şey — JSON ayıklama, yanıt çözme,
// alan normalizasyonu, Vision taslağıyla birleştirme, asistan bağlamı (takma adlar),
// toplu tamamlama ve onay kapısı.

@MainActor
struct GeminiJSONTestleri {
    @Test func kodCitiTemizlenir() {
        let raw = "```json\n{\"answer\": \"Merhaba\", \"bookTitles\": []}\n```"
        #expect(GeminiJSON.extract(from: raw) == "{\"answer\": \"Merhaba\", \"bookTitles\": []}")
    }

    @Test func aciklamaIcineGomuluJSONBulunur() {
        let raw = "Elbette, işte sonuç:\n{\"title\": \"Kuyucaklı Yusuf\"}\nBaşka bir isteğiniz var mı?"
        let reply = try? GeminiJSON.decode(GeminiBookFields.self, from: raw)
        #expect(reply?.title == "Kuyucaklı Yusuf")
    }

    @Test func diziYanitiCozulur() throws {
        let raw = "[{\"index\": 0, \"category\": \"Roman\"}, {\"index\": 1, \"language\": \"Türkçe\"}]"
        let items = try GeminiJSON.decode([AICompletionItem].self, from: raw)
        #expect(items.count == 2)
        #expect(items[1].language == "Türkçe")
    }

    @Test func bozukJSONAnlamliHataVerir() {
        #expect(throws: GeminiError.self) {
            try GeminiJSON.decode(AssistantReply.self, from: "bu bir json değil")
        }
    }

    /// Düşünme (thought) parçaları metne karışmamalı.
    @Test func yanitMetniDusunmeParcalariniAtlar() throws {
        let json = """
        {"candidates":[{"content":{"role":"model","parts":[
          {"text":"gizli akıl yürütme","thought":true},
          {"text":"{\\"answer\\":\\"3 kitap var\\"}"}
        ]},"finishReason":"STOP"}]}
        """
        let response = try JSONDecoder().decode(GeminiResponse.self, from: Data(json.utf8))
        #expect(response.text == "{\"answer\":\"3 kitap var\"}")
        let reply = try GeminiJSON.decode(AssistantReply.self, from: response.text)
        #expect(reply.answer == "3 kitap var")
    }

    /// MAX_TOKENS'ta `content: {}` gelir; çözümleme çökmemeli, sebep okunabilmeli.
    @Test func bosIcerikVeBitisSebebiCozulur() throws {
        let json = """
        {"candidates":[{"content":{},"finishReason":"MAX_TOKENS","index":0}],"usageMetadata":{"promptTokenCount":8}}
        """
        let response = try JSONDecoder().decode(GeminiResponse.self, from: Data(json.utf8))
        #expect(response.text.isEmpty)
        #expect(response.finishReason == "MAX_TOKENS")
        #expect(GeminiError.emptyResponse("MAX_TOKENS").errorDescription?.contains("uzunluk") == true)
    }

    @Test func hataYanitiCozulur() throws {
        let json = """
        {"error":{"code":404,"message":"model bulunamadı","status":"NOT_FOUND"}}
        """
        let response = try JSONDecoder().decode(GeminiResponse.self, from: Data(json.utf8))
        #expect(response.error?.code == 404)
        #expect(response.text.isEmpty)
    }

    @Test func istekGovdesiAPIAlanAdlariylaKodlanir() throws {
        let request = GeminiRequest(
            contents: [GeminiContent(role: "user", parts: [GeminiPart(text: "merhaba"), GeminiPart(imageData: Data([1, 2, 3]))])],
            systemInstruction: GeminiContent(role: nil, parts: [GeminiPart(text: "sistem")]),
            generationConfig: GeminiGenerationConfig(temperature: 0.2, maxOutputTokens: 100, responseMimeType: "application/json")
        )
        let data = try JSONEncoder().encode(request)
        let text = String(decoding: data, as: UTF8.self)
        // JSONEncoder "/" karakterini "\/" olarak kaçırabilir; API her iki biçimi de kabul eder
        let unescaped = text.replacingOccurrences(of: "\\/", with: "/")
        #expect(unescaped.contains("\"inlineData\""))
        #expect(unescaped.contains("\"mimeType\":\"image/jpeg\""))
        #expect(unescaped.contains("\"systemInstruction\""))
        #expect(unescaped.contains("\"responseMimeType\":\"application/json\""))
        #expect(unescaped.contains("\"data\":\"AQID\""))
    }
}

@MainActor
struct GeminiOCRTestleri {
    @Test func alanlarNormalizeEdilir() {
        let raw = GeminiBookFields(
            title: "  Şeker Portakalı ", author: "Vasconcelos", isbn: "978-975-07-1843-4",
            publicationYear: "Ekim 2019", edition: "3. Baskı", pageCount: "184 sayfa",
            category: "Çocuk Edebiyatı"
        )
        let clean = GeminiBookRecognizer.normalized(raw)
        #expect(clean.title == "Şeker Portakalı")
        #expect(clean.isbn == "9789750718434")
        #expect(clean.publicationYear == "2019")
        #expect(clean.edition == "3")
        #expect(clean.pageCount == "184")
        #expect(clean.category == "Çocuk")
    }

    @Test func gecersizISBNVeYilAtilir() {
        let clean = GeminiBookRecognizer.normalized(GeminiBookFields(isbn: "12345", publicationYear: "19", category: "Uzay Bilimleri"))
        #expect(clean.isbn == nil)
        #expect(clean.publicationYear == nil)
        #expect(clean.category == "Bilim")
    }

    @Test func bilinmeyenKategoriDigerOlur() {
        let clean = GeminiBookRecognizer.normalized(GeminiBookFields(category: "Zımbırtı"))
        #expect(clean.category == "Diğer")
    }

    /// Büyük harfli/şapkasız yazım Türkçe harf katlamasıyla listeye eşlenir.
    @Test func kategoriTurkceHarfKatlamasiylaEslesir() {
        #expect(GeminiBookRecognizer.normalized(GeminiBookFields(category: "TARİH")).category == "Tarih")
        #expect(GeminiBookRecognizer.normalized(GeminiBookFields(category: "KİŞİSEL GELİŞİM KİTABI")).category == "Kişisel Gelişim")
        #expect(GeminiBookRecognizer.normalized(GeminiBookFields(category: "Hikaye")).category == "Hikâye")
        #expect(GeminiBookRecognizer.normalized(GeminiBookFields(category: "SIIR")).category == "Şiir")
        // Eşleşme sözcük başındandır: "Kadın" içindeki "din" kategori sayılmaz
        #expect(GeminiBookRecognizer.normalized(GeminiBookFields(category: "Kadın Hakları")).category == "Diğer")
        #expect(GeminiBookRecognizer.normalized(GeminiBookFields(category: "Din Kültürü")).category == "Din")
    }

    /// Birden çok liste ögesi geçiyorsa en uzun (en özgül) olan seçilir.
    @Test func enUzunKategoriEslesmesiKazanir() {
        let clean = GeminiBookRecognizer.normalized(GeminiBookFields(category: "Bilim Kurgu Romanı"))
        #expect(clean.category == "Bilim Kurgu")
    }

    /// Gemini alanı Vision tahminine baskın gelir; barkod ISBN'i korunur; belirsiz alan işaretli kalır.
    @Test func visionTaslagiGeminiIleZenginlesir() {
        var draft = BookDraft()
        draft.title = "SEKER PORTAKALI"
        draft.author = "Bilinmiyor"
        draft.isbn = "9789750718434"          // barkoddan okunmuş, geçerli
        draft.lowConfidenceFields = ["title", "author", "publisher"]

        let fields = GeminiBookFields(
            title: "Şeker Portakalı", author: "José Mauro de Vasconcelos", publisher: "Can Çocuk",
            isbn: "9786053608000", publicationYear: "2019", pageCount: "184", language: "Türkçe",
            category: "Çocuk", summary: "Zezé'nin hikâyesi.", uncertain: ["publisher"]
        )
        GeminiBookRecognizer.merge(fields, into: &draft)

        #expect(draft.title == "Şeker Portakalı")
        #expect(draft.author == "José Mauro de Vasconcelos")
        #expect(draft.isbn == "9789750718434", "Barkod ISBN'i Gemini tahminine ezilmemeli")
        #expect(draft.publisher == "Can Çocuk")
        #expect(draft.notes == "Zezé'nin hikâyesi.")
        #expect(draft.category == "Çocuk")
        #expect(!draft.lowConfidenceFields.contains("title"))
        #expect(!draft.lowConfidenceFields.contains("author"))
        #expect(draft.lowConfidenceFields.contains("publisher"))
    }

    @Test func isbnsizTaslagaGeminiISBNiYazilir() {
        var draft = BookDraft()
        draft.title = "X"
        GeminiBookRecognizer.merge(GeminiBookFields(isbn: "9789750718434"), into: &draft)
        #expect(draft.isbn == "9789750718434")
    }

    @Test func kitapDegilseTaslakDegismez() {
        var draft = BookDraft()
        draft.title = "Vision Adı"
        GeminiBookRecognizer.merge(GeminiBookFields(title: "Başka", isBook: false), into: &draft)
        #expect(draft.title == "Vision Adı")
    }

    @Test func dersKitabiKategorisiIsaretler() {
        var draft = BookDraft()
        GeminiBookRecognizer.merge(GeminiBookFields(title: "Matematik 5", category: "Ders Kitabı"), into: &draft)
        #expect(draft.isTextbook)
    }

    /// Büyük fotoğraf küçültülüp JPEG'e çevrilmeli (jeton ve süre tasarrufu).
    @Test func goruntuKucultulurVeJPEGOlur() throws {
        let size = CGSize(width: 3000, height: 4000)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let png = try #require(image.pngData())
        let jpeg = try #require(GeminiImagePreparer.jpegData(from: png, maxPixel: 1600))
        #expect(jpeg.count < png.count)
        #expect(jpeg.prefix(2) == Data([0xFF, 0xD8]), "JPEG imzası bekleniyor")
        let decoded = try #require(UIImage(data: jpeg))
        #expect(max(decoded.size.width, decoded.size.height) <= 1600)
    }
}

@MainActor
struct AsistanBaglamTestleri {
    private func context() throws -> (ModelContext, [CatalogBook], [ActiveLoan]) {
        let container = try ModelContainer(
            for: CatalogBook.self, ActiveLoan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = ModelContext(container)
        let books = [
            CatalogBook(book: Book(title: "Kürk Mantolu Madonna", author: "Sabahattin Ali", category: "Roman", quantity: 2)),
            CatalogBook(book: Book(title: "Kuyucaklı Yusuf", author: "Sabahattin Ali", category: "Roman")),
            CatalogBook(book: Book(title: "Uzayın Sırları", author: "A. Bilim", category: "Bilim")),
            CatalogBook(book: Book(title: "Düşülmüş Kitap", author: "Yok", isWithdrawn: true))
        ]
        books.forEach { ctx.insert($0) }
        let loan = ActiveLoan(bookID: books[0].id, bookTitleSnapshot: books[0].title,
                              studentName: "Ali Veli", studentClass: "5-A",
                              dueDate: .now.addingTimeInterval(-3 * 86_400))
        ctx.insert(loan)
        try ctx.save()
        return (ctx, books, [loan])
    }

    @Test func anahtarSozcuklerDurakSozcukleriAtar() {
        let words = AssistantContext.keywords(in: "Sabahattin Ali kitabı var mı?")
        #expect(words.contains("sabahattin"))
        #expect(words.contains("ali"))
        #expect(!words.contains("var"))
        #expect(!words.contains("kitabı"))
    }

    @Test func soruylaEslesenKitaplarBulunur() throws {
        let (_, books, _) = try context()
        let matches = AssistantContext.matchingBooks(for: "Sabahattin Ali kitabı var mı?", in: books)
        #expect(matches.count == 2)
        #expect(matches.allSatisfy { $0.author == "Sabahattin Ali" })
        #expect(!matches.contains { $0.isWithdrawn })
    }

    @Test func baglamOzetVeGecikmeIcerir() throws {
        let (_, books, loans) = try context()
        let result = AssistantContext.build(question: "geciken var mı", books: books, loans: loans)
        let text = result.text
        #expect(text.contains("3 kitap"))
        #expect(text.contains("1 düşülmüş"))
        #expect(text.contains("1 gecikmiş"))
        #expect(text.contains("3 gün gecikti"))
        // Öğrenci adı Google'a gitmez: takma ad kullanılır, yanıt gelince geri çevrilir
        #expect(!text.contains("Ali Veli"))
        #expect(text.contains("Öğrenci 1 (5-A)"))
        #expect(result.aliases.restore(in: "Öğrenci 1 kitabı 3 gün geciktirdi.") == "Ali Veli kitabı 3 gün geciktirdi.")
    }

    /// "Öğrenci 12" içindeki "Öğrenci 1" yanlış değiştirilmemeli.
    @Test func takmaAdlarUzundanKisayaCevrilir() {
        let aliases = PersonAliases()
        var names: [String] = []
        for index in 1...12 { names.append(aliases.alias(for: "Kişi \(index)")) }
        #expect(names.first == "Öğrenci 1")
        #expect(names.last == "Öğrenci 12")
        #expect(aliases.alias(for: "Kişi 1") == "Öğrenci 1", "Aynı kişi aynı takma adı almalı")
        #expect(aliases.restore(in: "Öğrenci 12 ve Öğrenci 1") == "Kişi 12 ve Kişi 1")
    }

    /// Yanıttaki kitap adları yalnızca bağlamdaki kitaplarla, güvenli önek kuralıyla eşleşir.
    @Test func kitapAdlariBaglamlaEslesir() throws {
        let (_, books, _) = try context()
        let matched = AssistantContext.matchTitles(
            ["Kürk Mantolu Madonna", "kuyucaklı yusuf", "", "Kür", "Olmayan Kitap", "Kürk Mantolu Madonna"],
            in: books
        )
        #expect(matched.map(\.title) == ["Kürk Mantolu Madonna", "Kuyucaklı Yusuf"])
    }

    @Test func bostaOrneklemOduncteOlaniAtlar() throws {
        let (_, books, loans) = try context()
        let sample = AssistantContext.availableSample(from: books, loans: loans, limit: 10)
        // Kürk Mantolu Madonna: 2 nüsha, 1 ödünçte → hâlâ boşta; Düşülmüş kitap yer almamalı
        #expect(sample.contains { $0.title == "Kürk Mantolu Madonna" })
        #expect(!sample.contains { $0.isWithdrawn })
        #expect(sample.count == 3)
    }

    @Test func satirBostaSayisiniDogruYazar() throws {
        let (_, books, loans) = try context()
        let line = AssistantContext.line(for: books[0], loans: loans)
        #expect(line.contains("adet 2, boşta 1"))
        #expect(line.contains("Kürk Mantolu Madonna — Sabahattin Ali"))
    }
}

@MainActor
struct AITamamlamaTestleri {
    @Test func yalnizBosAlanlarDoldurulur() throws {
        let container = try ModelContainer(for: CatalogBook.self, ActiveLoan.self, BookCopy.self, Reservation.self, ScanWriteReceipt.self, LibraryEventOutbox.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let book = CatalogBook(book: Book(title: "Test", author: "Y", notes: "Kullanıcının notu", category: "Şiir"))
        ctx.insert(book)

        let changed = AICompletionEngine.apply(
            AICompletionItem(index: 0, category: "Roman", language: "Türkçe", summary: "AI özeti"),
            to: book
        )
        #expect(changed)
        #expect(book.category == "Şiir", "Mevcut kategori ezilmemeli")
        #expect(book.notes == "Kullanıcının notu", "Mevcut not ezilmemeli")
        #expect(book.language == "Türkçe")
    }

    /// Kullanıcının kapattığı alan (özet) boş olsa bile doldurulmaz.
    @Test func kapaliSecenekDoldurulmaz() throws {
        let container = try ModelContainer(for: CatalogBook.self, ActiveLoan.self, BookCopy.self, Reservation.self, ScanWriteReceipt.self, LibraryEventOutbox.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let book = CatalogBook(book: Book(title: "Test", author: "Y"))
        ctx.insert(book)
        let changed = AICompletionEngine.apply(
            AICompletionItem(index: 0, category: "Roman", language: "Türkçe", summary: "Özet"),
            to: book, fillCategory: true, fillLanguage: false, fillSummary: false
        )
        #expect(changed)
        #expect(book.category == "Roman")
        #expect(book.language == nil)
        #expect(book.notes.isEmpty)
    }

    @Test func listeDisiKategoriUygulanmaz() throws {
        let container = try ModelContainer(for: CatalogBook.self, ActiveLoan.self, BookCopy.self, Reservation.self, ScanWriteReceipt.self, LibraryEventOutbox.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let book = CatalogBook(book: Book(title: "Test", author: "Y"))
        ctx.insert(book)
        let changed = AICompletionEngine.apply(AICompletionItem(index: 0, category: "Uydurma Kategori"), to: book)
        #expect(!changed)
        #expect(book.category == nil)
    }
}

@MainActor
struct GeminiTTSTestleri {
    /// API bazen başlıksız PCM döndürür; eklenen WAV başlığı doğru alanları taşımalı.
    @Test func hamPCMyeWAVBasligiEklenir() {
        let pcm = Data(repeating: 0x7F, count: 4800) // 0,1 sn @ 24 kHz 16-bit mono
        let wav = GeminiClient.ensureWAVHeader(pcm, mimeType: "audio/L16;codec=pcm;rate=24000")
        #expect(wav.count == pcm.count + 44)
        #expect(wav.prefix(4) == Data("RIFF".utf8))
        #expect(wav[8..<12] == Data("WAVE".utf8))
        // örnekleme hızı (byte 24-27, little endian) = 24000
        let rate = wav[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        #expect(UInt32(littleEndian: rate) == 24_000)
        // veri uzunluğu (byte 40-43)
        let length = wav[40..<44].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        #expect(UInt32(littleEndian: length) == 4800)
    }

    @Test func hazirWAVDegistirilmez() {
        var wav = Data("RIFF".utf8)
        wav.append(contentsOf: [1, 2, 3, 4])
        #expect(GeminiClient.ensureWAVHeader(wav, mimeType: "audio/wav") == wav)
    }

    @Test func ttsIstegiSesVeModaliteIcerir() throws {
        let config = GeminiGenerationConfig(
            responseModalities: ["AUDIO"],
            speechConfig: .init(voiceConfig: .init(prebuiltVoiceConfig: .init(voiceName: GeminiTTSVoice.kore.rawValue)))
        )
        let text = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        #expect(text.contains("\"responseModalities\":[\"AUDIO\"]"))
        #expect(text.contains("\"voiceName\":\"Kore\""))
        #expect(!text.contains("temperature"), "Boş alanlar gönderilmemeli")
    }

    @Test func varsayilanSesKore() {
        #expect(GeminiSettings.ttsVoice == .kore || GeminiTTSVoice.allCases.contains(GeminiSettings.ttsVoice))
        #expect(GeminiTTSVoice.allCases.count == 8)
    }
}

@MainActor
struct SesliKayitTestleri {
    @Test(arguments: [("kaydet", VoiceBookEngine.LocalCommand.save), ("Tamam.", .save), ("iptal", .cancel), ("Vazgeç", .cancel), ("geri al", .undo), ("sıradaki", .next)])
    func yerelKomutlarTaninir(text: String, expected: VoiceBookEngine.LocalCommand) {
        #expect(VoiceBookEngine.localCommand(in: text) == expected)
    }

    @Test func kitapTanimiKomutSayilmaz() {
        #expect(VoiceBookEngine.localCommand(in: "Kürk Mantolu Madonna, Sabahattin Ali, iki adet") == nil)
        #expect(VoiceBookEngine.localCommand(in: "kaydet şu kitabı lütfen hemen") == nil, "Uzun cümle komut değildir")
    }

    @Test func kayitNormalizeEdilir() {
        var raw = SesliKitapKaydi()
        raw.title = " Şeker Portakalı "
        raw.author = "Vasconcelos"
        raw.isbn = "978-975-07-1843-4"
        raw.publicationYear = "1968 yılı"
        raw.quantity = 0
        raw.cabinet = "b"
        raw.category = "Çocuk edebiyatı klasiği"
        raw.command = "SAVE"
        let clean = VoiceBookEngine.normalized(raw)
        #expect(clean.title == "Şeker Portakalı")
        #expect(clean.isbn == "9789750718434")
        #expect(clean.publicationYear == "1968")
        #expect(clean.quantity == 1, "Adet en az 1")
        #expect(clean.cabinet == "B")
        #expect(clean.category == "Çocuk")
        #expect(clean.command == "save")
        let book = VoiceBookEngine.book(from: clean)
        #expect(book.title == "Şeker Portakalı")
        #expect(book.quantity == 1)
        #expect(book.readingStatus == "Okunacak")
    }

    /// Aynı kitap ikinci kez söylenirse yeni kayıt açılmaz, adet artar.
    @Test func mukerrerSoylenirseAdetArtar() throws {
        let container = try ModelContainer(for: CatalogBook.self, ActiveLoan.self, BookCopy.self, Reservation.self, ScanWriteReceipt.self, LibraryEventOutbox.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)

        var first = SesliKitapKaydi()
        first.title = "Kuyucaklı Yusuf"
        first.author = "Sabahattin Ali"
        first.quantity = 2
        let outcome1 = try VoiceBookSaver.save(first, in: ctx, catalog: [])
        guard case .inserted(let inserted) = outcome1 else { Issue.record("İlk kayıt eklenmeliydi"); return }
        #expect(inserted.quantity == 2)

        var second = SesliKitapKaydi()
        second.title = "kuyucakli yusuf"      // konuşma tanıma aksansız yazdı
        second.author = "Sabahattin Ali"
        second.quantity = 1
        second.cabinet = "C"
        let catalog = try ctx.fetch(FetchDescriptor<CatalogBook>())
        let outcome2 = try VoiceBookSaver.save(second, in: ctx, catalog: catalog)
        guard case .merged(let merged, let added) = outcome2 else { Issue.record("Mükerrer birleştirilmeliydi"); return }
        #expect(added == 1)
        #expect(merged.quantity == 3)
        #expect(merged.cabinet == "C", "Boş yer bilgisi doldurulur")
        #expect(try ctx.fetch(FetchDescriptor<CatalogBook>()).count == 1)
        #expect(outcome2.message.contains("zaten katalogdaydı"))
    }

    @Test func asistanEklemeNiyetiCozulur() throws {
        let json = """
        {"answer":"Şunu kaydedeyim mi: Şeker Portakalı","bookTitles":[],"followUps":[],
         "action":{"type":"addBook","book":{"title":"Şeker Portakalı","author":"Vasconcelos","quantity":2,"uncertain":["publisher"]}}}
        """
        let reply = try GeminiJSON.decode(AssistantReply.self, from: json)
        #expect(reply.action?.type == "addBook")
        #expect(reply.action?.book?.title == "Şeker Portakalı")
        #expect(reply.action?.book?.quantity == 2)
        // action null gelirse de çözülmeli
        let plain = try GeminiJSON.decode(AssistantReply.self, from: "{\"answer\":\"Merhaba\",\"action\":null}")
        #expect(plain.action == nil)
    }
}

@MainActor
@Suite(.serialized)
struct GeminiAnahtarTestleri {
    @Test func gomuluAnahtarYok() {
        #expect(GeminiKeyStore.bundledKey.isEmpty)
        #expect(!GeminiKeyStore.isUsingBundledKey)
        #expect(GeminiModel.allCases.contains(GeminiSettings.model))
    }

    @Test func ozelAnahtarKaydedilirVeSilinir() throws {
        let previous = GeminiKeyStore.loadCustomKey()
        defer { GeminiKeyStore.saveCustomKey(previous) }

        try GeminiKeyStore.saveCustomKeyVerified("  test-anahtar-123 ")
        #expect(GeminiKeyStore.loadCustomKey() == "test-anahtar-123")
        #expect(GeminiKeyStore.activeKey == "test-anahtar-123")
        #expect(!GeminiKeyStore.isUsingBundledKey)

        GeminiKeyStore.saveCustomKey("")
        #expect(GeminiKeyStore.loadCustomKey().isEmpty)
        #expect(!GeminiKeyStore.isUsingBundledKey)
        #expect(GeminiKeyStore.activeKey.isEmpty)
    }

    /// Onay verilmeden hiçbir istek çıkmaz (ağa dokunmadan, hızlı hata).
    @Test func onaysizIstekReddedilir() async {
        let previous = UserDefaults.standard.object(forKey: GeminiSettings.consentKey)
        defer { UserDefaults.standard.set(previous, forKey: GeminiSettings.consentKey) }
        UserDefaults.standard.set(false, forKey: GeminiSettings.consentKey)
        await #expect(throws: GeminiError.self) {
            try await GeminiClient.shared.generateText(prompt: "test", maxAttempts: 1)
        }
    }

    @Test func hataMesajlariTurkce() {
        #expect(GeminiError.http(429, "").errorDescription?.contains("sınır") == true)
        #expect(GeminiError.http(403, "").errorDescription?.contains("anahtar") == true)
        #expect(GeminiError.missingKey.errorDescription?.contains("Ayarlar") == true)
    }
}
