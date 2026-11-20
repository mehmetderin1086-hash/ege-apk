import Foundation
import Testing
import UIKit
@testable import Ikra

// MEB kütüphanesi: uygulamayla gelen katalog, kitap dizininin okunması ve konunun kitaptaki sayfalarının bulunması.

@Suite @MainActor struct MEBTests {
    @Test func bundledCatalogHoldsOnlyExamCoursesWithThemesAndBooks() {
        let catalog = MEBCatalog.shared
        #expect(catalog.courses.count == 14 && catalog.courses.allSatisfy(\.yks))
        #expect(catalog.grades.map(\.name) == ["Hazırlık", "9. Sınıf", "10. Sınıf", "11. Sınıf", "12. Sınıf", "Seçmeli Dersler"])
        // Her temanın öğrenme çıktısı ve seçilebilir en az bir konusu vardır.
        let themes = catalog.courses.flatMap { $0.grades.flatMap(\.themes) }
        #expect(themes.count > 150 && themes.allSatisfy { !$0.outcomes.isEmpty && !$0.topicGroups.isEmpty && !$0.title.isEmpty })
        // Kitap bağlantıları geçerli ve güvenli adreslerdir; her kitap katalogdaki bir derse bağlıdır.
        let ids = Set(catalog.courses.map(\.id))
        #expect(catalog.books.count > 50 && catalog.books.allSatisfy { ids.contains($0.course) && catalog.url($0.pdf)?.scheme == "https" && ["ders", "etkinlik"].contains($0.kind) })
        #expect(Set(catalog.books.map(\.id)).count == catalog.books.count)
        // 9. sınıf biyoloji: iki tema, ders kitabı önce listelenir.
        let biology = catalog.courses.first { $0.shortName == "Biyoloji" }
        #expect(biology?.themes(in: 11).map(\.shortTitle) == ["Yaşam", "Organizasyon"])
        #expect(biology?.themes(in: 11).first?.topicGroups.first?.topics.contains("Canlıların Ortak Özellikleri") == true)
        #expect(catalog.books(course: biology?.id ?? 0, grade: 11).first?.kind == "ders")
        // Dersin bütün sınıflarındaki kitaplar sınıf sırasıyla gelir (toplu indirme bunu kullanır).
        let all = catalog.books(course: biology?.id ?? 0)
        #expect(all.count >= 7 && all.map(\.grade) == all.map(\.grade).sorted() && all.first?.kind == "ders")
        #expect(catalog.courses(in: 11).map(\.shortName).contains("Matematik") && catalog.courses(in: 10).allSatisfy { !$0.themes(in: 10).isEmpty || !catalog.books(course: $0.id, grade: 10).isEmpty })
    }

    @Test func linksAndFilesAreBuiltSafely() {
        let catalog = MEBCatalog(version: "t", source: "https://tymm.meb.gov.tr", grades: [], courses: [], books: [])
        #expect(catalog.url("/assets/pdf/a.pdf")?.absoluteString == "https://tymm.meb.gov.tr/assets/pdf/a.pdf")
        #expect(catalog.url("https://meb.ai/x")?.host == "meb.ai" && catalog.url("http://meb.ai/x") == nil && catalog.url("  ") == nil && catalog.url("javascript:alert(1)") == nil)
        let book = MEBCatalog.Book(id: 36, title: "Biyoloji 9", kind: "ders", grade: 11, course: 21, pdf: "/assets/pdf/b.pdf", cover: "", bytes: 98_733_656)
        let file = MEBFile(book: book, catalog: catalog)
        #expect(file?.id == "kitap-36" && MEBLibrary.location("kitap-36").lastPathComponent == "kitap-36.pdf" && MEBFile.size(0).isEmpty && !MEBFile.size(book.bytes).isEmpty)
        let course = MEBCatalog.Course(id: 21, name: "Biyoloji Dersi", slug: "biyoloji-dersi", program: "", yks: true, grades: [])
        #expect(MEBFile(program: course, catalog: catalog) == nil && course.shortName == "Biyoloji")
        // Konu listesi verilmemiş temada temanın adı tek konu olur.
        let theme = MEBCatalog.Theme(id: 1, title: "2. Tema: Organizasyon", summary: "", hours: 0, outcomes: [], content: [.init(heading: "x", topics: [])], keywords: "")
        #expect(theme.topicGroups.count == 1 && theme.topicGroups[0].topics == ["Organizasyon"] && MEBCatalog.Theme(id: 2, title: "Giriş", summary: "", hours: 0, outcomes: [], content: [], keywords: "").shortTitle == "Giriş")
    }

    @Test func downloadedFileMustBeARealPDF() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "meb-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let good = folder.appending(path: "a.pdf"), bad = folder.appending(path: "b.pdf")
        try Data("%PDF-1.7\n...".utf8).write(to: good); try Data("<html>Hata</html>".utf8).write(to: bad)
        #expect(MEBLibrary.isPDF(good) && !MEBLibrary.isPDF(bad) && !MEBLibrary.isPDF(folder.appending(path: "yok.pdf")))
    }

    @Test func bookSearchFindsUndownloadedBooksAndAppliesEveryFilter() {
        let catalog = MEBCatalog.shared
        let biology = catalog.courses.first { $0.shortName == "Biyoloji" }!
        let books = MEBBookQuery.results(catalog: catalog, query: "  biyoloji  ")
        #expect(!books.isEmpty && books.allSatisfy { $0.course == biology.id })
        let selected = books[0]
        let stored: Set<String> = ["kitap-\(selected.id)"]
        let downloaded = MEBBookQuery.results(catalog: catalog, query: "biyoloji", grade: selected.grade,
                                               course: biology.id, downloadedOnly: true, stored: stored)
        #expect(downloaded.map(\.id) == [selected.id])
        #expect(MEBBookQuery.results(catalog: catalog, query: "biyoloji", grade: -1).isEmpty)
        #expect(MEBBookQuery.results(catalog: catalog, query: "", downloadedOnly: true).isEmpty)
        #expect(MEBBookQuery.results(catalog: catalog, query: "").count == catalog.books.count)
    }

    @Test func readingRecencySurvivesRelaunchAndIgnoresUnavailableFiles() throws {
        let suite = "meb-reading-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let books = MEBCatalog.shared.books.prefix(2).compactMap { MEBFile(book: $0) }
        #expect(books.count == 2)
        let library = MEBLibrary(defaults: defaults)
        library.recordOpened(key: books[0].id, at: Date(timeIntervalSince1970: 100))
        library.recordOpened(key: books[1].id, at: Date(timeIntervalSince1970: 200))
        let relaunched = MEBLibrary(defaults: defaults)
        #expect(MEBLibrary.mostRecent(in: books, openedAt: relaunched.openedAt)?.id == books[1].id)
        #expect(MEBLibrary.mostRecent(in: [books[0]], openedAt: relaunched.openedAt)?.id == books[0].id)
        #expect(MEBLibrary.mostRecent(in: [], openedAt: relaunched.openedAt) == nil)
        #expect(MEBLibrary.mostRecent(in: books, openedAt: [:]) == nil)
    }

    /// Gerçek kitaplardan alınmış dizin satırları (biyoloji: noktalı ve bölünmüş başlık; tarih: karışık; fizik: noktasız).
    private let dotted = """
    7
    Yaşam
    Güvenlik Sembolleri ................................................................................. 10
    Kitabın Tanıtımı ........................................................................................ 11
    YAŞAM BİLİMİ: BİYOLOJİ ................................................... 16
    1.1. BİYOLOJİNİN ÖNEMİ VE BİYOLOJİ BİLİMİNİN
    GELİŞMESİNDEKİ DÖNÜM NOKTALARI ........................... 16
    Biyolojinin Tanımı ve Önemi ......................................... 17
    1.2. BİLİMİN DOĞASI VE BİLİMSEL ARAŞTIRMA SÜREÇLERİ..22
    Bilim ve Bilimin Doğası................................................... 22
    1.3. BİLİM ETİĞİ ........................................................... 30
    1.4. CANLILARIN ORTAK ÖZELLİKLERİ ............................... 33
    Metabolizma ............................................................. 36
    TEMEL BİLEŞENLER ............................................................. 44
    1.5. İNORGANİK MOLEKÜLLER............................................... 44
    1.6. ORGANİK MOLEKÜLLER ............................................... 54
    """
    private let plain = """
    İÇİNDEKİLER
    KİTABIN TANITIMI 9
    4. ÜNİTE 4. ÜNİTE ENERJİ 206
    4.1. İÇ ENERJİ, ISI
    SICAKLIK ARASINDAKİ İLİŞKİ 210
    4.2.1. Termometreler 215
    4.3. HÂL DEĞİŞİMİ 226
    4.4. ISIL DENGE 236
    Kitabın Tanıtımı ............................................ 8-9
    SÖZLÜK 265
    """

    @Test func printedContentsBecomeAnIndex() {
        let entries = MEBBookIndex.parse(pages: [dotted])
        #expect(entries.count == 13 && entries.first == .init(title: "Güvenlik Sembolleri", page: 10, level: 2))
        // İki satıra bölünmüş başlık birleşir; sayfa başındaki "7" ve "Yaşam" başlığa karışmaz.
        #expect(entries.contains(.init(title: "1.1. BİYOLOJİNİN ÖNEMİ VE BİYOLOJİ BİLİMİNİN GELİŞMESİNDEKİ DÖNÜM NOKTALARI", page: 16, level: 1)))
        #expect(entries.contains(.init(title: "1.2. BİLİMİN DOĞASI VE BİLİMSEL ARAŞTIRMA SÜREÇLERİ", page: 22, level: 1)) && entries.contains(.init(title: "TEMEL BİLEŞENLER", page: 44, level: 0)))
        // Noktasız dizin; sırayı bozan satır ("8-9") atılır.
        let other = MEBBookIndex.parse(pages: [plain])
        #expect(other.map(\.page) == [9, 206, 210, 215, 226, 236, 265] && other[2].title == "4.1. İÇ ENERJİ, ISI SICAKLIK ARASINDAKİ İLİŞKİ" && other[4].title == "4.3. HÂL DEĞİŞİMİ")
        // Dizin olmayan sayfa: sonu sayıyla biten tek tük satır girdi sayılmaz.
        let body = "Canlıların ortak özellikleri vardır.\nBu bölümde hücreyi inceleyeceğiz.\nSoru 12\nDeney sonuçlarını tabloya yazınız.\nYaşam\nBilim insanları gözlem yapar."
        #expect(MEBBookIndex.parse(pages: [body]).isEmpty && MEBBookIndex.parse(pages: [""]).isEmpty)
    }

    @Test func topicIsMatchedToItsPagesInTheBook() {
        let index = MEBBookIndex(entries: MEBBookIndex.parse(pages: [dotted]), offset: 0)
        func title(_ topic: String) -> String? { index.match(topic).map { index.entries[$0].title } }
        #expect(title("Canlıların Ortak Özellikleri") == "1.4. CANLILARIN ORTAK ÖZELLİKLERİ" && title("İnorganik Moleküller") == "1.5. İNORGANİK MOLEKÜLLER")
        #expect(title("Bilim Etiği") == "1.3. BİLİM ETİĞİ" && title("Biyolojinin Önemi") == "Biyolojinin Tanımı ve Önemi" && title("Fotosentez") == nil && title("  ") == nil)
        // Konu, aynı ya da üst düzeydeki bir sonraki başlığa kadar sürer.
        #expect(index.pages(for: "Canlıların Ortak Özellikleri", pageCount: 184) == 32..<43 && index.pages(for: "Bilim Etiği", pageCount: 184) == 29..<32)
        #expect(index.pages(for: "Organik Moleküller", pageCount: 184) == 53..<65 && index.pages(for: "Organik Moleküller", pageCount: 40) == nil && index.pages(for: "Fotosentez", pageCount: 184) == nil)
        // Basılı numara ile PDF sırası farklıysa (kapak sayfaları sayılmamışsa) fark eklenir.
        #expect(MEBBookIndex(entries: index.entries, offset: 2).pages(for: "Bilim Etiği", pageCount: 184) == 31..<34)
        #expect(MEBBookIndex.offset(samples: [(index: 20, text: "19\nMetin"), (index: 26, text: "Başlık\nmetin\n25"), (index: 32, text: "resim"), (index: 38, text: "37\nMetin")]) == 2)
        // Tek tük sayı satırı (şık, tablo hücresi) farkı belirlemez.
        #expect(MEBBookIndex.offset(samples: [(index: 20, text: "3\nşık"), (index: 26, text: "metin")]) == 0 && MEBBookIndex.offset(samples: []) == 0)
        #expect(MEBBookIndex.stems("Canlıların Ortak Özellikleri ve Virüsler") == ["canli", "ortak", "özell", "virüs"] && MEBBookIndex.stems("SCHOOL LIFE") == MEBBookIndex.stems("School Life"))
        // "4.2.1." alt başlıktır; "4.2." konusunu bitirmez.
        #expect(MEBBookIndex.level("4.2. ISI VE SICAKLIK") == 1 && MEBBookIndex.level("4.2.1. Termometreler") == 2 && MEBBookIndex.level("TEMEL BİLEŞENLER") == 0 && MEBBookIndex.level("Bilimsel Yöntem") == 2)
        let physics = MEBBookIndex(entries: MEBBookIndex.parse(pages: [plain]), offset: 0)
        #expect(physics.pages(for: "İç Enerji Isı Sıcaklık Arasındaki İlişki", pageCount: 272) == 209..<225)
    }

    @Test func pageRangeIsClampedToTheDocument() {
        #expect(PDFPageText.range(from: 33, to: 43, count: 184) == 33...43 && PDFPageText.range(from: 43, to: 33, count: 184) == 33...43)
        #expect(PDFPageText.range(from: 0, to: 500, count: 184) == 1...40 && PDFPageText.range(from: 180, to: 999, count: 184) == 180...184)
        #expect(PDFPageText.range(from: 200, to: 210, count: 184) == 184...184 && PDFPageText.range(from: 1, to: 1, count: 0) == nil)
    }

    @Test func textComesOnlyFromTheChosenPages() throws {
        // Üç sayfalık PDF: her sayfada o sayfaya özgü bir cümle.
        let file = FileManager.default.temporaryDirectory.appending(path: "meb-" + UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: file) }
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 560)
        try UIGraphicsPDFRenderer(bounds: bounds).writePDF(to: file) { context in
            for word in ["Mitokondri", "Kloroplast", "Ribozom"] {
                context.beginPage()
                (String(repeating: "\(word) hücrenin önemli bir organelidir. ", count: 8) as NSString).draw(in: bounds.insetBy(dx: 30, dy: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
            }
        }
        let middle = PDFPageText.read(url: file, pages: 2...3)
        #expect(middle.contains("Kloroplast") && middle.contains("Ribozom") && !middle.contains("Mitokondri"))
        #expect(PDFPageText.read(url: file, pages: 1...1).contains("Mitokondri") && PDFPageText.read(url: file, pages: 9...12).contains("Ribozom"))
        #expect(PDFPageText.read(url: file.appendingPathExtension("yok"), pages: 1...2).isEmpty && PDFPageText.thumbnail(url: file, page: 2) != nil && PDFPageText.thumbnail(url: file, page: 7) == nil)
    }

    @Test func readerRestoresOnlyValidPages() {
        #expect(MEBReader.openingPage(start: nil, saved: 35, count: 184) == 35)
        #expect(MEBReader.openingPage(start: 8, saved: 35, count: 184) == 8)
        #expect(MEBReader.openingPage(start: nil, saved: 900, count: 184) == 184)
        #expect(MEBReader.openingPage(start: -3, saved: nil, count: 184) == 1)
        #expect(MEBReader.openingPage(start: nil, saved: nil, count: 0) == 1)
    }

    @Test func readerSuggestsTheTopicOfThePage() {
        #expect(MEBBookIndex.plainTitle("1.4. CANLILARIN ORTAK ÖZELLİKLERİ") == "Canlıların Ortak Özellikleri" && MEBBookIndex.plainTitle("2.3.1. Vektörlerin Özellikleri") == "Vektörlerin Özellikleri")
        #expect(MEBBookIndex.plainTitle("1.2. BİLİMİN DOĞASI VE BİLİMSEL ARAŞTIRMA SÜREÇLERİ") == "Bilimin Doğası ve Bilimsel Araştırma Süreçleri" && MEBBookIndex.plainTitle("Bilim ve Bilimin Doğası") == "Bilim ve Bilimin Doğası")
        let index = MEBBookIndex(entries: MEBBookIndex.parse(pages: [dotted]), offset: 0)
        // Sayfa 35, "1.4." konusunun içindedir (alt başlık "Metabolizma" 36'da başlar ama konu adı üst başlıktır).
        #expect(index.heading(atPDFPage: 35) == "Canlıların Ortak Özellikleri" && index.heading(atPDFPage: 37) == "Canlıların Ortak Özellikleri" && index.heading(atPDFPage: 44) == "İnorganik Moleküller")
        #expect(index.heading(atPDFPage: 3) == nil && MEBBookIndex(entries: index.entries, offset: 2).heading(atPDFPage: 35) == "Canlıların Ortak Özellikleri")
        #expect(MEBReader.savedPage("hiç-açılmamış-" + UUID().uuidString) == nil)
    }
}
