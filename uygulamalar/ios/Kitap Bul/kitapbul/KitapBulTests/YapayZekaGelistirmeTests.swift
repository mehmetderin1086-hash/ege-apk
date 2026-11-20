import Testing
import Foundation
import SwiftData
import UIKit
import AVFoundation
@testable import _01

// Paket 6 (Yapay zekâ ve ses): sesli kayıt kuyruğu, asistan yerel yanıtı, takma ad koruması,
// Gemini istek yapılandırması, ses oturumu koordinatörü, AI değişiklik günlüğü ve görsel sıkıştırma.
// Ağ yok: istekler sahte URLProtocol ile, ses donanımı sahte donanımla doğrulanır.

// MARK: - Sahte ağ

nonisolated private final class YZSayac: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    @discardableResult func artir() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
    var deger: Int { lock.lock(); defer { lock.unlock() }; return value }
}

nonisolated private final class YZMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest, Data) -> Result<(Int, Data), Error>)?
    nonisolated(unsafe) static var bodies: [Data] = []
    private static let lock = NSLock()

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        handler = nil; bodies = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            stream.close()
        }
        Self.lock.lock()
        Self.bodies.append(body)
        let handler = Self.handler
        Self.lock.unlock()
        guard let handler else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        switch handler(request, body) {
        case .success(let (status, data)):
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                                                  headerFields: ["Content-Type": "application/json"])!,
                                cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [YZMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private func yzOK(_ text: String, finish: String = "STOP") -> (Int, Data) {
    let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    return (200, Data("{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"\(escaped)\"}]},\"finishReason\":\"\(finish)\"}],\"usageMetadata\":{\"promptTokenCount\":10,\"candidatesTokenCount\":2}}".utf8))
}

/// Gemini ayarlarını sahte vekil + onay ile hazırlar, bitince eski değerleri geri yazar.
@MainActor
private func yzGeminiOrtami(limit: Int = 0, _ body: () async throws -> Void) async throws {
    let keys = [GeminiSettings.enabledKey, GeminiSettings.consentKey, GeminiSettings.proxyURLKey, GeminiUsage.limitKey, "geminiUsage", GeminiSettings.modelKey]
    let defaults = UserDefaults.standard
    let previous = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
    defer {
        keys.forEach { defaults.set(previous[$0] ?? nil, forKey: $0) }
        YZMockURLProtocol.reset()
        GeminiThinkingSupport.reset()
        GeminiDurumu.shared.refresh()
    }
    defaults.set(true, forKey: GeminiSettings.enabledKey)
    defaults.set(true, forKey: GeminiSettings.consentKey)
    defaults.set("http://localhost/gemini/", forKey: GeminiSettings.proxyURLKey)
    defaults.set(GeminiModel.flash.rawValue, forKey: GeminiSettings.modelKey)
    defaults.set(limit, forKey: GeminiUsage.limitKey)
    GeminiUsage.reset()
    GeminiThinkingSupport.reset()
    YZMockURLProtocol.reset()
    try await body()
}

private func yzClient() -> GeminiClient {
    GeminiClient(session: YZMockURLProtocol.session(), retryBaseDelay: 0)
}

private func yzContainer() throws -> ModelContainer {
    try ModelContainer(for: CatalogBook.self, ActiveLoan.self, BookCopy.self, Reservation.self, ScanWriteReceipt.self, LibraryEventOutbox.self,
                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
}

// MARK: - Sesli kayıt: bekleyen kuyruk (AI-06)

@MainActor
struct SesliKayitKuyruguTestleri {
    private func kayit(_ title: String, author: String? = nil, isbn: String? = nil, uncertain: [String]? = nil) -> SesliKitapKaydi {
        var kaydi = SesliKitapKaydi()
        kaydi.title = title
        kaydi.author = author
        kaydi.isbn = isbn
        kaydi.uncertain = uncertain
        return kaydi
    }

    @Test func yeniKitapEskisiniKuyrugaIndirirSilmez() {
        var kuyruk = BekleyenKayitKuyrugu()
        let ilk = kuyruk.push(kayit("Simyacı"))
        let ikinci = kuyruk.push(kayit("Küçük Prens"))
        #expect(kuyruk.count == 2)
        #expect(kuyruk.current?.title == "Küçük Prens")
        #expect(kuyruk.currentOperationID == ikinci)
        #expect(kuyruk.waitingCount == 1)
        kuyruk.removeCurrent()
        #expect(kuyruk.current?.title == "Simyacı")
        #expect(kuyruk.currentOperationID == ilk, "Kuyruğa inen kaydın işlem kimliği korunur")
        kuyruk.removeCurrent()
        #expect(kuyruk.isEmpty)
    }

    @Test func duzeltmeYalnizBastakiniDegistirir() {
        var kuyruk = BekleyenKayitKuyrugu()
        kuyruk.push(kayit("A"))
        kuyruk.push(kayit("B"))
        kuyruk.replaceCurrent(kayit("B düzeltildi"))
        #expect(kuyruk.ogeler.map { $0.kaydi.title } == ["B düzeltildi", "A"])
    }

    @Test func hepsiniKaydetKomutuTanınır() {
        #expect(VoiceBookEngine.localCommand(in: "hepsini kaydet") == .saveAll)
        #expect(VoiceBookEngine.localCommand(in: "Tümünü kaydet") == .saveAll)
        #expect(VoiceBookEngine.localCommand(in: "kaydet") == .save)
    }

    @Test func saveVeSupheliAlanOnizlemeyeDuser() {
        #expect(VoiceBookEngine.saveRoute(for: kayit("Simyacı", author: "Paulo Coelho", uncertain: ["author"])) == .preview)
    }

    @Test func saveSupheYokISBNYaDaYazarVarsaKaydeder() {
        #expect(VoiceBookEngine.saveRoute(for: kayit("Simyacı", isbn: "9789750719387", uncertain: [])) == .saveNow)
        #expect(VoiceBookEngine.saveRoute(for: kayit("Simyacı", author: "Paulo Coelho")) == .saveNow)
    }

    @Test func saveSupheYokAmaDogrulayiciYoksaOnizleme() {
        #expect(VoiceBookEngine.saveRoute(for: kayit("Simyacı")) == .preview)
        #expect(VoiceBookEngine.saveRoute(for: SesliKitapKaydi()) == .preview)
    }

    @Test func sohbetSozlugundeSilIptalSayilmaz() {
        #expect(VoiceBookEngine.localCommand(in: "sil", scope: .voice) == .cancel)
        #expect(VoiceBookEngine.localCommand(in: "sil", scope: .chat) == nil)
        #expect(VoiceBookEngine.localCommand(in: "iptal", scope: .chat) == .cancel)
        #expect(VoiceBookEngine.localCommand(in: "son kaydı sil", scope: .chat) == nil)
    }
}

// MARK: - Asistan: bulunamadı kartı, nesil kimliği, yerel yanıt

@MainActor
struct AsistanGelistirmeTestleri {
    @Test func bulunamadiKartiHataVeKitaplardaAraTakipSorusuTasir() {
        let card = AssistantEngine.notFoundCard(for: "Olmayan Kitap")
        #expect(card.isError)
        #expect(card.text.contains("Olmayan Kitap"))
        #expect(card.followUps.first?.hasPrefix(AssistantEngine.kitaplardaAraOnEki) == true)
    }

    @Test func gevsekAramaHatalıYazilanBasligiBulur() throws {
        let container = try yzContainer()
        let context = ModelContext(container)
        let kurk = CatalogBook(book: Book(title: "Kürk Mantolu Madonna", author: "Sabahattin Ali"))
        let yusuf = CatalogBook(book: Book(title: "Kuyucaklı Yusuf", author: "Sabahattin Ali"))
        [kurk, yusuf].forEach(context.insert)
        let found = AssistantTargetChoice.looseCandidates("Mantolu Madona", in: [kurk, yusuf])
        #expect(found.map(\.title) == ["Kürk Mantolu Madonna"])
        #expect(AssistantTargetChoice.looseCandidates("Hiç Alakasız", in: [kurk, yusuf]).isEmpty)
    }

    @Test func sayfadanCikinceEskiGorevYanitiKabulEdilmez() throws {
        let gate = VoiceEntryTaskGate()
        gate.activate()
        let eski = try #require(gate.currentToken)
        #expect(gate.accepts(eski))
        gate.deactivate()
        #expect(!gate.accepts(eski))
        gate.activate()
        #expect(!gate.accepts(eski), "Yeniden açılan sayfa eski nesil sonucunu kabul etmez")
    }

    @Test func yerelAsistanNiyetleriTanir() {
        #expect(YerelAsistan.intent(for: "Kaç kitap var?") == .kitapSayisi)
        #expect(YerelAsistan.intent(for: "Geciken ödünç var mı?") == .gecikenler)
        #expect(YerelAsistan.intent(for: "Kuyucaklı Yusuf var mı") == .kitapVarMi("kuyucakli yusuf"))
        #expect(YerelAsistan.intent(for: "Simyacı nerede?") == .kitapVarMi("simyaci"))
        #expect(YerelAsistan.intent(for: "5. sınıfa macera kitabı öner") == nil)
    }

    @Test func yerelAsistanKatalogdanYanitUretir() throws {
        let container = try yzContainer()
        let context = ModelContext(container)
        let a = CatalogBook(book: Book(title: "Kuyucaklı Yusuf", author: "Sabahattin Ali", quantity: 2, shelf: "3", cabinet: "B"))
        let b = CatalogBook(book: Book(title: "Simyacı", author: "Paulo Coelho"))
        let kalkan = CatalogBook(book: Book(title: "Düşülmüş", author: "X", isWithdrawn: true))
        [a, b, kalkan].forEach(context.insert)
        let gecikmis = ActiveLoan(bookID: a.id, bookTitleSnapshot: a.title, studentName: "Ayşe Yılmaz", studentClass: "7/A",
                                  dueDate: Calendar.current.date(byAdding: .day, value: -5, to: .now)!)
        context.insert(gecikmis)
        let books = [a, b, kalkan], loans = [gecikmis]

        let sayi = try #require(YerelAsistan.answer("Kaç kitap var?", books: books, loans: loans))
        #expect(sayi.text.contains("2 kitap"))
        #expect(sayi.text.contains("1 tanesi gecikmiş"))

        let geciken = try #require(YerelAsistan.answer("Geciken var mı?", books: books, loans: loans))
        #expect(geciken.text.contains("1 geciken"))
        #expect(geciken.text.contains("Ayşe Yılmaz"))
        #expect(geciken.bookIDs == [a.id])

        let var_ = try #require(YerelAsistan.answer("Kuyucaklı Yusuf var mı?", books: books, loans: loans))
        #expect(var_.text.contains("Kuyucaklı Yusuf"))
        #expect(var_.text.contains("boşta 1/2"))
        #expect(var_.bookIDs == [a.id])

        let yok = try #require(YerelAsistan.answer("Olmayan Kitap var mı?", books: books, loans: loans))
        #expect(yok.text.contains("bulamadım"))
        #expect(YerelAsistan.answer("Bana bir şiir yaz", books: books, loans: loans) == nil)
    }

    @Test func yerelYanitYalnizBaglantiVeSinirHatalarindaDevreye() {
        #expect(YerelAsistan.shouldAnswerLocally(after: GeminiError.network("x")))
        #expect(YerelAsistan.shouldAnswerLocally(after: GeminiError.limitReached(100)))
        #expect(YerelAsistan.shouldAnswerLocally(after: GeminiError.http(429, "")))
        #expect(!YerelAsistan.shouldAnswerLocally(after: GeminiError.missingKey))
        #expect(!YerelAsistan.shouldAnswerLocally(after: GeminiError.consentRequired))
    }
}

// MARK: - Takma ad koruması (AI-05 / AI-12)

@MainActor
struct TakmaAdKorumasiTestleri {
    @Test func kisaAdTurkceSozcukSiniriylaEslesir() {
        let aliases = PersonAliases()
        let out = aliases.pseudonymize("Canlı bir kitap ve Can'a ver", names: ["Can"])
        #expect(out.contains("Canlı"), "‘Canlı’ sözcüğü bozulmamalı")
        #expect(out.contains("Öğrenci 1"))
        #expect(!out.contains("Can'a"))
        #expect(aliases.restore(in: out) == "Canlı bir kitap ve Can'a ver")
    }

    @Test func halEkliAdSizmaz() {
        let aliases = PersonAliases()
        let out = aliases.pseudonymize("Mehmetin kitabı geç kaldı, Mehmet'e söyle", names: ["Mehmet"])
        #expect(!out.contains("Mehmet"))
        #expect(out.contains("kitabı geç kaldı"))
    }

    @Test func buyukKucukIVeDiacriticDuyarsiz() {
        let aliases = PersonAliases()
        #expect(!aliases.pseudonymize("ismail ışık iade etti", names: ["İsmail Işık"]).contains("ismail"))
        #expect(!aliases.pseudonymize("ISMAIL ISIK iade etti", names: ["İsmail Işık"]).lowercased().contains("ismail"))
        #expect(!aliases.pseudonymize("İSMAİL IŞIK iade etti", names: ["İsmail Işık"]).lowercased().contains("ismail"))
    }

    @Test func yazarAdiylaCakisanOgrenciAdiKorunur() {
        let aliases = PersonAliases()
        let korunan = aliases.pseudonymize("Orhan Pamuk romanları var mı", names: ["Orhan"], protecting: ["Orhan Pamuk"])
        #expect(korunan == "Orhan Pamuk romanları var mı")
        let degisen = aliases.pseudonymize("Orhan'a kitap ver", names: ["Orhan"], protecting: ["Orhan Pamuk"])
        #expect(degisen.contains("Öğrenci 1"))
    }

    @Test func uzunAdOnceDegisir() {
        let aliases = PersonAliases()
        let out = aliases.pseudonymize("Ali Veli Kaya geldi", names: ["Ali Veli", "Ali Veli Kaya"])
        #expect(out == "Öğrenci 1 geldi")
    }

    @Test func kayitsizKisiOdunçFiiliylaYakalanir() {
        let adlar = PersonAliases.kayitsizAdlar(in: "Ayşe'ye Simyacı'yı ver", known: [])
        #expect(adlar == ["Ayşe"])
        let iade = PersonAliases.kayitsizAdlar(in: "Ali Kaya iade etti", known: [])
        #expect(iade == ["Ali Kaya"])
        #expect(PersonAliases.kayitsizAdlar(in: "Ayşe'ye merhaba de", known: []).isEmpty, "Ödünç fiili yoksa ad sayılmaz")
    }

    @Test func kitapAdiYaDaKayitliKisiKayitsizSayilmaz() {
        let kitap = PersonAliases.kayitsizAdlar(in: "Madonna'ya ver", known: [], bookTitles: ["Kürk Mantolu Madonna"])
        #expect(kitap.isEmpty)
        let kayitli = PersonAliases.kayitsizAdlar(in: "Ayşe'ye ver", known: ["Ayşe Yılmaz"])
        #expect(kayitli.isEmpty)
    }

    @Test func kayitsizAdGecicTakmaAdlaGizlenir() {
        let aliases = PersonAliases()
        let soru = "Ayşe'ye Simyacı'yı ver"
        let adlar = PersonAliases.kayitsizAdlar(in: soru, known: [])
        let out = aliases.pseudonymize(soru, names: adlar)
        #expect(!out.contains("Ayşe"))
        #expect(out.contains("Simyacı"))
    }
}

// MARK: - Gemini istek yapılandırması (AI-08 / AI-13 / P-03)

@MainActor
@Suite(.serialized)
struct GeminiIstekYapilandirmasiTestleri {
    @Test func dusunmeButcesiModeleGoreSecilir() {
        #expect(GeminiThinking.off.config(for: .flash)?.thinkingBudget == 0)
        #expect(GeminiThinking.off.config(for: .flashLite)?.thinkingBudget == 0)
        #expect(GeminiThinking.off.config(for: .pro)?.thinkingBudget == GeminiThinking.proMinimumBudget)
        #expect(GeminiThinking.auto.config(for: .flash) == nil)
    }

    @Test func thinkingConfigJSONdaDogruKodlanir() throws {
        let off = GeminiGenerationConfig(temperature: 0.1, thinkingConfig: .init(thinkingBudget: 0))
        let offText = String(decoding: try JSONEncoder().encode(off), as: UTF8.self)
        #expect(offText.contains("\"thinkingConfig\":{\"thinkingBudget\":0}"))
        let auto = GeminiGenerationConfig(temperature: 0.1)
        #expect(!String(decoding: try JSONEncoder().encode(auto), as: UTF8.self).contains("thinkingConfig"))
    }

    @Test func eskiKullanimKaydiYeniAlanlarsizCozulur() throws {
        let legacy = #"{"month":"2026-10","requests":3,"promptTokens":5,"outputTokens":6,"failures":1}"#
        let snapshot = try JSONDecoder().decode(GeminiUsage.Snapshot.self, from: Data(legacy.utf8))
        #expect(snapshot.requests == 3)
        #expect(snapshot.retries == 0)
        #expect(snapshot.byModel.isEmpty)
    }

    @Test func yeniden429SonrasiBasariTekIstekSayilir() async throws {
        try await yzGeminiOrtami {
            let sayac = YZSayac()
            YZMockURLProtocol.handler = { _, _ in
                sayac.artir() == 1 ? .success((429, Data("{\"error\":{\"code\":429,\"message\":\"yavaş\"}}".utf8))) : .success(yzOK("doğru"))
            }
            let text = try await yzClient().generateText(prompt: "test", maxAttempts: 3)
            #expect(text == "doğru")
            let usage = GeminiUsage.load()
            #expect(usage.requests == 1, "Yeniden deneme aylık sınırı tüketmez")
            #expect(usage.retries == 1)
            #expect(usage.byModel[GeminiModel.flash.rawValue]?.requests == 1)
            #expect(usage.failures == 1)
        }
    }

    @Test func maxTokensJSONdaButceIkiyeKatlanipYenidenDenenir() async throws {
        try await yzGeminiOrtami {
            let sayac = YZSayac()
            YZMockURLProtocol.handler = { _, _ in
                sayac.artir() == 1
                    ? .success((200, Data("{\"candidates\":[{\"content\":{},\"finishReason\":\"MAX_TOKENS\"}]}".utf8)))
                    : .success(yzOK("{\"a\":1}"))
            }
            let text = try await yzClient().generateText(prompt: "json", maxOutputTokens: 1000, json: true, maxAttempts: 1)
            #expect(text == "{\"a\":1}")
            #expect(YZMockURLProtocol.bodies.count == 2)
            func budget(_ body: Data) -> Int? {
                let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
                return ((object?["generationConfig"] as? [String: Any])?["maxOutputTokens"] as? Int)
            }
            #expect(budget(YZMockURLProtocol.bodies[0]) == 1000)
            #expect(budget(YZMockURLProtocol.bodies[1]) == 2000)
            #expect(GeminiUsage.load().requests == 1)
        }
    }

    @Test func maxTokensYalnizBirKezYenidenDenenir() async throws {
        try await yzGeminiOrtami {
            YZMockURLProtocol.handler = { _, _ in
                .success((200, Data("{\"candidates\":[{\"content\":{},\"finishReason\":\"MAX_TOKENS\"}]}".utf8)))
            }
            await #expect(throws: GeminiError.self) {
                try await yzClient().generateText(prompt: "json", maxOutputTokens: 1000, json: true, maxAttempts: 1)
            }
            #expect(YZMockURLProtocol.bodies.count == 2)
        }
    }

    @Test func zamanAsimiAgHatasinaDoner() async throws {
        try await yzGeminiOrtami {
            YZMockURLProtocol.handler = { _, _ in .failure(URLError(.timedOut)) }
            do {
                _ = try await yzClient().generateText(prompt: "x", maxAttempts: 1)
                Issue.record("Hata bekleniyordu")
            } catch let error as GeminiError {
                guard case .network = error else { Issue.record("network bekleniyordu: \(error)"); return }
            }
        }
    }

    @Test func aylikSinirDolunca_finishRequestCagrilmaz() async throws {
        try await yzGeminiOrtami(limit: 1) {
            YZMockURLProtocol.handler = { _, _ in .success(yzOK("bir")) }
            _ = try await yzClient().generateText(prompt: "ilk", maxAttempts: 1)
            let once = GeminiUsage.load()
            #expect(once.requests == 1)
            await #expect(throws: GeminiError.self) {
                try await yzClient().generateText(prompt: "ikinci", maxAttempts: 1)
            }
            let sonra = GeminiUsage.load()
            #expect(sonra == once, "Sınır dolunca hiçbir sayaç (istek, jeton, hata) değişmemeli")
            #expect(YZMockURLProtocol.bodies.count == 1)
        }
    }

    @Test func modelThinkingConfigiReddederseAlanDusurulurVeOgrenilir() async throws {
        try await yzGeminiOrtami {
            YZMockURLProtocol.handler = { _, body in
                String(decoding: body, as: UTF8.self).contains("thinkingConfig")
                    ? .success((400, Data("{\"error\":{\"code\":400,\"message\":\"Unknown name thinkingConfig\"}}".utf8)))
                    : .success(yzOK("tamam"))
            }
            let text = try await yzClient().generateText(prompt: "ocr", maxAttempts: 1, thinking: .off)
            #expect(text == "tamam")
            let bodies = YZMockURLProtocol.bodies.map { String(decoding: $0, as: UTF8.self) }
            #expect(bodies.count == 2)
            #expect(bodies[0].contains("thinkingConfig"))
            #expect(!bodies[1].contains("thinkingConfig"))
            // Öğrenildi: sonraki istek alanı hiç göndermez
            _ = try await yzClient().generateText(prompt: "ocr2", maxAttempts: 1, thinking: .off)
            let sonraki = String(decoding: YZMockURLProtocol.bodies[2], as: UTF8.self)
            #expect(YZMockURLProtocol.bodies.count == 3)
            #expect(!sonraki.contains("thinkingConfig"))
        }
    }

    @Test func varsayilanIstekDusunmeyiKapatir() async throws {
        try await yzGeminiOrtami {
            YZMockURLProtocol.handler = { _, _ in .success(yzOK("x")) }
            _ = try await yzClient().generateText(prompt: "ocr", maxAttempts: 1)
            #expect(String(decoding: YZMockURLProtocol.bodies[0], as: UTF8.self).contains("\"thinkingBudget\":0"))
            _ = try await yzClient().generateText(prompt: "sohbet", maxAttempts: 1, thinking: .auto)
            #expect(!String(decoding: YZMockURLProtocol.bodies[1], as: UTF8.self).contains("thinkingConfig"))
        }
    }

    @Test func gorselHazirlayiciUstSinirKoyar() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 3200, height: 2400), format: {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            return format
        }())
        let big = renderer.jpegData(withCompressionQuality: 0.95) { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3200, height: 2400))
            UIColor.white.setFill()
            context.fill(CGRect(x: 100, y: 100, width: 1500, height: 900))
        }
        let small = try #require(GeminiImagePreparer.jpegData(from: big, maxPixel: 1600, quality: 0.8))
        let image = try #require(UIImage(data: small))
        #expect(max(image.size.width * image.scale, image.size.height * image.scale) <= 1600)
        #expect(small.count < big.count)
    }

    @Test func gorselSikistirmaYalnizEsigiAsanlariAdayYapar() throws {
        let context = ModelContext(try yzContainer())
        let buyuk = CatalogBook(book: Book(title: "Büyük", author: "A"))
        buyuk.backCoverData = Data(repeating: 1, count: 3000)
        let kucuk = CatalogBook(book: Book(title: "Küçük", author: "B"))
        kucuk.imprintData = Data(repeating: 1, count: 500)
        [buyuk, kucuk].forEach(context.insert)
        let adaylar = GorselSikistirmaMotoru.adaylar(in: [buyuk, kucuk], esik: 1000)
        #expect(adaylar.map(\.bookID) == [buyuk.id])
        #expect(adaylar.first?.backBytes == 3000)
        #expect(GorselSikistirmaMotoru.adaylar(in: [buyuk, kucuk], esik: 5000).isEmpty)
    }

    @Test func gorselSikistirmaKucultemezseDokunmaz() {
        #expect(GorselSikistirmaMotoru.sikistir(Data("jpeg değil".utf8)) == nil)
    }
}

// MARK: - GeminiDurumu ve erişilebilirlik probu

@MainActor
@Suite(.serialized)
struct GeminiDurumuTestleri {
    @Test func durumOnbellekliAyarlardanOkunur() throws {
        let defaults = UserDefaults.standard
        let keys = [GeminiSettings.enabledKey, GeminiSettings.consentKey, GeminiSettings.proxyURLKey]
        let previous = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer { keys.forEach { defaults.set(previous[$0] ?? nil, forKey: $0) }; GeminiDurumu.shared.refresh() }
        defaults.set(true, forKey: GeminiSettings.enabledKey)
        defaults.set(true, forKey: GeminiSettings.consentKey)
        defaults.set("http://localhost/gemini/", forKey: GeminiSettings.proxyURLKey)
        GeminiDurumu.shared.refresh()
        #expect(GeminiDurumu.shared.isActive)
        defaults.set(false, forKey: GeminiSettings.consentKey)
        GeminiDurumu.shared.refresh()
        #expect(!GeminiDurumu.shared.isActive)
        #expect(GeminiDurumu.shared.isActive == GeminiSettings.isActive)
    }

    @Test func probUcDurumuAyirir() async {
        defer { YZMockURLProtocol.reset() }
        let url = URL(string: "https://example.test/")!
        YZMockURLProtocol.handler = { request, _ in
            #expect(request.httpMethod == "HEAD")
            return .success((404, Data()))
        }
        #expect(await GeminiReachability.classify(url: url, session: YZMockURLProtocol.session()) == .ulasilabilir)
        YZMockURLProtocol.handler = { _, _ in .failure(URLError(.timedOut)) }
        #expect(await GeminiReachability.classify(url: url, session: YZMockURLProtocol.session()) == .engelliYavas)
        YZMockURLProtocol.handler = { _, _ in .failure(URLError(.notConnectedToInternet)) }
        #expect(await GeminiReachability.classify(url: url, session: YZMockURLProtocol.session()) == .cevrimdisi)
    }

    @Test func engelliDurumdaSesVeOCRPolitikasi() {
        let reachability = GeminiReachability.shared
        #expect(GeminiReachability.ttsTimeout == 6)
        #expect(GeminiReachability.blockedOCRTimeout == 8)
        #expect(reachability.durum != .engelliYavas || reachability.isBlockedOrOffline)
    }
}

// MARK: - Ses oturumu koordinatörü (AI-10 / AI-03)

nonisolated private final class SahteSesDonanimi: SesDonanimi, @unchecked Sendable {
    private let lock = NSLock()
    private var counts = (activate: 0, close: 0, reapply: 0)
    var activate: Int { lock.lock(); defer { lock.unlock() }; return counts.activate }
    var close: Int { lock.lock(); defer { lock.unlock() }; return counts.close }
    var reapply: Int { lock.lock(); defer { lock.unlock() }; return counts.reapply }
    func etkinlestir() throws { lock.lock(); counts.activate += 1; lock.unlock() }
    func kapat() { lock.lock(); counts.close += 1; lock.unlock() }
    func yenidenUygula() throws { lock.lock(); counts.reapply += 1; lock.unlock() }
}

@MainActor
private final class SahteKaydedici: SesKaydedici {
    var stopped = 0
    func stopAndWait() async { stopped += 1 }
}

@MainActor
private func yzBekle(_ kosul: () -> Bool, saniye: Double = 2) async -> Bool {
    let bitis = ContinuousClock.now + .seconds(saniye)
    while !kosul(), ContinuousClock.now < bitis { try? await Task.sleep(for: .milliseconds(10)) }
    return kosul()
}

@MainActor
struct SesOturumuTestleri {
    private func yeni() -> (SesOturumu, SahteSesDonanimi, SahteKaydedici) {
        let donanim = SahteSesDonanimi()
        let oturum = SesOturumu(donanim: donanim, center: NotificationCenter(), gozlemle: false)
        let kaydedici = SahteKaydedici()
        oturum.kaydedici = kaydedici
        return (oturum, donanim, kaydedici)
    }

    @Test func sistemPasiflestirinceDinlemeDurur() async throws {
        let (oturum, _, kaydedici) = yeni()
        var bildirildi = false
        oturum.onInterruptionBegan = { bildirildi = true }
        try await oturum.beginRecording()
        oturum.handleSessionInactive(bySystem: true)
        #expect(bildirildi)
        #expect(await yzBekle { kaydedici.stopped == 1 })
        #expect(oturum.kullanim == .bos)
    }

    @Test func kendiKapatmamizKesintiSayilmaz() async throws {
        let (oturum, _, kaydedici) = yeni()
        var bildirildi = false
        oturum.onInterruptionBegan = { bildirildi = true }
        try await oturum.beginRecording()
        oturum.handleSessionInactive(bySystem: false)
        #expect(!bildirildi)
        #expect(kaydedici.stopped == 0)
        #expect(oturum.kullanim == .kayit)
    }

    @Test func yalnizDevamOnerisindeYenidenDinler() {
        let (oturum, _, _) = yeni()
        var devam = 0
        oturum.onInterruptionResume = { devam += 1 }
        oturum.handleResumptionRecommendation(shouldResume: false)
        #expect(devam == 0)
        oturum.handleResumptionRecommendation(shouldResume: true)
        #expect(devam == 1)
    }

    @Test func hoparlorCalarkenKayitBeklerBitinceBaslar() async throws {
        let (oturum, _, _) = yeni()
        let calma = try await oturum.beginPlayback()
        var basladi = false
        let gorev = Task { @MainActor in
            try await oturum.beginRecording()
            basladi = true
        }
        try await Task.sleep(for: .milliseconds(150))
        #expect(!basladi, "Hoparlör çalarken mikrofon açılmamalı")
        await oturum.release(calma)
        #expect(await yzBekle { basladi })
        _ = try await gorev.value
        #expect(oturum.kullanim == .kayit)
    }

    @Test func calmaOncesiMikrofonKapanmasiGaranti() async throws {
        let (oturum, _, kaydedici) = yeni()
        try await oturum.beginRecording()
        #expect(oturum.kullanim == .kayit)
        try await oturum.beginPlayback()
        #expect(kaydedici.stopped == 1, "beginPlayback dönerken mikrofon kapanmış olmalı")
        #expect(oturum.kullanim == .oynatma)
    }

    @Test func eskiSahibinBirakmasiYeniOturumuKapatmaz() async throws {
        let (oturum, donanim, _) = yeni()
        let birinci = try await oturum.beginRecording()
        await oturum.release(birinci)
        let ikinci = try await oturum.beginRecording()
        let kapanisOnce = donanim.close
        await oturum.release(birinci)
        #expect(oturum.kullanim == .kayit)
        #expect(donanim.close == kapanisOnce)
        await oturum.release(ikinci)
        #expect(oturum.kullanim == .bos)
    }

    @Test func rotaDegisimindeKategoriYenidenUygulanir() async throws {
        let (oturum, donanim, _) = yeni()
        oturum.handleRouteChange([AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        #expect(oturum.yenidenUygulamaSayisi == 0, "Oturum boşken bir şey yapılmaz")
        try await oturum.beginRecording()
        oturum.handleRouteChange([AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        #expect(oturum.yenidenUygulamaSayisi == 1)
        #expect(await yzBekle { donanim.reapply == 1 })
        // Kendi kategori değişimimiz döngü üretmemeli
        oturum.handleRouteChange([AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.categoryChange.rawValue])
        #expect(oturum.yenidenUygulamaSayisi == 1)
    }
}

// MARK: - AI değişiklik günlüğü (P-04)

@MainActor
@Suite(.serialized)
struct AIDegisiklikGunlukTestleri {
    private func ortam(_ govde: (ModelContext) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("yz-gunluk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        AIDegisiklikGunlugu.directoryOverride = dir
        defer { AIDegisiklikGunlugu.directoryOverride = nil; try? FileManager.default.removeItem(at: dir) }
        try govde(ModelContext(try yzContainer()))
    }

    @Test func yazGeriAlEskiDegeriDondurur() throws {
        try ortam { context in
            let kitap = CatalogBook(book: Book(title: "Test", author: "Y"))
            context.insert(kitap)
            let gunluk = AIDegisiklikToplayici(tool: "tamamla")
            let degisti = AICompletionEngine.apply(AICompletionItem(index: 0, category: "Roman", language: "Türkçe", summary: nil),
                                                   to: kitap, journal: gunluk)
            #expect(degisti)
            #expect(gunluk.commit())
            let son = try #require(AIDegisiklikGunlugu.lastBatch())
            #expect(son.tool == "tamamla")
            #expect(Set(son.entries.map(\.field)) == ["category", "language"])
            #expect(son.entries.first { $0.field == "category" }?.oldValue == "")
            #expect(son.entries.first { $0.field == "category" }?.newValue == "Roman")

            let sonuc = try AIDegisiklikGunlugu.undoLastBatch(books: [kitap], context: context)
            #expect(sonuc == AIDegisiklikGunlugu.GeriAlmaSonucu(restored: 2, skipped: 0))
            #expect(kitap.category == nil)
            #expect(kitap.language == nil)
            #expect(BookFieldMetadata.decode(kitap.fieldMetadata)["category"] == nil, "Gemini damgası da kalkar")
            #expect(AIDegisiklikGunlugu.lastBatch() == nil)
        }
    }

    @Test func sonradanElleDegisenAlanaDokunulmaz() throws {
        try ortam { context in
            let kitap = CatalogBook(book: Book(title: "Test", author: "Y"))
            context.insert(kitap)
            let gunluk = AIDegisiklikToplayici(tool: "tamamla")
            _ = AICompletionEngine.apply(AICompletionItem(index: 0, category: "Roman", language: "Türkçe", summary: nil), to: kitap, journal: gunluk)
            gunluk.commit()
            kitap.category = "Şiir" // kullanıcı sonradan değiştirdi
            let sonuc = try AIDegisiklikGunlugu.undoLastBatch(books: [kitap], context: context)
            #expect(sonuc.restored == 1)
            #expect(sonuc.skipped == 1)
            #expect(kitap.category == "Şiir")
            #expect(kitap.language == nil)
        }
    }

    @Test func iptalEdilenYazimGunluğeGirmez() throws {
        try ortam { context in
            let kitap = CatalogBook(book: Book(title: "Test", author: "Y"))
            context.insert(kitap)
            let gunluk = AIDegisiklikToplayici(tool: "tamamla")
            _ = AICompletionEngine.apply(AICompletionItem(index: 0, category: "Roman", language: nil, summary: nil), to: kitap, journal: gunluk)
            gunluk.discard()
            #expect(gunluk.commit())
            #expect(AIDegisiklikGunlugu.lastBatch() == nil)
        }
    }

    @Test func kategoriTutarliligiGunlukleyipGeriAlinir() throws {
        try ortam { context in
            let kitap = CatalogBook(book: Book(title: "Test", author: "Y", category: "roman"))
            context.insert(kitap)
            let sayi = try CategoryConsistencyEngine.apply(["roman": "Roman"], to: [kitap], context: context, aiMapped: ["roman"])
            #expect(sayi == 1)
            #expect(kitap.category == "Roman")
            let son = try #require(AIDegisiklikGunlugu.lastBatch())
            #expect(son.tool == "kategori")
            let sonuc = try AIDegisiklikGunlugu.undoLastBatch(books: [kitap], context: context)
            #expect(sonuc.restored == 1)
            #expect(kitap.category == "roman")
        }
    }

    @Test func eskiSatirlarVeBozukSatirTolereEdilir() throws {
        try ortam { context in
            let kitap = CatalogBook(book: Book(title: "Test", author: "Y"))
            context.insert(kitap)
            let gunluk = AIDegisiklikToplayici(tool: "zenginlestirme")
            _ = AICompletionEngine.apply(AICompletionItem(index: 0, category: "Roman", language: nil, summary: nil), to: kitap, journal: gunluk)
            gunluk.commit()
            let url = try #require(AIDegisiklikGunlugu.url)
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("{yarım yazılmış satır\n".utf8))
            try handle.close()
            #expect(AIDegisiklikGunlugu.all().count == 1)
        }
    }
}

// MARK: - AIEngines: iptal sonrası sonuç yazılmaz (G6)

@MainActor
struct DilimlemeIptalTestleri {
    @Test func iptalEdilenDilimlemeSonucDondurmez() async {
        let gorev = Task<Void, Error> { @MainActor in
            while !Task.isCancelled { await Task.yield() }
            _ = try await ShelfScanEngine.sliceOffMain(Data(), rows: [])
        }
        gorev.cancel()
        await #expect(throws: CancellationError.self) { try await gorev.value }
    }
}
