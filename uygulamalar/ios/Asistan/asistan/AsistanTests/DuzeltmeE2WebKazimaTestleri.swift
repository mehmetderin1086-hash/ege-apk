import Foundation
import Testing
@testable import Asistan

/// İptal sonrası yan etkiyi gözlemek için iş parçacığı güvenli bayrak.
nonisolated final class E2Bayrak: @unchecked Sendable {
    private let kilit = NSLock()
    private var _deger = false
    func koy() { kilit.lock(); _deger = true; kilit.unlock() }
    var deger: Bool { kilit.lock(); defer { kilit.unlock() }; return _deger }
}

@Suite("E2-web-kazima düzeltmeleri") @MainActor struct DuzeltmeE2WebKazimaTestleri {
    // MARK: sureSinirli (bulgu 31)

    @Test func sureSinirliIptaliDinlemeyenIsiBeklemez() async {
        let baslangic = Date()
        // İptali hiç dinlemeyen iş (seri kuyruktaki Python çağrısı gibi): 3 sn sonra biter.
        let r: Int? = await sureSinirli(0.3) {
            await withCheckedContinuation { (d: CheckedContinuation<Int, Never>) in
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) { @Sendable in d.resume(returning: 1) }
            }
        }
        #expect(r == nil)
        #expect(Date().timeIntervalSince(baslangic) < 1.5, "süre sınırı işi beklemeden dönmeli")
    }

    @Test func sureSinirliIptalIseIletilirYanEtkiKalmaz() async {
        let bayrak = E2Bayrak()
        let r: Int? = await sureSinirli(0.2) {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { bayrak.koy() }
            return 1
        }
        #expect(r == nil)
        try? await Task.sleep(for: .seconds(1.2))
        #expect(!bayrak.deger, "zaman aşımından sonra iş iptal işaretini görmeli")
    }

    @Test func sureSinirliSonucuVeHatayiGecirir() async {
        let hizli: Int? = await sureSinirli(2) { 7 }
        #expect(hizli == 7)
        await #expect(throws: URLError.self) {
            _ = try await sureSinirli(2) { () async throws -> Int in throw URLError(.timedOut) }
        }
    }

    @Test func iptaldeBirakBaslamadanIptaldeIsiKosturmaz() async {
        let bayrak = E2Bayrak()
        let gorev = Task<Int?, Never> {
            withUnsafeCurrentTask { $0?.cancel() }
            return try? await iptaldeBirak { bayrak.koy(); return 1 }
        }
        let r = await gorev.value
        #expect(r == nil)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(!bayrak.deger)
    }

    // MARK: urlGuvenli sayısal biçimler (bulgu 158)

    @Test func urlGuvenliKisaltilmisVeAcikYazilmisAdresleriReddeder() {
        for s in ["https://127.1/", "https://10.1/", "https://0x7f.0.0.1/", "https://127.0x0.0.1/", "https://2130706433/", "https://3232235777/",
                  "https://0x7f000001/", "https://[0:0:0:0:0:0:0:1]/", "https://[0:0:0:0:0:ffff:7f00:1]/", "https://[::ffff:127.0.0.1]/",
                  "https://[fe80::1]/", "https://[febf::1]/", "https://[ff02::1]/", "https://[fd00::5]/", "https://[::]/"] {
            // Ayrıştırılamayan adres de getirilemez; reddedilmiş sayılır.
            #expect(URL(string: s).map { !WebSayfa.urlGuvenli($0) } ?? true, "\(s) reddedilmeli")
        }
        for s in ["https://example.com/x", "https://sub.alan.org/a?b=1", "https://8.8.8.8/", "https://[2606:4700:4700::1111]/", "https://v2.ornek.com.tr/"] {
            #expect(WebSayfa.urlGuvenli(URL(string: s)!), "\(s) kabul edilmeli")
        }
    }

    // MARK: Hızlı kazıma (bulgu 32)

    @Test func cokSatirliScriptVeStyleMetneGirmez() {
        let html = """
        <html><head><title>Sayfa</title><style>
        body { color: red; }
        </style></head><body><p>Görünür metin</p><script>
        var gizliDegisken = 1;
        </script><noscript>
        noscript uyarısı
        </noscript></body></html>
        """
        let rapor = WebKazimaHizli.rapor(html: html, kaynak: URL(string: "https://example.com/")!)
        let metin = rapor.ogeler.first { $0.tur == "metin" }?.deger ?? ""
        #expect(metin.contains("Görünür metin"))
        #expect(!metin.contains("gizliDegisken"))
        #expect(!metin.contains("color: red"))
        #expect(!metin.contains("noscript uyarısı"))
    }

    // MARK: CSV formül enjeksiyonu (bulgu 120)

    @Test func kazimaCSVFormulOnekleriniEtkisizlestirir() throws {
        let rapor = KazimaRaporu(kaynak: "https://example.com", baslik: "B", aciklama: "", dil: "tr", taramaTarihi: "2026-10-20T10:00:00.000Z", ogeler: [
            KazimaOgesi(id: "1", tur: "baglanti", ad: "=HYPERLINK(\"https://x\";\"t\")", deger: "+1", url: nil),
            KazimaOgesi(id: "2", tur: "tablo", ad: "@SUM(A1)", deger: "-2", url: nil),
            KazimaOgesi(id: "3", tur: "metin", ad: "Merhaba", deger: "Normal değer", url: "https://example.com/a")
        ])
        let csv = String(decoding: try KazimaDisaAktarici.veri(rapor, csv: true), as: UTF8.self)
        #expect(csv.contains("\"'=HYPERLINK(\"\"https://x\"\";\"\"t\"\")\""))
        #expect(csv.contains("\"'+1\""))
        #expect(csv.contains("\"'@SUM(A1)\""))
        #expect(csv.contains("\"'-2\""))
        #expect(csv.contains("\"Merhaba\",\"Normal değer\",\"https://example.com/a\""))
        #expect(csv.hasPrefix("\"tur\",\"ad\",\"deger\",\"url\""))
    }
}
