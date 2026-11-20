#if DEBUG
import Testing
import Foundation
@testable import Asistan

/// P3.10-kabul: sınama raporlarının merkezi yazıcısı (`AsistanSinama.kaydet`) ve kabul ölçütü.
/// Ağa, izne ya da gerçek modele çıkmaz; her test kendi geçici klasörüne yazar (Documents'a dokunmaz).
@Suite("P3.10 cihaz kabul turu")
struct Gelistirme_P3_10_kabul_Testleri {

    private func geciciKlasor() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appending(path: "kabul-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func oku(_ url: URL) throws -> [String: Any] {
        let veri = try Data(contentsOf: url)
        return try #require((try JSONSerialization.jsonObject(with: veri)) as? [String: Any])
    }

    // MARK: Koşu kimliği

    @Test func kosuKimligiArgumandanOkunur() {
        #expect(AsistanSinama.kosuKimligi(["Asistan", "--asistan-hiz-kabul", "--sinama-kosu=ABC-123"]) == "ABC-123")
        #expect(AsistanSinama.kosuKimligi(["Asistan", "--asistan-hiz-kabul"]) == nil)
        #expect(AsistanSinama.kosuKimligi(["Asistan", "--sinama-kosu="]) == nil, "boş kimlik yok sayılır")
        #expect(AsistanSinama.kosuKimligi(["--sinama-kosu=eski", "--sinama-kosu=yeni"]) == "yeni", "sonuncusu geçerli")
    }

    // MARK: Kabul ölçütü

    @Test func kabulOlcutu() {
        #expect(AsistanSinama.kabulBasarili(["tamamlandi": true, "hata": ""]))
        #expect(!AsistanSinama.kabulBasarili(["tamamlandi": false]))
        #expect(!AsistanSinama.kabulBasarili(["tamamlandi": true, "hata": "zaman doldu"]))
        #expect(AsistanSinama.kabulBasarili(["asama": "tamamlandi", "zamanAsimi": false, "hata": ""]), "asistan-sinama.json biçimi")
        #expect(!AsistanSinama.kabulBasarili(["asama": "tamamlandi", "zamanAsimi": true]))
        #expect(!AsistanSinama.kabulBasarili(["asama": "baglanti_hatasi"]))
        #expect(!AsistanSinama.kabulBasarili([:]))
    }

    @Test func altTurHatasiUstTamamlandiIleOrtulemez() {
        for alt: [String: Any] in [["hata": "ses yok"], ["dinlemeyeDondu": false], ["bitti": false], ["okundu": false]] {
            let rapor: [String: Any] = ["tamamlandi": true, "turlar": [alt]]
            #expect(!AsistanSinama.kabulBasarili(rapor))
            #expect(!SinamaKaydi.ozetle(ad: "live", json: rapor).basarili)
        }
        #expect(AsistanSinama.kabulBasarili(["tamamlandi": true, "turlar": [["bitti": true, "hata": ""]]]))
    }

    // MARK: Merkezi yazıcı

    @Test func kaydetKosuSurumVeBitisAlanlariniEkler() throws {
        let k = try geciciKlasor(); defer { try? FileManager.default.removeItem(at: k) }
        AsistanSinama.kaydet("asistan-ofis-sinama.json", ["tamamlandi": true, "dosyalar": [["ad": "a.docx"]]],
                             klasor: k, kosu: "K-1", surum: "0.21.0 (202610201530) · git abc · Debug")
        let json = try oku(k.appending(path: "asistan-ofis-sinama.json"))
        #expect(json["kosu"] as? String == "K-1")
        #expect(json["surum"] as? String == "0.21.0 (202610201530) · git abc · Debug")
        #expect(json["kosuBitti"] as? Bool == true)
        #expect(json["tamamlandi"] as? Bool == true, "var olan alanlar değişmez")
        #expect((json["dosyalar"] as? [Any])?.count == 1)
        let satirlar = SinamaKaydi.oku(klasor: k)
        #expect(satirlar.count == 1)
        #expect(satirlar.first?.ad == "ofis-sinama")
        #expect(satirlar.first?.kosu == "K-1")
        #expect(satirlar.first?.basarili == true)
    }

    @Test func kosuYoksaAlanYazilmaz() throws {
        let k = try geciciKlasor(); defer { try? FileManager.default.removeItem(at: k) }
        AsistanSinama.kaydet("asistan-x.json", ["tamamlandi": true], klasor: k, kosu: nil, surum: "t")
        let json = try oku(k.appending(path: "asistan-x.json"))
        #expect(json["kosu"] == nil)
        #expect(json["surum"] as? String == "t")
    }

    @Test func araYazimSatirUretmezSonYazimBasarisizSatirUretir() throws {
        let k = try geciciKlasor(); defer { try? FileManager.default.removeItem(at: k) }
        let url = k.appending(path: "asistan-hiz-kabul.json")
        // hiz-kabul benzeri: tur sürerken sakla(false).
        AsistanSinama.kaydet("asistan-hiz-kabul.json", ["tamamlandi": false, "turlar": [["ad": "otomatik-selam", "durum": "başladı"]]],
                             bitti: false, klasor: k, kosu: "K-2", surum: "t")
        #expect(SinamaKaydi.oku(klasor: k).isEmpty, "ara yazım tabloya düşmez")
        #expect(try oku(url)["kosuBitti"] as? Bool == false)
        // Son yazım başarısız olsa da satır düşer.
        AsistanSinama.kaydet("asistan-hiz-kabul.json", ["tamamlandi": false, "turlar": []], bitti: true, klasor: k, kosu: "K-2", surum: "t")
        let satirlar = SinamaKaydi.oku(klasor: k)
        #expect(satirlar.count == 1)
        #expect(satirlar.first?.basarili == false)
        #expect(satirlar.first?.ozet.hasPrefix("Tamamlanmadı") == true)
        #expect(try oku(url)["kosuBitti"] as? Bool == true)
    }

    @Test func sinamaBicimindeAsamaTamamlandiBasariliSayilir() throws {
        let k = try geciciKlasor(); defer { try? FileManager.default.removeItem(at: k) }
        AsistanSinama.kaydet("asistan-sinama.json", ["asama": "tamamlandi", "zamanAsimi": false, "hata": "", "sureSaniye": 12],
                             klasor: k, kosu: "K-3", surum: "t")
        AsistanSinama.kaydet("asistan-sinama.json", ["asama": "tamamlandi", "zamanAsimi": true, "hata": ""],
                             klasor: k, kosu: "K-4", surum: "t")
        let satirlar = SinamaKaydi.oku(klasor: k)
        #expect(satirlar.map(\.basarili) == [true, false])
        #expect(satirlar.first?.sureSn == 12)
    }

    @Test func hataliSonYazimHataOzetiTasir() throws {
        let k = try geciciKlasor(); defer { try? FileManager.default.removeItem(at: k) }
        AsistanSinama.kaydet("asistan-arsiv-sinama.json", ["tamamlandi": false, "hata": "RAR açılamadı"], klasor: k, kosu: nil, surum: "t")
        let satir = try #require(SinamaKaydi.oku(klasor: k).first)
        #expect(!satir.basarili)
        #expect(satir.ozet.contains("RAR açılamadı"))
    }

    @Test func iceAktarAyniRaporuIkinciKezEklemez() throws {
        let k = try geciciKlasor(); defer { try? FileManager.default.removeItem(at: k) }
        AsistanSinama.kaydet("asistan-ofis-sinama.json", ["tamamlandi": true], klasor: k, kosu: "K-5", surum: "t")
        #expect(SinamaKaydi.iceAktar(klasor: k) == 0, "satır zamanı dosyanın değişiklik anıdır")
        #expect(SinamaKaydi.oku(klasor: k).count == 1)
    }

    @Test func diziBicimiDegismezSonYazimdaSatirDuser() throws {
        let k = try geciciKlasor(); defer { try? FileManager.default.removeItem(at: k) }
        let url = k.appending(path: "asistan-otomatik-sinama.json")
        AsistanSinama.kaydet("asistan-otomatik-sinama.json", dizi: [["istek": "a", "basarili": true]], bitti: false, klasor: k)
        #expect(SinamaKaydi.oku(klasor: k).isEmpty)
        AsistanSinama.kaydet("asistan-otomatik-sinama.json", dizi: [["istek": "a"], ["istek": "b", "hata": "ağ yok"]], klasor: k)
        let dizi = try #require((try JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [[String: Any]])
        #expect(dizi.count == 2, "üst düzey dizi olarak kalır")
        let satir = try #require(SinamaKaydi.oku(klasor: k).first)
        #expect(!satir.basarili)
        #expect(satir.ozet.contains("ağ yok"))
    }

    @Test func gecersizNesneYazilmazCokmez() throws {
        let k = try geciciKlasor(); defer { try? FileManager.default.removeItem(at: k) }
        AsistanSinama.kaydet("asistan-bozuk.json", ["tarih": Date()], klasor: k, kosu: nil, surum: "t")
        #expect(!FileManager.default.fileExists(atPath: k.appending(path: "asistan-bozuk.json").path))
        #expect(SinamaKaydi.oku(klasor: k).isEmpty)
    }
}
#endif
