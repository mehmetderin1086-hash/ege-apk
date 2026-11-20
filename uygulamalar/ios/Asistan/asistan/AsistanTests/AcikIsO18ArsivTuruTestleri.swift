import Foundation
import Testing
@testable import Asistan

/// O18: arşivden çıkan dosyalar ayrı türle ('arsiv') kaydedilir ve İndirmeler ekranında ayrı bölümde listelenir.
@Suite("O18 arşiv türü") @MainActor struct AcikIsO18ArsivTuruTestleri {
    private func geciciDosya() throws -> URL {
        try FileManager.default.createDirectory(at: IndirmeYoneticisi.klasor, withIntermediateDirectories: true)
        let url = IndirmeYoneticisi.klasor.appending(path: UUID().uuidString + "-o18-deneme.txt")
        try Data("o18".utf8).write(to: url)
        return url
    }

    @Test func yerelKayitArsivTurunuTasir() throws {
        let url = try geciciDosya()
        defer { try? FileManager.default.removeItem(at: url) }
        let k = try #require(IndirmeYoneticisi.yerelKayit(url: url, gorunenAd: "deneme.txt", tur: IndirmeYoneticisi.arsivTuru))
        #expect(k.tur == "arsiv")
        #expect(k.durum == "done")
        #expect(k.yerel)
        #expect(k.dosya == url.lastPathComponent)
        #expect(k.ad == "deneme.txt")
    }

    @Test func yerelKayitVarsayilanTuruDosya() throws {
        let url = try geciciDosya()
        defer { try? FileManager.default.removeItem(at: url) }
        let k = try #require(IndirmeYoneticisi.yerelKayit(url: url, gorunenAd: "deneme.txt"))
        #expect(k.tur == "file")
        #expect(k.yerel)
    }

    @Test func klasorDisiDosyaKaydedilmez() throws {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString + "-o18-disarida.txt")
        try Data("o18".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(IndirmeYoneticisi.yerelKayit(url: url, gorunenAd: "x", tur: IndirmeYoneticisi.arsivTuru) == nil)
        // Klasör içinde ama dosya yoksa da kayıt yok.
        let yok = IndirmeYoneticisi.klasor.appending(path: UUID().uuidString + "-yok.txt")
        #expect(IndirmeYoneticisi.yerelKayit(url: yok, gorunenAd: "x") == nil)
    }

    @Test func gruplarSirayiKorurVeArsiviAyirir() {
        let a = IndirmeKaydi(adres: "https://example.com/a.pdf", tur: "file", ad: "a")
        let b = IndirmeKaydi(adres: "https://local.invalid/b.txt", tur: "arsiv", ad: "b")
        let c = IndirmeKaydi(adres: "https://example.com/c.mp4", tur: "video", ad: "c")
        let d = IndirmeKaydi(adres: "https://local.invalid/d.txt", tur: "arsiv", ad: "d")
        let g = IndirmelerEkrani.gruplar([a, b, c, d])
        #expect(g.indirmeler.map(\.ad) == ["a", "c"])
        #expect(g.arsiv.map(\.ad) == ["b", "d"])
    }

    @Test func yalnizArsivKaydiVarkenIndirmelerBos() {
        let b = IndirmeKaydi(adres: "https://local.invalid/b.txt", tur: "arsiv", ad: "b")
        let g = IndirmelerEkrani.gruplar([b])
        #expect(g.indirmeler.isEmpty)
        #expect(g.arsiv.count == 1)
        let bos = IndirmelerEkrani.gruplar([])
        #expect(bos.indirmeler.isEmpty && bos.arsiv.isEmpty)
    }

    @Test func uzakKayitYerelDegil() {
        #expect(!IndirmeKaydi(adres: "https://example.com/a.pdf", tur: "file").yerel)
        // Bayraktan önce yazılmış eski kayıt (nil): adres önekine bakılır.
        var eski = IndirmeKaydi(adres: "https://local.invalid/a.pdf", tur: "file")
        eski.yerelUretim = nil
        #expect(eski.yerel)
        var uretim = IndirmeKaydi(adres: "https://example.com/a.pdf", tur: "file")
        uretim.yerelUretim = true
        #expect(uretim.yerel)
        // Kullanıcının eklediği (bayrağı false) kayıt sahte adresi andırsa da yerel sayılmaz.
        #expect(!IndirmeKaydi(adres: "https://local.invalid/a.pdf", tur: "file").yerel)
    }

    @Test func yerelKayitYenidenIndirilmez() async {
        let y = IndirmeYoneticisi.ortak
        let onceki = y.hata
        let sayi = y.kayitlar.count
        defer { y.hata = onceki }
        let k = IndirmeKaydi(adres: "https://local.invalid/silinmis.txt", tur: IndirmeYoneticisi.arsivTuru, ad: "silinmis.txt", durum: "done", yerelUretim: true)
        await y.tekrar(k)
        #expect(y.hata == "Bu dosya iPhone'da üretildi; yeniden indirilemez.")
        #expect(y.kayitlar.count == sayi)
    }
}
