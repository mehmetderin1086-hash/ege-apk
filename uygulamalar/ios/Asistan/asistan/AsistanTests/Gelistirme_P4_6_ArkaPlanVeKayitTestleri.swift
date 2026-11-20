import Testing
import Foundation
@testable import Asistan

/// P4.6: APNs istemcisi (jeton, gövde, ortam), bildirim dokunuşu, toplantı kaydı/dökümü saf mantığı ve hazır beceri.
/// Ağ, izin, mikrofon ya da gerçek model gerekmez; döküm sahte çözücüyle geçici WAV üzerinde sınanır.
@Suite("P4.6-arka plan bildirimi ve toplantı kaydı")
@MainActor
struct Gelistirme_P4_6_ArkaPlanVeKayitTestleri {

    // MARK: APNs istemcisi

    @Test func jetonHexKucukHarfVeSifirDolgulu() {
        #expect(SunucuGorevleri.jetonHex(Data([0x00, 0x0f, 0xab, 0xff])) == "000fabff")
        #expect(SunucuGorevleri.jetonHex(Data()) == "")
    }

    @Test func cihazGovdesiAlanlari() throws {
        let veri = SunucuGorevleri.cihazGovdesi(jeton: "ab" + String(repeating: "0", count: 62), ortam: "development", paket: "com.mehmetderin.asistan")
        let s = try #require(try JSONSerialization.jsonObject(with: veri) as? [String: String])
        #expect(Set(s.keys) == ["token", "ortam", "paket"])
        #expect(s["token"]?.count == 64)
        #expect(s["ortam"] == "development")
        #expect(s["paket"] == "com.mehmetderin.asistan")
        let bos = try #require(try JSONSerialization.jsonObject(with: SunucuGorevleri.cihazGovdesi(jeton: "x", ortam: "production", paket: nil)) as? [String: String])
        #expect(bos["paket"] == "")
    }

    @Test func apnsOrtamiGomuluProfildenOkunur() {
        // Profil yok: TestFlight / App Store → production.
        #expect(SunucuGorevleri.apnsOrtami(profilMetni: nil) == "production")
        let gelistirme = "…<key>Entitlements</key><dict><key>aps-environment</key>\n\t\t<string>development</string></dict>…"
        #expect(SunucuGorevleri.apnsOrtami(profilMetni: gelistirme) == "development")
        let dagitim = "<key>aps-environment</key><string>production</string>"
        #expect(SunucuGorevleri.apnsOrtami(profilMetni: dagitim) == "production")
        // Profil var ama push yetkisi yok (geliştirme profili): sandbox varsayılır.
        #expect(SunucuGorevleri.apnsOrtami(profilMetni: "<plist></plist>") == "development")
    }

    @Test func ayniJetonIkinciKezGonderilmez() async throws {
        let ad = "p46-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: ad))
        defer { d.removePersistentDomain(forName: ad) }
        let jeton = String(repeating: "a", count: 64)
        d.set(jeton + "|" + SunucuGorevleri.guncelApnsOrtami, forKey: SunucuGorevleri.sonJetonAnahtari)
        // Kayıtlı imza aynıysa ağa çıkmadan döner (bağlantı olmasa da hata atmaz).
        try await SunucuGorevleri.ortak.cihazKaydet(jeton, varsayilanlar: d)
        #expect(d.string(forKey: SunucuGorevleri.sonJetonAnahtari) == jeton + "|" + SunucuGorevleri.guncelApnsOrtami)
    }

    // MARK: Bildirim dokunuşu

    @Test func gorevKimligiCozulur() {
        let id = UUID().uuidString.lowercased()
        #expect(TetikBildirimi.gorevKimligi(["gorev": id, "aps": ["alert": "x"]]) == id)
        #expect(TetikBildirimi.gorevKimligi(["gorev": "uuid-degil"]) == nil)
        #expect(TetikBildirimi.gorevKimligi(["gorev": 5]) == nil)
        #expect(TetikBildirimi.gorevKimligi([:]) == nil)
        // Paylaşım ve tetik bildirimlerinin yükünde 'gorev' yok: eski dallar etkilenmez.
        #expect(TetikBildirimi.gorevKimligi([PaylasimKutusu.bildirimAnahtari: "1"]) == nil)
        #expect(TetikBildirimi.gorevKimligi([TetikDeposu.istemAnahtari: "Hava nasıl?"]) == nil)
    }

    // MARK: Döküm parçaları

    func sinirlar(_ l: [Range<TimeInterval>]) -> [[Double]] { l.map { [$0.lowerBound, $0.upperBound] } }

    @Test func parcaAraliklari() {
        // 12:30 → üç parça (son 150 sn kendi başına).
        #expect(sinirlar(ToplantiDokumu.parcaAraliklari(sure: 750)) == [[0, 300], [300, 600], [600, 750]])
        // 5:10 → tek parça: 10 sn'lik artık öncekine katılır.
        #expect(sinirlar(ToplantiDokumu.parcaAraliklari(sure: 310)) == [[0, 310]])
        #expect(sinirlar(ToplantiDokumu.parcaAraliklari(sure: 600)) == [[0, 300], [300, 600]])
        #expect(sinirlar(ToplantiDokumu.parcaAraliklari(sure: 45)) == [[0, 45]])
        #expect(ToplantiDokumu.parcaAraliklari(sure: 0).isEmpty)
        #expect(ToplantiDokumu.parcaAraliklari(sure: -3).isEmpty)
        // 3 saat: 36 parça, her biri ≤ 5 dk (WAV ≈ 9,6 MB < 25 MB).
        let uc = ToplantiDokumu.parcaAraliklari(sure: 3 * 3600)
        #expect(uc.count == 36)
        #expect(uc.allSatisfy { $0.upperBound - $0.lowerBound <= 320 })
    }

    @Test func birlestirZamanDamgasi() {
        let m = ToplantiDokumu.birlestir([(0, "Açılış yapıldı."), (300, "  "), (600, "Karar: gezi yapılacak."), (3725, "Kapanış.")])
        #expect(m == "[00:00:00] Açılış yapıldı.\n\n[00:10:00] Karar: gezi yapılacak.\n\n[01:02:05] Kapanış.")
        #expect(ToplantiDokumu.zamanDamgasi(-4) == "00:00:00")
        #expect(ToplantiDokumu.cozulemedi(300) == "[05:00 bölümü çözülemedi]")
        #expect(ToplantiDokumu.cozulemedi(3900) == "[65:00 bölümü çözülemedi]")
    }

    @Test func belgeMetniSinirlanir() {
        #expect(ToplantiDokumu.belgeMetni("kısa", dosyaAdi: "a.txt") == "kısa")
        let uzun = ToplantiDokumu.belgeMetni(String(repeating: "x", count: 120), dosyaAdi: "2026-10-20-1405.txt", sinir: 100)
        #expect(uzun.hasPrefix(String(repeating: "x", count: 100) + "\n\n(Döküm"))
        #expect(uzun.contains("2026-10-20-1405.txt"))
        #expect(!uzun.contains(String(repeating: "x", count: 101)))
    }

    @Test func cozumleYenidenDenerVeYerTutucuYazar() async throws {
        let klasor = FileManager.default.temporaryDirectory.appending(path: "p46-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: klasor) }
        let ses = klasor.appending(path: "2026-10-20-1405.wav")
        // 2,5 sn, 16 kHz: 1 sn'lik parçalarla [0,1) + [1,2,5) (0,5 sn'lik artık katılır).
        let ornekler = (0..<40_000).map { i in Float(sin(Double(i) * 0.05) * 0.3) }
        try WhisperIstemcisi.wav(ornekler, oran: 16_000).write(to: ses)
        let s = P46Sayac()
        let dokum = try await ToplantiDokumu.cozumle(ses, parca: 1, ilerleme: { b, t in s.ilerledi(b, t) }, cozucu: { o, oran, ipucu in
            let n = s.artir(ipucu)
            #expect(oran == 16_000)
            #expect(!o.isEmpty)
            if n == 2 { return "Birinci bölüm." }
            throw P46GeciciHata()   // 1: ilk deneme düşer; 3-4: ikinci parça iki kez düşer
        })
        #expect(dokum == "[00:00:00] Birinci bölüm.\n\n[00:00:01] [00:01 bölümü çözülemedi]")
        #expect(s.ipucuListesi.count == 4)
        #expect(s.ipucuListesi[2] == "Birinci bölüm.")   // önceki parçanın sonu Whisper istemine bağlam olur
        #expect(s.ilerlemeListesi == [[1, 2], [2, 2]])
        let txt = try String(contentsOf: SesKaydedici.dokumYolu(ses), encoding: .utf8)
        #expect(txt == dokum)
    }

    @Test func okunamayanDosyaHataVerir() async {
        let yok = FileManager.default.temporaryDirectory.appending(path: "p46-yok-\(UUID().uuidString).m4a")
        await #expect(throws: ToplantiDokumu.Hata.self) {
            _ = try await ToplantiDokumu.cozumle(yok, cozucu: { _, _, _ in "x" })
        }
    }

    // MARK: Kaydedici saf yardımcıları

    @Test func yeterliAlanEsigi() {
        #expect(!SesKaydedici.yeterliAlanVar(bos: 499_999_999))
        #expect(SesKaydedici.yeterliAlanVar(bos: 500_000_000))
        #expect(!SesKaydedici.yeterliAlanVar(bos: 0))
        // Çok uzun kayıt (10 sa ≈ 576 MB pay) 500 MB'ı aşan alan ister.
        #expect(!SesKaydedici.yeterliAlanVar(bos: 550_000_000, sureSaat: 10))
        #expect(SesKaydedici.yeterliAlanVar(bos: 600_000_000, sureSaat: 10))
    }

    @Test func dosyaAdiVeSeviye() throws {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 20; c.hour = 14; c.minute = 5
        var tk = Calendar(identifier: .gregorian); tk.timeZone = try #require(TimeZone(identifier: "UTC"))
        let tarih = try #require(tk.date(from: c))
        #expect(SesKaydedici.dosyaAdi(tarih, saatDilimi: try #require(TimeZone(identifier: "UTC"))) == "2026-10-20-1405.m4a")
        #expect(SesKaydedici.dokumYolu(URL(filePath: "/tmp/2026-10-20-1405.m4a")).lastPathComponent == "2026-10-20-1405.txt")
        #expect(SesKaydedici.seviyeOrani(db: -160) == 0)
        #expect(SesKaydedici.seviyeOrani(db: 0) == 1)
        #expect(SesKaydedici.seviyeOrani(db: -25) == 0.5)
        #expect(SesKaydedici.seviyeOrani(db: -.infinity) == 0)
        #expect(SesKaydedici.seviyeOrani(db: .nan) == 0)
    }

    @Test func kayitlarYenidenEskiyeVeYalnizM4a() throws {
        let k = FileManager.default.temporaryDirectory.appending(path: "p46-k-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: k, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: k) }
        for ad in ["2026-10-19-0900.m4a", "2026-10-20-1405.m4a", "2026-10-20-1405.txt", "2026-10-20-1405_2.m4a"] {
            try Data().write(to: k.appending(path: ad))
        }
        #expect(SesKaydedici.kayitlar(k).map(\.lastPathComponent) == ["2026-10-20-1405_2.m4a", "2026-10-20-1405.m4a", "2026-10-19-0900.m4a"])
    }

    @Test func kayitEkraniBicimleri() {
        #expect(KayitEkrani.sureMetni(65) == "01:05")
        #expect(KayitEkrani.sureMetni(3725) == "1:02:05")
        #expect(KayitEkrani.gorunenAd(URL(filePath: "/x/2026-10-20-1405.m4a")) == "20.10.2026 14:05")
        #expect(KayitEkrani.gorunenAd(URL(filePath: "/x/2026-10-20-1405_2.m4a")) == "20.10.2026 14:05 (2)")
        #expect(KayitEkrani.gorunenAd(URL(filePath: "/x/ses.m4a")) == "ses")
    }

    // MARK: Hazır beceri ve istem

    @Test func toplantiIstemiBecerisizCalisir() {
        let i = ToplantiDokumIsi.istem(kayit: "20.10.2026 14:05")
        #expect(i.contains("ofisBelgesiOlustur") && i.contains("hatırlatıcı") && i.contains("uydurma"))
        #expect(!i.contains("toplanti-dokumu"), "kaldırılan beceriye başvurmaz")
        #expect(BeceriDeposu.hazirPaket().isEmpty, "hazır beceri paketi kaldırıldı")
    }
}

/// Sahte çözücünün çağrı sayacı (ağsız; @Sendable kapanıştan güvenli artırılır).
nonisolated final class P46Sayac: @unchecked Sendable {
    private let kilit = NSLock()
    private var n = 0
    private var ipuclari: [String?] = []
    func artir(_ ipucu: String?) -> Int { kilit.withLock { n += 1; ipuclari.append(ipucu); return n } }
    var ipucuListesi: [String?] { kilit.withLock { ipuclari } }
    private var ilerlemeler: [[Int]] = []
    func ilerledi(_ b: Int, _ t: Int) { kilit.withLock { ilerlemeler.append([b, t]) } }
    var ilerlemeListesi: [[Int]] { kilit.withLock { ilerlemeler } }
}

nonisolated struct P46GeciciHata: Error {}
