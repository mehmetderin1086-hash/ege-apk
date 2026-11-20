import AVFoundation
import Foundation
import Testing
@testable import Asistan

/// 28 Ekim A–Z turu: Live mikrofon dönüşü, ses sağlayıcı hata görünürlüğü.
@MainActor
@Suite struct AZTuruTestleri {
    private enum SahteHata: Error { case http(Int) }

    @Test func gecici_oturum_hatalari_yeniden_denenir() {
        #expect(SesOturumuKapisi.gecici(560557684))   // '!int' cannotInterruptOthers
        #expect(SesOturumuKapisi.gecici(AVAudioSession.ErrorCode.insufficientPriority.rawValue))
        #expect(SesOturumuKapisi.gecici(AVAudioSession.ErrorCode.isBusy.rawValue))
        #expect(!SesOturumuKapisi.gecici(AVAudioSession.ErrorCode.cannotStartRecording.rawValue))
        #expect(!SesOturumuKapisi.gecici(0))
        // Bekleme toplamı tur arası gecikmeyi ölçülü tutar.
        #expect(SesOturumuKapisi.beklemeler.reduce(0, +) <= 1000)
    }

    @Test func live_acilis_hatasi_tek_sefer_onarilir() {
        #expect(SesOturumu.canliOnarilir(canliMod: true, onPlanda: true, hata: "Dinleme başlatılamadı: OSStatus 560557684", denenen: 0))
        #expect(!SesOturumu.canliOnarilir(canliMod: true, onPlanda: true, hata: "Dinleme başlatılamadı", denenen: 1))
        #expect(!SesOturumu.canliOnarilir(canliMod: false, onPlanda: true, hata: "Dinleme başlatılamadı", denenen: 0))
        #expect(!SesOturumu.canliOnarilir(canliMod: true, onPlanda: false, hata: "Dinleme başlatılamadı", denenen: 0))
        #expect(!SesOturumu.canliOnarilir(canliMod: true, onPlanda: true, hata: "Mikrofon ya da konuşma tanıma izni yok.", denenen: 0))
    }

    @Test func bulut_ses_hatasi_kisa_neden_verir() {
        #expect(Konusmaci.kisaNeden(SahteHata.http(502)) == "HTTP 502")
        let uzun = NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: String(repeating: "a", count: 90)])
        #expect(Konusmaci.kisaNeden(uzun).count == 61)
    }

    @Test func her_yerde_ara_vurgusu_utf16_araligina_uyar() {
        let a = HerYerdeAraEkrani.vurgulu("Hücre zarı", [NSRange(location: 0, length: 5)])
        let vurgulu = a.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }.map { String(a[$0.range].characters) }
        #expect(vurgulu == ["Hücre"])
        // Taşan aralık yok sayılır, çökme olmaz.
        #expect(String(HerYerdeAraEkrani.vurgulu("ab", [NSRange(location: 1, length: 9)]).characters) == "ab")
    }

    @Test func claude_web_yaniti_atifla_cozulur() throws {
        let yanit: [String: Any] = ["content": [
            ["type": "server_tool_use", "name": "web_search"],
            ["type": "web_search_tool_result", "content": [["url": "https://support.apple.com/tr-tr/120421", "title": "Apple"]]],
            ["type": "text", "text": "Hayır, mikrofon çalışmaz.", "citations": [["url": "https://support.apple.com/tr-tr/120421"]]],
        ]]
        let s = try WebArastirici.claudeCoz(JSONSerialization.data(withJSONObject: yanit))
        #expect(s.hasPrefix("Hayır, mikrofon çalışmaz."))
        #expect(s.contains("Kaynaklar:\nhttps://support.apple.com/tr-tr/120421"))
        // Arama çalışmadı (adres yok): bellekten yanıt kaynaklı sonuç sayılmaz.
        let aramasiz: [String: Any] = ["content": [["type": "text", "text": "Bellekten: sanırım çalışmaz."]]]
        #expect(throws: WebArastirici.Hata.self) { try WebArastirici.claudeCoz(JSONSerialization.data(withJSONObject: aramasiz)) }
        let gecersizAdres: [String: Any] = ["content": [["type": "text", "text": "x", "citations": [["url": "javascript:alert(1)"]]]]]
        #expect(throws: WebArastirici.Hata.self) { try WebArastirici.claudeCoz(JSONSerialization.data(withJSONObject: gecersizAdres)) }
    }

}

