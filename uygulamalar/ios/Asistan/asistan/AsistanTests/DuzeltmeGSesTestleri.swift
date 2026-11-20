import Foundation
import Testing
@testable import Asistan

/// Ses katmanı düzeltmeleri: Live motor sırası, ses oturumu bırakma, tap bekçisi, OpenAI uyarı olayları,
/// bulut sesi yedeği, kamera kare yaşı ve bulut Whisper süzgeci (ağsız, mikrofonsuz, saf mantık).
@Suite("G-ses düzeltmeleri") @MainActor
struct DuzeltmeGSesTestleri {

    // MARK: Live motor sırası (bulgu 55, 136)

    @Test func claudeSeciliykenGercekZamanliMotorDenenmez() {
        #expect(SesOturumu.canliMotorSirasi(canliMotor: "claude", openaiAnahtariVar: true, canliClaude: true).isEmpty)
        #expect(SesOturumu.canliMotorSirasi(canliMotor: "claude", openaiAnahtariVar: false, canliClaude: false).isEmpty)
    }

    @Test func openaiSirasiYalnizClaudeAnahtarinaUyar() {
        #expect(SesOturumu.canliMotorSirasi(canliMotor: "openai", openaiAnahtariVar: true, canliClaude: true) == [.openai])
        #expect(SesOturumu.canliMotorSirasi(canliMotor: "openai", openaiAnahtariVar: true, canliClaude: false) == [.openai, .gemini])
        #expect(SesOturumu.canliMotorSirasi(canliMotor: "openai", openaiAnahtariVar: false, canliClaude: true).isEmpty)
        #expect(SesOturumu.canliMotorSirasi(canliMotor: "openai", openaiAnahtariVar: false, canliClaude: false) == [.gemini])
        #expect(SesOturumu.canliMotorSirasi(canliMotor: "gemini", openaiAnahtariVar: false, canliClaude: true) == [.gemini])
    }

    // MARK: Ses oturumu bırakma (bulgu 5)

    @Test func oturumYalnizHerSeyBostayakenBirakilir() {
        #expect(SesOturumu.oturumBirakilir(dinleyiciCalisiyor: false, konusuyor: false, sozKesmeCalisiyor: false,
                                           gercekZamanli: false, beyinBosta: true, uyandirmaBekliyor: false))
        #expect(!SesOturumu.oturumBirakilir(dinleyiciCalisiyor: true, konusuyor: false, sozKesmeCalisiyor: false,
                                            gercekZamanli: false, beyinBosta: true, uyandirmaBekliyor: false))
        #expect(!SesOturumu.oturumBirakilir(dinleyiciCalisiyor: false, konusuyor: true, sozKesmeCalisiyor: false,
                                            gercekZamanli: false, beyinBosta: true, uyandirmaBekliyor: false))
        #expect(!SesOturumu.oturumBirakilir(dinleyiciCalisiyor: false, konusuyor: false, sozKesmeCalisiyor: true,
                                            gercekZamanli: false, beyinBosta: true, uyandirmaBekliyor: false))
        #expect(!SesOturumu.oturumBirakilir(dinleyiciCalisiyor: false, konusuyor: false, sozKesmeCalisiyor: false,
                                            gercekZamanli: true, beyinBosta: true, uyandirmaBekliyor: false))
        #expect(!SesOturumu.oturumBirakilir(dinleyiciCalisiyor: false, konusuyor: false, sozKesmeCalisiyor: false,
                                            gercekZamanli: false, beyinBosta: false, uyandirmaBekliyor: false))
        #expect(!SesOturumu.oturumBirakilir(dinleyiciCalisiyor: false, konusuyor: false, sozKesmeCalisiyor: false,
                                            gercekZamanli: false, beyinBosta: true, uyandirmaBekliyor: true))
    }

    @Test func etkinlestirmeIstegiNesliArtirir() {
        let n = SesOturumuNesli()
        #expect(n.deger == 0)
        #expect(n.artir() == 1)
        n.artir()
        #expect(n.deger == 2)
    }

    // MARK: Tap bekçisi (bulgu 68)

    @Test func tamponSonEklemeSuresiTapSusunceBuyur() async throws {
        let t = SesTamponu()
        t.ayarla(oran: 16_000, azamiSure: 3)
        #expect(t.sonEklemedenBeri < 0.5)
        try await Task.sleep(for: .milliseconds(200))
        #expect(t.sonEklemedenBeri >= 0.15)
        [Float](repeating: 0.1, count: 160).withUnsafeBufferPointer { t.ekle($0) }
        #expect(t.sonEklemedenBeri < 0.1)
    }

    // MARK: OpenAI Realtime olayları (bulgu 70)

    @Test func iptalEdilecekYanitYokHatasiOturumuBozmaz() {
        typealias O = OpenAIRealtimeMesajlari
        let iptal: [String: Any] = ["type": "error", "error": ["code": "response_cancel_not_active", "message": "Cancellation failed: no active response found"]]
        #expect(O.coz(iptal) == .uyari("Cancellation failed: no active response found"))
        #expect(O.coz(["type": "error", "error": ["code": "invalid_api_key", "message": "boom"]]) == .hata("boom"))
        #expect(O.coz(["type": "error", "error": ["message": "boom"]]) == .hata("boom"))
        #expect(O.coz(["type": "response.created"]) == .yanitBasladi)
    }

    // MARK: Bulut sesi yedeği (bulgu 72)

    @Test func yedegeDusulunceKalanCumlelerIPhoneSesiyle() {
        #expect(Konusmaci.kuyrukKimligi(secim: "azure:Elif", yedekte: false) == "azure:Elif")
        #expect(Konusmaci.kuyrukKimligi(secim: "azure:Elif", yedekte: true) == Konusmaci.yerelYedek)
    }

    // MARK: Kamera kare yaşı (bulgu 162)

    @Test func bayatKareModeleGitmez() {
        let simdi = Date()
        #expect(KameraAkisi.kareTaze(yazildi: simdi.addingTimeInterval(-0.4), simdi: simdi))
        #expect(!KameraAkisi.kareTaze(yazildi: simdi.addingTimeInterval(-(KameraAkisi.azamiKareYasi + 0.5)), simdi: simdi))
        #expect(!KameraAkisi.kareTaze(yazildi: .distantPast, simdi: simdi))
    }

    // MARK: Bulut Whisper süzgeci (bulgu 137)

    @Test func bulutWhisperUydurmasiAppleMetniniEzmez() {
        #expect(SesOturumu.bulutSonucuTemizle("Altyazı M.K.") == "")
        #expect(SesOturumu.bulutSonucuTemizle(SesOturumu.whisperIpucu) == "")
        #expect(SesOturumu.bulutSonucuTemizle("Türkçe sesli asistan komutu.") == "")
        #expect(SesOturumu.bulutSonucuTemizle("   ") == "")
        #expect(SesOturumu.bulutSonucuTemizle("Yarın saat üçte hatırlatıcı koy") == "Yarın saat üçte hatırlatıcı koy")
    }
}
