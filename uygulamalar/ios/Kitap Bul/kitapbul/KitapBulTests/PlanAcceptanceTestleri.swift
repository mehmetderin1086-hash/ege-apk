import Testing
import Foundation
import SwiftData
import CoreGraphics
import Vision
@testable import _01

nonisolated private final class PlanMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        let (status, data) = handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct PlanAcceptanceTestleri {
    nonisolated static var physicalBarcodeVerification: Bool {
#if targetEnvironment(simulator)
        return false
#else
        return true
#endif
    }
    @Test func catalogOnlyRecommendationsRejectUnknownAmbiguousAndUnavailableBooks() {
        let one = CatalogBook(book: Book(title: "Aynı Başlık", author: "Yazar A", quantity: 1))
        let two = CatalogBook(book: Book(title: "Aynı Başlık", author: "Yazar B", quantity: 1))
        let available = CatalogBook(book: Book(title: "Müsait Eser", author: "Y", quantity: 1))
        let loan = ActiveLoan(bookID: one.id, bookTitleSnapshot: one.title, studentName: "Öğrenci", studentClass: "7/A", dueDate: .now)
        let generated = AIRecommendationReply(recommendations: [
            .init(title: "Katalog Dışı", reason: "", bookID: UUID().uuidString),
            .init(title: "Aynı Başlık", reason: "Belirsiz"),
            .init(title: "Aynı Başlık", reason: "Ödünçte", bookID: one.id.uuidString),
            .init(title: "Yanlış model başlığı", reason: "Uygun", bookID: available.id.uuidString),
            .init(title: "Müsait Eser", reason: "Tekrar", bookID: available.id.uuidString)
        ], note: nil)
        let result = AIRecommendEngine.validated(generated, candidates: [one, two, available], loans: [loan])
        #expect(result.recommendations.count == 1)
        #expect(result.recommendations.first?.title == available.title)
        #expect(result.recommendations.first?.bookID == available.id.uuidString)
    }

    @Test func userEditsLockFieldsAndPreserveNewOCRProvenance() throws {
        var scanned = Book(title: "Taranan Kitap", author: "Yazar")
        scanned.fieldMetadata = BookFieldMetadata.encode(["title": .init(source: "gemini", confidence: 0.82)])
        let first = BookFieldMetadata.stampChanges(before: nil, after: scanned, source: "manual")
        #expect(BookFieldMetadata.decode(first.fieldMetadata)["title"]?.source == "gemini")
        #expect(!BookFieldMetadata.isLocked("title", metadata: first.fieldMetadata))
        var edited = first; edited.title = "Kullanıcının Düzelttiği Ad"
        let saved = BookFieldMetadata.stampChanges(before: first, after: edited, source: "manual")
        #expect(BookFieldMetadata.isLocked("title", metadata: saved.fieldMetadata))
        let roundTrip = try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(saved))
        #expect(roundTrip.fieldMetadata == saved.fieldMetadata)
    }

    @Test func studentCardIdentityDoesNotCollideForSameNameOrNumber() {
        let one = Student(name: "Aynı Ad", number: "101", className: "7/A")
        let two = Student(name: "Aynı Ad", number: "101", className: "7/B")
        #expect(StudentCardBuilder.barcodeValue(for: one) != StudentCardBuilder.barcodeValue(for: two))
        #expect(StudentCardBuilder.barcodeValue(for: one).hasPrefix("OGRID"))
    }

    @Test func reportExcelAndCSVKeepSameRowsAndEscapeContent() throws {
        let rows = [["Bölüm", "Gösterge", "Değer"], ["Türkçe & <özet>", "=1+1", "Ş, Ğ, İ, Ö, Ü, Ç"], ["A", "İade", "2"]]
        let csv = String(decoding: ReportTableExporter.csv(rows), as: UTF8.self)
        #expect(csv.contains("'=1+1"))
        let entries = ZIPReader.entries(in: ReportTableExporter.excel(rows))
        let sheet = try #require(entries.first { $0.name == "xl/worksheets/sheet1.xml" })
        let xml = String(decoding: sheet.data, as: UTF8.self)
        #expect(xml.contains("Türkçe &amp; &lt;özet&gt;"))
        #expect(xml.components(separatedBy: "<row ").count - 1 == rows.count)
        #expect(!xml.contains("<f>"))
    }

    @Test func atomicUsageLimitAndProxyNeedsNoClientCredential() async throws {
        let keys = [GeminiSettings.enabledKey, GeminiSettings.consentKey, GeminiSettings.proxyURLKey, GeminiUsage.limitKey, "geminiUsage"]
        let defaults = UserDefaults.standard, previous = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        let key = GeminiKeyStore.loadCustomKey()
        defer {
            keys.forEach { defaults.set(previous[$0] ?? nil, forKey: $0) }
            GeminiKeyStore.saveCustomKey(key); PlanMockURLProtocol.handler = nil
        }
        GeminiKeyStore.saveCustomKey("")
        defaults.set(true, forKey: GeminiSettings.enabledKey); defaults.set(true, forKey: GeminiSettings.consentKey)
        defaults.set("https://proxy.example.test/gemini", forKey: GeminiSettings.proxyURLKey)
        defaults.set(1, forKey: GeminiUsage.limitKey); GeminiUsage.reset()
        #expect(GeminiSettings.isActive)
        PlanMockURLProtocol.handler = { request in
            #expect(request.url?.host == "proxy.example.test")
            #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == nil)
            return (200, Data("{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"doğru\"}]},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":10,\"candidatesTokenCount\":2}}".utf8))
        }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [PlanMockURLProtocol.self]
        let client = GeminiClient(session: URLSession(configuration: config))
        let text = try await client.generateText(prompt: "test", maxAttempts: 1)
        #expect(text == "doğru")
        #expect(GeminiUsage.load().requests == 1)
        #expect(GeminiUsage.load().promptTokens == 10)
        await #expect(throws: GeminiError.self) { try await client.generateText(prompt: "sınır", maxAttempts: 1) }
        #expect(GeminiUsage.load().requests == 1)
    }

    @Test(.enabled(if: PlanAcceptanceTestleri.physicalBarcodeVerification,
        "Fiziksel cihaz kabulü: iOS 27 Simulator Vision, bağımsız üretilen Code128/QR kontrol görsellerinde de boş sonuç veriyor."))
    func printProofPDFsHaveReadableBarcodeAndQR() throws {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let code = "OGRID" + id.uuidString.replacingOccurrences(of: "-", with: "")
        var profile = LibraryPrintProfile(); profile.calibration = true
        let cards = StudentCardBuilder.build([.init(name: "Örnek Öğrenci", className: "7/A", number: "101", barcodeValue: code)], profile: profile)
        let labels = SpineLabelBuilder.build([.init(callNumber: "813 / YAZ", title: "Uzun Başlıklı Türkçe Kitap Ş Ğ İ Ö Ü Ç", accessionCode: "DEMO-0001", barcodeValue: "KBDEMO0001", bookID: id)], template: .buyuk, profile: profile)
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("Plan-QA")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try cards.write(to: directory.appendingPathComponent("Ogrenci-Karti-Prova.pdf"), options: .atomic)
        try labels.write(to: directory.appendingPathComponent("Kitap-Etiketi-Prova.pdf"), options: .atomic)
        func barcodeValues(_ data: Data) throws -> [String] {
            let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
            let page = try #require(document.page(at: 1))
            let rect = page.getBoxRect(.mediaBox)
            let context = try #require(CGContext(data: nil, width: Int(rect.width * 3), height: Int(rect.height * 3), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: rect.width * 3, height: rect.height * 3))
            context.scaleBy(x: 3, y: 3); context.drawPDFPage(page)
            let image = try #require(context.makeImage())
            let request = VNDetectBarcodesRequest()
            request.revision = VNDetectBarcodesRequestRevision3
#if targetEnvironment(simulator)
            request.usesCPUOnly = true
#endif
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap(\.payloadStringValue)
        }
        #expect(try barcodeValues(cards).contains(code))
        #expect(try barcodeValues(labels).contains(KitapQR.url(for: id).absoluteString))
    }
}
