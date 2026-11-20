import Foundation
import Synchronization
import Testing
@testable import Asistan

/// O15: WKWebView gezinme kararında DNS denetimi (`WebSayfa.gezinmeGuvenli`).
/// Ağsız: çözücü enjekte edilir. Çözücü ayrık görevde koştuğundan görev-yerel test bağlamı yoktur;
/// gözlemler kilitli kutuya yazılıp testte denetlenir.
@Suite("O15 web gezinme DNS denetimi")
struct AcikIsO15WebGezinmeDnsTestleri {

    /// Çözücü çağrılarını (sayı + ana iş parçacığında mı) kaydeder.
    nonisolated final class Gozlem: Sendable {
        private let durum = Mutex<(sayi: Int, anaIplikte: Bool)>((0, false))
        func kaydet() { let ana = Thread.isMainThread; durum.withLock { $0.sayi += 1; if ana { $0.anaIplikte = true } } }
        var sayi: Int { durum.withLock { $0.sayi } }
        var anaIplikte: Bool { durum.withLock { $0.anaIplikte } }
    }

    @Test("Özel ağa çözülen ad reddedilir")
    func ozeleCozulenAdReddedilir() async {
        let g = Gozlem()
        let sonuc = await WebSayfa.gezinmeGuvenli(URL(string: "https://ornek.com/sayfa")!, cozucu: { _ in g.kaydet(); return true })
        #expect(sonuc == false)
        #expect(g.sayi == 1)
    }

    @Test("Herkese açık adrese çözülen ad kabul edilir")
    func herkeseAcikAdKabul() async {
        let g = Gozlem()
        let sonuc = await WebSayfa.gezinmeGuvenli(URL(string: "https://ornek.com/sayfa")!, cozucu: { _ in g.kaydet(); return false })
        #expect(sonuc == true)
        #expect(g.sayi == 1)
    }

    @Test("http ve yerel adlar çözücüye gitmeden reddedilir")
    func httpCozucusuz() async {
        let g = Gozlem()
        let cozucu: @Sendable (String) -> Bool = { _ in g.kaydet(); return false }
        #expect(await WebSayfa.gezinmeGuvenli(URL(string: "http://ornek.com")!, cozucu: cozucu) == false)
        #expect(await WebSayfa.gezinmeGuvenli(URL(string: "https://localhost/")!, cozucu: cozucu) == false)
        #expect(await WebSayfa.gezinmeGuvenli(URL(string: "about:blank")!, cozucu: cozucu) == false)
        #expect(g.sayi == 0)
    }

    @Test("IP sabitleri çözücüsüz karara bağlanır")
    func ipSabitleri() async {
        let g = Gozlem()
        let cozucu: @Sendable (String) -> Bool = { _ in g.kaydet(); return true }
        #expect(await WebSayfa.gezinmeGuvenli(URL(string: "https://192.168.1.1/")!, cozucu: cozucu) == false)
        #expect(await WebSayfa.gezinmeGuvenli(URL(string: "https://8.8.8.8/")!, cozucu: cozucu) == true)
        #expect(await WebSayfa.gezinmeGuvenli(URL(string: "https://[::1]/")!, cozucu: cozucu) == false)
        #expect(g.sayi == 0)
    }

    @Test("Çözücü ana iş parçacığında çağrılmaz (ana aktörden çağrılsa da)")
    @MainActor
    func cozucuAnaIplikteDegil() async {
        let g = Gozlem()
        let sonuc = await WebSayfa.gezinmeGuvenli(URL(string: "https://ornek.com")!, cozucu: { _ in g.kaydet(); return false })
        #expect(sonuc == true)
        #expect(g.sayi == 1)
        #expect(g.anaIplikte == false)
    }
}
