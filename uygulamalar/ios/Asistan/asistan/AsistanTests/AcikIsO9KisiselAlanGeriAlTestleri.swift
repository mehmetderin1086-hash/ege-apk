import Foundation
import Testing
@testable import Asistan

/// İçeriğin tarih dışı kimliği (JSON gidiş-dönüşünde Date hassasiyetine bağlı kalmamak için).
private func imza(_ i: KisiselAlan.Icerik) -> [String] {
    i.komutlar.map { "k:\($0.id.uuidString):\($0.baslik):\($0.metin)" } + i.yanitlar.map { "y:\($0.id.uuidString):\($0.metin)" }
}

/// O9: kişisel alan geri yüklemesinin geri alınması uygulama yeniden açıldıktan sonra da çalışır.
@Suite("O9 kişisel alan kalıcı geri alma") @MainActor
struct AcikIsO9KisiselAlanGeriAlTestleri {
    private func klasor() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appending(path: "o9-kisisel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    /// İçinde yalnız verilen yanıt bulunan bir kişisel alan yedeği.
    private func yedek(_ yanit: String, dir: URL) throws -> Data {
        let kaynak = KisiselAlan(dosya: dir.appending(path: "kaynak-\(UUID().uuidString).json"))
        #expect(kaynak.yanitKaydet(yanit))
        return try kaynak.yedekVerisi()
    }

    // (a) A → yedek B → yeniden açılış: geri alma sunulur, A'ya döner, kopya silinir; üçüncü açılışta sunulmaz.
    @Test func geriAlmaYenidenAcilistaSurerVeBirKezUygulanir() throws {
        let dir = try klasor(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "alan.json")
        let ilk = KisiselAlan(dosya: url)
        #expect(ilk.yanitKaydet("A içeriği"))
        let a = ilk.icerik
        #expect(ilk.yedegiYukle(try yedek("B içeriği", dir: dir)))
        #expect(ilk.icerik.yanitlar.map(\.metin) == ["B içeriği"])

        let ikinci = KisiselAlan(dosya: url)
        #expect(ikinci.icerik.yanitlar.map(\.metin) == ["B içeriği"])
        #expect(ikinci.oncekiIcerik.map(imza) == imza(a))
        #expect(ikinci.geriYuklemeyiGeriAl())
        #expect(imza(ikinci.icerik) == imza(a))
        #expect(ikinci.oncekiIcerik == nil)
        #expect(!FileManager.default.fileExists(atPath: ikinci.oncekiDosya.path))

        let ucuncu = KisiselAlan(dosya: url)
        #expect(ucuncu.oncekiIcerik == nil)
        #expect(imza(ucuncu.icerik) == imza(a))
        #expect(!ucuncu.geriYuklemeyiGeriAl())
    }

    // (b) Ana dosya bozuk: geri alma sunulmaz, ana dosyaya yazılmaz.
    @Test func bozukAnaDosyadaGeriAlmaSunulmaz() throws {
        let dir = try klasor(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "alan.json")
        let bozuk = Data("not valid json".utf8)
        try bozuk.write(to: url)
        try JSONEncoder().encode(KisiselAlan.Icerik()).write(to: dir.appending(path: "alan.onceki.json"))

        let alan = KisiselAlan(dosya: url)
        #expect(FileManager.default.fileExists(atPath: alan.oncekiDosya.path))
        #expect(alan.oncekiIcerik == nil)
        #expect(!alan.geriYuklemeyiGeriAl())
        #expect(try Data(contentsOf: url) == bozuk)
        // Önceki kopya da korunur (ana alan düzelince yeniden değerlendirilebilir).
        #expect(FileManager.default.fileExists(atPath: alan.oncekiDosya.path))
    }

    // (c) Önceki kopyası bozuk: geri alma sunulmaz, kopya silinmez.
    @Test func bozukOncekiKopyaSilinmez() throws {
        let dir = try klasor(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "alan.json")
        let ilk = KisiselAlan(dosya: url)
        #expect(ilk.yanitKaydet("Kalıcı"))
        let bozuk = Data("{bozuk".utf8)
        try bozuk.write(to: ilk.oncekiDosya)

        let alan = KisiselAlan(dosya: url)
        #expect(alan.icerik.yanitlar.map(\.metin) == ["Kalıcı"])
        #expect(alan.oncekiIcerik == nil)
        #expect(!alan.geriYuklemeyiGeriAl())
        #expect(try Data(contentsOf: alan.oncekiDosya) == bozuk)
    }

    // (d) Ana dosya yazılamıyorsa geri yükleme false döner ve önceki kopya diskte bırakılmaz.
    @Test func yarimKalanGeriYuklemeOncekiKopyaBirakmaz() throws {
        let dir = try klasor(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "alan.json")
        let alan = KisiselAlan(dosya: url)   // dosya yok: okunabilir, boş varsayılan
        let veri = try yedek("Yüklenemeyecek", dir: dir)
        // Ana dosya yolunda boş olmayan bir klasör: atomik yazım (taşıma) başarısız olur.
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url.appending(path: "engel.txt"))

        #expect(!alan.yedegiYukle(veri))
        #expect(alan.hata != nil)
        #expect(alan.oncekiIcerik == nil)
        #expect(!FileManager.default.fileExists(atPath: alan.oncekiDosya.path))
        #expect(!alan.icerik.yanitlar.map(\.metin).contains("Yüklenemeyecek"))
    }

    // (d') Bellekte önceki başarılı geri yüklemenin geri alması varken yarım kalan yükleme disk kopyasını onunla eşitler.
    @Test func yarimKalanGeriYuklemeOncekiGeriAlmayiKorur() throws {
        let dir = try klasor(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "alan.json")
        let alan = KisiselAlan(dosya: url)
        #expect(alan.yanitKaydet("A içeriği"))
        let a = alan.icerik
        #expect(alan.yedegiYukle(try yedek("B içeriği", dir: dir)))
        let veri = try yedek("C içeriği", dir: dir)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url.appending(path: "engel.txt"))

        #expect(!alan.yedegiYukle(veri))
        #expect(alan.oncekiIcerik.map(imza) == imza(a))
        let disk = try JSONDecoder().decode(KisiselAlan.Icerik.self, from: Data(contentsOf: alan.oncekiDosya))
        #expect(imza(disk) == imza(a))
    }
}
