import Testing
import Foundation
@testable import Asistan

@Suite("İletişim ve kişiselleştirme") @MainActor
struct IletisimTestleri {
    @Test func whatsappAliciVeMetinGuvenliKodlanir() throws {
        let metin = "Merhaba 👋 A&B? + çay / yarın"
        let url = try #require(IletisimAraci.adres(islem: "whatsapp", hedef: "+90 (555) 123-4567", metin: metin))
        let c = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(c.host == "wa.me")
        #expect(c.path == "/905551234567")
        #expect(c.queryItems?.first?.value == metin)
        #expect(IletisimAraci.adres(islem: "whatsapp", hedef: "05551234567", metin: "x") == nil)
        #expect(IletisimAraci.adres(islem: "ara", hedef: "*21*555#", metin: nil) == nil)
        #expect(IletisimAraci.adres(islem: "ara", hedef: "555?body=hello", metin: nil) == nil)
        #expect(IletisimAraci.adres(islem: "mesaj", hedef: "a@x.com&body=wrong", metin: nil) == nil)
    }
    @Test func smsMetniVeFacetimeAdresleri() throws {
        let url = try #require(IletisimAraci.adres(islem: "mesaj", hedef: "+90 555 123 4567", metin: "Bir & iki"))
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "Bir & iki")
        #expect(IletisimAraci.adres(islem: "facetime", hedef: "test@example.com", metin: nil)?.scheme == "facetime")
        #expect(IletisimAraci.adres(islem: "facetime", hedef: "test@example.com?x=y", metin: nil) == nil)
    }
    @Test func profilKaliciVeSinirli() throws {
        let alan = "dost.\(UUID())"
        let d = try #require(UserDefaults(suiteName: alan)); defer { d.removePersistentDomain(forName: alan) }
        let a = Ayarlar(defaults: d); a.dostAdi = "Mavi"; a.dostTarzi = "sakin"
        #expect(Ayarlar(defaults: d).gorunenAd == "Mavi")
        #expect(a.dostBaglami.contains("Sakin"))
        a.dostAdi = String(repeating: "x", count: 300)
        #expect(a.gorunenAd.count == 40)
    }
    @Test func sunucuTabanindaV1Tekrarlanmaz() {
        for base in ["https://example.com/dersdas/claude", "https://example.com/dersdas/claude/v1", "https://example.com/dersdas/claude/v1/"] {
            #expect(SunucuGorevleri.adres(URL(string: base)!).absoluteString == "https://example.com/dersdas/claude/v1/asistan/jobs")
            #expect(SunucuGorevleri.asistanAdresi(URL(string: base)!, "live-token").absoluteString == "https://example.com/dersdas/claude/v1/asistan/live-token")
        }
    }
    @Test func eksikHavaDizileriCokmez() {
        let y = HavaAraci.Yanit(current: .init(temperature_2m: 20, apparent_temperature: 20, relative_humidity_2m: 50, weather_code: 0, wind_speed_10m: 3), daily: .init(time: ["2026-10-18"], temperature_2m_max: [], temperature_2m_min: [], weather_code: [], precipitation_probability_max: []))
        #expect(HavaAraci.metin(y, ad: "İstanbul").contains("20°C"))
    }
}
