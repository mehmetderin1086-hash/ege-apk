import Foundation
import Synchronization
import Testing
@testable import Ikra

/// Uygulama içi motor: sunucu mantığı uygulamanın kendi sürecinde çalışır. Buradaki testler ağa çıkmaz (canlı olan hariç).
/// Motorun askı durumu uygulama genelinde tektir; testler bu yüzden sırayla çalışır.
@Suite("Gömülü motor", .serialized) struct EmbeddedEngineTests {
    nonisolated private struct Status: Decodable, Sendable {
        struct Providers: Decodable, Sendable { var transport: String? }
        var ok: Bool?
        var features: [String]?
        var providers: Providers?
    }
    nonisolated private static let live = ProcessInfo.processInfo.environment["LIVE_ENGINE"] == "1"

    /// Köprünün bildirdiği "yedek yolu kullan" sürelerini toplar.
    nonisolated private final class Waits: Sendable {
        private let values = Mutex<[TimeInterval]>([])
        func add(_ value: TimeInterval) { values.withLock { $0.append(value) } }
        var all: [TimeInterval] { values.withLock { $0 } }
    }

    /// Yalnız köprüyü sınayan sahte motor paketi: `handle` işlevinin gövdesi verilen JavaScript'tir.
    nonisolated private static func fake(_ handle: String, waits: Waits = Waits()) -> EmbeddedEngine {
        EmbeddedEngine(source: { "globalThis.__engine = { handle: function (call, path, body) { \(handle) } };" }, key: { "x" }, unavailable: { waits.add($0) })
    }

    @Test func motorUygulamaIcindeBaslarVeDurumBildirir() async throws {
        let status: Status = try await EmbeddedEngine.shared.call("/v1/status", [String: String]())
        #expect(status.ok == true)
        #expect(status.providers?.transport == "anthropic")
        #expect(status.features?.contains("podcast2") == true)
        // Uygulama içinde kalıcı senaryo işleri ve sunucu yedeği yoktur.
        #expect(status.features?.contains("scriptJobs") == false)
        #expect(status.features?.contains("backup1") == false)
    }

    @Test func hataGovdesiSunucudakiyleAyniBicimdedir() async {
        do {
            let _: Status = try await EmbeddedEngine.shared.call("/v1/yok", [String: String]())
            Issue.record("Bilinmeyen uç hata vermeliydi")
        } catch let error as APIError {
            #expect(error.status == 400)
            #expect(error.code == "invalid_request")
            // İstekten kaynaklanan hata yedek yolda da aynı biter: yedeğe düşülmez.
            #expect(!error.canUseBackup)
        } catch {
            Issue.record("Beklenmeyen hata: \(error)")
        }
    }

    @Test func anahtarYokkenIstekYedegeDusebilecekBicimdeBiter() async throws {
        let url = try #require(Bundle.main.url(forResource: "engine", withExtension: "jsbundle"))
        let keyless = EmbeddedEngine(source: { try String(contentsOf: url, encoding: .utf8) }, key: { nil })
        do {
            let _: Status = try await keyless.call("/v1/script-models", [String: String]())
            Issue.record("Anahtarsız istek hata vermeliydi")
        } catch let error as APIError {
            // Bağlantı kurulamamış sayılır: istek yedeğe düşebilir ama motor askıya alınmaz.
            #expect(error.canUseBackup)
            #expect(!error.claudeUnavailable)
        }
    }

    @Test func paketYoksaMotorAnlasilirHataVerirVeYedegeDusulebilir() async {
        struct Missing: Error {}
        let broken = EmbeddedEngine(source: { throw Missing() }, key: { "x" })
        do {
            let _: Status = try await broken.call("/v1/status", [String: String]())
            Issue.record("Paket yokken hata vermeliydi")
        } catch let error as APIError {
            #expect(error.code == "engine")
            #expect(error.claudeUnavailable)
        } catch {
            Issue.record("Beklenmeyen hata: \(error)")
        }
    }

    @Test func yalnizClaudeaDayananUclarUygulamaIcindeCalisir() {
        for path in ["/v1/script", "/v1/script-models", "/v1/study", "/v1/study-v2", "/v1/library-ask", "/v1/verify-script", "/v1/deck", "/v1/voice-ask"] {
            #expect(Backend.enginePaths.contains(path), "\(path) uygulama içinde çalışmalı")
        }
        // Cihazda yapılamayan işler sunucuda kalır: sunucu sesleri, iş belirteci, YouTube, akış, yedek, dosya dönüştürme.
        for path in ["/v1/chirp-tts", "/v1/xtts-tts", "/v1/audio-job", "/v1/speak", "/v1/status", "/v1/youtube/start", "/v1/feed/info",
                     "/v1/backup/list", "/v1/deck/pptx", "/v1/deck-image", "/v1/extract", "/v1/script/start", "/v1/media/start"] {
            #expect(!Backend.enginePaths.contains(path), "\(path) sunucuda kalmalı")
        }
    }

    @Test func testlerdeGercekClaudeCagrisiYapilmaz() {
        #expect(Self.live || !Backend.engineReady)
        #expect(Self.live || !Backend.usesEngine("/v1/script"))
    }

    /// Motorun yazdığı senaryonun iş belirteci motorun kendi sırrıyla imzalıdır: sunucudaki seslendirme onu reddeder (bölüm ilk
    /// sahnede düşerdi). Böyle bir yanıtın sunucuda kullanılabilir belirteci yoktur; seslendirmeden önce sunucudan ses işi istenir.
    @Test func motorunYazdigiSenaryonunBelirteciSunucuyaGonderilmez() throws {
        let script = #"{"title":"T","summary":"","keyPoints":[],"chapters":[],"sourceNotes":""}"#
        let local = try JSONDecoder().decode(ScriptResponse.self, from: Data(#"{"jobToken":"motor-belirteci","local":true,"script":\#(script)}"#.utf8))
        #expect(local.local == true && local.serverJobToken == nil)
        let server = try JSONDecoder().decode(ScriptResponse.self, from: Data(#"{"jobToken":"sunucu-belirteci","script":\#(script)}"#.utf8))
        #expect(server.local == nil && server.serverJobToken == "sunucu-belirteci")
    }

    @Test func hataNedeniYedegeGecisiVeMotorunAskiyaAlinmasiniBelirler() {
        let account = APIError(status: 429, code: "rate_limited", message: "x", reason: "claude_unavailable")
        #expect(account.canUseBackup && account.claudeUnavailable)
        // Yalnız bağlantı koptuysa istek yedeğe düşer ama sonraki istek yine uygulama içinde denenir.
        let network = APIError(status: 502, code: "upstream_error", message: "x", reason: "claude_unreachable")
        #expect(network.canUseBackup && !network.claudeUnavailable)
        #expect(!APIError(status: 502, code: "upstream_error", message: "x").canUseBackup)
        #expect(!APIError(status: 400, code: "invalid_request", message: "x", reason: nil).canUseBackup)
    }

    @Test func askiyaAlinanMotorSuresiDolanaKadarKullanilmaz() {
        // Testlerde motor zaten kapalıdır; askı durumu ayrıca gözlenebilir olmalı ve geri alınabilmeli.
        Backend.suspendEngine()
        #expect(!Backend.engineReady)
        #expect(!Backend.usesEngine("/v1/script"))
        Backend.resumeEngine()
        #expect(Self.live || !Backend.engineReady)
    }

    @Test func askiSuresiSinirlanirVeSurenAskiKisaltilmaz() {
        defer { Backend.resumeEngine() }
        Backend.resumeEngine()
        // Çok kısa bildirilen süre alt sınıra, çok uzunu üst sınıra çekilir (iki yol arasında gidip gelinmesin, yedekte de kalınmasın).
        Backend.suspendEngine(for: 1)
        #expect(abs(Backend.engineSuspendedUntil.timeIntervalSinceNow - Backend.suspensionBounds.lowerBound) < 2)
        Backend.suspendEngine(for: 86_400)
        #expect(abs(Backend.engineSuspendedUntil.timeIntervalSinceNow - Backend.suspensionBounds.upperBound) < 2)
        // Daha kısa bir bildirim süren askıyı kısaltmaz.
        Backend.suspendEngine(for: 60)
        #expect(Backend.engineSuspendedUntil.timeIntervalSinceNow > 3000)
    }

    @Test(.timeLimit(.minutes(1))) func iptalEdilenIstekMotorYanitVermeseDeHemenBiter() async {
        let engine = Self.fake("/* yanıt vermez */")
        let task = Task { try await engine.request("/v1/x", body: Data("{}".utf8)) }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        // İstek motora ulaşmadan iptal edildiyse motor hiç çalıştırılmaz.
        let early = Task { try await engine.request("/v1/x", body: Data("{}".utf8)) }
        early.cancel()
        let earlyResult = await early.result
        #expect(throws: CancellationError.self) { try earlyResult.get() }
    }

    @Test(.timeLimit(.minutes(1))) func motorHataFirlatirsaIstekAsiliKalmazVeYedekYolAcilir() async {
        let waits = Waits()
        let engine = Self.fake("throw new Error('patladı')", waits: waits)
        do {
            let _: Status = try await engine.call("/v1/x", [String: String]())
            Issue.record("Motor hatası istekte görünmeliydi")
        } catch let error as APIError {
            #expect(error.code == "engine")
            #expect(error.claudeUnavailable)
        } catch {
            Issue.record("Beklenmeyen hata: \(error)")
        }
        #expect(waits.all == [Backend.suspension])
    }

    @Test(.timeLimit(.minutes(1))) func hesapKullanilamiyorBildirimiYanitinBasligindanOkunur() async throws {
        // Arka plandaki bir iş Claude'dan "kullanılamıyor" aldıysa bunu sıradaki yanıt (ör. iş yoklaması) başlıkla taşır.
        let waits = Waits()
        let engine = Self.fake(#"__host.done(call, 200, '{"ok":true}', '{"X-Claude-Unavailable":"120"}')"#, waits: waits)
        let status: Status = try await engine.call("/v1/x", [String: String]())
        #expect(status.ok == true)
        #expect(waits.all == [120])
        let quiet = Waits()
        let _: Status = try await Self.fake(#"__host.done(call, 200, '{"ok":true}', '{}')"#, waits: quiet).call("/v1/x", [String: String]())
        #expect(quiet.all.isEmpty)
    }

    /// Gerçek Claude API çağrısı yapar (ücretli): `TEST_RUNNER_LIVE_ENGINE=1 xcodebuild test …` ile çalışır.
    /// Uygulamanın gerçek yolunu sınar: paket uygulama kaynaklarından, anahtar derlemeden gelir; istek `APIClient` üzerinden gider.
    @Test(.enabled(if: live)) func canliModelListesiUygulamaIcindenGelir() async throws {
        #expect(Backend.usesEngine("/v1/script-models"))
        let catalog = try await APIClient.shared.scriptModels()
        #expect(catalog.models.contains { $0.id == "claude-opus-5-5" })
        // Doğrudan Claude API yalnız Claude modellerini listeler (vekildeki katalog başka sağlayıcıları da taşır).
        #expect(catalog.providers.map(\.id) == ["claude"])
    }

    /// Canlı sunucudaki Chirp köprüsü, uzun bir aradan sonraki ilk isteği ara sıra "Ses motoru ses yanıtı okunamadı" (502) ile
    /// düşürüyor (11-12 Eki 2026'da iki kez görüldü; büyük olasılıkla Google oturumu yenilenirken). Uygulama sahneyi yeniden dener;
    /// testler de bir kez yineler.
    nonisolated private static func chirp(_ request: TTSRequest, engine: SpeechEngine, readings: [Pronunciation] = []) async throws -> TTSResponse {
        do {
            return try await APIClient.shared.remoteTTS(request, engine: engine, readings: readings)
        } catch let error as APIError where error.status == 502 {
            return try await APIClient.shared.remoteTTS(request, engine: engine, readings: readings)
        }
    }

    /// "Claude + Chirp": sahnedeki formül ve kısaltmaların okunuşu uygulama içinde, gerçek Claude ile hazırlanır.
    @Test(.enabled(if: live)) func canliOkunusHazirligiFormulVeKisaltmalariOkur() async throws {
        #expect(Backend.usesEngine("/v1/speech-readings"))
        let turns = [TTSTurn(speaker: .a, text: "Fotosentezde CO2 ve H2O kullanılır; sonunda ATP üretilir. O da bunu biliyor.", style: "")]
        let readings = try await APIClient.shared.speechReadings(turns, language: .tr)
        #expect(readings.contains { $0.from == "CO2" && $0.to == "karbondioksit" })
        #expect(readings.contains { $0.from == "ATP" })
        // Sıradan sözcükler (ör. "O" zamiri) okunuş listesine girmez.
        #expect(!readings.contains { $0.from.count == 1 })
        // Türkçe dışı bölümde hazırlık yapılmaz.
        #expect(try await APIClient.shared.speechReadings(turns, language: .en).isEmpty)
    }

    /// "Claude + Chirp" uçtan uca (ücretli: Claude ve Google Chirp; sunucuda bir "araç" hakkı harcar):
    /// `TEST_RUNNER_LIVE_ENGINE=1 TEST_RUNNER_LIVE_CHIRP=1 xcodebuild test …`. Okunuşlar uygulama içinde hazırlanır, ses canlı
    /// sunucudaki Chirp'ten gelir: sunucu, motoru "claude" yazan ayarları ve okunuş eklenmiş seslendirme isteğini kabul etmeli,
    /// okunuşları sese uygulamalı ve hazırlanmış sesi düz Chirp sesinden ayrı saklamalıdır.
    @Test(.enabled(if: live && ProcessInfo.processInfo.environment["LIVE_CHIRP"] == "1")) func canliClaudeChirpSahnesiSeslendirilir() async throws {
        // Her çalıştırmada farklı metin: önceki çalıştırmaların sunucu önbelleği sonucu etkilemesin.
        let tag = ["elma", "armut", "kiraz", "ayva", "erik", "incir", "nar", "dut"].randomElement()! + " " + ["bir", "iki", "üç", "dört", "beş", "altı", "yedi"].randomElement()!
        let turns = [ScriptTurn(speaker: .a, text: "Deneme \(tag). Fotosentezde CO2 ve H2O kullanılır; sonunda ATP üretilir.", style: "sakin")]
        let script = PodcastScript(title: "Claude + Chirp denemesi", summary: "Deneme", keyPoints: ["Fotosentez"],
                                   chapters: [ScriptChapter(title: "Giriş", scenes: [ScriptScene(turns: turns)])], sourceNotes: "")
        var settings = PodcastSettings(speechProvider: "claude")
        settings.format = .tekAnlatici
        let job = try await APIClient.shared.audioJob(AudioJobRequest(script: script, settings: settings, previousJobToken: nil, purpose: "edit"))
        let request = TTSRequest(jobToken: job.jobToken, sceneIndex: 0, turns: turns.map { TTSTurn(speaker: $0.speaker, text: $0.text, style: $0.style) })
        let readings = try await APIClient.shared.speechReadings(request.turns, language: .tr)
        #expect(readings.contains { $0.from == "CO2" && $0.to == "karbondioksit" })
        #expect(Pronunciations.attach(to: request, adding: readings).replacements?.count == readings.count + Pronunciations.all.count)
        let prepared = try await Self.chirp(request, engine: .claude, readings: readings)
        let clip = try WAV.parse(try #require(Data(base64Encoded: prepared.audio)))
        #expect(clip.duration > 2 && clip.duration < 30)
        let plain = try await Self.chirp(request, engine: .chirp)
        let note = "okunuş: \(readings.map { $0.from + "→" + $0.to }), hazırlanmış: \(prepared.durationSec) sn (önbellek: \(prepared.cached == true)), düz: \(plain.durationSec) sn (önbellek: \(plain.cached == true))"
        print("CANLI \(note)")
        // Okunuşlar sese yansır: düz Chirp sesi ayrı üretilir (önbellekten hazırlanmış ses dönmez) ve farklıdır. Süre karşılaştırılmaz:
        // farklı iki ses aynı uzunlukta çıkabilir (11 Eki 2026'da görüldü; Chirp sesi 512 örneklik adımlarla uzar).
        #expect(prepared.cached != true && plain.cached != true, "\(note)")
        #expect(prepared.audio != plain.audio, "\(note)")
        // Aynı okunuşlarla ikinci istek, hazırlanmış sesi önbellekten alır (Chirp kotası yeniden harcanmaz).
        let again = try await APIClient.shared.remoteTTS(request, engine: .claude, readings: readings)
        #expect(again.cached == true && again.audio == prepared.audio)
    }

    /// Podcast'in asıl akışı uçtan uca (ücretli: Claude senaryosu, Google Chirp; sunucuda bir "araç" hakkı):
    /// `TEST_RUNNER_LIVE_ENGINE=1 TEST_RUNNER_LIVE_CHIRP=1`. Senaryoyu motor yazar; sunucu motorun belirtecini reddeder, kendi
    /// ses işinin belirteciyle ilk sahneyi seslendirir.
    @Test(.enabled(if: live && ProcessInfo.processInfo.environment["LIVE_CHIRP"] == "1"), .timeLimit(.minutes(5)))
    func canliMotorSenaryosuSunucudaSeslendirilir() async throws {
        var settings = PodcastSettings(speechProvider: "chirp")
        settings.durationMin = 5
        settings.format = .tekAnlatici
        let source = "Fotosentez, bitkilerin ışık enerjisini kullanarak karbondioksit ve sudan glikoz ve oksijen ürettiği olaydır. Kloroplastlarda gerçekleşir. Işığa bağlı tepkimeler tilakoit zarında, Calvin döngüsü stromada geçer."
        let response = try await APIClient.shared.script(ScriptRequest(settings: settings, sources: [.text(source, name: "Ders notu")]))
        #expect(response.local == true && response.serverJobToken == nil)
        let first = try #require(response.script.flatScenes.first)
        let turns = first.scene.turns.map { TTSTurn(speaker: $0.speaker, text: $0.text, style: $0.style) }
        // Motorun belirteci sunucuda geçersizdir: düzeltmeden önce seslendirme burada düşüyordu.
        do {
            _ = try await APIClient.shared.remoteTTS(TTSRequest(jobToken: response.jobToken, sceneIndex: 0, turns: turns), engine: .chirp)
            Issue.record("Sunucu, motorun belirtecini kabul etmemeliydi")
        } catch let error as APIError {
            #expect(error.code == "job_token_invalid", "\(error.code): \(error.message)")
        }
        // Uygulamanın yaptığı: sunucudan ses işi alınır (motorun belirteci önceki belirteç olarak verilse de yok sayılır).
        let job = try await APIClient.shared.audioJob(AudioJobRequest(script: response.script, settings: settings, previousJobToken: response.jobToken, purpose: "edit"))
        let audio = try await Self.chirp(TTSRequest(jobToken: job.jobToken, sceneIndex: 0, turns: turns), engine: .chirp)
        let clip = try WAV.parse(try #require(Data(base64Encoded: audio.audio)))
        print("CANLI senaryo: \(response.script.flatScenes.count) sahne, ilk sahne \(turns.count) replik, ses \(clip.duration) sn")
        #expect(clip.duration > 2)
    }

    @Test(.enabled(if: live)) func canliDurumSunucudanGelirVeSenaryoIsleriKapalidir() async throws {
        let status = try await APIClient.shared.status()
        #expect(status.ok == true)
        // Senaryoyu uygulama yazar: sunucunun kalıcı senaryo işleri kullanılmaz.
        #expect(status.features?.contains("scriptJobs") == false)
        #expect(status.features?.contains("podcast2") == true)
    }
}
