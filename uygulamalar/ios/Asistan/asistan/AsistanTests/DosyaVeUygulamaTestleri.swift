import Foundation
import Testing
@testable import Asistan

@Suite("Dosyalar ve uygulama köprüleri") @MainActor
struct DosyaVeUygulamaTestleri {
    private func alan() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "asistan-dosya-test-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    @Test func klasorIcerikAramaKalicilikVeIptal() async throws {
        let root = try alan(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "Belgeler", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "Alt"), withIntermediateDirectories: true)
        try "Biyoloji: hücre ve kalıtım notları".write(to: folder.appending(path: "Alt/not.txt"), atomically: true, encoding: .utf8)
        try "Ayrı içerik".write(to: folder.appending(path: "Hücre.md"), atomically: true, encoding: .utf8)
        let store = root.appending(path: "baglar.json")
        let k = DosyaKitapligi(kayitURL: store)
        try k.bagla(folder); try k.bagla(folder)
        #expect(k.klasorler.count == 1)
        #expect(DosyaKitapligi(kayitURL: store).klasorler.count == 1)
        let r = try await k.ara("hücre", icerikte: true)
        #expect(r.sonuclar.count == 2)
        let sonuc = try #require(r.sonuclar.first { $0.ad == "not.txt" })
        #expect(try await k.oku(sonuc.id.uuidString).contains("kalıtım"))
        #expect(try await k.ara("hücre", icerikte: false).sonuclar.count == 1)
        await #expect(throws: DosyaTarayici.Hata.self) { try await k.oku(sonuc.id.uuidString) }
        k.kaldir(try #require(k.klasorler.first).id)
        #expect(k.klasorler.isEmpty)
        #expect(FileManager.default.fileExists(atPath: folder.path))
    }
    @Test func sinirDisiDosyalarVeSembolikBaglarOkunmaz() throws {
        let root = try alan(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "izinli"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dis = root.appending(path: "ozel.txt"); try "Özel".write(to: dis, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: folder.appending(path: "bag.txt"), withDestinationURL: dis)
        for yol in ["../ozel.txt", dis.path, "bag.txt"] {
            #expect(throws: DosyaTarayici.Hata.self) { try DosyaTarayici.guvenliURL(root: folder, yol: yol) }
        }
    }
    @Test func bozukKayitEzilmez() throws {
        let root = try alan(); defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appending(path: "bag.json"); let data = Data("bozuk".utf8); try data.write(to: store)
        let k = DosyaKitapligi(kayitURL: store)
        #expect(k.hata != nil)
        #expect(throws: DosyaTarayici.Hata.self) { try k.bagla(root) }
        #expect(try Data(contentsOf: store) == data)
    }
    @Test func buyukIcerikVeDesteklenmeyenDosya() throws {
        let root = try alan(); defer { try? FileManager.default.removeItem(at: root) }
        let large = root.appending(path: "buyuk.txt"); try Data(repeating: 65, count: 2_000_001).write(to: large)
        #expect(throws: DosyaTarayici.Hata.self) { try DosyaTarayici.metin(large) }
        let unknown = root.appending(path: "dosya.bin"); try Data([0,1,2]).write(to: unknown)
        #expect(throws: DosyaTarayici.Hata.self) { try DosyaTarayici.metin(unknown) }
        #expect(DosyaTarayici.alinti("İSTANBUL bilgisi", sorgu: "istanbul") != nil)
    }
    @Test func whatsappGirdisiJSONVeTekKopru() throws {
        let message = "Merhaba \"Mehmet\"\nA+B & C?"
        let raw = try #require(UygulamaBaglantilari.whatsappGirdisi(hedef: "+90 555 123 45 67", metin: message))
        let data = try #require(raw.data(using: .utf8))
        let obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(obj == ["telefon": "905551234567", "mesaj": message])
        #expect(UygulamaBaglantilari.whatsappGirdisi(hedef: "javascript:alert(1)", metin: message) == nil)
        #expect(UygulamaBaglantilari.whatsappGirdisi(hedef: "+905551234567", metin: "  ") == nil)
        let suite = "baglantilar.test.\(UUID())"; let d = try #require(UserDefaults(suiteName: suite)); defer { d.removePersistentDomain(forName: suite) }
        let b = UygulamaBaglantilari(defaults: d)
        try b.kaydet(ad: "Gönder", uygulama: "WhatsApp", kestirme: "Bir", whatsapp: true)
        try b.kaydet(ad: "Gönder", uygulama: "WhatsApp", kestirme: "İki", whatsapp: true)
        #expect(b.kayitlar.count == 1)
        #expect(UygulamaBaglantilari(defaults: d).kayitlar.first?.kestirme == "İki")
        let durum = b.ozet(uygulamaKoprusuKurulu: true)
        #expect(durum == .init(uygulamaKoprusuKurulu: true, bagliEylemSayisi: 1, whatsappHazir: true))
        #expect(durum.durumMetni == "Uygulama köprüsü hazır · 1 bağlı eylem · WhatsApp köprüsü bağlı")
    }
    @Test func gercekUygulamaKataloguVeHazirKestirmeler() throws {
        let suite = "katalog.test.\(UUID())"; let d = try #require(UserDefaults(suiteName: suite)); defer { d.removePersistentDomain(forName: suite) }
        let k = UygulamaKatalogu(defaults: d)
        #expect(k.uygulamalar.count >= 80)
        #expect(Set(k.uygulamalar.map(\.id)).count == k.uygulamalar.count)
        #expect(k.bul("whatsapp")?.id == "net.whatsapp.WhatsApp")
        #expect(k.bul("HESAP MAKİNESİ")?.id == "com.apple.calculator")
        #expect(k.bul("ScreenSharingServer") == nil)
        #expect(!k.kopruEklendi)
        let url = try k.kopruHazirla()
        #expect(try Data(contentsOf: url).prefix(4) == Data("AEA1".utf8))
        let app = try #require(k.bul("Telegram"))
        #expect(k.calistirmaURL(app) == nil)
        k.kopruEklendi = true
        #expect(UygulamaKatalogu(defaults: d).kopruEklendi)
        let runURL = try #require(k.calistirmaURL(app))
        let components = try #require(URLComponents(url: runURL, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.first(where: { $0.name == "text" })?.value == "ph.telegra.Telegraph")
        #expect(components.queryItems?.first(where: { $0.name == "name" })?.value == "Mehmet Uygulama Koprusu")
    }
    @Test func katalogDisiUygulamaTekKopruyeEklenir() throws {
        let suite = "katalog.ozel.test.\(UUID())"; let d = try #require(UserDefaults(suiteName: suite)); defer { d.removePersistentDomain(forName: suite) }
        let k = UygulamaKatalogu(defaults: d)
        try k.ozelEkle(ad: "Yeni Uygulama", kimlik: "com.ornek.yeni", digerAdlar: "Yeni, Ornek")
        #expect(k.bul("örnek")?.id == "com.ornek.yeni")
        #expect(UygulamaKatalogu(defaults: d).bul("Yeni Uygulama")?.id == "com.ornek.yeni")
        k.kopruEklendi = true
        let app = try #require(k.bul("Yeni"))
        let url = try #require(k.calistirmaURL(app))
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "text" })?.value == "com.ornek.yeni")
        #expect(throws: UygulamaKatalogu.Hata.self) { try k.ozelEkle(ad: "", kimlik: "gecersiz kimlik") }
    }
}
