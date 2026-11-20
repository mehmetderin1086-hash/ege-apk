import Foundation
import Testing
import ZIPFoundation
@testable import Asistan

/// P2.15: tanı günlüğü v2 (seri kuyruk, 500 KB döndürme, seviye + istek kimliği öneki, merkezi maskeleme,
/// ayrıntılı tanı anahtarı) ve uygulama içi maskeli tanı paketi (`/tani`, Sağlık → Tanı paketi).
@Suite("P2.15 Tanı günlüğü v2", .serialized) @MainActor struct Gelistirme_P2_15_TaniGunluguTestleri {

    private func geciciKlasor(_ ad: String) throws -> URL {
        let k = FileManager.default.temporaryDirectory.appending(path: "p215-\(ad)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: k, withIntermediateDirectories: true)
        return k
    }

    private func oku(_ klasor: URL, _ ad: String) throws -> String {
        try String(contentsOf: klasor.appending(path: ad), encoding: .utf8)
    }

    private func boyut(_ klasor: URL) -> Int {
        (try? klasor.appending(path: "tani.log").resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    nonisolated private static func esZamanliYaz(_ adet: Int, klasor: URL) {
        DispatchQueue.concurrentPerform(iterations: adet) { i in TaniGunlugu.yaz("eşzamanlı \(i)", klasor: klasor) }
    }

    // MARK: (1) Döndürme

    @Test func sinirAsilincaDondurulurVeIkinciDondurmedeYedekYenilenir() throws {
        let k = try geciciKlasor("dondur"); defer { try? FileManager.default.removeItem(at: k) }
        #expect(TaniGunlugu.sinir == 500_000)
        var i = 0
        while boyut(k) <= 1000 {
            TaniGunlugu.yaz("eski \(i)", klasor: k, sinir: .max); i += 1
        }
        TaniGunlugu.yaz("yeni satır", klasor: k, sinir: 1000)
        let yedek = try oku(k, "tani.1.log")
        #expect(yedek.contains("eski 0") && !yedek.contains("yeni satır"))
        let yeni = try oku(k, "tani.log")
        #expect(yeni.hasSuffix("yeni satır\n") && yeni.split(separator: "\n").count == 1)
        // İkinci döndürme: tani.1.log bir önceki tani.log ile değişir.
        while boyut(k) <= 1000 {
            TaniGunlugu.yaz("ara \(i)", klasor: k, sinir: .max); i += 1
        }
        TaniGunlugu.yaz("ikinci", klasor: k, sinir: 1000)
        let yedek2 = try oku(k, "tani.1.log")
        #expect(yedek2.contains("yeni satır") && !yedek2.contains("eski 0"))
        #expect(try oku(k, "tani.log").hasSuffix("ikinci\n"))
    }

    // MARK: (2) Eşzamanlı yazım

    @Test func esZamanli300YazimdaBolunmusSatirYok() throws {
        let k = try geciciKlasor("eszaman"); defer { try? FileManager.default.removeItem(at: k) }
        Self.esZamanliYaz(300, klasor: k)
        let satirlar = try oku(k, "tani.log").split(separator: "\n").map(String.init)
        #expect(satirlar.count == 300)
        let numaralar = Set(satirlar.compactMap { s -> Int? in
            guard let r = s.range(of: " B eşzamanlı ") else { return nil }
            return Int(s[r.upperBound...])
        })
        #expect(numaralar == Set(0..<300))
    }

    // MARK: (3) İstek kimliği

    @Test func istekKimligiYapilandirilmamisGoreveGecerDetachedaGecmez() async throws {
        let k = try geciciKlasor("kimlik"); defer { try? FileManager.default.removeItem(at: k) }
        let gorev = TaniGunlugu.$istek.withValue("abc123") { Task { TaniGunlugu.yaz("miras", klasor: k) } }
        await gorev.value
        let ayrik = TaniGunlugu.$istek.withValue("abc123") { Task.detached { TaniGunlugu.yaz("ayrık", klasor: k) } }
        await ayrik.value
        TaniGunlugu.yaz("kimliksiz", klasor: k)
        let satirlar = try oku(k, "tani.log").split(separator: "\n").map(String.init)
        #expect(satirlar.count == 3)
        #expect(satirlar[0].contains("[r=abc123] miras"))
        #expect(!satirlar[1].contains("[r=") && satirlar[1].hasSuffix(" B ayrık"))
        #expect(!satirlar[2].contains("[r="))
        let kimlik = TaniGunlugu.yeniKimlik()
        #expect(kimlik.count == 6 && kimlik.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test func satirBicimiOnekliVeTekSatir() {
        let z = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(TaniGunlugu.satir("x", zaman: z, istek: nil, seviye: .bilgi) == "\(z.ISO8601Format()) B x")
        #expect(TaniGunlugu.satir("y", zaman: z, istek: "ab12cd", seviye: .hata) == "\(z.ISO8601Format()) H [r=ab12cd] y")
        #expect(!TaniGunlugu.satir("a\nb\r\nc", zaman: z, istek: nil, seviye: .uyari).contains("\n"))
        // Ayrıntılı tanı kapalıyken uzun hata dökümü kesilir.
        let eski = TaniGunlugu.ayrintiliBitis; defer { TaniGunlugu.ayrintiliBitis = eski }
        TaniGunlugu.ayrintiliBitis = nil
        #expect(TaniGunlugu.kisalt(String(repeating: "a", count: 2000)).count == TaniGunlugu.kisaSinir + 1)
    }

    // MARK: (4) Seviye tahmini

    @Test func seviyeTahminTablosu() {
        let tablo: [(String, TaniGunlugu.Seviye)] = [
            ("MODEL HATA claude 1200 ms", .hata), ("WEB ARAMA DÜŞTÜ: zaman aşımı", .hata),
            ("YEREL SUNUCU ÖLÜ: yeniden", .hata), ("KUYRUK kaydedilemedi: x", .hata), ("HAFIZA KURTARMA BAŞARISIZ", .hata),
            ("AĞ koptu", .uyari), ("LIVE koptu: ağ", .uyari), ("SÜZGEÇ atlandı (800 ms)", .uyari), ("ARKA PLAN GÖREVİ SÜRESİ DOLDU", .uyari),
            ("GEÇİCİ HATA → aynı adım yeniden denenecek", .uyari),
            ("MODELLER claude-haiku-5-5, gpt-6.1-sol", .bilgi), ("AÇILIŞ: sürüm 1.0", .bilgi),
        ]
        for (olay, beklenen) in tablo { #expect(TaniGunlugu.tahmin(olay) == beklenen, "\(olay)") }
        // Açık seviye verilirse tahmin yapılmaz.
        #expect(TaniGunlugu.satir("MODEL HATA", zaman: .now, istek: nil, seviye: .bilgi).contains(" B MODEL HATA"))
    }

    // MARK: (5) Maskeleme

    @Test func maskelemeKisiselVeGizliBicimleri() {
        let tablo: [(String, String)] = [
            ("yazan mehmet@ornek.com oldu", "yazan ‹e-posta› oldu"),
            ("ara 0532 123 45 67", "ara ‹telefon›"),
            ("numara +90 532 1234567.", "numara ‹telefon›."),
            ("05321234567", "‹telefon›"),
            ("anahtar sk-abcdefghijklmnop1234 son", "anahtar ‹anahtar› son"),
            ("Authorization: Bearer xyz", "Authorization: Bearer ‹anahtar›"),
            ("jeton eyJhbGciOi.eyJzdWIi.abc-def", "jeton ‹anahtar›"),
            ("IBAN TR12 0006 1005 1978 6457 8413 26", "IBAN ‹iban›"),
            ("kimlik 10000000146", "kimlik ‹kimlik›"),
            ("https://a.com/x?token=1 bitti", "https://a.com/x?‹…› bitti"),
            ("özet 0123456789abcdef0123456789abcdef", "özet ‹anahtar›"),
            ("g AIzaSyA1b2C3d4E5f6G7h8I9j0KlMnOpQrStUvW", "g ‹anahtar›"),
        ]
        for (ham, beklenen) in tablo { #expect(TaniGunlugu.maskele(ham) == beklenen, "\(ham)") }
        for degismez in ["port 18317", "gpt-6.1-sol", "claude-haiku-5-5", "/var/mobile/Containers/Data/Application/ABCDEF/Documents",
                         "kimlik 550E8400-E29B-41D4-A716-446655440000", "sürüm 202610201530", "MODEL HATA 1200 ms"] {
            #expect(TaniGunlugu.maskele(degismez) == degismez, "\(degismez)")
        }
        // Yazım anında da maskelenir.
        #expect(TaniGunlugu.satir("e-posta a.b@c.org", zaman: .now, istek: nil, seviye: .bilgi).hasSuffix("e-posta ‹e-posta›"))
    }

    // MARK: (6) Ayrıntılı tanı

    @Test func icerikYalnizAyrintiliAcikkenHam() {
        let eski = TaniGunlugu.ayrintiliBitis; defer { TaniGunlugu.ayrintiliBitis = eski }
        TaniGunlugu.ayrintiliBitis = nil
        #expect(!TaniGunlugu.ayrintiliAcik)
        #expect(TaniGunlugu.icerik("merhaba dünya") == "‹13 karakter›")
        TaniGunlugu.ayrintiliBitis = Date.now.addingTimeInterval(-60)
        #expect(!TaniGunlugu.ayrintiliAcik && TaniGunlugu.icerik("abc") == "‹3 karakter›")
        TaniGunlugu.ayrintiliBitis = Date.now.addingTimeInterval(86_400)
        #expect(TaniGunlugu.ayrintiliAcik)
        #expect(TaniGunlugu.icerik("merhaba dünya") == "merhaba dünya")
        TaniGunlugu.ayrintiliBitis = nil
        #expect(UserDefaults.standard.object(forKey: TaniGunlugu.ayrintiliAnahtar) == nil)
    }

    // MARK: (7) Tanı paketi

    @Test func taniPaketiMaskeliVeOzetli() async throws {
        let k = try geciciKlasor("paket-kaynak"), h = try geciciKlasor("paket-hedef")
        defer { try? FileManager.default.removeItem(at: k); try? FileManager.default.removeItem(at: h) }
        // Eski (v1, maskesiz) satırlar doğrudan dosyaya yazılır: paket bunları yeniden maskelemeli.
        try Data("2026-10-01T10:00:00Z MODEL HATA mehmet@ornek.com\n".utf8).write(to: k.appending(path: "tani.1.log"))
        try Data("2026-10-20T10:00:00Z H [r=abc123] AĞ koptu 0532 123 45 67\n".utf8).write(to: k.appending(path: "tani.log"))
        try Data("eski".utf8).write(to: h.appending(path: "Asistan-tani-20260101-0000.zip"))
        let url = try await TaniPaketi.olustur(klasor: k, hedefKlasor: h, ozet: "Bağlantı: hazır (mehmet@ornek.com)")
        #expect(url.lastPathComponent.hasPrefix("Asistan-tani-") && url.pathExtension == "zip")
        #expect(!FileManager.default.fileExists(atPath: h.appending(path: "Asistan-tani-20260101-0000.zip").path))
        let arsiv = try Archive(url: url, accessMode: .read)
        var icerik: [String: String] = [:]
        for e in arsiv {
            var veri = Data()
            _ = try arsiv.extract(e) { veri.append($0) }
            icerik[e.path] = String(decoding: veri, as: UTF8.self)
        }
        #expect(Set(icerik.keys) == ["tani.log", "tani.1.log", "ozet.txt"])
        let hepsi = icerik.values.joined(separator: "\n")
        #expect(!hepsi.contains("mehmet@ornek.com") && !hepsi.contains("0532 123 45 67"))
        #expect(icerik["tani.1.log"]?.contains("MODEL HATA ‹e-posta›") == true)
        #expect(icerik["tani.log"]?.contains("[r=abc123] AĞ koptu ‹telefon›") == true)
        let ozet = icerik["ozet.txt"] ?? ""
        #expect(ozet.contains("Sürüm:") && ozet.contains("iOS:") && ozet.contains("Ayrıntılı tanı:") && ozet.contains("Bağlantı: hazır (‹e-posta›)"))
    }

    @Test func ozetMetniBolumleriVar() {
        let s = TaniPaketi.ozetMetni()
        #expect(s.contains("Bağlantı:") && s.contains("Model sayısı:") && s.contains("Hız ölçümleri") && s.contains("İzleme kayıtları"))
    }

    // MARK: (8) /tani komutu ve görüntüleyici çözümlemesi

    @Test func taniKomutuCozulur() {
        #expect(SlashKomutlari.coz("/tani") == .tani)
        #expect(SlashKomutlari.coz("/diag") == .tani)
        #expect(SlashKomutlari.yardimMetni.contains("/tani"))
    }

    @Test func goruntuleyiciSatirCozumlemesi() {
        let yeni = TaniSatiri.coz("2026-10-20T10:00:00Z H [r=abc123] MODEL HATA x", sira: 0)
        #expect(yeni.seviye == .hata && yeni.istek == "abc123")
        let kimliksiz = TaniSatiri.coz("2026-10-20T10:00:00Z U AĞ koptu", sira: 1)
        #expect(kimliksiz.seviye == .uyari && kimliksiz.istek == nil)
        // v1 satırı (seviye öneki yok): olaydan tahmin edilir.
        let eski = TaniSatiri.coz("2026-10-01T10:00:00Z BİTİR HATA: zaman aşımı", sira: 2)
        #expect(eski.seviye == .hata && eski.istek == nil)
        #expect(TaniSatiri.coz("2026-10-01T10:00:00Z MODELLER a", sira: 3).seviye == .bilgi)
    }
}
