import Foundation
import CryptoKit
import Testing
@testable import Asistan

@Suite("Büyük dosya ve sınırlı belge işleme")
struct BuyukDosyaTestleri {
    @Test @MainActor func bozukYuklemeKaydiYeniYuklemeyleEzilmez() throws {
        let ad = "yukleme-test-\(UUID())"
        let ayarlar = try #require(UserDefaults(suiteName: ad))
        defer { ayarlar.removePersistentDomain(forName: ad) }
        let anahtar = "asistan.buyukYuklemeler.v1"
        let veri = Data("bozuk kayıt".utf8)
        ayarlar.set(veri, forKey: anahtar)
        let yukleyici = BuyukDosyaYukleyici(ayarlar: ayarlar)
        yukleyici.baslat(URL(fileURLWithPath: "/gecersiz"))
        #expect(!yukleyici.etkin)
        #expect(yukleyici.hata?.contains("korunuyor") == true)
        #expect(ayarlar.data(forKey: anahtar) == veri)
    }

    @Test func gbOfsetiDosyayiBellegeAlmadanOkunur() async throws {
        let u = FileManager.default.temporaryDirectory.appending(path: "sparse-\(UUID())")
        defer { try? FileManager.default.removeItem(at: u) }
        FileManager.default.createFile(atPath: u.path, contents: nil)
        let f = try FileHandle(forWritingTo: u)
        let ofset: Int64 = 3 * 1024 * 1024 * 1024
        try f.truncate(atOffset: UInt64(ofset + 6)); try f.seek(toOffset: UInt64(ofset)); try f.write(contentsOf: Data("son123".utf8)); try f.close()
        let parca = try await BuyukDosyaYukleyici.parcaOku(u, ofset: ofset, boyut: 1024, beklenenBoyut: ofset + 6)
        #expect(String(data: parca, encoding: .utf8) == "son123")
    }

    @Test func akiskanHashVeSonParcaDogru() async throws {
        let u = FileManager.default.temporaryDirectory.appending(path: "hash-\(UUID())")
        defer { try? FileManager.default.removeItem(at: u) }
        let veri = Data(repeating: 42, count: BuyukDosyaYukleyici.parcaBoyutu + 17)
        try veri.write(to: u)
        let bilgi = try await BuyukDosyaYukleyici.dosyaOzeti(u)
        #expect(bilgi.boyut == Int64(veri.count))
        #expect(bilgi.ozet == BuyukDosyaYukleyici.ozet(veri))
        let son = try await BuyukDosyaYukleyici.parcaOku(u, ofset: Int64(BuyukDosyaYukleyici.parcaBoyutu), boyut: 1024, beklenenBoyut: bilgi.boyut)
        #expect(son == Data(repeating: 42, count: 17))
    }

    @Test func sunucuYanlisDosyaVeyaOfsetVeremez() throws {
        let k = YuklemeKaydi(id: UUID().uuidString, ad: "a.bin", boyut: 100, sha256: "abc", sunucu: "kimlik", ofset: 0)
        let d = YuklemeDurumu(id: k.id, name: k.ad, size: 100, sha256: "abc", offset: 101, status: "uploading", chunk_bytes: 8)
        #expect(throws: CalismaHatasi.self) { try BuyukDosyaYukleyici.durumDogrula(d, kayit: k) }
        let g = YuklemeDurumu(id: k.id, name: k.ad, size: 100, sha256: "abc", offset: 20, status: "uploading", chunk_bytes: 8)
        try BuyukDosyaYukleyici.durumDogrula(g, kayit: k)
    }

    @Test func yuklemeSiniriIslemeSiniriDegildir() {
        let d = KasaDosyasi(id: "id", name: "buyuk.csv", size: 2 * 1024 * 1024 * 1024, sha256: "hash")
        #expect(!d.kaynakOlabilir(tur: "research")); #expect(!d.kaynakOlabilir(tur: "analysis"))
        let k = KasaDosyasi(id: "id", name: "tablo.xlsx", size: 2 * 1024 * 1024, sha256: "hash")
        #expect(k.kaynakOlabilir(tur: "analysis")); #expect(!k.kaynakOlabilir(tur: "research"))
    }

    @Test func buyukArastirmaYalnizSunucuDestekliyorsaAcilir() throws {
        let eski = try JSONDecoder().decode(CalismaYetenekleri.self, from: Data(#"{"version":2,"modules":{},"paid_enabled":false}"#.utf8))
        #expect(eski.arastirmaKaynakSiniri == 200_000)
        let yeni = try JSONDecoder().decode(CalismaYetenekleri.self, from: Data(#"{"version":2,"modules":{"source_retrieval":true},"paid_enabled":false,"limits":{"file_bytes":10737418240,"storage_bytes":53687091200,"research_source_bytes":67108864}}"#.utf8))
        #expect(yeni.arastirmaKaynakSiniri == 64 * 1024 * 1024)
        let d = KasaDosyasi(id: "id", name: "Kaynak.TXT", size: 64 * 1024 * 1024, sha256: "hash")
        #expect(!d.kaynakOlabilir(tur: "research", arastirmaSiniri: eski.arastirmaKaynakSiniri))
        #expect(d.kaynakOlabilir(tur: "research", arastirmaSiniri: yeni.arastirmaKaynakSiniri))
        #expect(!d.kaynakOlabilir(tur: "audio", arastirmaSiniri: yeni.arastirmaKaynakSiniri))
        #expect(!d.kaynakOlabilir(tur: "study", arastirmaSiniri: yeni.arastirmaKaynakSiniri))
        #expect(!d.kaynakOlabilir(tur: "document", arastirmaSiniri: yeni.arastirmaKaynakSiniri))
        let fazla = KasaDosyasi(id: "id", name: "a.txt", size: d.size + 1, sha256: "hash")
        #expect(!fazla.kaynakOlabilir(tur: "research", arastirmaSiniri: Int64.max))
        let pdf = KasaDosyasi(id: "id", name: "a.pdf", size: 1000, sha256: "hash")
        #expect(!pdf.kaynakOlabilir(tur: "research", arastirmaSiniri: yeni.arastirmaKaynakSiniri))
    }

    @Test func calismaTuruDegisinceKaynakYenidenDogrulanir() {
        let d = KasaDosyasi(id: "id", name: "kitap.txt", size: 64 * 1024 * 1024, sha256: "")
        #expect(KasaDosyasi.kaynakUyarisi([d], tur: "research", arastirmaSiniri: d.size) == nil)
        #expect(KasaDosyasi.kaynakUyarisi([d], tur: "document", arastirmaSiniri: d.size) != nil)
        #expect(KasaDosyasi.kaynakUyarisi([d], tur: "analysis", arastirmaSiniri: d.size) != nil)
        #expect(KasaDosyasi.kaynakUyarisi([d, d, d], tur: "research", arastirmaSiniri: d.size) != nil)
        #expect(KasaDosyasi.kaynakUyarisi([], tur: "document", arastirmaSiniri: d.size) == nil)
    }

    @Test func ofisXmlAcmaSiniriGercekteUygulanir() throws {
        let u = FileManager.default.temporaryDirectory.appending(path: "ofis-sinir-\(UUID()).docx")
        defer { try? FileManager.default.removeItem(at: u) }
        try ZipYazici.olustur([("word/document.xml", Data(repeating: 32, count: 8_000_001))]).write(to: u)
        #expect(throws: BelgeOkuyucu.Hata.self) { try BelgeOkuyucu.oku(u) }
    }

    @Test func normalOfisMetniHalaOkunur() throws {
        let u = FileManager.default.temporaryDirectory.appending(path: "ofis-\(UUID()).docx")
        defer { try? FileManager.default.removeItem(at: u) }
        let xml = Data("<w:document xmlns:w=\"urn:w\"><w:p><w:t>İstanbul 42</w:t></w:p></w:document>".utf8)
        try ZipYazici.olustur([("word/document.xml", xml)]).write(to: u)
        #expect(try BelgeOkuyucu.oku(u).metin.contains("İstanbul 42"))
    }
}
