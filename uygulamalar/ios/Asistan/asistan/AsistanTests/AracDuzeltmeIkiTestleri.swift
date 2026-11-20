import Foundation
import Testing
@testable import Asistan

/// Araçlar alanı ikinci düzeltme turu: yan etki sınıflaması (pdfIslem, fotograflar), OAuth adres güvenliği,
/// fotoğraf kimlik tablosunun istek başına ayrılması. Ağ, izin ve model yok.
@MainActor
@Suite("Araçlar düzeltme turu 2")
struct AracDuzeltmeIkiTestleri {
    @Test func pdfIslemYazanIslemlerYanEtkili() {
        for i in ["birlestir", "bol", "dondur", "sikistir", "doldur", "imzala", "birleştir", "Sıkıştır"] {
            #expect(GorevGunlugu.yanEtkiliMi("pdfIslem", islem: i), "\(i)")
        }
        for i in ["bilgi", "alanlar"] { #expect(!GorevGunlugu.yanEtkiliMi("pdfIslem", islem: i), "\(i)") }
        #expect(GorevGunlugu.islemAdi(PdfAraci.Arguments(islem: "bilgi", kaynaklar: "ek:1", sayfalar: nil, derece: nil, degerlerJSON: nil,
                                                          konum: nil, hedefMB: nil, dosyaAdi: nil)) == "bilgi")
    }

    @Test func fotograflarSaltOkunur() {
        #expect(!GorevGunlugu.yanEtkiliMi("fotograflar", islem: "ara"))
        #expect(!GorevGunlugu.yanEtkiliMi("fotograflar", islem: nil))
    }

    @Test func oauthAdresleriOzelAgaGidemez() {
        for s in ["https://auth.ornek/token", "http://localhost:3000/oauth", "http://127.0.0.1:8080/x"] {
            #expect(McpIstemci.oauthAdresiGecerli(s), "\(s) kabul edilmeli")
        }
        for s in ["https://192.168.1.1/token", "https://10.0.0.5/a", "https://169.254.169.254/latest", "https://router.local/x",
                  "http://ornek.com/x", "https://[::1]/x", "ftp://x.com"] {
            #expect(!McpIstemci.oauthAdresiGecerli(s), "\(s) reddedilmeli")
        }
    }

    @Test func fotografKimlikTablosuIstegeGoreAyrilir() {
        FotografAraci.kimlikleriKaydet(["F1": "a"], istek: "istek-x")
        FotografAraci.kimlikleriKaydet(["F1": "b"], istek: "istek-y")
        #expect(FotografAraci.kimlikleriGetir(istek: "istek-x") == ["F1": "a"])
        #expect(FotografAraci.kimlikleriGetir(istek: "istek-y") == ["F1": "b"])
        // Kendi tablosu olmayan yeni istek (sonraki mesaj) en son tabloyu görür.
        #expect(FotografAraci.kimlikleriGetir(istek: "istek-z") == ["F1": "b"])
    }
}
