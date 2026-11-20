import Foundation
import Testing
@testable import Asistan

/// İkinci düzeltme turu, K6 (indirme + Kepçe): süzgeç kısıtları, on yıl sayıları, yeniden denemede yer payı,
/// sahipsiz klasör temizliği, yönlendirme denetimi ve son adres iletisi (ağsız, saf mantık).
@Suite("K6-indirme-kepce düzeltmeleri")
struct Duzeltme2K6indirmekepceTestleri {
    let kuran = "Kur'an-ı Kerim Meali"

    // MARK: Süzgeç kısıtları yalnız ek doğrulama (bulgu 26, 29)

    @Test func etiketsizDilKisitiDogruAdayiDusurmez() {
        let p = IndirmeEslesme.puan(istek: "Kuran meali 15. cüz", kisitlar: ["15. cüz", "Türkçe"], baslik: "\(kuran) 15. Cüz", kanal: "Vav Radyo")
        #expect(p >= IndirmeEslesme.esik)
        let tarkan = IndirmeEslesme.puan(istek: "Tarkan Kuzu Kuzu", kisitlar: ["sanatçı: Tarkan", "şarkı: Kuzu Kuzu", "Ses dosyası"],
                                         baslik: "Tarkan - Kuzu Kuzu", kanal: "Tarkan")
        #expect(tarkan >= IndirmeEslesme.esik)
    }

    @Test func betimleyiciKisitlarZorunluSimgeOlmaz() {
        for k in ["resmi kanal", "en çok dinlenen", "resmi video", "işlem: indirme", "tarih: 2023", "adet: 1",
                  "sadece ses", "Son Çıkan Şarkısı", "Resmi Kanal", "1080p kalite", "Türkçe altyazılı"] {
            #expect(IndirmeEslesme.simgeler(IndirmeEslesme.kisitMetni([k])).isEmpty, "\(k) zorunlu simge üretmemeli")
        }
        #expect(IndirmeEslesme.kisitMetni(["sanatçı: Tarkan", "şarkı: Şımarık", "sadece ses"]) == "Tarkan Şımarık")
    }

    @Test func bicimKisitliNetIstekOtomatikSecilir() {
        let p = IndirmeEslesme.puan(istek: "Tarkan Şımarık", kisitlar: ["Tarkan", "Şımarık", "Türkçe", "1080p kalite"],
                                    baslik: "Tarkan - Şımarık (Official Video)", kanal: "Tarkan")
        let a = IndirmeEslesme.Aday(baslik: "Tarkan - Şımarık (Official Video)", kanal: "Tarkan", sure: 240, url: "https://youtube.com/a", puan: p)
        #expect(IndirmeEslesme.sec(istek: "Tarkan Şımarık", adaylar: [a]).secilen?.url == a.url)
    }

    @Test func etiketliOkuyucuKisitiHalaDenetler() {
        // Kısıt ayırt edici simgeyi (okuyucu) yine zorunlu tutar: yanlış okuyucu inmez.
        let yanlis = IndirmeEslesme.puan(istek: "Kuran meali 15. cüz", kisitlar: ["okuyucu: Ayhan Kaya", "Türkçe"],
                                         baslik: "\(kuran) 15. Cüz - Köksal Engür", kanal: "Vav Radyo")
        #expect(yanlis < IndirmeEslesme.esik)
        #expect(IndirmeEslesme.kisitMetni(["okuyucu: ayhan kaya", "sadece ses"]) == "ayhan kaya")
    }

    // MARK: Kesme işaretli on yıl sayıları (bulgu 82, 29b)

    @Test func kesmeliVeKesmesizOnYilAyniSimge() {
        #expect(IndirmeEslesme.puan(istek: "Best of 90's pop", baslik: "Best of 90s Pop Hits", kanal: "x") >= IndirmeEslesme.esik)
        #expect(IndirmeEslesme.puan(istek: "90'lar Türkçe pop", baslik: "90lar Türkçe Pop", kanal: "x") >= IndirmeEslesme.esik)
        #expect(IndirmeEslesme.simgeler("90s 1990ların 2000ler") == ["90", "1990", "2000"])
        // Sayı kapısı başka sayıyı yine reddeder; tek haneli/harfli adlar dokunulmaz.
        #expect(IndirmeEslesme.puan(istek: "80's pop", baslik: "90s Pop", kanal: "x") <= 0.3)
        #expect(IndirmeEslesme.simgeler("2pac 4k 4s") == ["2pac", "4s"])
    }

    // MARK: Yeniden denemede yer payı (bulgu 25, 28)

    @Test func onDenetimEldekiParcalariDuser() {
        let gb: Int64 = 1_000_000_000
        // İlk deneme (klasör boş): eski pay aynen.
        #expect(MotorluIndirici.onDenetimPayi(boyut: 3 * gb / 2, birlesecek: true, eldeki: 0) == 3 * gb)
        #expect(MotorluIndirici.onDenetimPayi(boyut: 3 * gb / 2, birlesecek: false, eldeki: 0) == 3 * gb / 2)
        // 1,3 GB inmiş 1,5 GB'lık video: kalan 0,2 + çıktı 1,5.
        #expect(MotorluIndirici.onDenetimPayi(boyut: 15 * gb / 10, birlesecek: true, eldeki: 13 * gb / 10) == 17 * gb / 10)
        // Eldeki tahminden büyükse fazla düşülmez; eksi değer sıfır sayılır.
        #expect(MotorluIndirici.onDenetimPayi(boyut: gb, birlesecek: true, eldeki: 2 * gb) == gb)
        #expect(MotorluIndirici.onDenetimPayi(boyut: gb, birlesecek: false, eldeki: -5) == gb)
    }

    @Test func eldekiBaytDiskteKaplananiToplar() throws {
        let klasor = FileManager.default.temporaryDirectory.appending(path: "k6-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: klasor) }
        let video = klasor.appending(path: "video.mp4")
        try Data(repeating: 7, count: 200_000).write(to: video)
        #expect(MotorluIndirici.eldekiBayt([video]) >= 200_000)
        #expect(MotorluIndirici.eldekiBayt([klasor.appending(path: "ses.m4a")]) == 0)
        #expect(MotorluIndirici.eldekiBayt([]) == 0)
    }

    // MARK: Sahipsiz klasör temizliği görüntü anına bağlı (bulgu 83)

    @Test func goruntudenSonraAcilanKlasorSilinmez() {
        let an = Date(timeIntervalSince1970: 1_000_000)
        let yeni = UUID()
        #expect(!MotorluIndirici.silinmeli(yeni, etkin: [], bekleyen: [], tarih: an.addingTimeInterval(1), simdi: an))
        #expect(MotorluIndirici.silinmeli(yeni, etkin: [], bekleyen: [], tarih: an.addingTimeInterval(-60), simdi: an))
        #expect(MotorluIndirici.silinmeli(yeni, etkin: [], bekleyen: [], tarih: an, simdi: an))
        #expect(MotorluIndirici.silinmeli(nil, etkin: [], bekleyen: [], tarih: an.addingTimeInterval(1), simdi: an))
    }

    // MARK: Yönlendirme denetimi temsilci kuyruğunu DNS'le kilitlemez (bulgu 84) — yalnız ağsız yollar

    @Test func yonlendirmeSayisalVeGecersizAdresteHemenYanitlanir() {
        let kutu = K6Kutu()
        var ozel = URLRequest(url: URL(string: "https://192.168.1.10/x")!)
        ozel.setValue("a=1", forHTTPHeaderField: "Cookie")
        AkisIndirici.yonlendirmeyiDenetle(ozel, onceki: URL(string: "https://example.com/v")) { kutu.koy($0) }
        #expect(kutu.cagrildi && kutu.istek == nil)

        let kutu2 = K6Kutu()
        AkisIndirici.yonlendirmeyiDenetle(URLRequest(url: URL(string: "http://93.184.215.14/x")!), onceki: nil) { kutu2.koy($0) }
        #expect(kutu2.cagrildi && kutu2.istek == nil)

        let kutu3 = K6Kutu()
        var acik = URLRequest(url: URL(string: "https://93.184.215.14/x")!)
        acik.setValue("a=1", forHTTPHeaderField: "Cookie")
        AkisIndirici.yonlendirmeyiDenetle(acik, onceki: URL(string: "https://example.com/v")) { kutu3.koy($0) }
        #expect(kutu3.cagrildi && kutu3.istek?.url == acik.url)
        #expect(kutu3.istek?.value(forHTTPHeaderField: "Cookie") == nil, "başka ana makineye çerez gitmemeli")
    }

    // MARK: Son adres iletisi (bulgu 85)

    @Test func sonAdresIletisiYonlendirmeyiAyirir() {
        let ilk = URL(string: "https://nas.ornek.ts.net/dosya.pdf")
        #expect(IndirmeTemsilcisi.guvensizSonAdresMetni(son: ilk, ilk: ilk).hasPrefix("Bu sunucu yerel ağda"))
        #expect(IndirmeTemsilcisi.guvensizSonAdresMetni(son: URL(string: "https://NAS.ornek.ts.net/b"), ilk: ilk).hasPrefix("Bu sunucu"))
        #expect(IndirmeTemsilcisi.guvensizSonAdresMetni(son: URL(string: "https://ic.ornek/x"), ilk: ilk).contains("yönlendi"))
    }

    // MARK: Ortak WKWebView kullanan iş bırakılmaz (bulgu 27)

    @Test func birakilmayanIsSureDolsaDaBeklenir() async {
        let baslangic = Date()
        let r: Int? = await sureSinirli(0.2, birakilabilir: false) {
            await withCheckedContinuation { (d: CheckedContinuation<Int, Never>) in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) { @Sendable in d.resume(returning: 1) }
            }
        }
        #expect(r == nil)
        #expect(Date().timeIntervalSince(baslangic) >= 0.7, "grup iptali dinlemeyen işin kapanmasını beklemeli")
    }
}

/// Eşzamanlı tamamlayıcı sonucu için küçük kilitli kutu.
nonisolated final class K6Kutu: @unchecked Sendable {
    private let kilit = NSLock()
    private var _istek: URLRequest?
    private var _cagrildi = false
    func koy(_ r: URLRequest?) { kilit.withLock { _istek = r; _cagrildi = true } }
    var istek: URLRequest? { kilit.withLock { _istek } }
    var cagrildi: Bool { kilit.withLock { _cagrildi } }
}
