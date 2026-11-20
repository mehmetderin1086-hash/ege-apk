import Testing
import Foundation
@testable import Asistan

/// O16: Görev köprüsü bildirimleri. Sohbet ekranı `.asistanSor` yayınını üstlenince `GorevKopru.alindi(url)`,
/// Beyin çevrimdışı kuyruğa alınca `GorevKopru.kuyrugaAlindi(metin)` çağırır. Ağ, izin ve gerçek model gerekmez.
@Suite("O16-görev köprüsü bildirimleri", .serialized)
@MainActor
struct AcikIsO16GorevKopruTestleri {
    let alan = "o16.\(UUID().uuidString)"

    func beyin() -> Beyin {
        let ud = UserDefaults(suiteName: alan)!
        let k = OnayKapisi(); k.otomatikKarar = false
        return Beyin(ayarlar: Ayarlar(defaults: ud), depo: HafizaDeposu(baglam: HafizaTestleri.kap.mainContext), onay: k, modelVitesi: ModelVitesi(defaults: ud))
    }

    func suitiSil() { UserDefaults(suiteName: alan)?.removePersistentDomain(forName: alan) }

    func bekle(_ kosul: () -> Bool, sinir: Int = 60) async {
        for _ in 0..<sinir where !kosul() { try? await Task.sleep(for: .milliseconds(50)) }
    }

    /// Köprünün yayınladığı `asistan://sor` adresi (teslimDongusu ile aynı kuruluş).
    func sorAdresi(_ metin: String) -> URL {
        var c = URLComponents(); c.scheme = "asistan"; c.host = "sor"; c.queryItems = [URLQueryItem(name: "metin", value: metin)]
        return c.url!
    }

    // MARK: (a) çevrimdışı kuyruk bildirimi

    @Test func cevrimdisiKuyrugaGirenKestirmeIstegiBekletiliyorDer() async throws {
        await GorevKopruTestKilidi.ortak.al()   // başka bir süit aynı anda GorevKopru.ortak.calistir çağırıp görevi devralmasın
        defer { GorevKopruTestKilidi.ortak.birak() }
        defer { suitiSil() }
        let b = beyin()
        defer { b.kuyruk.hepsiniSil(); AgIzleyici.ortak.durumGuncelle(true) }
        let s = "kestirme-\(UUID())"
        let t = Task { await GorevKopru.ortak.calistir(s, sinir: 1) }
        await bekle { GorevKopru.ortak.beklenen == s }
        try #require(GorevKopru.ortak.beklenen == s, "kestirme isteği köprüye alınmadı")
        AgIzleyici.ortak.durumGuncelle(false)
        b.gonder(s)
        #expect(GorevKopru.ortak.kuyrukta == true, "kuyruğa giren beklenen istek işaretlenmeli")
        #expect(b.bekleyenGonderiler.count == 1)
        let sonuc = await t.value
        #expect(sonuc == GorevKopru.teslimEdilemediMetni(kuyrukta: true, cevrimdisi: true))
        #expect(sonuc.contains("bekletiliyor"))
    }

    @Test func beklenmeyenIstekKuyrugaGirinceIsaretlenmez() async throws {
        await GorevKopruTestKilidi.ortak.al()
        defer { GorevKopruTestKilidi.ortak.birak() }
        defer { suitiSil() }
        let b = beyin()
        defer { b.kuyruk.hepsiniSil(); AgIzleyici.ortak.durumGuncelle(true) }
        // Kestirmenin beklediği başka bir istek yokken (kilit altında hiçbir süit görev başlatmaz) bayrak kapalı kalır.
        try #require(GorevKopru.ortak.beklenen == nil)
        try #require(GorevKopru.ortak.kuyrukta == false)
        AgIzleyici.ortak.durumGuncelle(false)
        b.gonder("beklenmeyen-\(UUID())")
        #expect(b.bekleyenGonderiler.count == 1)
        #expect(GorevKopru.ortak.kuyrukta == false)
    }

    // MARK: (b) teslim bildirimi

    @Test func alindiTeslimiKaydederVeBayragiKaliciAcar() {
        // GorevKopru bayrağı UserDefaults.standard'a yazar (enjeksiyon yok): önceki değer geri konur, test iz bırakmaz.
        let onceki = UserDefaults.standard.object(forKey: GorevKopru.teslimAnahtari)
        defer {
            if let onceki { UserDefaults.standard.set(onceki, forKey: GorevKopru.teslimAnahtari) }
            else { UserDefaults.standard.removeObject(forKey: GorevKopru.teslimAnahtari) }
        }
        let url = sorAdresi("o16-teslim-\(UUID())")
        GorevKopru.ortak.alindi(url)
        #expect(GorevKopru.ortak.alinanlar.contains(url))
        #expect(UserDefaults.standard.bool(forKey: GorevKopru.teslimAnahtari))
    }

    /// Teslim bildirildikten sonra tek seferlik istek (4000+ karakter: kabul eşleşmez) teslim alınana kadar yinelenir,
    /// `alindi` gelince yayın kesilir (sohbet ekranının `.asistanSor` alıcısının yaptığı).
    @Test func tekSeferlikIstekTeslimAlinincaYayinKesilir() async throws {
        // Kendi köprü örneği: başka süitlerin ortak köprüye yazdığı bekleyen soru bu ölçümü bozamaz.
        let k = GorevKopru()
        let onceki = UserDefaults.standard.object(forKey: GorevKopru.teslimAnahtari)
        defer {
            if let onceki { UserDefaults.standard.set(onceki, forKey: GorevKopru.teslimAnahtari) }
            else { UserDefaults.standard.removeObject(forKey: GorevKopru.teslimAnahtari) }
        }
        k.alindi(sorAdresi("o16-isinma-\(UUID())"))   // dinleyici teslim bildiriyor
        let soru = "o16-\(UUID())-" + String(repeating: "a", count: 4_001)
        #expect(!GorevKopru.yinelenebilir(soru))
        let url = sorAdresi(soru)
        let sayac = O16YayinSayaci()
        let gozlemci = NotificationCenter.default.addObserver(forName: .asistanSor, object: nil, queue: nil) { n in
            let gelen = n.object as? URL
            MainActor.assumeIsolated {
                if gelen == url { sayac.n += 1 }
            }
        }
        defer {
            NotificationCenter.default.removeObserver(gozlemci)
            k.kabul(soru, nesil: -1)   // döngüyü durdur
        }
        k.teslimEt(soru)
        // Bu örnekte yalnız test `alindi` çağırır; test barındırıcısının sohbet ekranı ortak köprüyü etkiler, bunu değil.
        await bekle({ sayac.n >= 2 }, sinir: 80)
        try #require(k.bekleyenSoru == soru, "bekleyen soru erken boşaldı")
        #expect(sayac.n >= 2, "teslim alınmamış tek seferlik istek yinelenmeli")
        k.alindi(url)
        let simdiki = sayac.n
        try await Task.sleep(for: .milliseconds(1_200))
        try #require(k.bekleyenSoru == soru, "bekleyen soru erken boşaldı")
        #expect(sayac.n == simdiki, "teslim alındıktan sonra yeniden yayınlanmamalı")
        #expect(!GorevKopru.yayinlanmali(tekSefer: true, yayinlandi: true, teslimBildirilir: true, alindi: true))
    }
}

/// `GorevKopru.ortak` tek görev izler; ona `calistir` ile dokunan testler (O16, P2.2) birbirini devralmasın diye sıraya girer.
@MainActor
final class GorevKopruTestKilidi {
    static let ortak = GorevKopruTestKilidi()
    private var dolu = false
    private var bekleyenler: [CheckedContinuation<Void, Never>] = []

    func al() async {
        if !dolu { dolu = true; return }
        await withCheckedContinuation { bekleyenler.append($0) }
    }

    func birak() {
        if bekleyenler.isEmpty { dolu = false } else { bekleyenler.removeFirst().resume() }
    }
}

@MainActor
private final class O16YayinSayaci { var n = 0 }
