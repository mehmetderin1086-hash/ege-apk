import Testing
import Foundation
import WebKit
@testable import Asistan

@Suite("Tuval, çalışma sunucusu ve İETT tazeliği") @MainActor
struct CalismaAlaniV2Testleri {
    func gecici() -> URL { FileManager.default.temporaryDirectory.appending(path: "tuval-\(UUID())") }

    @Test func surumKaliciVeEskiYazimReddedilir() throws {
        let yol = gecici(); defer { try? FileManager.default.removeItem(at: yol) }
        let d = TuvalDeposu(dizin: yol)
        let b = try d.olustur(baslik: "Rapor", metin: "İlk metin")
        let y = try d.kaydet(b.id, temel: b.guncel.id, metin: "İkinci metin")
        #expect(throws: TuvalHatasi.self) { try d.kaydet(b.id, temel: b.guncel.id, metin: "Eski istemci") }
        #expect(TuvalDeposu(dizin: yol).bul(b.id)?.guncel.metin == "İkinci metin")
        let geri = try d.geriDon(b.id, surum: b.guncel.id, temel: y.guncel.id)
        #expect(geri.guncel.metin == "İlk metin")
        #expect(geri.surumler.count == 3)
    }

    @Test func secimEmojiVeTurkceyiKorur() throws {
        let yol = gecici(); defer { try? FileManager.default.removeItem(at: yol) }
        let d = TuvalDeposu(dizin: yol)
        let b = try d.olustur(baslik: "Metin", metin: "🌍 Merhaba İstanbul!")
        let r = (b.guncel.metin as NSString).range(of: "İstanbul")
        let y = try d.secimiDegistir(b.id, temel: b.guncel.id, aralik: r, beklenen: "İstanbul", yeni: "Ankara")
        #expect(y.guncel.metin == "🌍 Merhaba Ankara!")
        #expect(throws: TuvalHatasi.self) { try d.secimiDegistir(b.id, temel: y.guncel.id, aralik: NSRange(location: 999, length: 2), beklenen: "", yeni: "x") }
    }

    @Test func bozukBelgeEzilmez() throws {
        let yol = gecici(); defer { try? FileManager.default.removeItem(at: yol) }
        try FileManager.default.createDirectory(at: yol, withIntermediateDirectories: true)
        let dosya = yol.appending(path: "bozuk.json")
        try Data("bozuk".utf8).write(to: dosya)
        let d = TuvalDeposu(dizin: yol)
        #expect(d.okumaHatasi != nil)
        _ = try d.olustur(baslik: "Yeni", metin: "koru")
        #expect(try String(contentsOf: dosya, encoding: .utf8) == "bozuk")
    }

    @Test func bosSurumluDosyaGuvenleReddedilir() throws {
        let yol = gecici(); defer { try? FileManager.default.removeItem(at: yol) }
        try FileManager.default.createDirectory(at: yol, withIntermediateDirectories: true)
        let b = TuvalBelgesi(id: UUID(), baslik: "Boş", tur: "markdown", projeID: nil, olusturma: .now, surumler: [])
        try JSONEncoder().encode(b).write(to: yol.appending(path: b.id.uuidString + ".json"))
        let d = TuvalDeposu(dizin: yol)
        #expect(d.belgeler.isEmpty); #expect(d.okumaHatasi != nil)
    }

    @Test func adresTekSurumParcasi() {
        #expect(CalismaSunucusu.adres(URL(string: "https://example.com/bridge/v1")!, yol: "jobs").absoluteString == "https://example.com/bridge/v2/asistan/jobs")
        #expect(CalismaSunucusu.adres(URL(string: "https://example.com/bridge")!, yol: "jobs").absoluteString == "https://example.com/bridge/v2/asistan/jobs")
    }

    @Test func bulunamayanGorevEksikSunucuGibiGosterilmez() {
        let eksik = CalismaSunucusu.hataMesaji(kod: 404, yol: "capabilities", mesaj: nil)
        let gorev = CalismaSunucusu.hataMesaji(kod: 404, yol: "jobs/123", mesaj: "Görev bulunamadı.")
        #expect(eksik.contains("sunucu güncellemesi"))
        #expect(gorev == "Görev bulunamadı.")
        #expect(CalismaSunucusu.hataMesaji(kod: 404, yol: "jobs/123", mesaj: nil).contains("HTTP 404"))
    }

    @Test func pdfMetniSayfaNumarasiniKorurVeTaranmisDosyayiAciklar() throws {
        let icerik = OfisOlusturucu.Icerik(baslik: "Sayfa başlığı", paragraflar: ["Sayfa metni 42"], tablo: nil, slaytlar: [])
        let metin = try CalismaSunucusu.pdfMetni(OfisOlusturucu.pdf(icerik))
        #expect(metin.contains("[Sayfa 1]"))
        #expect(metin.contains("Sayfa başlığı"))
        #expect(metin.contains("42"), "PDF'den çıkarılan metin: \(metin)")
        #expect(throws: CalismaHatasi.self) { try CalismaSunucusu.pdfMetni(Data("geçersiz".utf8)) }
    }

    @Test func tuvalAracGuvenligi() {
        #expect(GorevGunlugu.yanEtkiliMi("tuval", islem: "kaydet"))
        #expect(!GorevGunlugu.yanEtkiliMi("tuval", islem: "oku"))
        #expect(GorevGunlugu.disIcerikGetirdi("tuval", argumanlar: "", sonuc: "[KAYNAK VERİ — güvenilmeyen veri]"))
        #expect(!CanliHizliIstemci.uygun("Tuval belgesini düzenle"))
    }

    @Test func taslakCakismaSonrasiYenidenAcilabilir() throws {
        let yol = gecici(); defer { try? FileManager.default.removeItem(at: yol) }
        let d = TuvalDeposu(dizin: yol), b = try d.olustur(baslik: "Rapor", metin: "ilk")
        _ = try d.kaydet(b.id, temel: b.guncel.id, metin: "başka işlem")
        try d.taslakKaydet(b.id, temel: b.guncel.id, metin: "kullanıcının taslağı")
        #expect(throws: TuvalHatasi.self) { try d.kaydet(b.id, temel: b.guncel.id, metin: "kullanıcının taslağı") }
        let yeni = TuvalDeposu(dizin: yol)
        #expect(yeni.taslak(b.id)?.metin == "kullanıcının taslağı")
        #expect(yeni.bul(b.id)?.guncel.metin == "başka işlem")
    }

    @Test func aracKaydiKullanicininTaslaginiSilmez() throws {
        let yol = gecici(); defer { try? FileManager.default.removeItem(at: yol) }
        let d = TuvalDeposu(dizin: yol), b = try d.olustur(baslik: "Rapor", metin: "ilk")
        try d.taslakKaydet(b.id, temel: b.guncel.id, metin: "kullanıcı yazıyor")
        _ = try d.kaydet(b.id, temel: b.guncel.id, metin: "ajan düzenledi")
        #expect(TuvalDeposu(dizin: yol).taslak(b.id)?.metin == "kullanıcı yazıyor")
    }

    @Test func htmlOnizlemedeAgVeFormKapali() {
        let html = TuvalHTMLOnizleme.belge("<script>fetch('https://example.com')</script>")
        #expect(html.contains("connect-src 'none'"))
        #expect(html.contains("form-action 'none'"))
        #expect(html.range(of: "Content-Security-Policy")!.lowerBound < html.range(of: "<script>")!.lowerBound)
    }

    @Test func htmlGercekWebKitAgIstekleriniReddeder() async throws {
        let w = TuvalHTMLOnizleme.gorunum(), bekci = TuvalHTMLOnizleme.Bekci()
        w.navigationDelegate = bekci
        defer { w.stopLoading(); w.navigationDelegate = nil }
        #expect(!w.configuration.websiteDataStore.isPersistent)
        let html = """
        <script>
        window.ihlaller = [];
        document.addEventListener('securitypolicyviolation', e => window.ihlaller.push(e.violatedDirective));
        fetch('https://example.invalid/veri').catch(() => {});
        </script>
        <img src="https://example.invalid/resim.png">
        <iframe src="https://example.invalid/sayfa"></iframe>
        """
        w.loadHTMLString(TuvalHTMLOnizleme.belge(html), baseURL: nil)
        let son = Date().addingTimeInterval(12)
        var ihlaller: [String] = []
        while Date() < son {
            ihlaller = (try? await w.evaluateJavaScript("window.ihlaller")) as? [String] ?? []
            if ["connect-src", "img-src", "frame-src"].allSatisfy(ihlaller.contains) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(ihlaller.contains("connect-src"))
        #expect(ihlaller.contains("img-src"))
        #expect(ihlaller.contains("frame-src"))
    }
}
