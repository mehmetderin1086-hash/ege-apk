import Foundation
import Testing
@testable import Asistan

/// P2.13: Eller serbest / Live'da sesli onay kararı, onay kapısının sesli soruculu yolu ve Siri devrinin sesli bayrağı.
/// Ağ, izin, mikrofon ve gerçek model gerektirmez (ses örnekleri kodda üretilir).
@Suite("Gelistirme P2.13 · Sesli onay ve Siri'den sesli devir") @MainActor
struct SesliOnayTestleri {
    static let oran = 16_000.0

    /// `sure` sn sinüs (genlik `genlik`) ardından `sessizlik` sn sıfır.
    static func tampon(sure: Double, genlik: Float, sessizlik: Double = 0) -> [Float] {
        let n = Int(sure * oran)
        var o = (0..<n).map { i in genlik * Float(sin(2 * Double.pi * 220 * Double(i) / oran)) }
        o += [Float](repeating: 0, count: Int(sessizlik * oran))
        return o
    }

    /// 1,8 sn tampon: 0,4 sn 0,08 genlikli konuşma + 1,4 sn sessizlik (dinleyicinin teslim ettiği tipik onay tamponu).
    static var konusmaTamponu: [Float] { tampon(sure: 0.4, genlik: 0.08, sessizlik: 1.4) }

    // MARK: (1) karar

    @Test func evetNoktaliEnerjiliOnaydir() {
        #expect(SesliOnayKarari.karar(metin: "Evet.", ornekler: Self.konusmaTamponu, oran: Self.oran) == .evet)
    }

    @Test func kisikEvetBelirsizdir() {
        // Tüm tampon ~0,01 RMS: kısa onay eşiğinin (0,02) altında; sessizlik uydurması onay sayılmaz.
        #expect(SesliOnayKarari.karar(metin: "evet", ornekler: Self.tampon(sure: 1.0, genlik: 0.015), oran: Self.oran) == .belirsiz)
        #expect(SesliOnayKarari.karar(metin: "evet", ornekler: Self.tampon(sure: 1.8, genlik: 0.005), oran: Self.oran) == .belirsiz)
    }

    @Test func hayirRettir() {
        #expect(SesliOnayKarari.karar(metin: "hayır", ornekler: Self.konusmaTamponu, oran: Self.oran) == .hayir)
        #expect(SesliOnayKarari.karar(metin: "Vazgeç!", ornekler: Self.konusmaTamponu, oran: Self.oran) == .hayir)
    }

    @Test func kosulluEvetBelirsizdir() {
        #expect(SesliOnayKarari.karar(metin: "evet ama bekle", ornekler: Self.konusmaTamponu, oran: Self.oran) == .belirsiz)
        #expect(SesliOnayKarari.karar(metin: "bilmiyorum", ornekler: Self.konusmaTamponu, oran: Self.oran) == .belirsiz)
    }

    @Test func buyukIliIptalRettir() {
        #expect(SesliOnayKarari.karar(metin: "İptal", ornekler: Self.konusmaTamponu, oran: Self.oran) == .hayir)
        // Dosya sistemi/dikte NFD verebilir: I + U+0307.
        #expect(SesliOnayKarari.sozcukKarari("I\u{0307}ptal") == .hayir)
    }

    @Test func cokKelimeliEvet() {
        #expect(SesliOnayKarari.karar(metin: "Evet, gönder.", ornekler: Self.konusmaTamponu, oran: Self.oran) == .evet)
        #expect(SesliOnayKarari.sozcukKarari("  ONAYLIYORUM ") == .evet)
    }

    @Test func sohbetSozuOnaySayilmaz() {
        #expect(SesliOnayKarari.karar(metin: "tamam", ornekler: Self.konusmaTamponu, oran: Self.oran) == .belirsiz)
        #expect(SesliOnayKarari.sozcukKarari("Olur.") == .belirsiz)
        #expect(SesliOnayKarari.sozcukKarari("evet") == .evet)
        #expect(SesliOnayKarari.sozcukKarari("onaylıyorum") == .evet)
    }

    @Test func bosOrnekBelirsizdir() {
        #expect(SesliOnayKarari.karar(metin: "evet", ornekler: [], oran: Self.oran) == .belirsiz)
        #expect(SesliOnayKarari.karar(metin: "evet", ornekler: Self.konusmaTamponu, oran: 0) == .belirsiz)
    }

    @Test func pencereRmsSeyrelmeyiOnler() {
        // 3 sn tamponda 0,3 sn konuşma: tüm tampon RMS'i düşük, en yüksek 250 ms penceresi yüksek.
        let o = Self.tampon(sure: 0.3, genlik: 0.06, sessizlik: 2.7)
        #expect(SesTamponu.enerji(o).rms < 0.02)
        #expect(SesliOnayKarari.pencereRms(o, oran: Self.oran) > 0.035)
        #expect(SesliOnayKarari.pencereRms([], oran: Self.oran) == 0)
    }

    // MARK: (2) soru metni

    @Test func soruMetniAliciyiIcerirVeSoruylaBiter() {
        let m = SesliOnayKarari.soruMetni(baslik: "Mesaj gönderilsin mi?", ayrinti: "Alıcı: Ayşe Yılmaz. Metin: Yarın geliyorum")
        #expect(m.contains("Ayşe Yılmaz"))
        #expect(m.hasSuffix("Evet ya da hayır de."))
        #expect(!m.contains("?."))
        let uzun = SesliOnayKarari.soruMetni(baslik: "Ara", ayrinti: String(repeating: "uzun ayrıntı ", count: 100))
        #expect(uzun.count <= SesliOnayKarari.soruSiniri)
        #expect(uzun.hasSuffix("Evet ya da hayır de."))
    }

    // MARK: (3) bağlantı bayrağı

    @Test func sesliBayragiCozumuDegistirmez() throws {
        let sesli = try #require(URL(string: "asistan://sor?metin=x&ses=1"))
        let yazili = try #require(URL(string: "asistan://sor?metin=x"))
        #expect(AsistanBaglantisi.sesliMi(sesli))
        #expect(!AsistanBaglantisi.sesliMi(yazili))
        #expect(AsistanBaglantisi.coz(sesli) == .sor("x"))
        #expect(AsistanBaglantisi.coz(yazili) == .sor("x"))
    }

    // MARK: (4) köprü adresi

    @Test func kopruAdresiSesliIkenSesBayragiTasir() throws {
        let sesli = try #require(GorevKopru.soruAdresi("saat", sesli: true))
        let yazili = try #require(GorevKopru.soruAdresi("saat", sesli: false))
        let ogeler = URLComponents(url: sesli, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(ogeler.contains(URLQueryItem(name: "ses", value: "1")))
        #expect(!(URLComponents(url: yazili, resolvingAgainstBaseURL: false)?.queryItems ?? []).contains { $0.name == "ses" })
        #expect(AsistanBaglantisi.sesliMi(sesli))
        #expect(AsistanBaglantisi.coz(sesli) == .sor("saat"))
        // Yazılı adres eski kuruluşla birebir aynı (O16 testleri ve teslim kayıtları bozulmasın).
        var c = URLComponents(); c.scheme = "asistan"; c.host = "sor"; c.queryItems = [URLQueryItem(name: "metin", value: "saat")]
        #expect(yazili == c.url)
    }

    // MARK: (5) onay kapısı + sesli sorucu

    func bekle(_ kosul: () -> Bool, sinir: Int = 60) async {
        for _ in 0..<sinir where !kosul() { try? await Task.sleep(for: .milliseconds(50)) }
    }

    @Test(.timeLimit(.minutes(1))) func sesliEvetDiyaloguYanitlar() async {
        let k = OnayKapisi(zorunluOtomatikKararaUyar: false)
        var sorulan: String?
        k.sesliSorucu = { i in sorulan = i.ayrinti; return true }
        let sonuc = await k.iste(baslik: "Mesaj gönderilsin mi?", ayrinti: "Alıcı: Ayşe")
        #expect(sonuc == true)
        #expect(sorulan == "Alıcı: Ayşe")
        #expect(k.bekleyen == nil)
    }

    @Test(.timeLimit(.minutes(1))) func belirsizdeDiyalogEkrandaKalir() async {
        let k = OnayKapisi(zorunluOtomatikKararaUyar: false)
        var cagrildi = false
        k.sesliSorucu = { _ in cagrildi = true; return nil }
        let t = Task { await k.iste(baslik: "Ara", ayrinti: "Ayşe") }
        await bekle { cagrildi && k.bekleyen != nil }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(cagrildi)
        #expect(k.bekleyen != nil)
        k.yanitla(false, id: k.bekleyen?.id)
        #expect(await t.value == false)
    }

    @Test(.timeLimit(.minutes(1))) func dokunmaOnceGelirseSesliKararYokSayilir() async {
        let k = OnayKapisi(zorunluOtomatikKararaUyar: false)
        var bitti = false
        k.sesliSorucu = { _ in
            try? await Task.sleep(for: .milliseconds(300))
            bitti = true
            return true
        }
        let t = Task { await k.iste(baslik: "Ara", ayrinti: "Ayşe") }
        await bekle { k.bekleyen != nil }
        k.yanitla(false)   // kullanıcı ekrandan "Hayır" dedi
        #expect(await t.value == false)
        await bekle { bitti }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(bitti)
        #expect(k.bekleyen == nil)
    }

    @Test(.timeLimit(.minutes(1))) func otomatikKarardaSesliSoruAcilmaz() async {
        let k = OnayKapisi(zorunluOtomatikKararaUyar: false)
        k.otomatikKarar = true
        var cagrildi = false
        k.sesliSorucu = { _ in cagrildi = true; return false }
        #expect(await k.iste(baslik: "Ara", ayrinti: "Ayşe") == true)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!cagrildi)
    }

    @Test(.timeLimit(.minutes(1))) func siradakiIstekDeSesliSorulur() async {
        let k = OnayKapisi(zorunluOtomatikKararaUyar: false)
        var sorulanlar: [String] = []
        k.sesliSorucu = { i in sorulanlar.append(i.baslik); return i.baslik == "ikinci" ? true : nil }
        let t1 = Task { await k.iste(baslik: "birinci", ayrinti: "") }
        await bekle { k.bekleyen?.baslik == "birinci" }
        let t2 = Task { await k.iste(baslik: "ikinci", ayrinti: "") }
        await bekle { k.bekleyenSayisi == 2 }
        k.yanitla(false, id: k.bekleyen?.id)
        #expect(await t1.value == false)
        #expect(await t2.value == true)
        #expect(sorulanlar == ["birinci", "ikinci"])
    }
}
